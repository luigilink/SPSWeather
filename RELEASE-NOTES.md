# SPSWeather - Release Notes

## [3.6.0] - 2026-11-27

SPSWeather now checks each farm against the **supported limits of SharePoint** (content database size, site collections, managed
paths, Distributed Cache memory and more), links the dashboards and the cockpit to each other, warns before the removal of the
`-EnableSMTP` switch in 4.0.0, and registers its scheduled task with a full configuration path and quoted paths. **A farm that is
already above a supported limit shows new alerts at its first run**: it is the check doing its job, and the new `Limits` block lets you
adapt it.

### Added

- **Supported limits of SharePoint** (area *Capacity & limits*, section `SPSLimitStatus`; English and French). Each run compares the farm
  with the limits that Microsoft supports and reports the ones that are reached: the data size of each content database (warning from
  150 GB, failure above 200 GB; the log is not counted), the site collections per content database (5000 / 10000), the content
  databases per farm (375 / 500), the web applications per farm (15 / 20), the managed paths (15 / 20 per web application and for
  host-named site collections), the memory of each Distributed Cache host (failure above 16 GB), the application pools per web server
  (a warning above 10) and the fixed limits of the search topology. The check is **read-only and active by default**, and a farm below
  every threshold adds **no row**: its report is the one of before. The used size of a database is read (`FILEPROPERTY(name, 'SpaceUsed')`)
  only for a database whose allocated size already reaches the warning threshold. The new optional `Limits` block of the configuration
  sets a `Warning` and a `Failure` for each check, turns checks off (`Disabled`) and accepts `Exceptions` for one object, for instance a
  document archive supported up to 4 TB, with a `Reason` shown in the row. The thresholds join the settings that each run records and that
  the cockpit shows; the name of an object is never recorded. `Test-SPSWeatherReadiness.ps1` reports an unusable value of the block.
  New wiki page *Limits*. See the change log for the details (#137).
- **The dashboard and the cockpit link to each other.** With `Dashboard.Cockpit = $true`, the header of each farm dashboard has an *Open
  the cockpit* link, and the cockpit has an *Open the farm dashboard* link on the card of each farm and in its detail on the *IT* tab.
  The links are relative (the file name alone), so they work from IIS, a file share or a local folder, and need no `Dashboard.Url`.
  Without `Dashboard.Cockpit` the dashboard is **byte for byte the one of 3.5.0** (#141).
- **Readiness warns when the scheduled task still carries the deprecated `-EnableSMTP` switch.** 4.0.0 removes it; a task that still has it
  would then fail to start and the morning run would not happen. `Test-SPSWeatherReadiness.ps1` has a new *Scheduled task* section that
  reads the task (read-only) and shows a `[WARN]` with what to do. The line is `[SKIP]`, never a failure, when the task is not on that
  host, when the host is not Windows, or when the task cannot be read (#136).

### Changed

- The wiki *Usage* and *Configuration* pages say that `-EnableSmtp` is removed in 4.0.0 and how to get ready (#136).
- The wiki *Prerequisites* page has a new section on the service account (the maintainer uses the SharePoint farm account; check the
  rights against your own farm) and one on what the script changes on the run server. The scheduled task table of *Usage* shows the real
  task (#145).

### Fixed

- **The scheduled task could not find a relative `-ConfigFile`, and split a path that holds a space.** The task has no working directory
  and its arguments were written as typed and without quotation marks: with `-ConfigFile 'Config\contoso-PROD.psd1'` the run of 06:00
  stopped with `Missing ...`, and a folder such as `D:\My Scripts\SPSWeather` became several arguments. `-Action Install` now writes the
  **full path** of the configuration file (and stops when the file does not exist) and registers the arguments in the `-File` form, with
  the two paths between double quotation marks. **A task registered by an earlier version keeps working as it was and gets the new
  arguments the next time you run `-Action Install`.** The wiki no longer asks for an absolute path or for a folder without space (#147).
- **The wiki and the README showed `-Install` and `-Uninstall` as switches of `SPSWeather.ps1`**, which has `-Action Install|Uninstall|Default`.
  Someone who copied the installation command got a parameter error. A test now fails when a page shows a parameter that the script does
  not have (#145).

### Upgrade notes

- **No change is required.** The `Limits` block and `Dashboard.Cockpit` are optional. See `Config\CONTOSO-PROD.example.psd1`.
- **Expect new alerts at the first run if a farm is above a supported limit** (a content database of 180 GB is a warning). To adapt a
  threshold, or to accept a known case such as a large archive, use the `Limits` block (see the wiki page *Limits*).
- Replace the `Modules` folder and the scripts with the new ones (keep `Config\` and `Results\`).
- To get the new arguments in the scheduled task, run `-Action Install` again, **signed in as the service account**. It is not required
  for the task to keep running. If the task still carries `-EnableSMTP`, define `SMTPEnabled` in the configuration first, so that the
  emails keep flowing (see the wiki page *Usage*).
- This line is for **SharePoint Server Subscription Edition**. For SharePoint Server 2016 and 2019 (out of support on 14 July 2026), stay on
  [v2.4.1](https://github.com/luigilink/SPSWeather/releases/tag/v2.4.1).

### What has been tested

- More than 1,400 automated tests pass on PowerShell 7 and on Windows PowerShell 5.1 (continuous integration), and the code analysis is
  clean. The arguments of the scheduled task are started for real with Windows PowerShell 5.1 from a folder with spaces.
- On a Subscription Edition lab farm, a **read-only probe** exercised the reads of the limits: the site count, the managed paths, the used
  size of the data files and the matching of the SQL server and the database. **A complete scheduled run with the limit checks and the
  links has not yet been done on a farm**: the report, the email and the cockpit were built from test data, and the dashboard page was
  opened in a browser. A report of what worked and what did not is welcome (https://github.com/luigilink/SPSWeather/issues).

### Known issues

- **The note about Remote BLOB Storage does not show.** The size of a content database does not count the external BLOBs of Remote BLOB
  Storage, and the note that should say so on such a database is never added (#149). Nothing else depends on it.

### Not in this release

- A check of the IIS configuration against SharePoint (#138) is planned for 3.7.0. The nightly activity indicators of the cockpit, editing
  the settings from the page, the removal of `-EnableSmtp` and securing the access to the hosted pages are planned for later versions
  (#112, #119, #140, #85).

A full list of changes can be found in the [change log](CHANGELOG.md).
