# SPSWeather - Release Notes

## [2.0.1] - 2026-06-28

A patch release: one remoting correctness fix and dead-code cleanup.

### Fixed

- `Invoke-SPSCommand` no longer runs the SharePoint command on the **local**
  server when the CredSSP session cannot be opened. Previously, if
  `New-PSSession` failed (CredSSP misconfigured or the target unreachable), the
  scriptblock was executed locally and returned data for the wrong server. It now
  fails with a clear, server-scoped error.

### Removed

- Dead code: the orphaned `Get-SQLInstancesStatus` / `Get-SQLDatabasesStatus`
  public functions (never called and broken) and the unused private
  `Invoke-SPSWebRequestUrl` helper. A real SQL Server health check is planned for
  2.1.0.

### Notes

- No configuration or credential change since 2.0.0; this is a drop-in update.
- Per-farm resilience (continue when one farm server is unreachable) will land
  with the data-driven report refactor in 2.1.0.

A full list of changes can be found in the [change log](CHANGELOG.md).
