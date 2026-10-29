# Lightweight, dependency-free checks for the Windows recorder.
# Run from the repository root in Windows PowerShell 5.1 and PowerShell 7:
#   .\tests\windows\Invoke-RecorderChecks.ps1
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$recorderPath = Join-Path $repoRoot 'collector\windows\Enable-HomelabDocsRecorder.ps1'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($recorderPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "Recorder syntax validation failed: $details"
}
Write-Host '[PASS] Recorder parses without syntax errors.'

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

    . $recorderPath

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

    $oldPath = Join-Path $global:HomelabDocsRecorderState.QueueDir 'expired-test-event.json'
    [System.IO.File]::WriteAllText($oldPath, '{}', [System.Text.UTF8Encoding]::new($false))
    (Get-Item -LiteralPath $oldPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
    Apply-HomelabDocsQueuePolicy
    if (Test-Path -LiteralPath $oldPath) { throw 'Expired queue file was not removed.' }
    Write-Host '[PASS] Retention policy removes expired queue files.'

    1..100 | ForEach-Object {
        $name = ('quota-test-{0:D3}.json' -f $_)
        [System.IO.File]::WriteAllText((Join-Path $global:HomelabDocsRecorderState.QueueDir $name), '{}', [System.Text.UTF8Encoding]::new($false))
    }
    $quotaRejected = $false
    try {
        Write-HomelabDocsCommandEvent -CommandLine 'Get-ChildItem -Force' -Succeeded $true -WorkingDirectory $tempRoot -NativeExitCode $null
    } catch {
        $quotaRejected = $_.Exception.Message -match 'queue is full'
    }
    if (-not $quotaRejected) { throw 'Queue count quota did not reject a new event at capacity.' }
    Write-Host '[PASS] Queue quota rejects new events instead of evicting existing evidence.'
    Write-Host 'Recorder checks passed. No API requests were sent.'
}
finally {
    if ($global:HomelabDocsRecorderState) { Stop-HomelabDocsRecorder }
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
