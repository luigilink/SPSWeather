# SPSWeather - Release Notes

## [2.3.3] - 2026-06-29

### Fixed

- Distributed Cache report on SharePoint Subscription Edition now populates
  Port / Size / ServiceName / CacheStatus on hosts where `Get-SPCacheHostConfig`
  returns null: the function falls back to the historical AppFabric cmdlets
  (`Use-CacheCluster` + `Get-CacheHost` + `Get-AFCacheHostConfiguration`), which
  are still installed on SE.

A full list of changes can be found in the [change log](CHANGELOG.md).
