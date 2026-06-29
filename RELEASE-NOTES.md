# SPSWeather - Release Notes

## [2.3.4] - 2026-06-29

### Fixed

- Distributed Cache report on SharePoint Subscription Edition now populates
  Port / Size / ServiceName / CacheStatus from the SE-native cluster cmdlets
  (`Get-SPCacheClusterHealth` + `Get-SPCacheClusterInfo`), with a graceful
  degradation to the SP DC defaults (22233, AppFabricCachingService) when
  `Get-SPCacheHostConfig` cannot resolve the host. Removes the AppFabric
  fallback from 2.3.3 (those cmdlets do not exist on SE).

A full list of changes can be found in the [change log](CHANGELOG.md).
