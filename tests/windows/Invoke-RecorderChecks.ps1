# Lightweight, dependency-free checks for the Windows recorder.
# Run from the repository root in Windows PowerShell 5.1 and PowerShell 7:
#   .\tests\windows\Invoke-RecorderChecks.ps1
$ErrorActionPreference = 'Stop'
if ($global:HomelabDocsRecorderState -and $global:HomelabDocsRecorderState.Enabled) {
    throw 'Run these checks in a separate, disposable PowerShell session; a recorder is already enabled in this session.'
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$recorderPath = Join-Path $repoRoot 'collector\windows\Enable-HomelabDocsRecorder.ps1'
$uploaderPath = Join-Path $repoRoot 'collector\windows\Send-HomelabDocsQueue.ps1'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($recorderPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "Recorder syntax validation failed: $details"
}
Write-Host '[PASS] Recorder parses without syntax errors.'
$uploaderTokens = $null
$uploaderParseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($uploaderPath, [ref]$uploaderTokens, [ref]$uploaderParseErrors) | Out-Null
if ($uploaderParseErrors.Count -gt 0) {
    $details = ($uploaderParseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "Uploader syntax validation failed: $details"
}
Write-Host '[PASS] Background uploader parses without syntax errors.'
if ((Get-Content -Raw -LiteralPath $recorderPath) -match 'Invoke-RestMethod') {
    throw 'Network requests must not be made by the interactive recorder script.'
}
Write-Host '[PASS] Interactive recorder contains no direct HTTP request.'

$originalLocalAppData = $env:LOCALAPPDATA
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("documentor-recorder-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $env:LOCALAPPDATA = $tempRoot
    $configDir = Join-Path $tempRoot 'HomelabDocs'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $config = @{
        api_url = 'http://127.0.0.1:8765'
        recorder = @{
            max_queued_events = 100
            max_queue_bytes = 1048576
            retention_days = 1
            redaction_patterns = @('(?i)private_marker\s+\S+')
        }
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $configDir 'client.json'), $config, [System.Text.UTF8Encoding]::new($false))
    ConvertTo-SecureString 'synthetic-test-token' -AsPlainText -Force |
        ConvertFrom-SecureString |
        Set-Content -LiteralPath (Join-Path $configDir 'token.dpapi') -NoNewline

    . $recorderPath -DisableUploader

    $redacted = Protect-HomelabDocsCommand -CommandLine 'tool --private_marker fake-secret-value'
    if ($redacted -notmatch '^\[REDACTED:') { throw 'Custom redaction pattern did not redact the command.' }
    Write-Host '[PASS] Custom secret filter redacts the full command.'

    $builtInRedacted = Protect-HomelabDocsCommand -CommandLine 'tool --password super-secret-value'
    if ($builtInRedacted -notmatch '^\[REDACTED:') { throw 'Built-in secret filter did not redact the command.' }
    Write-Host '[PASS] Built-in secret filter remains active.'

    $safe = Protect-HomelabDocsCommand -CommandLine 'Get-ChildItem -Force'
    if ($safe -ne 'Get-ChildItem -Force') { throw 'A harmless synthetic command was unexpectedly redacted.' }
    Write-Host '[PASS] Harmless command metadata remains recordable.'

    Write-HomelabDocsCommandEvent -CommandLine 'Get-ChildItem -Force' -Succeeded $true -WorkingDirectory $tempRoot -NativeExitCode $null
    $queued = @(Get-ChildItem -LiteralPath $global:HomelabDocsRecorderState.QueueDir -Filter '*.json' -File)
    if ($queued.Count -ne 1) { throw "Expected one queued event, found $($queued.Count)." }
    $queuedEvent = Get-Content -Raw -LiteralPath $queued[0].FullName | ConvertFrom-Json
    if ($queuedEvent.payload.output_capture -ne 'disabled') { throw 'Recorder must keep output capture disabled.' }
    Write-Host '[PASS] Event is queued as metadata only.'

    $originalMaxQueueBytes = $global:HomelabDocsRecorderState.MaxQueueBytes
    $global:HomelabDocsRecorderState.MaxQueueBytes = $global:HomelabDocsRecorderState.QueueBytes + 1
    $global:HomelabDocsRecorderState.LastQueueScanUtc = [DateTime]::UtcNow
    $byteQuotaRejected = $false
    try {
        Write-HomelabDocsCommandEvent -CommandLine 'Get-ChildItem -Force' -Succeeded $true -WorkingDirectory $tempRoot -NativeExitCode $null
    } catch {
        $byteQuotaRejected = $_.Exception.Message -match 'byte quota'
    } finally {
        $global:HomelabDocsRecorderState.MaxQueueBytes = $originalMaxQueueBytes
    }
    if (-not $byteQuotaRejected) { throw 'Queue byte quota did not reject an event that would exceed the configured limit.' }
    $queuedAfterByteCheck = @(Get-ChildItem -LiteralPath $global:HomelabDocsRecorderState.QueueDir -Filter '*.json' -File)
    if ($queuedAfterByteCheck.Count -ne 1) { throw 'Byte-quota rejection unexpectedly changed the existing queue.' }
    Write-Host '[PASS] Queue byte quota rejects overflow without deleting existing events.'

    $oldPath = Join-Path $global:HomelabDocsRecorderState.QueueDir 'expired-test-event.json'
    [System.IO.File]::WriteAllText($oldPath, '{}', [System.Text.UTF8Encoding]::new($false))
    (Get-Item -LiteralPath $oldPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
    $global:HomelabDocsRecorderState.LastQueueScanUtc = [DateTime]::MinValue
    Apply-HomelabDocsQueuePolicy
    if (Test-Path -LiteralPath $oldPath) { throw 'Expired queue file was not removed.' }
    Write-Host '[PASS] Retention policy removes expired queue files.'

    Get-ChildItem -LiteralPath $global:HomelabDocsRecorderState.QueueDir -Filter '*.json' -File | Remove-Item -Force
    1..100 | ForEach-Object {
        $name = ('quota-test-{0:D3}.json' -f $_)
        [System.IO.File]::WriteAllText((Join-Path $global:HomelabDocsRecorderState.QueueDir $name), '{}', [System.Text.UTF8Encoding]::new($false))
    }
    $global:HomelabDocsRecorderState.LastQueueScanUtc = [DateTime]::MinValue
    $quotaRejected = $false
    try {
        Write-HomelabDocsCommandEvent -CommandLine 'Get-ChildItem -Force' -Succeeded $true -WorkingDirectory $tempRoot -NativeExitCode $null
    } catch {
        $quotaRejected = $_.Exception.Message -match 'queue is full'
    }
    if (-not $quotaRejected) { throw 'Queue count quota did not reject a new event at capacity.' }
    Write-Host '[PASS] Queue quota rejects new events instead of evicting existing evidence.'
    Write-Host 'Recorder checks passed. The harness does not start the uploader or send API requests.'
}
finally {
    if ($global:HomelabDocsRecorderState) { Stop-HomelabDocsRecorder }
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
