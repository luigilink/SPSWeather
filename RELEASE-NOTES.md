# SPSWeather - Release Notes

## [2.2.1] - 2026-06-29

A patch release fixing the readiness secret check.

### Fixed

- `Test-SPSWeatherReadiness.ps1` no longer skips the secret validation with
  "Module not loaded; cannot validate the secret". It used `Get-Command` to look
  up `Get-SPSSecret`, which is a private function and therefore invisible; it now
  calls it inside the SPSWeather.Common session state and actually verifies that
  the credential in secrets.psd1 decrypts under the current account.

A full list of changes can be found in the [change log](CHANGELOG.md).
