# SPSWeather - Release Notes

## [2.2.2] - 2026-06-29

### Added

- The readiness check now tests WinRM/CredSSP on **every server of the local
  farm** (Get-SPServer, role <> Invalid), merged with the per-farm servers
  declared in the config, instead of only the declared entry point. SharePoint is
  loaded version-aware (2016/2019 snap-in, Subscription Edition module). Use
  -SkipSharePoint to fall back to declared servers when run off-server.
- New public helpers Get-SPSInstalledProductVersion and Import-SPSSharePointCommand
  (ported from SPSUserSync).

A full list of changes can be found in the [change log](CHANGELOG.md).
