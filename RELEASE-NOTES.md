# SPSWeather - Release Notes

## [3.2.0] - 2026-11-13

### Changed

- The short alert email now lists at most **10 items per area**; the remainder is
  summarized as "+ N more (X failures, Y warnings)" with a pointer to the dashboard.
  Failures are listed before warnings, and every counter (KPI strip, intro sentence, area
  header, subject, outcome) still counts all items. The dashboard keeps the full list.
  Set `EmailMaxItemsPerArea` in the environment config (or `-MaxItemsPerArea` on
  `ConvertTo-SPSWeatherEmailBody`) to change the limit; `0` lists everything, as before.
- The test suite is split into one test file per function with broader mock-based coverage,
  and CI now also runs it under Windows PowerShell 5.1 (the production runtime) and analyzes
  all first-party code with PSScriptAnalyzer. No change to shipped module behavior.

### Fixed

- SQL alias mapping: declaring the real SQL server in `Farms[].SqlServers` while SharePoint
  reaches it through cliconfg aliases no longer produces the contradictory "used by
  SharePoint but not declared in config" / "declared in config but not used by any database"
  notes. A declared entry now matches either the alias name or the real server the alias
  resolves to (TCP and named-pipe aliases); a named instance must still match exactly.
- An unreachable server is now counted as a **failure** in the Event Log errors section, like
  in every other section (it was only a warning there).

### Upgrade notes

- No configuration change is required.
- The alert email is shorter by default (10 items per area). If you prefer the previous
  exhaustive list, add `EmailMaxItemsPerArea = 0` to your environment config.
- Counters can shift: each unreachable server now adds one failure (instead of one warning)
  in the Event Log section, so the failure/warning totals of such a run change accordingly.
  The overall outcome is usually unchanged, because the other per-server sections already
  reported that server as a failure.

A full list of changes can be found in the [change log](CHANGELOG.md).
