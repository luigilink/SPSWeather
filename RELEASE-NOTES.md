# SPSWeather - Release Notes

## [2.3.5] - 2026-06-29

### Fixed

- Distributed Cache report on SharePoint Subscription Edition no longer shows
  a phantom 'Microsoft' row (a 2.3.4 regression caused by iterating cluster
  health HostInfo objects whose ToString starts with
  'Microsoft.SharePoint.Internal.Caching...'). The function iterates the
  SPDistributedCacheServiceInstance set again; cluster Size still comes from
  Get-SPCacheClusterInfo.

A full list of changes can be found in the [change log](CHANGELOG.md).
