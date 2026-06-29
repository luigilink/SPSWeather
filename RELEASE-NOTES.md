# SPSWeather - Release Notes

## [2.2.5] - 2026-06-29

### Fixed

- The SPSWeather Event Log is now created reliably: Add-SPSWeatherEvent re-points
  a source that legacy scripts bound to the Application log, instead of giving up
  silently, so install/run/alert events are recorded.

A full list of changes can be found in the [change log](CHANGELOG.md).

## [2.2.4] - 2026-06-29

### Fixed

- The scheduled task is now created reliably on -Install: Add-SPSSheduledTask
  registers in create-or-update mode instead of skipping when a task exists, and
  surfaces registration failures (throw) instead of silently swallowing them.
- Unattended runs no longer prompt for credentials: Get-SPSSecret/Set-SPSSecret
  are exported, so the script resolves the DPAPI-stored credential instead of
  prompting.
- -Install / -Uninstall now log to the SPSWeather Event Log and print an explicit
  success line, so the install outcome is visible in Event Viewer.

A full list of changes can be found in the [change log](CHANGELOG.md).

## [2.2.3] - 2026-06-29

### Changed

- The readiness check probes WinRM with a short, configurable timeout
  (-TimeoutSeconds, default 5) and reports an unreachable server as WARN instead
  of blocking FAIL, so the pre-flight cannot hang on a down node.
- Invoke-SPSCommand opens the CredSSP PSSession with a 30s OpenTimeout so a down
  server fails fast.

A full list of changes can be found in the [change log](CHANGELOG.md).
