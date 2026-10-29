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

## Local queue, quotas and retries

Events are written as individual JSON files under `%LOCALAPPDATA%\HomelabDocs\queue`. The recorder attempts to upload queued events after each command, processing at most 20 files per prompt. If the API is unavailable, the failed event remains on disk and the batch stops; the recorder waits 15 seconds before retrying to avoid delaying every prompt during an outage. Each queued event has a stable client event ID so retrying after a lost response does not create duplicate database rows.

Defaults are 5,000 queued events, 50 MiB total queue size, and 30 days of local queue retention. Expired queue files are deleted when the recorder next tries to write an event. The recorder does **not** evict newer events to make room: when a quota is reached, the current event is not queued and the error is exposed by `Get-HomelabDocsRecorderStatus`. Check status if the API has been unavailable for a while.

Optional settings belong in `%LOCALAPPDATA%\HomelabDocs\client.json`, alongside the existing `api_url` property:

```json
{
  "api_url": "https://documentor.example.internal",
  "recorder": {
    "max_queued_events": 5000,
    "max_queue_bytes": 52428800,
    "retention_days": 30,
    "redaction_patterns": [
      "(?i)my_internal_secret_flag\\s+\\S+",
      "(?i)company-token-[A-Za-z0-9]+"
    ]
  }
}
```

The limits are validated: event count 100–50,000; queue size 1 MiB–2 GiB; retention 1–365 days. `redaction_patterns` is an optional array of up to 50 regular expressions, each at most 256 characters. A command matching any default or custom pattern is replaced in full before it is written locally. Each regex match has a 100 ms timeout; a timeout fails closed and redacts the command. Custom filters are additive and cannot disable built-in filters.

The queue is local evidence and can contain command text after redaction. Protect the Windows user account and do not copy the queue into Git or share it casually. Retention deletes expired local queue files, so choose a policy consistent with your evidence-retention needs.

## Secret filtering

Commands matching built-in sensitive-term, credential-assignment, bearer-token, CLI-flag and private-key patterns are replaced with a generic redaction marker before local persistence. Optional user-defined regex patterns can be added in `client.json`; they are additive and have a per-match timeout. This is intentionally conservative, but **heuristic redaction is not a guarantee**: secrets can be expressed in unexpected ways.

Until the filter is reviewed against your actual workflows, avoid entering commands that contain credentials while recording. Use the pause control before running a sensitive command. Do not rely on this recorder as a secret-management boundary.

## Current limitations

- Command metadata only: command output, screenshots, GUI activity, browser activity and full transcripts are not captured.
- It relies on the PowerShell history/prompt lifecycle; commands that do not return to the prompt normally may be recorded late or not recorded.
- It records command completion time, not an exact start time.
- The working directory is the directory captured before the command, but nested prompts and custom prompt implementations require testing.
- The last native exit-code value may be stale for PowerShell cmdlets.
- There is no automatic startup/profile integration or remote host correlation yet.
- Queue retention and quotas are implemented but have not been exercised in a real Windows session; expired queued events are deleted according to the configured retention policy.
- The script has not yet been validated on your Windows workstation. Treat it as experimental until tested with synthetic commands.

## Validation

A dependency-free Windows test harness is provided. From the repository root, run it in Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\tests\windows\Invoke-RecorderChecks.ps1
```

It parses the recorder and exercises built-in/custom redaction, metadata-only queueing, expiry cleanup and count-quota behavior using synthetic temporary files. It does not send API requests. It has been added to the repository but has **not yet been executed** in either PowerShell runtime. These checks do not replace a live API integration test.

## Next recorder work

1. Run the harness in Windows PowerShell 5.1 and PowerShell 7, then fix any compatibility issues.
2. Validate the prompt hook against default and customized prompts and confirm completion-status/working-directory semantics.
3. Add tests for byte quota, regex timeout, invalid configuration and upload/retry behavior before regular use.
4. Consider optional bounded output capture only after a separate redaction and consent design; it must remain off by default.
5. Add explicit task/session labels and target-host metadata.
