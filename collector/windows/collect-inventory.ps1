# Collects bounded inventory only. Does not collect command history, screenshots, secrets, or file contents.
$ErrorActionPreference = 'Stop'
$configDir = Join-Path $env:LOCALAPPDATA 'HomelabDocs'
$configPath = Join-Path $configDir 'client.json'
$tokenPath = Join-Path $configDir 'token.dpapi'
if (-not (Test-Path $configPath) -or -not (Test-Path $tokenPath)) {
    throw 'Client is not configured. Run Set-HomelabDocsClient.ps1 first.'
}
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$api = ([string]$config.api_url).TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($api)) { throw 'The configured Documentor API URL is empty.' }
$apiUri = [Uri]$api
if (-not $apiUri.IsAbsoluteUri -or ($apiUri.Scheme -ne 'https' -and $apiUri.Host -notin @('localhost', '127.0.0.1', '::1'))) {
    throw 'Documentor inventory uploads require HTTPS for remote connections. HTTP is allowed only for loopback development.'
}
$secureToken = Get-Content -Raw -Path $tokenPath | ConvertTo-SecureString
$tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr) }
$headers = @{ Authorization = "Bearer $token" }

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, FileSystem, Size, FreeSpace, VolumeName
$adapters = Get-NetIPConfiguration | ForEach-Object {
    [pscustomobject]@{
        InterfaceAlias = $_.InterfaceAlias
        InterfaceDescription = $_.NetAdapter.InterfaceDescription
        IPv4Address = @($_.IPv4Address | ForEach-Object { $_.IPAddress })
        IPv4DefaultGateway = @($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
        DNSServer = @($_.DNSServer.ServerAddresses)
    }
}
$services = Get-CimInstance Win32_Service | Where-Object { $_.State -eq 'Running' } | Select-Object Name, DisplayName, StartMode, State
$softwareRoots = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
$apps = Get-ItemProperty $softwareRoots -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Sort-Object DisplayName -Unique

$state = [ordered]@{
    collected_by = 'windows-powershell-inventory-v1'
    computer = [ordered]@{
        hostname = $env:COMPUTERNAME
        manufacturer = $computer.Manufacturer
        model = $computer.Model
        domain = $computer.Domain
        total_physical_memory_bytes = $computer.TotalPhysicalMemory
    }
    operating_system = [ordered]@{
        caption = $os.Caption
        version = $os.Version
        build_number = $os.BuildNumber
        architecture = $os.OSArchitecture
        last_boot_up_time = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToUniversalTime().ToString('o') } else { $null }
    }
    bios = [ordered]@{ manufacturer = $bios.Manufacturer; version = $bios.SMBIOSBIOSVersion }
    disks = @($disks)
    network_adapters = @($adapters)
    running_services = @($services)
    installed_applications = @($apps)
}
$body = [ordered]@{
    host_id = $env:COMPUTERNAME.ToLowerInvariant()
    source = 'windows-inventory'
    state = $state
} | ConvertTo-Json -Depth 12

try {
    Invoke-RestMethod -Method Post -Uri "$($api.TrimEnd('/'))/api/v1/snapshots" -Headers $headers -ContentType 'application/json' -Body $body | ConvertTo-Json -Depth 5
} catch {
    throw "Snapshot upload failed. Check API URL, HTTPS certificate trust, token, and network access. $($_.Exception.Message)"
} finally {
    $token = $null
    $secureToken = $null
}
