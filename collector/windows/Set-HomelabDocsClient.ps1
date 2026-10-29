$ErrorActionPreference = 'Stop'
$apiUrl = Read-Host 'Central engine HTTPS URL (e.g. https://docs.homelab.example)'
if ([string]::IsNullOrWhiteSpace($apiUrl)) { throw 'API URL is required.' }
$uri = [Uri]$apiUrl
if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1', '::1')) {
    throw 'Use HTTPS for network connections. HTTP is permitted only for localhost development.'
}
$secureToken = Read-Host 'API bearer token' -AsSecureString
if ($secureToken.Length -lt 32) { throw 'Token appears too short. Use a long random token generated on the server.' }
$dir = Join-Path $env:LOCALAPPDATA 'HomelabDocs'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
@{ api_url = $apiUrl.TrimEnd('/') } | ConvertTo-Json | Set-Content -Encoding UTF8 -Path (Join-Path $dir 'client.json')
$secureToken | ConvertFrom-SecureString | Set-Content -Encoding ASCII -Path (Join-Path $dir 'token.dpapi')
Write-Host "Client configuration saved under $dir"
Write-Host 'The token is encrypted using Windows DPAPI for this user account. Do not commit these files to Git.'
