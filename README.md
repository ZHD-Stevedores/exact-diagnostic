# Exact Synergy Enterprise Diagnostics

Read-only PowerShell diagnostics for Exact Synergy Enterprise webservice hosting.

The script is intended for system administrators who need to collect first-pass evidence from a Synergy webserver without changing IIS, SQL Server, Exact configuration, application files, or live data.

## What It Collects

- PowerShell command/module availability
- OS and PowerShell version details
- IIS sites, bindings, applications, app pools, and app pool identities
- IIS authentication settings and Windows Authentication providers
- `.svc` handler mappings, with an `appcmd.exe` fallback if the IIS PowerShell module is unavailable
- Synergy service file presence, including common `Exact.*.svc` endpoints
- Relevant Exact/Synergy DLL and config file metadata
- Redacted config markers around metadata, entity services, authorization, DocumentFlow, RequestFlow, and connection strings
- ACL summaries for the Synergy root, services folder, and relevant config files
- Windows feature state for IIS, ASP.NET, .NET, and WCF pieces
- Installed Exact/.NET/WCF-related components
- Local SQL Server clues from services and registry only
- SQL server names parsed from Exact/Synergy connection strings, with credentials redacted
- SQL Client Alias registry entries, if present
- DNS/TCP reachability checks to parsed SQL server hosts, without logging into SQL Server
- Recent relevant Application/System event log errors
- Local HTTP checks against common Exact Synergy service endpoints

## Safety

The script is read-only. It does not:

- modify IIS
- modify SQL Server
- modify Exact/Synergy configuration
- write to application folders
- create or change Exact/Synergy records
- require or use SQL credentials
- query SQL databases

The output can still contain server names, filesystem paths, app pool identities, installed component versions, and event log excerpts. Review the generated output before sharing it outside your organization.

## License

Copyright (c) 2026 ZHD (zhd.nl).

This repository is source-available under the PolyForm Internal Use License 1.0.0. You may use and modify it for internal business operations, including internal diagnostics and troubleshooting. You may not redistribute it, sublicense it, or embed/bundle it into a commercial product or service without prior written permission from ZHD.

See [LICENSE](LICENSE) for the full terms.

## Usage

Run from an elevated PowerShell prompt on the Exact Synergy Enterprise webserver. This is the recommended default command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -BaseUrl "http://server.example.local/Synergy"
```

The script is non-interactive. It does not ask for usernames or passwords. If a module, path, permission, or endpoint is unavailable, the script records that in the output and continues.

## Advanced Options

Most administrators do not need these options. Use them only when the default command is not enough.

If the Synergy path is not detected automatically:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SynergyPath "C:\inetpub\wwwroot\Synergy"
```

To run without specifying a base URL:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1
```

To collect more event log history:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SinceHours 168
```

If a smaller run is preferred:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SkipEventLogs -SkipHttpChecks
```

To skip SQL network reachability checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-ExactSynergyDiagnostics.ps1 -SkipSqlNetworkChecks
```

## Output

The script writes a timestamped text file in the current directory:

```text
ExactSynergyDiagnostics-YYYYMMDD-HHMMSS.txt
```

Send that file to the engineer or vendor investigating the webservice issue.

## Notes

This tool is diagnostic only. It does not decide whether the problem is an Exact functional setup issue, an IIS/WCF hosting issue, a SQL connectivity issue, or an account/permissions issue. It collects enough evidence to make that next conversation more precise.
