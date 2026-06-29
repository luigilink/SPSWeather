# SPSWeather - Release Notes

## [2.2.3] - 2026-06-29

### Changed

- The readiness check probes WinRM with a short, configurable timeout
  (-TimeoutSeconds, default 5) and reports an unreachable server as WARN instead
  of blocking FAIL, so the pre-flight cannot hang on a down node.
- Invoke-SPSCommand opens the CredSSP PSSession with a 30s OpenTimeout so a down
  server fails fast.

A full list of changes can be found in the [change log](CHANGELOG.md).
