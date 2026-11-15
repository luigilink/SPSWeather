# SPSWeather - Release Notes

## [3.3.0] - 2026-11-15

### Added

- **Email settings in the environment configuration.** `SMTPEnabled` (`$true` / `$false`)
  decides whether the alert email is sent, and `SMTPPreview` writes the email body to
  `Results\<App>-<Env>-<Farm>-mail.html` (overwritten at each run, before any send attempt),
  so the email can be reviewed on a host that has no SMTP relay. The two keys are independent:
  with `SMTPEnabled = $false` and `SMTPPreview = $true` nothing is sent and the HTML is kept.
- Safer behavior around the email: a non-boolean value is reported and treated as disabled
  (the text `'false'` is never read as true), and sending is skipped with a clear warning when
  `SMTPToAddress`, `SMTPFromAddress` or `SMTPServer` is missing or empty. These warnings are
  shown in the transcript and recorded in the `SPSWeather` Event Log (**event ID 2001**), so an
  unattended run that stops sending the email leaves a trace.

### Changed

- **`-EnableSmtp` is deprecated** and will be removed in 4.0.0. While `SMTPEnabled` is not
  defined in the configuration the switch still sends the email, with a deprecation warning, so
  existing configurations and scheduled tasks keep working. When `SMTPEnabled` is defined, the
  configuration takes precedence and the switch is ignored.
- `-Action Install` registers the scheduled task **without** `-EnableSMTP` when the configuration
  defines `SMTPEnabled`. Otherwise it keeps the switch in the task and warns you to add the key
  and run `-Action Install` again.
- The readiness check (`Test-SPSWeatherReadiness.ps1`) validates `SMTPEnabled` and `SMTPPreview`
  as booleans and no longer requires `SMTPToAddress`, `SMTPFromAddress` and `SMTPServer` when
  `SMTPEnabled = $false`, so an environment without a relay can pass the pre-flight.

### Upgrade notes

- **No change is required**: an existing configuration without `SMTPEnabled` and a scheduled task
  that still carries `-EnableSMTP` keep sending the email exactly as before.
- To migrate: add `SMTPEnabled = $true` (or `$false`) to your environment configuration, then run
  `-Action Install` again to drop the deprecated switch from the scheduled task. The task reads the
  configuration at each run, so changing the value later needs no reinstall.
- No SMTP relay? Set `SMTPEnabled = $false` and `SMTPPreview = $true`, run, and open the
  `Results\*-mail.html` file.
- See the example configuration `Config\CONTOSO-PROD.example.psd1` for the new keys.

A full list of changes can be found in the [change log](CHANGELOG.md).
