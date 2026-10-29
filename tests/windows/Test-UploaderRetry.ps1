# Integration test for the background uploader: synthetic API returns 503 once, then succeeds.
# Uses only loopback networking, a temporary directory, and a DPAPI token owned by this test user.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$uploaderPath = Join-Path $repoRoot 'collector\windows\Send-HomelabDocsQueue.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("documentor-uploader-test-" + [Guid]::NewGuid().ToString('N'))
$serverJob = $null
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $configDir = Join-Path $tempRoot 'HomelabDocs'
    $queueDir = Join-Path $configDir 'queue'
    New-Item -ItemType Directory -Path $queueDir -Force | Out-Null

    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = $probe.LocalEndpoint.Port
    $probe.Stop()

    $readyPath = Join-Path $tempRoot 'server-ready.txt'
    $requestLogPath = Join-Path $tempRoot 'requests.jsonl'
    $serverJob = Start-Job -ArgumentList $port, $readyPath, $requestLogPath -ScriptBlock {
        param([int]$Port, [string]$ReadyPath, [string]$RequestLogPath)
        $ErrorActionPreference = 'Stop'
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        try {
            $listener.Start()
            [System.IO.File]::WriteAllText($ReadyPath, 'ready')
            $requestCount = 0
            while ($requestCount -lt 2) {
                $client = $listener.AcceptTcpClient()
                try {
                    $stream = $client.GetStream()
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
                    try {
                        $requestLine = $reader.ReadLine()
                        if ([string]::IsNullOrWhiteSpace($requestLine)) { throw 'Empty HTTP request line.' }
                        $headers = @{}
                        while ($true) {
                            $line = $reader.ReadLine()
                            if ([string]::IsNullOrEmpty($line)) { break }
                            $separator = $line.IndexOf(':')
                            if ($separator -gt 0) {
                                $headers[$line.Substring(0, $separator).Trim()] = $line.Substring($separator + 1).Trim()
                            }
                        }
                        $contentLength = 0
                        if ($headers.ContainsKey('Content-Length')) { $contentLength = [int]$headers['Content-Length'] }
                        $bodyChars = New-Object char[] $contentLength
                        $read = 0
                        while ($read -lt $contentLength) {
                            $count = $reader.Read($bodyChars, $read, $contentLength - $read)
                            if ($count -le 0) { throw 'Unexpected end of HTTP request body.' }
                            $read += $count
                        }
                        $body = -join $bodyChars
                        Add-Content -LiteralPath $RequestLogPath -Value $body
                        $requestCount++

                        if ($requestCount -eq 1) {
                            $statusCode = 503
                            $reason = 'Service Unavailable'
                            $responseBody = '{"detail":"synthetic temporary failure"}'
                        } else {
                            $statusCode = 200
                            $reason = 'OK'
                            $responseBody = '{"id":1,"stored":true}'
                        }
                        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
                        $crlf = [string][char]13 + [string][char]10
                        $responseHeaders = "HTTP/1.1 $statusCode $reason$crlf" +
                            "Content-Type: application/json$crlf" +
                            "Content-Length: $($responseBytes.Length)$crlf" +
                            "Connection: close$crlf$crlf"
                        $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($responseHeaders)
                        $stream.Write($headerBytes, 0, $headerBytes.Length)
                        $stream.Write($responseBytes, 0, $responseBytes.Length)
                        $stream.Flush()
                    } finally {
                        $reader.Dispose()
                    }
                } finally {
                    $client.Close()
                }
            }
        } finally {
            $listener.Stop()
        }
    }

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $readyPath) -and [DateTime]::UtcNow -lt $readyDeadline) {
        if ($serverJob.State -in @('Failed', 'Stopped', 'Completed')) {
            throw 'Synthetic HTTP server did not start.'
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Timed out waiting for synthetic HTTP server startup.' }

    $config = @{
        api_url = "http://127.0.0.1:$port"
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText((Join-Path $configDir 'client.json'), $config, [System.Text.UTF8Encoding]::new($false))
    ConvertTo-SecureString 'synthetic-uploader-test-token' -AsPlainText -Force |
        ConvertFrom-SecureString |
        Set-Content -LiteralPath (Join-Path $configDir 'token.dpapi') -NoNewline

    $event = @{
        client_event_id = 'uploader-retry-event-0001'
        host_id = 'synthetic-host'
        event_type = 'powershell_command'
        timestamp = [DateTime]::UtcNow.ToString('o')
        summary = 'Synthetic uploader retry test'
        payload = @{ output_capture = 'disabled' }
        evidence_refs = @()
    } | ConvertTo-Json -Depth 5 -Compress
    [System.IO.File]::WriteAllText((Join-Path $queueDir '0001-event.json'), $event, [System.Text.UTF8Encoding]::new($false))

    & $uploaderPath -ConfigDirectory $configDir -IdleTimeoutSeconds 2 -RetryDelaySeconds 1

    $remaining = @(Get-ChildItem -LiteralPath $queueDir -Filter '*.json' -File)
    if ($remaining.Count -ne 0) { throw "Uploader did not remove the event after a successful retry; queue has $($remaining.Count) file(s)." }

    $requests = @(Get-Content -LiteralPath $requestLogPath)
    if ($requests.Count -ne 2) { throw "Expected exactly two upload attempts (one failure, one success), received $($requests.Count)." }
    $firstRequest = $requests[0] | ConvertFrom-Json
    $secondRequest = $requests[1] | ConvertFrom-Json
    if ($firstRequest.client_event_id -ne $secondRequest.client_event_id) {
        throw 'Uploader retry changed the client_event_id; server-side idempotency would not protect against duplicate delivery.'
    }
    if ($firstRequest.client_event_id -ne 'uploader-retry-event-0001') { throw 'Uploader sent an unexpected event.' }

    $status = Get-Content -Raw -LiteralPath (Join-Path $configDir 'uploader-status.json') | ConvertFrom-Json
    if ($status.status -ne 'idle' -or -not $status.last_success_utc) {
        throw "Uploader did not finish in idle state after recovery; status was '$($status.status)'."
    }
    Write-Host '[PASS] Uploader retries after a temporary API failure, preserves event identity, and clears the queue after success.'
}
finally {
    if ($serverJob) {
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
