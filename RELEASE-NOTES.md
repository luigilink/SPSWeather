# SPSWeather - Release Notes

## [3.0.0] - 2026-08-25

### Removed

- **BREAKING**: dropped SharePoint Server 2016 and 2019 support. Both reached
  end of support on 14 July 2026; SPSWeather now targets **SharePoint Server
  Subscription Edition** exclusively.
- The `Microsoft.SharePoint.PowerShell` PSSnapin loader path (`Add-PSSnapin`)
  is gone from `Import-SPSSharePointCommand` and from `Invoke-SPSCommand`'s
  remote baseScript. SPSWeather now always loads the `SharePointServer`
  module.
- The AppFabric branch of `Get-AppFabricStatus` (`Use-CacheCluster` /
  `Get-CacheHost` / `Get-AFCacheHostConfiguration`) is gone. Only the
  Subscription Edition cluster path remains.

### Changed

- `Get-SPSInstalledProductVersion` is now a plain "SharePoint installed?"
  check (no version heuristic).
- README and wiki state the Subscription Edition requirement and point
  2016/2019 users at the previous major release (v2.3.7).

### Migration

Customers still running SharePoint Server 2016 or 2019 must stay on
**SPSWeather v2.3.7** and are encouraged to migrate their farm to
Subscription Edition. Upgrading a Subscription Edition farm to
SPSWeather 3.0.0 requires no config change.

A full list of changes can be found in the [change log](CHANGELOG.md).
