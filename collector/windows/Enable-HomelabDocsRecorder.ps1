# Dot-source this script in a PowerShell session to enable command metadata recording:
#   . .\Enable-HomelabDocsRecorder.ps1
# It does not capture command output or screenshots. Commands matching secret filters
# are redacted before they are written to the local queue.

$ErrorActionPreference = 'Stop'

if ($global:HomelabDocsRecorderState -and $global:HomelabDocsRecorderState.Enabled) {
    Write-Host 'Documentor recorder is already enabled in this PowerShell session.'
    return
}

$configDir = Join-Path $env:LOCALAPPDATA 'HomelabDocs'
$configPath = Join-Path $configDir 'client.json'
$tokenPath = Join-Path $configDir 'token.dpapi'
if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $tokenPath)) {
    throw 'Documentor client is not configured. Run Set-HomelabDocsClient.ps1 first.'
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$apiUrl = ([string]$config.api_url).TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($apiUrl)) { throw 'The configured Documentor API URL is empty.' }
$uri = [Uri]$apiUrl
if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1', '::1')) {
    throw 'Documentor recorder requires HTTPS for remote connections.'
}

$queueDir = Join-Path $configDir 'queue'
New-Item -ItemType Directory -Force -Path $queueDir | Out-Null
$originalPrompt = (Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock

$recorderConfig = $config.recorder
$maxQueuedEvents = 5000
$maxQueueBytes = 50 * 1024 * 1024
$retentionDays = 30
if ($null -ne $recorderConfig.max_queued_events) { $maxQueuedEvents = [int]$recorderConfig.max_queued_events }
if ($null -ne $recorderConfig.max_queue_bytes) { $maxQueueBytes = [long]$recorderConfig.max_queue_bytes }
if ($null -ne $recorderConfig.retention_days) { $retentionDays = [int]$recorderConfig.retention_days }
if ($maxQueuedEvents -lt 100 -or $maxQueuedEvents -gt 50000) { throw 'recorder.max_queued_events must be between 100 and 50000.' }
if ($maxQueueBytes -lt (1MB) -or $maxQueueBytes -gt (2GB)) { throw 'recorder.max_queue_bytes must be between 1 MiB and 2 GiB.' }
if ($retentionDays -lt 1 -or $retentionDays -gt 365) { throw 'recorder.retention_days must be between 1 and 365.' }

$defaultExcludedPatterns = @(
    '(?i)\b(password|passwd|token|secret|api[_-]?key|client[_-]?secret|private[_-]?key|credential)\b',
    '(?i)authorization\s*:',
    '(?i)bearer\s+[A-Za-z0-9._~+/-]{12,}',
    '(?i)(--password|--token|--api-key|-password|-token)\s+\S+',
    '(?i)(password|passwd|token|secret|api[_-]?key|client[_-]?secret)\s*[=:]\s*[^\s;,&]+',
    '(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
$customPatterns = @()
if ($null -ne $recorderConfig.redaction_patterns) {
    if ($recorderConfig.redaction_patterns -isnot [System.Array] -or $recorderConfig.redaction_patterns.Count -gt 50) {
        throw 'recorder.redaction_patterns must be an array containing no more than 50 regular expressions.'
    }
    foreach ($pattern in $recorderConfig.redaction_patterns) {
        $candidate = [string]$pattern
        if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.Length -gt 256) {
            throw 'Each recorder.redaction_patterns entry must contain 1-256 characters.'
        }
        try {
            $null = [regex]::new($candidate, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromMilliseconds(100))
        } catch {
            throw "Invalid recorder redaction pattern: $candidate"
        }
        $customPatterns += $candidate
    }
}

$global:HomelabDocsRecorderState = @{
    Enabled = $true
    Paused = $false
    ApiUrl = $apiUrl
    HostId = $env:COMPUTERNAME.ToLowerInvariant()
    SessionId = [Guid]::NewGuid().ToString('N')
    QueueDir = $queueDir
    LastHistoryId = 0
    PreviousWorkingDirectory = (Get-Location).Path
    OriginalPrompt = $originalPrompt
    LastError = $null
    NextRetryUtc = [DateTime]::MinValue
    MaxQueuedEvents = $maxQueuedEvents
    MaxQueueBytes = $maxQueueBytes
    RetentionDays = $retentionDays
    ExcludedPatterns = @($defaultExcludedPatterns) + @($customPatterns)
}

function global:Protect-HomelabDocsCommand {
    param([Parameter(Mandatory)][string]$CommandLine)

    $state = $global:HomelabDocsRecorderState
    foreach ($pattern in $state.ExcludedPatterns) {
        try {
            if ([regex]::IsMatch(
                $CommandLine,
                $pattern,
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [TimeSpan]::FromMilliseconds(100)
            )) {
                return '[REDACTED: command matched a sensitive-data filter]'
            }
        } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
            return '[REDACTED: secret filter timed out]'
        }
    }

    $clean = $CommandLine -replace '[\r\n]+', ' '
    if ($clean.Length -gt 4000) { $clean = $clean.Substring(0, 4000) }
    return $clean
}

function global:Send-HomelabDocsQueuedEvents {
    $state = $global:HomelabDocsRecorderState
    if (-not $state -or -not $state.Enabled -or $state.Paused) { return }
    if ([DateTime]::UtcNow -lt $state.NextRetryUtc) { return }

    $files = Get-ChildItem -LiteralPath $state.QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 20
    foreach ($file in $files) {
        try {
            $body = [System.IO.File]::ReadAllText($file.FullName)
            $null = Invoke-RestMethod -Method Post -Uri "$($state.ApiUrl)/api/v1/events" -Headers @{ Authorization = "Bearer $($state.Token)" } -ContentType 'application/json' -Body $body -TimeoutSec 3
            Remove-Item -LiteralPath $file.FullName -Force
            $state.LastError = $null
            $state.NextRetryUtc = [DateTime]::MinValue
        } catch {
            $state.LastError = $_.Exception.Message
            $state.NextRetryUtc = [DateTime]::UtcNow.AddSeconds(15)
            # Keep the failed item and stop this batch; the next prompt retries it.
            break
        }
    }
}

function global:Apply-HomelabDocsQueuePolicy {
    $state = $global:HomelabDocsRecorderState
    $cutoff = [DateTime]::UtcNow.AddDays(-$state.RetentionDays)
    $files = @(Get-ChildItem -LiteralPath $state.QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        if ($file.LastWriteTimeUtc -lt $cutoff) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    $remaining = @(Get-ChildItem -LiteralPath $state.QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    $totalBytes = [long](($remaining | Measure-Object -Property Length -Sum).Sum)
    if ($remaining.Count -ge $state.MaxQueuedEvents -or $totalBytes -ge $state.MaxQueueBytes) {
        throw ("Documentor queue is full ({0} events, {1} bytes). The event was not queued; check recorder status and API connectivity." -f $remaining.Count, $totalBytes)
    }
}

function global:Write-HomelabDocsCommandEvent {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][bool]$Succeeded,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowNull()][object]$NativeExitCode
    )

    $state = $global:HomelabDocsRecorderState
    $safeCommand = Protect-HomelabDocsCommand -CommandLine $CommandLine
    $event = @{
        client_event_id = [Guid]::NewGuid().ToString()
        host_id = $state.HostId
        event_type = 'powershell_command'
        timestamp = [DateTime]::UtcNow.ToString('o')
        session_id = $state.SessionId
        summary = $safeCommand
        payload = @{
            command = $safeCommand
            working_directory = $WorkingDirectory
            powershell_success = $Succeeded
            last_native_exit_code = $NativeExitCode
            capture_method = 'PowerShell prompt/history hook'
            output_capture = 'disabled'
        }
        evidence_refs = @()
    }

    $fileName = '{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'), $event.client_event_id
    $path = Join-Path $state.QueueDir $fileName
    $json = $event | ConvertTo-Json -Depth 10 -Compress
    $encoded = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    Apply-HomelabDocsQueuePolicy
    if ($encoded.Length -gt $state.MaxQueueBytes) {
        throw 'Documentor event exceeds the configured maximum queue size and was not queued.'
    }
    $currentBytes = [long]((Get-ChildItem -LiteralPath $state.QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)
    if (($currentBytes + $encoded.Length) -gt $state.MaxQueueBytes) {
        throw 'Documentor queue byte quota would be exceeded; the event was not queued.'
    }
    $temporaryPath = "$path.tmp"
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
}

function global:Get-HomelabDocsRecorderStatus {
    $state = $global:HomelabDocsRecorderState
    if (-not $state) {
        return [pscustomobject]@{ Enabled = $false; Paused = $false; QueuedEvents = 0; LastError = $null }
    }
    $queued = @(Get-ChildItem -LiteralPath $state.QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    $queueFiles = @(Get-ChildItem -LiteralPath $state.QueueDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    $queueBytes = [long](($queueFiles | Measure-Object -Property Length -Sum).Sum)
    [pscustomobject]@{
        Enabled = $state.Enabled
        Paused = $state.Paused
        QueuedEvents = $queued
        QueuedBytes = $queueBytes
        MaxQueuedEvents = $state.MaxQueuedEvents
        MaxQueueBytes = $state.MaxQueueBytes
        RetentionDays = $state.RetentionDays
        SessionId = $state.SessionId
        LastError = $state.LastError
        OutputCapture = 'disabled'
    }
}

function global:Pause-HomelabDocsRecorder {
    if ($global:HomelabDocsRecorderState) { $global:HomelabDocsRecorderState.Paused = $true }
    Write-Host 'Documentor recording paused. Commands entered while paused will not be recorded.'
}

function global:Resume-HomelabDocsRecorder {
    if ($global:HomelabDocsRecorderState) {
        $global:HomelabDocsRecorderState.Paused = $false
        Send-HomelabDocsQueuedEvents
    }
    Write-Host 'Documentor recording resumed.'
}

function global:Stop-HomelabDocsRecorder {
    $state = $global:HomelabDocsRecorderState
    if (-not $state) { return }
    $state.Enabled = $false
    if ($state.OriginalPrompt) {
        Set-Item -Path Function:global:prompt -Value $state.OriginalPrompt
    } else {
        Remove-Item Function:global:prompt -ErrorAction SilentlyContinue
    }
    $state.Token = $null
    Write-Host 'Documentor recording stopped for this PowerShell session. Queued events remain on disk.'
}

function global:prompt {
    # Capture automatic variables before running any other commands in this function.
    $lastSucceeded = $?
    $nativeExitCode = $global:LASTEXITCODE
    $state = $global:HomelabDocsRecorderState

    if ($state -and $state.Enabled -and -not $state.Paused) {
        $lastCommand = Get-History -Count 1 -ErrorAction SilentlyContinue
        if ($lastCommand -and $lastCommand.Id -gt $state.LastHistoryId) {
            $state.LastHistoryId = $lastCommand.Id
            $line = [string]$lastCommand.CommandLine
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                try {
                    Write-HomelabDocsCommandEvent -CommandLine $line -Succeeded ([bool]$lastSucceeded) -WorkingDirectory ([string]$state.PreviousWorkingDirectory) -NativeExitCode $nativeExitCode
                    Send-HomelabDocsQueuedEvents
                } catch {
                    $state.LastError = $_.Exception.Message
                }
            }
        }
        $state.PreviousWorkingDirectory = (Get-Location).Path
    }

    if ($state -and $state.OriginalPrompt) {
        & $state.OriginalPrompt
    } else {
        "PS $((Get-Location).Path)> "
    }
}

Write-Host 'Documentor recorder enabled for this PowerShell session.'
Write-Host 'Commands are recorded as metadata only; command output and screenshots are not captured.'
Write-Host 'Use Pause-HomelabDocsRecorder, Resume-HomelabDocsRecorder, Get-HomelabDocsRecorderStatus, or Stop-HomelabDocsRecorder.'
