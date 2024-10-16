# Usage

## Parameters

| Parameter         | Description                                               |
| ----------------- | --------------------------------------------------------- |
| `-ConfigFile`     | Specifies the path to the configuration file.             |
| `-EnableSmtp`     | Sends the results via email using SMTP.                   |
| `-Install`        | Add the SPSWeather script in task scheduler               |
| `-InstallAccount` | Specifies the service account who runs the scheduled task |
| `-Uninstall`      | Remove the SPSWeather script from task scheduler          |

### Basic Usage Example

```powershell
.\SPSWeather.ps1 -ConfigFile 'contoso-PROD.json'
```

### Enable Email Notifications Example

```powershell
.\SPSWeather.ps1 -ConfigFile 'contoso-PROD.json' -EnableSmtp
```

### Installation Usage Example

```powershell
.\SPSWeather.ps1 -ConfigFile 'contoso-PROD.json' -Install -InstallAccount (Get-Credential)
```

### Uninstallation Usage Example

```powershell
.\SPSWeather.ps1 -ConfigFile 'contoso-PROD.json' -Uninstall
```
