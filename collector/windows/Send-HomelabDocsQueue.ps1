param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigDirectory,
    [int]$IdleTimeoutSeconds = 60
)

# Runs in a separate PowerShell process. Never pass tokens as process arguments.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$configPath = Join-Path $ConfigDirectory 'client.json'
$tokenPath = Join-Path $ConfigDirectory 'token.dpapi'
$queueDir = Join-Path $ConfigDirectory 'queue'
$statusPath = Join-Path $ConfigDirectory 'uploader-status.json'
$mutexName = 'Local\HomelabDocsUploader'
$mutex = $null
$ownsMutex = $false

function Write-UploaderStatus {
    param(
        [string]$Status,
        [string]$LastError = '',
        [Nullable[datetime]]$LastSuccessUtc = $null,
        [Nullable[datetime]]$RetryAfterUtc = $null
    )
    $status = @{
        status = $Status
        updated_utc = [DateTime]::UtcNow.ToString('o')
        last_error = $LastError
        last_success_utc = if ($LastSuccessUtc.HasValue) { $LastSuccessUtc.Value.ToString('o') } else { $null }
        retry_after_utc = if ($RetryAfterUtc.HasValue) { $RetryAfterUtc.Value.ToString('o') } else { $null }
        process_id = $PID
    }
    $temp = "$statusPath.tmp"
    [System.IO.File]::WriteAllText($temp, ($status | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $statusPath -Force
}

try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    try { $ownsMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { exit 0 }

    if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $tokenPath)) {
        Write-UploaderStatus -Status 'not_configured' -LastError 'Client configuration or DPAPI token file is missing.'
        exit 2
    }

    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $apiUrl = ([string]$config.api_url).TrimEnd('/')
    $uri = [Uri]$apiUrl
    if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1', '::1')) {
        Write-UploaderStatus -Status 'configuration_error' -LastError 'HTTPS is required for remote API connections.'
        exit 2
    }

    $secureToken = Get-Content -Raw -LiteralPath $tokenPath | ConvertTo-SecureString
    $tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr) }
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-UploaderStatus -Status 'configuration_error' -LastError 'The stored token could not be decrypted for this Windows user.'
        exit 2
    }

    $idleSince = [DateTime]::UtcNow
    $lastSuccess = $null
    $lastError = ''
    $consecutiveFailures = 0
    while ($true) {
        $files = @(Get-ChildItem -LiteralPath $queueDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 20)
        if ($files.Count -eq 0) {
            if (([DateTime]::UtcNow - $idleSince).TotalSeconds -ge $IdleTimeoutSeconds) {
                Write-UploaderStatus -Status 'idle' -LastError $lastError -LastSuccessUtc $lastSuccess
                break
            }
            Start-Sleep -Seconds 2
            continue
        }

        $idleSince = [DateTime]::UtcNow
        $uploadedAny = $false
        foreach ($file in $files) {
            try {
                $body = [System.IO.File]::ReadAllText($file.FullName)
                $null = Invoke-RestMethod -Method Post -Uri "$apiUrl/api/v1/events" -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body -TimeoutSec 3
                Remove-Item -LiteralPath $file.FullName -Force
                $lastSuccess = [DateTime]::UtcNow
                $lastError = ''
                $consecutiveFailures = 0
                $uploadedAny = $true
                Write-UploaderStatus -Status 'uploading' -LastSuccessUtc $lastSuccess
            } catch {
                # Do not store request bodies or authorization headers in status.
                $lastError = $_.Exception.GetType().FullName + ': upload failed'
                $consecutiveFailures++
                $retryAfter = [DateTime]::UtcNow.AddSeconds(15)
                Write-UploaderStatus -Status 'retry_wait' -LastError $lastError -LastSuccessUtc $lastSuccess -RetryAfterUtc $retryAfter
                if ($consecutiveFailures -ge 3) {
                    Write-UploaderStatus -Status 'retry_deferred' -LastError $lastError -LastSuccessUtc $lastSuccess -RetryAfterUtc $retryAfter
                    break
                }
                Start-Sleep -Seconds 15
                break
            }
        }

        if ($consecutiveFailures -ge 3) { break }
        if (-not $uploadedAny -and $files.Count -gt 0 -and $consecutiveFailures -gt 0) { continue }
    }
} catch {
    try { Write-UploaderStatus -Status 'worker_error' -LastError ($_.Exception.GetType().FullName + ': background uploader failed') } catch {}
} finally {
    if ($ownsMutex -and $mutex) { try { $mutex.ReleaseMutex() } catch {} }
    if ($mutex) { $mutex.Dispose() }
    $token = $null
}
