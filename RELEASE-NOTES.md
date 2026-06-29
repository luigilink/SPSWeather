# SPSWeather - Release Notes

## [2.3.1] - 2026-06-29

### Fixed

- `Clear-SPSLog` now actually targets `.log` files (it was filtering on an
  undefined variable). Retention 0 disables pruning.

### Changed

- New config setting `LogRetentionDays` (default 180, 0 disables) replaces the
  hardcoded 180-day retention, mirroring `JsonHistoryRetentionDays`.

A full list of changes can be found in the [change log](CHANGELOG.md).
