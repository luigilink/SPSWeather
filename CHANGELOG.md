# Change log for SPSWeather

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.3.6] - 2026-06-29

### Fixed

- `Get-AppFabricStatus` (SE branch) now reports the real cache Size in MB
  (e.g. '2048 MB') and the actual CachePort. `Get-SPCacheHostConfig` only
  returns its full payload when executed locally on the cache host after
  `Use-SPCacheCluster`; the function now does exactly that, opening a
  CredSSP session per cache host and calling `Get-SPCacheHostConfig
  -HostName $env:COMPUTERNAME` from inside. When the local lookup still
  fails, the row falls back to the SE cluster tier (Small/Medium/Large)
  suffixed ' (tier)'. The 2016/2019 (AppFabric) branch is unchanged
  (#51, #53).

## [2.3.6] - 2026-06-29

### Fixed

- Distributed Cache: the email body header for the cache size column is now
  'Size' (it was 'Size (MB)' but the value was the SE sizing tier - Small /
  Medium / Large - when Get-SPCacheHostConfig is null). The fallback value
  is now displayed as 'Small (tier)' / 'Medium (tier)' / ... to make clear
  it is not a raw MB number (#53).

## [2.3.5] - 2026-06-29

### Fixed

- `Get-AppFabricStatus` (SE branch) no longer reports a phantom 'Microsoft'
  cache host: v2.3.4 iterated `(Get-SPCacheClusterHealth).Hosts`, which is a
  collection of HostInfo objects whose `ToString()` starts with
  `Microsoft.SharePoint.Internal.Caching...`, yielding 'Microsoft' as a fake
  short name and pushing the real DC host into the 'Not a cache host' list.
  Iteration is back on `SPDistributedCacheServiceInstance` (Server.Address is
  the correct short name); `Get-SPCacheClusterInfo.Size` is still used for
  the cluster Size (#51).

## [2.3.4] - 2026-06-29

### Fixed

- `Get-AppFabricStatus` (SE branch) now uses `Get-SPCacheClusterHealth.Hosts`
  (canonical FQDN list) and `Get-SPCacheClusterInfo.Size` as the source of
  truth, instead of relying on `Get-SPCacheHostConfig` which returns null on
  several SE builds. Port/Size/ServiceName/CacheStatus degrade gracefully to
  the SP DC defaults (22233, AppFabricCachingService, Up when the SP service
  instance is Online) when `Get-SPCacheHostConfig` cannot resolve the host.
  Removes the dead AppFabric fallback added in 2.3.3 (those cmdlets are not
  present on SE) (#49).

## [2.3.3] - 2026-06-29

### Fixed

- `Get-AppFabricStatus` (SE branch) falls back to the historical AppFabric
  cmdlets (`Use-CacheCluster` + `Get-CacheHost` + `Get-AFCacheHostConfiguration`)
  when `Get-SPCacheHostConfig` returns null on Subscription Edition. Port / Size
  / ServiceName / CacheStatus are now populated on hosts where the SE-native
  cmdlet cannot resolve the host name (#47).

## [2.3.2] - 2026-06-29

### Fixed

- `Get-AppFabricStatus` (SE branch) iterates Distributed Cache hosts via
  `Get-SPServiceInstance` (filtered on `SPDistributedCacheServiceInstance`) and
  uses the instance's `Server.Address`, falling back to the short name when the
  cluster stores a different form. This fixes the missing Port / Size /
  ServiceName / CacheStatus on the actual DC host (typically a WFE) on
  SharePoint Subscription Edition (#45).

### Changed

- Farm servers that are not part of the Distributed Cache cluster are now
  reported as 'Not a cache host' (informational, `IsInfo = $true`) instead of
  a red 'SPService Not Found' alert, since hosting Distributed Cache on a
  subset of servers (often a single WFE) is a legitimate topology (#45).

## [2.3.1] - 2026-06-29

### Fixed

- `Clear-SPSLog` no longer filters on an undefined `$logFileName` variable (which
  resolved to `*`, accidentally working but never targeting `.log` files
  specifically). It now takes a `-Filter` parameter (default `*.log`) and honors
  `-Retention 0` to disable pruning (#42).

### Changed

- Log retention is no longer hardcoded to 180 days: new config setting
  `LogRetentionDays` (default 180, 0 disables pruning), mirroring
  `JsonHistoryRetentionDays` (#42).

## [2.3.0] - 2026-06-29

### Added

- New `Export-SPSWeatherReport` produces a self-contained rich HTML report
  (sticky top banner with overall status + OK/Alert counts, side nav, sticky
  table headers, live filter, alert row highlight). Written next to the email
  body as `<file>-rich.html`. The Outlook email body keeps its inline-style
  layout and now embeds a small Outlook-safe summary banner (#38).
- New `Backup-SPSWeatherJsonFile` + `Compare-SPSWeatherSnapshots` and a
  `Results\history\` folder of timestamped JSON snapshots; the previous run is
  archived before overwrite and a trend (`Alert N -> M`) is rendered in the
  email banner and as a KPI in the standalone report. New config setting
  `JsonHistoryRetentionDays` (default 30 days; 0 disables pruning) (#39).

### Changed

- **Breaking**: replaced the `-Install` / `-Uninstall` switches with a single
  `-Action [Install|Uninstall|Default]` parameter (default `Default`),
  mirroring SPSUpdate/SPSWakeUp. There is no back-compat alias - existing
  scheduled tasks installed by 2.2.x still run the same `-ConfigFile` argument
  set, only the install/uninstall command lines change (#40).
- Per-server SYS checks (IIS app pools, W3WP, certs, last reboot, .NET, disks,
  event log) now open one direct CredSSP session per server via
  `Invoke-SPSCommand` instead of fanning out `Invoke-Command` from the entry
  session. This removes the double-hop and collects nodes that previously
  failed with `0x80090322` (e.g. WFE1) (#37).
- IIS Application Pool report renders 'Unreachable' rows explicitly (red) so
  the cell is no longer empty when a node is down.

## [2.2.5] - 2026-06-29

### Fixed

- `Add-SPSWeatherEvent` no longer returns silently when its source is already
  registered against another log (legacy flat scripts could bind 'SPSWeather'
  to Application): it now re-points the source to the SPSWeather log and only
  warns if the registration/write fails. This is why no SPSWeather log or events
  appeared on a fresh install (#35).
- Per-server SYS checks (IIS app pools, W3WP, certs, last reboot, .NET, disks,
  event log) wrap each server in try/catch: an unreachable node yields a single
  'Unreachable' row instead of dumping a raw 0x80090322 double-hop error and
  aborting the whole farm's collection (#33). Fixed a `$nulll` typo that always
  blanked the .NET version.
- Search checks (crawl status, crawl logs, topology) wrap the Search admin calls
  in try/catch: a down Search topology host yields one 'Search unavailable' row
  instead of a raw 503 stack trace (#34).

## [2.2.4] - 2026-06-29

### Fixed

- `Add-SPSSheduledTask` no longer warns and skips when the task already exists:
  it now registers the task in create-or-update mode (logon type 6) so `-Install`
  reliably creates or refreshes the SharePoint task. Registration failures now
  `throw` (with arguments and exception detail) instead of being swallowed by
  `Write-Error`, so a failed install is visible (#30).
- `Get-SPSSecret` / `Set-SPSSecret` are now exported by the module. The entry
  script called them directly, but they lived in `Private/`, so the scheduled run
  could not resolve the stored credential and fell back to an interactive
  credential prompt. Exporting them fixes the unattended run (#32).
- `-Install` / `-Uninstall` write a dedicated entry to the SPSWeather Event Log
  (EventID 1003 / 1002) and print an explicit success line, so the installation
  outcome is traceable in Event Viewer.

### Added

- `Add-SPSSheduledTask` gains an optional `-Description` parameter for the task
  registration metadata.

## [2.2.3] - 2026-06-29

### Changed

- `Test-SPSWeatherReadiness.ps1` probes WinRM with a short, configurable timeout
  (`-TimeoutSeconds`, default 5) via a CIM session, so an unreachable farm server
  can no longer hang the pre-flight. An unreachable server is now a WARN (the run
  skips it) instead of a blocking FAIL.
- `Invoke-SPSCommand` opens the CredSSP PSSession with a 30s `-OpenTimeout` so a
  down server fails fast instead of waiting the default connect timeout.

## [2.2.2] - 2026-06-29

### Added

- Port `Get-SPSInstalledProductVersion` and `Import-SPSSharePointCommand` from
  SPSUserSync: detect the SharePoint version and load the right command surface
  (2016/2019 -> Microsoft.SharePoint.PowerShell snap-in, Subscription Edition ->
  SharePointServer module).
- `Test-SPSWeatherReadiness.ps1` now enumerates every server of the local farm
  with `Get-SPServer` (role <> Invalid) and tests WinRM/CredSSP on each, merged
  with the per-farm servers declared in the config, instead of only the declared
  entry point. Use `-SkipSharePoint` to fall back to declared servers (#26).

## [2.2.1] - 2026-06-29

### Fixed

- `Test-SPSWeatherReadiness.ps1` skipped the secret check ("Module not loaded;
  cannot validate the secret") because it looked up the private `Get-SPSSecret`
  with `Get-Command`, which only sees exported functions. It now calls
  `Get-SPSSecret` inside the module session state, so secrets.psd1 is actually
  validated (DPAPI decrypt).

## [2.2.0] - 2026-06-28

### Added

- SQL alias resolution and per-farm SQL declaration (#22). SharePoint reaches SQL
  through cliconfg client aliases, so `Get-SPDatabase` returns the alias rather
  than the real server. SPSWeather now:
  - resolves each SQL alias from the cliconfg registry (64-bit `ConnectTo` and
    32-bit `Wow6432Node`) to the real server\instance, protocol, port and bitness
    (new `Resolve-SPSSqlAlias` public function and a new `SQLAliasStatus` report
    section / ExclusionRules key);
  - accepts an optional per-farm `SqlServers` array in the config and cross-checks
    declared vs discovered SQL servers, flagging mismatches and 32/64-bit alias
    inconsistencies as advisories.

## [2.1.0] - 2026-06-28

### Added

- `Test-SPSWeatherReadiness.ps1`: a read-only pre-flight check that validates the
  module import, the configuration `.psd1` and its required keys, the
  DPAPI-decryptable `secrets.psd1` credential, Administrator rights and per-farm
  WinRM/CredSSP reachability before a run (#19).
- SQL Server health checks (`Get-SPSSqlStatus`), collected from a SharePoint
  server with dependency-free ADO.NET (no `SqlServer` module). SQL servers are
  discovered via `Get-SPDatabase`. Four new report sections / ExclusionRules
  keys: `SQLInstanceStatus`, `SQLDatabaseStatus`, `SQLDiskStatus`,
  `SQLAvailabilityStatus`, covering instance config (MAXDOP, memory, TempDB),
  databases (state, recovery model, sizes, last full backup), volume free space
  (`sys.dm_os_volume_stats`) and AlwaysOn/Agent. Thresholds
  `SQLDiskFreeThresholdPercent` (15) and `SQLBackupMaxAgeDays` (3) are
  configurable (#17).
- Per-farm resilience: a farm whose server is unreachable over CredSSP is now
  logged (console warning + SPSWeather event ID 3001) and skipped, instead of
  letting the failure abort the whole run (#18).

### Changed

- Refactor the report assembly in `SPSWeather.ps1` into a testable
  `ConvertTo-SPSWeatherReport` module function with identical output, replacing
  ~140 lines of repeated per-section `Add-Member` blocks (#18).

## [2.0.1] - 2026-06-28

### Fixed

- `Invoke-SPSCommand` no longer runs the SharePoint command on the **local**
  server when the CredSSP session cannot be opened. It used to add the remote
  session only when `New-PSSession` succeeded, so a session failure (CredSSP
  misconfigured or server unreachable) silently executed the scriptblock
  locally; it now fails with a clear, server-scoped error (#15).

### Removed

- Dead code: the orphaned public functions `Get-SQLInstancesStatus` /
  `Get-SQLDatabasesStatus` (never called, and broken — they wrote to a
  `$jsonObject` that did not exist in their scope) and the unused private helper
  `Invoke-SPSWebRequestUrl`. A proper SQL Server health check is planned for
  2.1.0 (#16, see #17).

## [2.0.0] - 2026-06-28

This is a major modernization release. The flat helper modules become a real
`SPSWeather.Common` PowerShell module, the embedded CredentialManager dependency
is replaced by a DPAPI `secrets.psd1`, the configuration moves to a `.psd1` data
file, and the tool gains Windows Event Log instrumentation. See the migration
notes in `RELEASE-NOTES.md`.

### Added

- `src/Modules/SPSWeather.Common/` — a proper module with a manifest, a loader
  that dot-sources `Private/` then `Public/`, and a Public/Private split (one file
  per function). `ModuleVersion` is the single source of truth for the version (#3, #4).
- `.gitattributes`, `.editorconfig` and `PSScriptAnalyzerSettings.psd1` to enforce
  the UTF-8 BOM + CRLF (PowerShell) / LF (yml, md, json) encoding policy and lint
  rules (#2).
- Cross-platform Pester structural test suite and a `pester.yml` CI workflow
  running Pester and PSScriptAnalyzer on pull requests (#5).
- DPAPI credential store: `Get-SPSSecret` / `Set-SPSSecret`, `Config/secrets.psd1`
  (gitignored) and `Config/secrets.example.psd1` (#9).
- `Add-SPSWeatherEvent` and a dedicated `SPSWeather` Windows Event Log; the entry
  script emits start (1000), completion (1001), ALERT (2000) and email-failure
  (3000) events (#10).
- `wiki/_Sidebar.md` and `wiki/Release-Process.md`; the whole wiki was rewritten
  for the 2.0.0 layout (#11).
- `Get-SPSFailedTimerJob` now evaluates failures over a configurable lookback
  window with failure-ratio metrics (failed runs, total runs, failure percentage,
  threshold percentage, IsInfo), and the report gained the matching columns.

### Changed

- Move the script tree from `scripts/` to `src/` (#3).
- `SPSWeather.ps1` imports the `SPSWeather.Common` manifest instead of the
  `util.psm1` chain and derives its displayed version from `ModuleVersion` (#4).
- Migrate the environment configuration from JSON to a `.psd1` data file read with
  `Import-PowerShellDataFile`; the `StoredCredential` field becomes `CredentialKey` (#8).
- `Join-HtmlBodyFromPSo` builds a self-contained HTML document with email-optimized
  CSS (no reliance on caller-scope variables) (#7).
- `release.yml` packages the contents of `src/` so the ZIP extracts straight to
  `SPSWeather.ps1`, `Config/` and `Modules/` (#6).
- `Remove-SPSSheduledTask` now declares `SupportsShouldProcess` (#3).
- Below-threshold timer-job failures are rendered as warnings instead of hard
  failures.

### Removed

- The embedded third-party CredentialManager dependency (signed DLLs + UTF-16
  manifest) and all Windows Credential Manager usage, replaced by the DPAPI
  `secrets.psd1` store (#9).
- The legacy flat `scripts/Modules/*.util.psm1` helper modules (#3).

### Fixed

- Restore the report's HTML `<head>`/CSS wrapper that previously lived in the
  `html.util.psm1` module scope and was otherwise lost in the module split (#7).

## [1.0.3] - 2023-10-16

### Added

- scripts/SPSWeather.ps1 - Add Installation process:

  - New parameters: Install, Uninstall and InstallAccount
  - New functions: Add-SPSSheduledTask and Remove-SPSSheduledTask

- Wiki Documentation in repository - Add :
  - wiki/Configuration.md
  - wiki/Getting-Started.md
  - wiki/Home.md
  - wiki/Usage.md
  - .github/workflows/wiki.yml

### Changed

- scripts/SPSWeather.ps1 - Remove ExclusionRules parameter
- scripts/Config/CONTOSO-PROD.json - Add ExclusionRules parameter

## [1.0.2] - 2023-10-10

### Added

- README.md
  - Add code_of_conduct.md badge
- Add CODE_OF_CONDUCT.md file
- Add Issue Templates files:
  - 1_bug_report.yml
  - 2_feature_request.yml
  - 3_documentation_request.yml
  - 4_improvement_request.yml
  - config.yml

### Changed

- release.yml
  - Zip scripts folder and mane it with Tag version
- PULL_REQUEST_TEMPLATE.md => Remove examples and unit test tasks

## [1.0.1] - 2023-10-09

### Changed

- README.md
  - Add Requirement and Changelog sections

### Added

- Add RELEASE-NOTES.md file
- Add CHANGELOG.md file
- Add CONTRIBUTING.md file
- Add release.yml file
- Add scripts folder with first version of SPSWeather
