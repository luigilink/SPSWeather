# SPSWeather - Release Notes

## [3.5.0] - 2026-11-26

SPSWeather gets a **cockpit**: one self-contained HTML page that shows every farm of an environment, for management and for the IT team,
built from what the runs already leave in `Results\`. Nothing new is collected from the farms. The page is **opt-in** (`Dashboard.Cockpit`);
with the key absent a run writes what it wrote in 3.4.1, plus the run journal and a footer line on the dashboards, both described below. This release also fixes two defects: the
history shared between environments, and a Failed timer jobs check that never reported a failure.

### Added

- **The cockpit page** (`Export-SPSWeatherCockpit`, written by the run when `Dashboard.Cockpit = $true`): one HTML file,
  `<App>-<Env>-cockpit.html` in `Dashboard.OutputPath` (`Results\` when it is empty), with nothing loaded from outside. Five tabs:
  **Executive** (health, days without failure, open attention items, collection, trend, weather), **IT** (causes grouped, farms by
  section, stability, detail per farm), **Data quality**, **Collection tracking** (the run journal) and **Settings & method** (the settings
  in effect and their changes, how the figures are computed). Periods of 7, 14, 30 and 60 days; the cards say in a sentence what their
  figure means (fixed rules on the data, no external service). English and French, light and dark theme, responsive from 390 px,
  keyboard accessible. The period, the language, the theme and the tab are kept in the address (`#tab=it&p=14&lang=fr-FR`), so a link
  can be shared. Every value that comes from a farm is HTML-escaped. See the wiki pages *Cockpit page* and *Cockpit data*.
- **A button in the consolidated email**: with `EmailMode = 'Consolidated'` and a `Dashboard.Url`, an *Open the cockpit* button points to
  the page. Without `Dashboard.Cockpit` or without a `Url`, the email is **byte for byte the one of 3.4.1** (the tests compare it with the
  body that 3.4.1 produces).
- **A run journal**, `Results\<App>-<Env>.runs.json`: every run appends one record (start, duration, script version, language, email mode,
  outcome of the email, and for each farm whether it was collected or unreachable, with its counts). A farm that cannot be reached leaves no
  JSON snapshot, so the journal is the only trace of it over time. The record also holds the **settings in effect** (the thresholds with
  their source `config` or `default`, and the names of the exclusion rules; no server, address, credential, URL or path). A small
  `.lock` file stays next to the journal so that two overlapping runs do not lose a record. The journal is pruned with
  `JsonHistoryRetentionDays`, never holds more than 1000 records, and a journal that cannot be read is kept aside as `.corrupt`. A journal
  that cannot be written only produces a warning, never a failed run.
- **The footer of the per-farm dashboard** says which configuration file the run used and which SQL thresholds it applied (`(default)`
  next to a value the file does not set), so that an alert that looks wrong can be explained at once. Translated in English and French.
- **`Test-SPSWeatherReadiness.ps1`** checks `Dashboard.Cockpit`: the key, the page that will be written, whether the folder accepts a file
  and lets it be removed (a small temporary file, removed at once; nothing is created), and the address of the button. `New-SPSDashboardSite.ps1`
  says that the same folder serves the page.
- A new Event ID, **3002**: the cockpit page could not be written (a share that is down, a folder that refuses the file). The run goes on;
  the dashboards and the emails are already done.

### Changed

- The thresholds are resolved in one place. With a valid configuration nothing changes. A value that is not a whole number of 0 or more
  (`abc`, a blank, `-1`) used to give an undefined result (an error, or a threshold of 0 that flagged everything): it is now reported
  (transcript, Event ID 2001) and the default is used.
- The bars of the per-farm dashboard are counted by the same code as the cockpit. The numbers are the same as before.

### Fixed

- **The Failed timer jobs check reports a failure again.** A collector handed its parameters to the remote script block as the caller wrote
  them, so a parameter that kept its default reached the block empty. The entry script calls the Failed timer jobs collector without the
  24 hour look-back and the 5 % threshold, so the look-back was zero hours and the check **never returned a row**. It has been so since
  2.0.0. A timer job that failed more often than 5 % of its runs over the last 24 hours now appears in the dashboard and in the alerts of
  the email. **A farm that has failing timer jobs will show a new warning at its first run with 3.5.0**: it is the check doing what its
  documentation says, not a new problem. The same fix is in the 2.x line (2.4.1).
- **The history of a farm is no longer shared between environments.** `Results\history\<Farm>\` is shared by the environments that name
  a farm the same (`CONTENT` in a `PROD` and a `QUAL` configuration). The bars of the dashboard showed the runs of every environment as their
  own, and the retention of one environment deleted the archives of the others. Each environment now reads and removes only its own
  archives. Archives of another environment that a retention had already deleted are gone.

### Upgrade notes

- **No change is required.** The only new key is optional: `Dashboard.Cockpit` (`$false` by default). A value other than `$true` or `$false`
  is reported and the page is not produced. See `Config\CONTOSO-PROD.example.psd1`.
- Replace the `Modules` folder and the scripts with the new ones (keep `Config\` and `Results\`). The account that runs SPSWeather must be
  able to create files in `Results\` (the journal, its `.lock`) and, to get the page, in `Dashboard.OutputPath`.
- To get the page: set `Dashboard.Cockpit = $true`, run `Test-SPSWeatherReadiness.ps1`, then run. To open it from the email, set
  `Dashboard.Url` and `EmailMode = 'Consolidated'`. The page is only as complete as the history in `Results\`: it fills in over the
  first days of runs.
- This line is for **SharePoint Server Subscription Edition**. For SharePoint Server 2016 and 2019 (out of support on 14 July 2026), stay on
  [v2.4.1](https://github.com/luigilink/SPSWeather/releases/tag/v2.4.1).

### What has been tested

- More than 1,000 automated tests pass on PowerShell 7 and on Windows PowerShell 5.1 (continuous integration), and the code analysis is
  clean. The page was checked in a browser at 390, 768 and 1320 px, in both languages and both themes.
- On a Subscription Edition lab farm: the run journal and the settings in effect were written by real runs, and the dataset and the page
  were built from that real history. **The scheduled run that writes the page itself (`Dashboard.Cockpit = $true`) and the Failed timer jobs
  fix have only been exercised with the real block of the entry script and a simulated farm, not yet by a scheduled run on a farm.** A
  report of what worked and what did not is welcome (https://github.com/luigilink/SPSWeather/issues).

### Not in this release

- The nightly activity indicators of the cockpit (a reserved `kpi` section is empty), editing the settings from the page, and securing the
  access to the hosted pages are planned for later versions (#112, #119, #85).

A full list of changes can be found in the [change log](CHANGELOG.md).
