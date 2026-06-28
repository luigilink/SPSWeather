# Getting Started

## Prerequisites

- **PowerShell 5.1** (Windows Management Framework 5.0 or above) on every farm server. SPSWeather uses class-based reporting types that require WMF 5.0+.
- **CredSSP** configured (see below) so the script can remote into each farm server as the service account.
- **Administrative privileges** on the server that runs SPSWeather (required to create the `SPSWeather` Windows Event Log on first use and to call most SharePoint cmdlets).
- An **SMTP server** reachable from the run server (only needed with `-EnableSmtp`).
- A **service account** that can reach the farms; its credential is stored in `Config\secrets.psd1` (see [Configuration](Configuration)).

## Configure CredSSP

### Option 1: Manually configure CredSSP

You can configure CredSSP with the relevant PowerShell cmdlets (and, if needed, group policy for the allowed delegate computers).

### Option 2: Configure CredSSP through a DSC resource

You can use the [xCredSSP](https://github.com/PowerShell/xCredSSP) DSC resource and include it in your SharePoint server configurations:

```powershell
xCredSSP CredSSPServer { Ensure = "Present"; Role = "Server" }
xCredSSP CredSSPClient { Ensure = "Present"; Role = "Client"; DelegateComputers = $CredSSPDelegates }
```

`$CredSSPDelegates` can be a wildcard (such as `*.contoso.com`) or a list of specific servers.

## Installation

1. [Download the latest release](https://github.com/luigilink/SPSWeather/releases/latest) and unzip it to a directory on your SharePoint Server. The archive extracts straight to `SPSWeather.ps1`, `Config\` and `Modules\` (the `SPSWeather.Common` module ships inside `Modules\`).
2. Copy `Config\CONTOSO-PROD.example.psd1` to your own config (e.g. `Config\contoso-PROD.psd1`) and edit it for your environment. See [Configuration](Configuration).
3. Register the scheduled task **while signed in as the service account** so the credential is encrypted under that account:

```powershell
.\SPSWeather.ps1 -ConfigFile 'Config\contoso-PROD.psd1' -Install -InstallAccount (Get-Credential)
```

> [!IMPORTANT]
> Run the `-Install` step as the **same account** you pass to `-InstallAccount`. The credential is stored in `Config\secrets.psd1` as a DPAPI SecureString that only that account, on that machine, can decrypt at run time.

## First run

Trigger a one-off run (with email) to validate the setup:

```powershell
.\SPSWeather.ps1 -ConfigFile 'Config\contoso-PROD.psd1' -EnableSmtp
```

The HTML report is written under `Results\` and, with `-EnableSmtp`, emailed to the configured recipients. Lifecycle events are written to the `SPSWeather` Windows Event Log.

## Next step

Continue with the [Configuration](Configuration) page.

## Change log

A full list of changes is in the [change log](https://github.com/luigilink/SPSWeather/blob/main/CHANGELOG.md).
