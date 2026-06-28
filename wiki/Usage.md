# Usage

## Parameters

| Parameter | Description |
|---|---|
| `-ConfigFile` | Path to the environment configuration `.psd1` file. |
| `-EnableSmtp` | Send the HTML report by email over SMTP. |
| `-Install` | Register SPSWeather as a scheduled task and store the service credential in `secrets.psd1`. |
| `-InstallAccount` | The service account that runs the scheduled task (required with `-Install`). |
| `-Uninstall` | Remove the SPSWeather scheduled task and the stored secret. |

### Basic run

```powershell
.\SPSWeather.ps1 -ConfigFile 'Config\contoso-PROD.psd1'
```

### Run and email the report

```powershell
.\SPSWeather.ps1 -ConfigFile 'Config\contoso-PROD.psd1' -EnableSmtp
```

### Install the scheduled task

Run this **as the service account** so the stored credential is decryptable at run time:

```powershell
.\SPSWeather.ps1 -ConfigFile 'Config\contoso-PROD.psd1' -Install -InstallAccount (Get-Credential)
```

### Uninstall

```powershell
.\SPSWeather.ps1 -ConfigFile 'Config\contoso-PROD.psd1' -Uninstall
```

## Output

Each run writes, next to `SPSWeather.ps1`:

- `Results\<app>-<env>-<date>.html` — the HTML report (also used as the email body).
- `Results\<app>-<env>-<date>.json` — a JSON snapshot of the collected data.
- `Logs\<app>-<env>-<date>.log` — the PowerShell transcript. Logs older than the retention window are pruned automatically.

The email subject is prefixed with the overall status, e.g. `[ALERT]contoso_PROD - Meteo SharePoint <date>`. The priority is raised to **High** when an alert is detected.

## Windows Event Log

SPSWeather writes lifecycle entries to a dedicated **`SPSWeather`** Windows Event Log (created on first use; requires the run to be elevated):

| Event ID | Type | Meaning |
|---|---|---|
| 1000 | Information | A health-check run started. |
| 1001 | Information | The run completed with no alert. |
| 2000 | Warning | The run completed with **ALERT** conditions. |
| 3000 | Error | The report email could not be sent. |

Filter the log in Event Viewer (or via `Get-WinEvent -LogName SPSWeather`) to monitor runs across servers; each entry carries a header with the SPSWeather version, user and computer name.

## Scheduling

`-Install` registers a scheduled task named `SPSWeather-<app>-<env>` that runs `SPSWeather.ps1 -ConfigFile <file> -EnableSMTP` as the service account. Adjust the trigger in Task Scheduler to your preferred cadence.

## Next step

For maintainers, see the [Release Process](Release-Process).
