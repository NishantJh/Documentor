# Windows PowerShell Recorder (Preview)

The first recorder is deliberately opt-in and records command metadata only. It is a preview, not a complete desktop activity recorder.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7.
- A reachable Documentor API endpoint.
- A valid bearer token configured using `collector/windows/Set-HomelabDocsClient.ps1`.
- The API must be reachable over HTTPS for remote connections. HTTP is allowed only for loopback development.

## Start recording

Open a PowerShell session, change to the repository checkout, then dot-source the recorder:

```powershell
. .\collector\windows\Enable-HomelabDocsRecorder.ps1
```

Dot-sourcing is intentional: it installs a prompt hook into the current PowerShell session. It does not modify your PowerShell profile or automatically start on login.

The recorder observes the most recent PowerShell history entry after it completes. It stores a sanitized command line, host ID, session ID, timestamp, prior working directory, PowerShell success flag and last native exit-code value. The native exit-code value may be stale for cmdlets and should not be treated as authoritative unless the command was a native process.

## Controls

```powershell
Get-HomelabDocsRecorderStatus
Pause-HomelabDocsRecorder
Resume-HomelabDocsRecorder
Stop-HomelabDocsRecorder
```

- **Pause** skips recording commands while paused.
- **Resume** resumes recording and attempts to upload queued events.
- **Stop** restores the previous prompt function where possible and stops recording in the current session. It does not delete queued events.
- Status shows whether recording is enabled/paused, the number of queued events and the latest upload error.

## Local queue and retries

Events are written as individual JSON files under `%LOCALAPPDATA%\HomelabDocs\queue`. The recorder attempts to upload queued events after each command, processing at most 20 files per prompt. If the API is unavailable, the failed event remains on disk and the batch stops; the recorder waits 15 seconds before retrying to avoid delaying every prompt during an outage. Each queued event has a stable client event ID so retrying after a lost response does not create duplicate database rows.

The queue is local evidence and can contain command text after redaction. Protect the Windows user account and do not copy the queue into Git or share it casually. Queue retention and disk quotas are not yet implemented.

## Secret filtering

Commands containing common sensitive terms such as password, token, secret, API key, credentials, private key, or Authorization headers are replaced with a generic redaction marker before local persistence. Commands with common password/token CLI flags are also redacted. This is intentionally conservative, but **heuristic redaction is not a guarantee**: secrets can be expressed in unexpected ways.

Until the filter is reviewed against your actual workflows, avoid entering commands that contain credentials while recording. Use the pause control before running a sensitive command. Do not rely on this recorder as a secret-management boundary.

## Current limitations

- Command metadata only: command output, screenshots, GUI activity, browser activity and full transcripts are not captured.
- It relies on the PowerShell history/prompt lifecycle; commands that do not return to the prompt normally may be recorded late or not recorded.
- It records command completion time, not an exact start time.
- The working directory is the directory captured before the command, but nested prompts and custom prompt implementations require testing.
- The last native exit-code value may be stale for PowerShell cmdlets.
- There is no automatic startup/profile integration, queue quota, retention policy, or remote host correlation yet.
- The script has not yet been validated on your Windows workstation. Treat it as experimental until tested with synthetic commands.

## Next recorder work

1. Add automated PowerShell syntax checks where an available local runner permits them.
2. Validate the prompt hook against default and customized prompts in Windows PowerShell 5.1 and PowerShell 7.
3. Add a configurable queue quota and retention policy.
4. Improve secret filtering with tests and user-configurable exclusions.
5. Consider optional bounded output capture only after a separate redaction and consent design; it must remain off by default.
6. Add explicit task/session labels and target-host metadata.
