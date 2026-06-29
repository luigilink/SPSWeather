# SPSWeather - Release Notes

## [2.3.2] - 2026-06-29

### Fixed

- Distributed Cache report now collects Port / Size / ServiceName / CacheStatus
  for the actual cache host on SharePoint Subscription Edition (previously the
  details were empty because the cluster expected the FQDN while the call used
  the short name).

### Changed

- Servers that are not part of the Distributed Cache cluster are reported as
  'Not a cache host' (informational) instead of a red 'SPService Not Found'
  alert. Hosting Distributed Cache on a subset of servers (often a single WFE)
  is a legitimate topology.

A full list of changes can be found in the [change log](CHANGELOG.md).
