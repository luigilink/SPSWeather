# Health Checks

This page lists every check SPSWeather runs against each farm in scope, what it reports, and the `ExclusionRules` key that disables it (see [Configuration → ExclusionRules](Configuration#exclusionrules)).

## SharePoint checks

| Check | Reports | ExclusionRules key |
|---|---|---|
| SharePoint version | Build/version of each SharePoint server | _(always)_ |
| Servers | The SharePoint servers of the farm | _(always)_ |
| Upgrade status | Whether a configuration upgrade action is required | _(always)_ |
| Health Analyzer | Failing Health Analyzer rules surfaced in Central Administration | `HealthStatus` |
| Trust farm API | HTTP status of the trusted-farm REST API | `APIHttpStatus` |
| Site collections | HTTP status of the monitored site collections | `SPSiteHttpStatus` |
| Failed timer jobs | Timer-job failures over a lookback window, with a failure-ratio threshold | `FailedTimerJob` |
| Solutions (WSP) | Farm solution deployment status | `WSPStatus` |
| Content databases | Status and size of each content database | _(always)_ |
| User Profile audiences | Audience compilation status | _(always)_ |

## Search checks

| Check | Reports | ExclusionRules key |
|---|---|---|
| Crawl status | Last crawl status per content source | _(always)_ |
| Crawl logs | Crawl log error/warning counts | _(always)_ |
| Search topology | State of the search topology components | _(always)_ |

## System / IIS checks

| Check | Reports | ExclusionRules key |
|---|---|---|
| Distributed Cache | AppFabric / Distributed Cache instance status | _(always)_ |
| IIS application pools | State of the IIS application pools | _(always)_ |
| IIS worker processes | `w3wp.exe` resource usage | `IISW3WPStatus` |
| IIS site certificates | TLS certificate validity/expiry per IIS site | _(always)_ |
| Last reboot | Last reboot time of each server | _(always)_ |
| .NET version | Installed .NET Framework version | _(always)_ |
| Application event errors | Recent errors in the Windows Application event log | `EvtViewerStatus` |
| Disk usage | Drive size and free space | _(always)_ |

## How an ALERT is raised

Every check returns rows flagged as informational or not (an internal `IsInfo` flag). When **any** collected check contains at least one **non-informational (failed)** row, SPSWeather:

- tags the email subject with `[ALERT]` (otherwise `[INFO]`), and
- raises the email priority to **High**, and
- writes a **Warning** (event ID 2000) to the [SPSWeather Event Log](Usage#windows-event-log).

In the HTML report, failing rows use the `tdfailed` (red) style, below-threshold timer-job failures use `tdwarning` (orange), and healthy rows use `tdsuccess` (green).

## Disabling checks

Add the corresponding key to `ExclusionRules` in your config to skip a check. Authorized values:

`None`, `APIHttpStatus`, `SPSiteHttpStatus`, `EvtViewerStatus`, `IISW3WPStatus`, `HealthStatus`, `WSPStatus`, `FailedTimerJob`.

Checks marked _(always)_ above are not individually excludable.

## See also

- [Configuration](Configuration) — the `config.psd1` reference
- [Usage](Usage) — running, scheduling, the event log and troubleshooting
