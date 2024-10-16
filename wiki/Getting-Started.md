# Getting Started

## Prerequisites

- PowerShell 5.0 or later
- Administrative privileges on the SharePoint Server
- SMTP server configured (if using `EnableSmtp`)
- StoredCredential configured (if using `Install`)

## Installation

1. [Download the latest release](https://github.com/luigilink/SPSWeather/releases/latest) and unzip to a directory on your SharePoint Server.
2. Prepare your JSON configuration file with the required SMTP and farm details.
3. Add the script in task scheduler by running the following command:

```powershell
.\SPSWeather.ps1 -ConfigFile 'contoso-PROD.json' -Install -InstallAccount (Get-Credential)
```

> [!IMPORTANT]
> Configure the StoredCredential parameter in json before running the script in installation mode

## Next Step

For the next steps, go to the [Configuration](./Configuration) page.

## Change log

A full list of changes in each version can be found in the [change log](https://github.com/luigilink/SPSWeather/blob/main/CHANGELOG.md).
