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
| Timer service instances | Status of the Timer service instance of every server of the farm: all must be `Online` (see below) | `TimerServiceStatus` |
| Failed timer jobs | Timer-job failures over a lookback window, with a failure-ratio threshold | `FailedTimerJob` |
| Solutions (WSP) | Farm solution deployment status | `WSPStatus` |
| Content databases | Status and size of each content database | _(always)_ |
| User Profile audiences | Audience compilation status | _(always)_ |

### Timer service instances

Every server of the farm must have its **Timer service instance** `Online`. SPSWeather lists one row per
instance (`(Get-SPFarm).TimerService.Instances`) in the *Timer Service - Instances* section of the
*Timer Jobs* card, and **any status other than `Online` is a failure**: a single instance in another
state breaks the communication between the servers, which notably blocks the deployment of a WSP (the job
that deploys it never runs on that server). A farm that returns no instance, or a query that fails, is also
reported as a failure (`No instance` / `Unreachable`), never as healthy.

The check is **read-only**: SPSWeather detects and reports, it never changes the status of an instance. The
manual check, and the fix that some administrators apply once the cause is understood (it changes the farm:
test it first), are:

```powershell
$farm = Get-SPFarm
$farm.TimerService.Instances | Select-Object @{ n = 'Server'; e = { $_.Server.Name } }, Status

$notOnline = $farm.TimerService.Instances | Where-Object { $_.Status -ne 'Online' }
foreach ($instance in $notOnline) {
    $instance.Status = [Microsoft.SharePoint.Administration.SPObjectStatus]::Online
    $instance.Update()
}
```

Add `TimerServiceStatus` to `ExclusionRules` to skip the check.

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

## SQL Server checks

SQL data is collected from a SharePoint server with dependency-free ADO.NET
(`System.Data.SqlClient` — no `SqlServer` module needed). The SQL servers are
discovered from `Get-SPDatabase`, so checks follow the farm's own databases. The
service account needs `VIEW SERVER STATE` and read access to `master`/`msdb`. An
unreachable instance produces a single red row instead of failing the run.

| Check | Reports | ExclusionRules key |
|---|---|---|
| Alias mapping | cliconfg alias → real server\instance, protocol (TCP/NP), port, bitness (32/64); declared-vs-discovered validation | `SQLAliasStatus` |
| Instances | Edition/version/build, MAXDOP (advisory if ≠ 1), max server memory, TempDB file count vs CPUs | `SQLInstanceStatus` |
| Databases | State, recovery model, data/log size, last full backup age, compatibility level, AutoShrink/AutoClose | `SQLDatabaseStatus` |
| Disk volumes | Free space per volume hosting SQL files (`sys.dm_os_volume_stats`) | `SQLDiskStatus` |
| Availability | AlwaysOn AG replica sync health and recent failed SQL Agent jobs | `SQLAvailabilityStatus` |

SharePoint best practice is to reach SQL through **cliconfg client aliases**, so
`Get-SPDatabase` returns the alias rather than the real server. The alias is
enough to connect (`System.Data.SqlClient` resolves it via SNI on the SharePoint
server, exactly like SharePoint), and SPSWeather additionally **resolves the
alias from the registry** to show the real target. You can optionally declare the
SQL alias(es)/server(s) per farm with a `SqlServers` array in the config; SPSWeather
then cross-checks **declared vs discovered** and flags any mismatch (and 32/64-bit
alias inconsistencies) as advisories. A declared entry matches either the alias name or
the real server the alias resolves to, so declaring the real SQL server is enough when
SharePoint reaches it through aliases (host names are compared case-insensitively on the
short name; a named instance must match exactly).

SQL alert thresholds are configurable in the environment config: `SQLDiskFreeThresholdPercent`
(default 15) and `SQLBackupMaxAgeDays` (default 3). Each key sits at the top level of the file and holds a
whole number of 0 or more; a value that cannot be used is reported (transcript, Event ID 2001) and the default
is applied. The footer of the dashboard says which configuration file was used and which values were applied,
with `(default)` next to a value that the file does not set. Database offline state, a
missing/old full backup, low volume free space, an unhealthy AG replica, a failed
backup job, or an unreachable instance raise an alert; best-practice deviations
(MAXDOP, memory, TempDB, AutoShrink/AutoClose) are shown as orange advisories
without raising the global alert.

## Capacity & limits

Since **3.6.0**, SPSWeather compares the farm with the supported limits of SharePoint: the data size of each content database, the site
collections per database, the content databases and web applications per farm, the managed paths, the memory of the Distributed Cache
hosts, the application pools per web server and the search topology. It is read-only, active by default, and it adds a row **only when
a threshold is reached** (section `SPSLimitStatus`, area *Capacity & limits*): a failure above the limit raises the alert, a warning
from 75 % of it does not. See [Limits](Limits) for the thresholds, the exceptions and how the size of a database is measured.

## How an ALERT is raised

Every check returns rows flagged as informational or not (an internal `IsInfo` flag). When **any** collected check contains at least one **non-informational (failed)** row, SPSWeather:

- tags the email subject with `[ALERT]` (otherwise `[INFO]`), and
- raises the email priority to **High**, and
- writes a **Warning** (event ID 2000) to the [SPSWeather Event Log](Usage#windows-event-log).

In the HTML report, failing rows use the `tdfailed` (red) style, below-threshold timer-job failures use `tdwarning` (orange), and healthy rows use `tdsuccess` (green).

## Disabling checks

Add the corresponding key to `ExclusionRules` in your config to skip a check. Authorized values:

`None`, `APIHttpStatus`, `SPSiteHttpStatus`, `EvtViewerStatus`, `IISW3WPStatus`, `HealthStatus`, `WSPStatus`, `FailedTimerJob`, `TimerServiceStatus`, `SQLAliasStatus`, `SQLInstanceStatus`, `SQLDatabaseStatus`, `SQLDiskStatus`, `SQLAvailabilityStatus`, `LimitStatus`.

Checks marked _(always)_ above are not individually excludable.

## The checks and the cockpit page

The [Cockpit page](Cockpit-Page) (`Dashboard.Cockpit = $true`) collects **nothing** from the farms: it counts what the runs have already recorded. It follows the rules of this page:
a check that is excluded with `ExclusionRules` is not collected, so it is absent from the counts, and the page lists the excluded checks (*Data quality* and *Settings & method* tabs) so that a
missing check is never mistaken for a healthy one.

## See also

- [Configuration](Configuration) — the `config.psd1` reference
- [Usage](Usage) — running, scheduling, the event log and troubleshooting
