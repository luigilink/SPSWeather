# SPSWeather - Release Notes

## [2.3.6] - 2026-06-29

### Fixed

- Distributed Cache report on SharePoint Subscription Edition now shows the
  real cache Size in MB (e.g. '2048 MB') and the actual CachePort. The
  function opens a CredSSP session per cache host and runs Use-SPCacheCluster
  + Get-SPCacheHostConfig -HostName $env:COMPUTERNAME locally - the SE cmdlet
  only returns the full payload when executed on the cache host itself.
  When the local lookup still fails, the row falls back to the SE cluster
  tier (Small/Medium/Large) suffixed ' (tier)'.
- 2016/2019 (AppFabric) branch is unchanged.

A full list of changes can be found in the [change log](CHANGELOG.md).
