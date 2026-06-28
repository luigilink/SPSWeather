# SPSWeather - Release Notes

## [2.1.0] - 2026-06-28

A feature release: SQL Server health checks, a pre-flight readiness script, a
testable report assembly, and per-farm resilience.

### Added

- **SQL Server health checks** (`Get-SPSSqlStatus`), collected from a SharePoint
  server with **dependency-free ADO.NET** (no `SqlServer` module required). The
  SQL servers are discovered from `Get-SPDatabase`, so the checks follow the
  farm's own databases. Four new report sections (and `ExclusionRules` keys):
  - `SQLInstanceStatus` - edition/version/build, MAXDOP, max server memory,
    TempDB file count vs CPUs.
  - `SQLDatabaseStatus` - state, recovery model, data/log size, last full backup
    age, compatibility level, AutoShrink/AutoClose.
  - `SQLDiskStatus` - free space per SQL volume (`sys.dm_os_volume_stats`).
  - `SQLAvailabilityStatus` - AlwaysOn AG sync health and recent failed SQL Agent
    jobs.
  Thresholds `SQLDiskFreeThresholdPercent` (default 15) and `SQLBackupMaxAgeDays`
  (default 3) are configurable. The service account needs `VIEW SERVER STATE`
  plus read access to `master`/`msdb`.
- **`Test-SPSWeatherReadiness.ps1`** - a read-only pre-flight check (config,
  secrets DPAPI decryptability, Administrator rights, per-farm WinRM/CredSSP
  reachability).
- **Per-farm resilience** - an unreachable farm server is logged (SPSWeather
  event ID 3001) and skipped instead of aborting the whole run.

### Changed

- The report assembly moved into a testable `ConvertTo-SPSWeatherReport` module
  function (identical output), replacing ~140 repeated lines in `SPSWeather.ps1`.

### Notes

- No configuration or credential change is required to upgrade from 2.0.x. The
  SQL sections appear automatically; add their `ExclusionRules` keys to opt out.

A full list of changes can be found in the [change log](CHANGELOG.md).
