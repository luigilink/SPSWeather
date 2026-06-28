# SPSWeather - Release Notes

## [2.2.0] - 2026-06-28

A feature release: SQL client alias (cliconfg) resolution and per-farm SQL
declaration.

### Added

- **SQL alias resolution.** SharePoint best practice reaches SQL through cliconfg
  client aliases, so `Get-SPDatabase` returns the alias, not the real server.
  SPSWeather now resolves each alias from the registry (64-bit `ConnectTo` and
  32-bit `Wow6432Node`) to the real **server\instance, protocol, port and
  bitness**, shown in a new **SQL - Alias Mapping** report table (new
  `SQLAliasStatus` ExclusionRules key and a `Resolve-SPSSqlAlias` function).
- **Per-farm SQL declaration.** You can declare the SQL alias(es)/server(s) a farm
  uses with an optional `SqlServers` array in the config. SPSWeather cross-checks
  **declared vs discovered** SQL servers and flags mismatches (and 32/64-bit alias
  inconsistencies) as advisories. Auto-discovery via `Get-SPDatabase` is kept; the
  connection still uses the alias name, exactly like SharePoint.

### Notes

- Backward compatible: the `SqlServers` key is optional; without it, SPSWeather
  behaves as in 2.1.0 (auto-discovery) and still resolves discovered aliases.
- Alias resolution (registry) and the SQL queries run on the SharePoint server;
  validate them on a real farm.

A full list of changes can be found in the [change log](CHANGELOG.md).
