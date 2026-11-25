# SPSWeather - Release Notes

## [3.4.0] - 2026-11-25

### Added

- **One consolidated email for all the farms of an environment.** The new optional key
  `EmailMode` of the environment configuration is `PerFarm` (default: one short email per farm, as
  before) or `Consolidated`: a single email with the **totals of checks across the farms** on top
  (failures, warnings, OK), then **one card per farm**, worst first. A card shows the status of the
  farm (`ALERT`, `WARNING`, `HEALTHY` or `UNREACHABLE`), a health bar and percentage, the counts, the
  three areas that need the most attention and a button to the dashboard of the farm. A farm that
  cannot be reached gets a grey `UNREACHABLE` card instead of being left out of the report (in this
  mode one `[ALERT]` email is still sent when every farm is unreachable). The subject is
  `[ALERT] <App>/<Env> - 3 farms (1 ALERT, 1 WARN, 1 OK) - SPSWeather`: the tag is the worst status
  (an unreachable farm counts as `ALERT`), in English like the per-farm email so existing inbox rules
  keep working, and the priority is High when a farm is in alert or unreachable. `SMTPPreview` writes
  `Results\<App>-<Env>-mail.html` in this mode. An invalid `EmailMode` is reported (transcript, event ID
  2001, readiness `[WARN]`) and treated as `PerFarm`.
- **New check: every Timer service instance of the farm must be `Online`.** One row per instance of
  `(Get-SPFarm).TimerService.Instances`. Any status other than `Online` is a failure: a single instance
  in another state breaks the communication between the servers, which notably blocks the deployment
  of a WSP. A farm that returns no instance, or a query that fails, is reported as a failure, never as
  healthy. The check is read-only (it never changes the status of an instance) and is shown in the
  *Timer Jobs* card of the dashboard and in both emails. It is enabled by default; add
  `TimerServiceStatus` to `ExclusionRules` to skip it.
- **Localization of the dashboard and of the alert email, with a French (`fr-FR`) translation.** The
  labels live in resource files, one per culture, and the new `Language` key of the environment
  configuration (`en-US` by default, `fr-FR`, or `auto` for the UI culture of the account that runs the
  script) selects the language. A culture that misses a translation shows the English text; an
  unavailable language, or a translation file that is defective, falls back to English with a warning
  (transcript, event ID 2001, readiness `[WARN]`) and never stops a report. Only the display is
  translated: the values of the checks, the detail-table column headers, the email subject tags and the
  Event Log messages stay in English. Numbers, percentages and dates follow the display language
  (`78 %`, `dd/MM`). See the wiki page *Localization* to add a language.

### Fixed

- The history title of the dashboard said `last 1 runs` on the first run; it now reads `last run`.
- The generation time and the history dates no longer depend on the culture of the host (no Buddhist
  or Hijri year on a Thai or Arabic server).

### Upgrade notes

- **No change is required.** `Language` defaults to `en-US` and `EmailMode` to `PerFarm`: with the
  default values the dashboard and the per-farm email are the same as in 3.3.0, apart from the new
  Timer service check (one more row per server in the counters) and the `last run` wording of the
  dashboard history title.
- The new Timer service check is enabled by default and adds one check per server to the counters and
  to the history. A server whose Timer service instance is not `Online` now raises an alert: that is the
  point of the check. Add `TimerServiceStatus` to `ExclusionRules` to turn it off.
- To receive one email for all the farms, set `EmailMode = 'Consolidated'` in the environment
  configuration (the scheduled task reads the configuration at each run: no reinstall needed). To
  review it without an SMTP relay, use `SMTPEnabled = $false` and `SMTPPreview = $true`, then open
  `Results\<App>-<Env>-mail.html`.
- For a French dashboard and email, set `Language = 'fr-FR'`.
- See the example configuration `Config\CONTOSO-PROD.example.psd1` for the new keys.
