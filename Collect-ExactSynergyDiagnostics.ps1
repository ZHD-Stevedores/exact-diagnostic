<#
.SYNOPSIS
Read-only diagnostics for Exact Synergy Enterprise webservice hosting.

.NOTES
Copyright (c) 2026 ZHD (zhd.nl).
Licensed under the PolyForm Internal Use License 1.0.0. See LICENSE.

.DESCRIPTION
This script is intended for a live Exact Synergy Enterprise webserver. It only reads
IIS, filesystem, registry/uninstall, and file metadata. It does not modify IIS,
SQL Server, Exact configuration, or application files.

Run on the Synergy webserver in an elevated PowerShell session if possible:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1

Optional:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SynergyPath "C:\inetpub\wwwroot\Synergy"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -BaseUrl "http://server.example.local/Synergy"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SinceHours 168
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SkipEventLogs -SkipHttpChecks

The output file is written to the current directory unless -OutputPath is set.
#>

[CmdletBinding()]
param(
    [string]$SynergyPath,
    [string]$OutputPath,
    [string[]]$BaseUrl,
    [int]$SinceHours = 72,
    [switch]$SkipEventLogs,
    [switch]$SkipHttpChecks
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

function Write-Section {
    param([string]$Title)
    "`r`n===== $Title =====" | Out-File -FilePath $script:OutputPath -Append -Encoding UTF8
}

function Write-Line {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Text = ""
    )
    process {
        if ($null -eq $Text) {
            "" | Out-File -FilePath $script:OutputPath -Append -Encoding UTF8
        }
        else {
            [string]$Text | Out-File -FilePath $script:OutputPath -Append -Encoding UTF8
        }
    }
}

function Redact-Text {
    param([string]$Text)
    if ($null -eq $Text) { return "" }

    $redacted = $Text
    $redacted = $redacted -replace "(?i)((password|pwd|secret|token)\s*=\s*[""']?)[^;""'\s<>]+", '$1[REDACTED]'
    $redacted = $redacted -replace "(?i)((user\s+id|uid)\s*=\s*[""']?)[^;""'\s<>]+", '$1[REDACTED]'

    if ($redacted -match '(?i)password|pwd|secret|token') {
        $redacted = $redacted -replace "(?i)(value\s*=\s*[""'])[^""']+([""'])", '$1[REDACTED]$2'
        $redacted = $redacted -replace "(?i)(connectionString\s*=\s*[""'])[^""']+([""'])", '$1[REDACTED]$2'
    }

    return $redacted
}

function Shorten-Text {
    param(
        [string]$Text,
        [int]$MaxLength = 3000
    )

    if ($null -eq $Text) { return "" }
    $singleLine = $Text -replace '\s+', ' '
    if ($singleLine.Length -le $MaxLength) { return $singleLine }
    return $singleLine.Substring(0, $MaxLength) + " ...[truncated]"
}

function Safe-Command {
    param(
        [string]$Name,
        [scriptblock]$Block
    )

    try {
        & $Block
    }
    catch {
        Write-Line "$Name failed: $($_.Exception.Message)"
    }
}

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-Location) ("ExactSynergyDiagnostics-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

"" | Out-File -FilePath $OutputPath -Encoding UTF8
$script:OutputPath = (Resolve-Path $OutputPath).Path

Write-Section "Run Info"
Write-Line "Timestamp: $(Get-Date -Format o)"
Write-Line "ComputerName: $env:COMPUTERNAME"
Write-Line "User: $env:USERDOMAIN\$env:USERNAME"
Write-Line "PowerShell: $($PSVersionTable.PSVersion)"
Write-Line "Is64BitProcess: $([Environment]::Is64BitProcess)"
Write-Line "BaseUrl: $($BaseUrl -join ', ')"
Write-Line "SinceHours: $SinceHours"
Write-Line "SkipEventLogs: $SkipEventLogs"
Write-Line "SkipHttpChecks: $SkipHttpChecks"
try {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    Write-Line "IsAdministrator: $($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
}
catch {
    Write-Line "IsAdministrator: unavailable ($($_.Exception.Message))"
}

Write-Section "PowerShell Command/Module Availability"
Safe-Command "Command/module availability" {
    foreach ($commandName in @("Get-CimInstance", "Get-WmiObject", "Get-WinEvent", "Invoke-WebRequest", "Get-WindowsFeature", "Get-WebHandler", "Get-WebConfiguration", "Get-WebConfigurationProperty")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            Write-Line "Command available: $commandName ($($command.CommandType))"
        }
        else {
            Write-Line "Command missing: $commandName"
        }
    }

    foreach ($moduleName in @("WebAdministration", "ServerManager", "IISAdministration")) {
        $module = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($module) {
            Write-Line "Module available: $moduleName version=$($module.Version) path=$($module.Path)"
        }
        else {
            Write-Line "Module missing: $moduleName"
        }
    }

    $appCmdPath = Join-Path $env:windir "System32\inetsrv\appcmd.exe"
    Write-Line "appcmd.exe path: $appCmdPath exists=$(Test-Path $appCmdPath)"
}

Write-Section "OS"
Safe-Command "OS info" {
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        Get-CimInstance Win32_OperatingSystem |
            Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime |
            Format-List | Out-String | Write-Line
    }
    elseif (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
        Get-WmiObject Win32_OperatingSystem |
            Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime |
            Format-List | Out-String | Write-Line
    }
    else {
        Write-Line "Neither Get-CimInstance nor Get-WmiObject is available."
    }
}

Write-Section "IIS Discovery"
$script:iisAvailable = $false
$candidatePaths = New-Object System.Collections.Generic.List[string]
$script:iisLocationsToInspect = New-Object System.Collections.Generic.List[object]
$script:DetectedSynergyPath = $null

function Add-IisLocationToInspect {
    param(
        [string]$SiteName,
        [string]$AppPath,
        [string]$PhysicalPath
    )

    if (-not $SiteName) { return }

    $location = $SiteName
    if ($AppPath -and $AppPath -ne "/") {
        $location = "$SiteName$AppPath"
    }

    foreach ($existing in $script:iisLocationsToInspect) {
        if ($existing.Location -eq $location) { return }
    }

    $script:iisLocationsToInspect.Add((New-Object PSObject -Property @{
        SiteName = $SiteName
        AppPath = $AppPath
        PhysicalPath = $PhysicalPath
        Location = $location
    })) | Out-Null
}

function Test-LooksLikeSynergyPath {
    param(
        [string]$AppPath,
        [string]$PhysicalPath,
        [string]$SiteName
    )

    if (($AppPath -match '(?i)synergy|exact') -or
        ($PhysicalPath -match '(?i)synergy|exact') -or
        ($SiteName -match '(?i)synergy|exact')) {
        return $true
    }

    if ($PhysicalPath) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($PhysicalPath)
        $metadataSvc = Join-Path $expandedPath "Services\Exact.Metadata.svc"
        $entitySvc = Join-Path $expandedPath "Services\Exact.Entity.REST.svc"
        if (Test-Path $metadataSvc -or Test-Path $entitySvc) {
            return $true
        }
    }

    return $false
}

Safe-Command "Import WebAdministration" {
    Import-Module WebAdministration -ErrorAction Stop
    $script:iisAvailable = $true
}

if ($script:iisAvailable) {
    Safe-Command "IIS sites/applications" {
        Get-ChildItem IIS:\Sites | ForEach-Object {
            $site = $_
            Write-Line "Site: $($site.Name)"
            Write-Line "  State: $($site.State)"
            Write-Line "  PhysicalPath: $($site.physicalPath)"
            Write-Line "  Bindings:"
            $site.Bindings.Collection | ForEach-Object {
                Write-Line "    $($_.protocol) $($_.bindingInformation)"
            }

            Get-WebApplication -Site $site.Name | ForEach-Object {
                Write-Line "  Application: $($_.Path)"
                Write-Line "    AppPool: $($_.applicationPool)"
                Write-Line "    PhysicalPath: $($_.PhysicalPath)"
                if (Test-LooksLikeSynergyPath -SiteName $site.Name -AppPath $_.Path -PhysicalPath $_.PhysicalPath) {
                    $candidatePaths.Add($_.PhysicalPath)
                    Add-IisLocationToInspect -SiteName $site.Name -AppPath $_.Path -PhysicalPath $_.PhysicalPath
                }
            }

            if (Test-LooksLikeSynergyPath -SiteName $site.Name -AppPath "/" -PhysicalPath $site.physicalPath) {
                $candidatePaths.Add($site.physicalPath)
                Add-IisLocationToInspect -SiteName $site.Name -AppPath "/" -PhysicalPath $site.physicalPath
            }
        }
    }

    Safe-Command "Application pools" {
        Get-ChildItem IIS:\AppPools | ForEach-Object {
            Write-Line "AppPool: $($_.Name)"
            Write-Line "  State: $($_.State)"
            Write-Line "  ManagedRuntimeVersion: $($_.managedRuntimeVersion)"
            Write-Line "  ManagedPipelineMode: $($_.managedPipelineMode)"
            Write-Line "  Enable32BitAppOnWin64: $($_.enable32BitAppOnWin64)"
            Write-Line "  AutoStart: $($_.autoStart)"
            Write-Line "  IdentityType: $($_.processModel.identityType)"
            if ($_.processModel.userName) {
                Write-Line "  IdentityUserName: $($_.processModel.userName)"
            }
        }
    }

    Safe-Command "SVC handler mappings" {
        Get-WebHandler |
            Where-Object { $_.Path -like "*.svc" -or $_.Name -match "(?i)svc|WCF" } |
            Select-Object Name, Path, Verb, Modules, ScriptProcessor, ResourceType |
            Format-Table -AutoSize | Out-String -Width 240 | Write-Line
    }

    Write-Section "IIS Authentication Settings"
    Safe-Command "IIS authentication settings" {
        if ($script:iisLocationsToInspect.Count -eq 0) {
            Write-Line "No Synergy/Exact IIS application location was detected for authentication inspection."
        }

        foreach ($iisLocation in $script:iisLocationsToInspect) {
            Write-Line "Location: $($iisLocation.Location)"
            Write-Line "  PhysicalPath: $($iisLocation.PhysicalPath)"

            foreach ($authName in @("anonymousAuthentication", "windowsAuthentication", "basicAuthentication")) {
                try {
                    $enabledProperty = Get-WebConfigurationProperty `
                        -PSPath "MACHINE/WEBROOT/APPHOST" `
                        -Location $iisLocation.Location `
                        -Filter "system.webServer/security/authentication/$authName" `
                        -Name enabled

                    if ($enabledProperty -and $enabledProperty.PSObject.Properties["Value"]) {
                        $enabledValue = $enabledProperty.Value
                    }
                    else {
                        $enabledValue = $enabledProperty
                    }

                    Write-Line "  $authName enabled: $enabledValue"
                }
                catch {
                    Write-Line "  $authName enabled: unavailable ($($_.Exception.Message))"
                }
            }

            try {
                $providers = Get-WebConfiguration `
                    -PSPath "MACHINE/WEBROOT/APPHOST" `
                    -Location $iisLocation.Location `
                    -Filter "system.webServer/security/authentication/windowsAuthentication/providers/add" |
                    ForEach-Object { $_.value }
                Write-Line "  windowsAuthentication providers: $($providers -join ', ')"
            }
            catch {
                Write-Line "  windowsAuthentication providers: unavailable ($($_.Exception.Message))"
            }
        }
    }
}
else {
    Write-Line "WebAdministration module not available; IIS details could not be collected."

    Write-Section "IIS appcmd.exe Fallback"
    Safe-Command "appcmd fallback" {
        $appCmdPath = Join-Path $env:windir "System32\inetsrv\appcmd.exe"
        if (-not (Test-Path $appCmdPath)) {
            Write-Line "appcmd.exe not found at $appCmdPath."
        }
        else {
            Write-Line "appcmd.exe found at $appCmdPath. Collecting read-only IIS summaries."
            & $appCmdPath list site /text:* 2>&1 | Out-String -Width 240 | Write-Line
            & $appCmdPath list app /text:* 2>&1 | Out-String -Width 240 | Write-Line
            & $appCmdPath list apppool /text:* 2>&1 | Out-String -Width 240 | Write-Line
            & $appCmdPath list config /section:system.webServer/handlers 2>&1 |
                Select-String -Pattern '(?i)\.svc|WCF|svc-' |
                Out-String -Width 240 | Write-Line
            & $appCmdPath list config /section:system.webServer/security/authentication/windowsAuthentication 2>&1 |
                Out-String -Width 240 | Write-Line
            & $appCmdPath list config /section:system.webServer/security/authentication/anonymousAuthentication 2>&1 |
                Out-String -Width 240 | Write-Line
        }
    }
}

if (-not $SynergyPath -and $candidatePaths.Count -gt 0) {
    $SynergyPath = $candidatePaths |
        Where-Object { $_ -match '(?i)synergy' } |
        Select-Object -First 1

    if (-not $SynergyPath) {
        $SynergyPath = $candidatePaths | Select-Object -First 1
    }
}

if (-not $SynergyPath) {
    Write-Section "Synergy Path Fallback Search"
    Safe-Command "Synergy path fallback search" {
        $searchRoots = @(
            "C:\inetpub",
            "D:\inetpub",
            "C:\Program Files\Exact Software",
            "C:\Program Files (x86)\Exact Software",
            "C:\Program Files\Exact",
            "C:\Program Files (x86)\Exact"
        ) | Where-Object { Test-Path $_ }

        if ($searchRoots.Count -eq 0) {
            Write-Line "No common Synergy installation roots found for fallback search."
        }

        foreach ($searchRoot in $searchRoots) {
            Write-Line "Searching for Exact.Metadata.svc under $searchRoot ..."
            $foundSvc = Get-ChildItem -Path $searchRoot -Recurse -File -Filter "Exact.Metadata.svc" -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($foundSvc) {
                $servicesFolder = Split-Path -Parent $foundSvc.FullName
                $detectedRoot = Split-Path -Parent $servicesFolder
                Write-Line "Found Exact.Metadata.svc: $($foundSvc.FullName)"
                Write-Line "Detected Synergy root: $detectedRoot"
                $script:DetectedSynergyPath = $detectedRoot
                break
            }
        }
    }

    if ($script:DetectedSynergyPath) {
        $SynergyPath = $script:DetectedSynergyPath
    }
}

Write-Section "Synergy Path"
if ($SynergyPath) {
    $expandedSynergyPath = [Environment]::ExpandEnvironmentVariables($SynergyPath)
    Write-Line "Input/Detected SynergyPath: $SynergyPath"
    Write-Line "Expanded SynergyPath: $expandedSynergyPath"
    Write-Line "Exists: $(Test-Path $expandedSynergyPath)"
}
else {
    Write-Line "No Synergy path detected. Re-run with -SynergyPath if needed."
}

if ($SynergyPath) {
    $root = [Environment]::ExpandEnvironmentVariables($SynergyPath)
    $services = Join-Path $root "Services"

    Write-Section "Synergy Service Files"
    Safe-Command "Service files" {
        Write-Line "Services path: $services"
        Write-Line "Services path exists: $(Test-Path $services)"

        if (Test-Path $services) {
            $serviceNames = @(
                "Exact.Entity.REST.svc",
                "Exact.Entities.svc",
                "Exact.Metadata.svc",
                "Exact.RequestFlow.REST.svc",
                "Exact.DocumentFlow.REST.svc",
                "Exact.ResourceFlow.REST.svc",
                "Exact.AccountFlow.REST.svc"
            )

            foreach ($name in $serviceNames) {
                $path = Join-Path $services $name
                if (Test-Path $path) {
                    $item = Get-Item $path
                    Write-Line "FOUND $name | Length=$($item.Length) | LastWriteTime=$($item.LastWriteTime)"
                }
                else {
                    Write-Line "MISSING $name"
                }
            }
        }
    }

    Write-Section "Relevant DLLs"
    Safe-Command "Relevant DLLs" {
        $dllPatterns = @(
            "Exact.Services.REST.ESE*.dll",
            "Exact.DocumentFlow*.dll",
            "Exact.RequestFlow*.dll",
            "Exact.ResourceFlow*.dll",
            "Exact.AccountFlow*.dll",
            "Exact.Services*.dll"
        )

        foreach ($pattern in $dllPatterns) {
            Write-Line "Pattern: $pattern"
            Get-ChildItem -Path $root -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
                Select-Object FullName, Length, LastWriteTime |
                Format-Table -AutoSize | Out-String -Width 240 | Write-Line
        }
    }

    Write-Section "Relevant Config Files"
    Safe-Command "Config files" {
        $configPatterns = @(
            "web.config",
            "Exact.Metadata.config",
            "Exact*.config",
            "*.svc"
        )

        foreach ($pattern in $configPatterns) {
            Write-Line "Pattern: $pattern"
            Get-ChildItem -Path $root -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
                Select-Object FullName, Length, LastWriteTime |
                Format-Table -AutoSize | Out-String -Width 260 | Write-Line
        }
    }

    Write-Section "Config Content Markers Redacted"
    Safe-Command "Config content markers" {
        $configs = @()
        foreach ($pattern in @("web.config", "Exact*.config")) {
            $configs += Get-ChildItem -Path $root -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
        }

        $configs = $configs | Sort-Object FullName -Unique
        foreach ($config in $configs) {
            Write-Line "File: $($config.FullName)"
            $matches = Select-String -Path $config.FullName -Pattern "connectionString|providerName|metadata|authorization|baco|DataService|Entity|DocumentFlow|RequestFlow|password|pwd|secret|token" -CaseSensitive:$false -ErrorAction SilentlyContinue
            foreach ($match in $matches) {
                Write-Line ("  L{0}: {1}" -f $match.LineNumber, (Shorten-Text (Redact-Text $match.Line.Trim()) 1000))
            }
        }
    }

    Write-Section "ACL Summary"
    Safe-Command "ACL summary" {
        $aclTargets = @($root, $services)
        foreach ($pattern in @("web.config", "Exact*.config")) {
            $aclTargets += Get-ChildItem -Path $root -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
        }

        $aclTargets = $aclTargets | Sort-Object -Unique
        foreach ($target in $aclTargets) {
            if (Test-Path $target) {
                Write-Line "ACL: $target"
                (Get-Acl $target).Access |
                    Select-Object IdentityReference, FileSystemRights, AccessControlType, IsInherited |
                    Format-Table -AutoSize | Out-String -Width 240 | Write-Line
            }
        }
    }
}

Write-Section "Windows Feature State"
Safe-Command "Windows features" {
    Import-Module ServerManager -ErrorAction Stop
    $featureNames = @(
        "Web-Server",
        "Web-WebServer",
        "Web-Windows-Auth",
        "Web-Basic-Auth",
        "Web-Asp-Net",
        "Web-Asp-Net45",
        "Web-Net-Ext",
        "Web-Net-Ext45",
        "Web-ISAPI-Ext",
        "Web-ISAPI-Filter",
        "NET-Framework-Core",
        "NET-Framework-45-Core",
        "NET-WCF-HTTP-Activation45",
        "NET-WCF-TCP-PortSharing45"
    )

    Get-WindowsFeature -Name $featureNames -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, InstallState |
        Format-Table -AutoSize | Out-String -Width 240 | Write-Line
}

Write-Section "Installed Components Search"
Safe-Command "Installed components" {
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($uninstallRoot in $uninstallRoots) {
        Get-ItemProperty $uninstallRoot -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "(?i)Exact|Synergy|WCF Data Services|Data Services|\.NET"
            } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
            Sort-Object DisplayName |
            Format-Table -AutoSize | Out-String -Width 240 | Write-Line
    }
}

Write-Section "Local SQL Server Clues (Read-Only)"
Safe-Command "Local SQL services" {
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(MSSQL|SQL)' -or $_.DisplayName -match '(?i)SQL Server' } |
        Select-Object Name, DisplayName, Status, StartType |
        Sort-Object Name |
        Format-Table -AutoSize | Out-String -Width 240 | Write-Line
}

Safe-Command "Local SQL registry login modes" {
    $instanceNamesPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
    if (-not (Test-Path $instanceNamesPath)) {
        Write-Line "No local SQL Server instance-name registry key found at $instanceNamesPath."
    }
    else {
        $instanceNames = Get-ItemProperty $instanceNamesPath
        $instanceNames.PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS' } |
            ForEach-Object {
                $instanceName = $_.Name
                $instanceId = $_.Value
                $serverKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"
                $loginMode = $null

                if (Test-Path $serverKey) {
                    $loginMode = (Get-ItemProperty $serverKey -ErrorAction SilentlyContinue).LoginMode
                }

                $loginModeText = switch ($loginMode) {
                    1 { "Windows Authentication only" }
                    2 { "Mixed Mode" }
                    default { "Unknown/not found" }
                }

                Write-Line "Instance: $instanceName | Id: $instanceId | LoginMode: $loginMode ($loginModeText)"
            }
    }
}

Write-Section ".NET Framework Registry"
Safe-Command ".NET Framework registry" {
    Get-ChildItem "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP" -Recurse -ErrorAction SilentlyContinue |
        Get-ItemProperty -Name Version, Release -ErrorAction SilentlyContinue |
        Select-Object PSChildName, Version, Release |
        Format-Table -AutoSize | Out-String -Width 160 | Write-Line
}

if (-not $SkipEventLogs) {
    Write-Section "Recent Relevant Event Log Entries"
    Safe-Command "Recent event logs" {
        $since = (Get-Date).AddHours(-1 * [Math]::Abs($SinceHours))
        $eventPattern = '(?i)Exact|Synergy|ASP\.NET|\.NET Runtime|Application Error|W3SVC|WAS|IIS|Windows Process Activation'

        foreach ($logName in @("Application", "System")) {
            Write-Line "Log: $logName since $since"
            $events = Get-WinEvent -FilterHashtable @{
                    LogName = $logName
                    StartTime = $since
                    Level = @(1, 2, 3)
                } -ErrorAction SilentlyContinue |
                Where-Object { $_.ProviderName -match $eventPattern -or $_.Message -match $eventPattern } |
                Select-Object -First 80

            foreach ($event in $events) {
                Write-Line ("[{0}] Id={1} Level={2} Provider={3}" -f $event.TimeCreated, $event.Id, $event.LevelDisplayName, $event.ProviderName)
                Write-Line ("  Message: {0}" -f (Shorten-Text (Redact-Text $event.Message) 2000))
            }
        }
    }
}

if (-not $SkipHttpChecks) {
    Write-Section "HTTP Local Service Checks"
    Safe-Command "Local HTTP checks" {
    $baseCandidates = New-Object System.Collections.Generic.List[string]
    $baseCandidates.Add("http://localhost/Synergy") | Out-Null
    $baseCandidates.Add("http://$env:COMPUTERNAME/Synergy") | Out-Null

    foreach ($configuredBaseUrl in $BaseUrl) {
        if ($configuredBaseUrl) {
            $baseCandidates.Add($configuredBaseUrl.TrimEnd("/")) | Out-Null
        }
    }

    foreach ($base in $baseCandidates) {
        foreach ($path in @(
            "services/Exact.Metadata.svc",
            "services/Exact.Metadata.svc?wsdl",
            "services/Exact.Entities.svc?wsdl",
            "services/Exact.Entity.REST.svc/",
            'services/Exact.Entity.REST.svc/$metadata',
            "services/Exact.DocumentFlow.REST.svc/",
            'services/Exact.DocumentFlow.REST.svc/$metadata',
            "services/Exact.RequestFlow.REST.svc/",
            'services/Exact.RequestFlow.REST.svc/$metadata'
        )) {
            $uri = "$base/$path"
            try {
                $response = Invoke-WebRequest -Uri $uri -UseDefaultCredentials -UseBasicParsing -Method GET -TimeoutSec 10
                Write-Line "$uri -> HTTP $($response.StatusCode) type=$($response.Headers['Content-Type']) bytes=$($response.RawContentLength) server=$($response.Headers['Server']) dataservice=$($response.Headers['DataServiceVersion'])"
            }
            catch {
                $status = ""
                $contentType = ""
                $location = ""
                $auth = ""
                if ($_.Exception.Response) {
                    try { $status = "HTTP " + [int]$_.Exception.Response.StatusCode } catch {}
                    try { $contentType = $_.Exception.Response.Headers["Content-Type"] } catch {}
                    try { $location = $_.Exception.Response.Headers["Location"] } catch {}
                    try { $auth = $_.Exception.Response.Headers["WWW-Authenticate"] } catch {}
                }
                Write-Line "$uri -> FAILED $status type=$contentType location=$location auth=$auth error=$($_.Exception.Message)"
            }
        }
    }
    }
}
else {
    Write-Section "HTTP Local Service Checks"
    Write-Line "Skipped by -SkipHttpChecks."
}

Write-Section "Done"
Write-Line "Diagnostics written to: $script:OutputPath"

Write-Host "Diagnostics written to: $script:OutputPath"
