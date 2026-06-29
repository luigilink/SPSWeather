# SPSWeather - Release Notes

## [2.3.7] - 2026-06-29

### Fixed

- Distributed Cache table on SharePoint Subscription Edition now shows the
  real cache Size in MB (e.g. 2048). The function now opens the per-cache-host
  CredSSP session with the FQDN target derived from the farm entry server,
  so Kerberos no longer fails silently with 0x80090322 on hosts whose DNS
  returns the short name.

A full list of changes can be found in the [change log](CHANGELOG.md).
