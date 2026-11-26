# Dashboard

Since **3.1.0**, SPSWeather renders a modern **cards dashboard** per farm and sends a
short, alert-only email that links to it. The dashboard HTML is meant to be hosted on an
IIS site (as SPSUpdate does), so operators browse a stable URL per farm.

## What you get

- **One dashboard per farm**, written as `<App>-<Env>-<Farm>-dashboard.html`:
  - an **overall-health donut** (OK / warning / failure split) with a weather glyph;
  - a **30-run history bar chart** with trend arrows versus the previous run;
  - **up to nine functional-area cards** (Farm & Upgrade, Trust Farm, Search, Distributed
    Cache, Timer Jobs & Solutions, Health Analyzer, IIS, System, SQL Server; empty areas
    are hidden) each with a collapsible detail table.
- **One short email per farm** (with `SMTPEnabled = $true`; `SMTPPreview = $true` keeps an HTML copy under `Results\`): only the items needing attention,
  grouped by area (failures first), a KPI strip, and an **Open full dashboard** button
  pointing at the hosted URL. Each area lists at most `EmailMaxItemsPerArea` items
  (default 10, `0` = no limit); the rest is summarized as "+ N more" and the counters
  always include every item.
- **One consolidated email for all the farms** (`EmailMode = 'Consolidated'`, instead of one email
  per farm): a header with the weather of the worst farm, the **totals of checks across all the
  farms** (failures, warnings, OK), then **one card per farm**, worst first. A card shows the status
  of the farm (`ALERT`, `WARNING`, `HEALTHY` or `UNREACHABLE`), a health bar and percentage, the
  counts, the three areas with the most failures (`+ N more` for the rest) and a button to the
  dashboard of the farm (hidden when `Dashboard.Url` is empty). A farm that could not be reached
  gets a grey card instead of disappearing from the report. The subject is
  `[ALERT] <App>/<Env> - 3 farms (1 ALERT, 1 WARN, 1 OK) - SPSWeather`: the tag is the worst status
  (an unreachable farm counts as `ALERT`), in English like the per-farm email, and the priority is
  High when a farm is in alert or unreachable. The dashboards, the history and the JSON snapshots
  are unchanged; `SMTPPreview = $true` writes `Results\<App>-<Env>-mail.html`.

The dashboard replaces the legacy full-table HTML report; data collection is unchanged.

The dashboard and the email are shown in English by default; set `Language = 'fr-FR'` in the
configuration for French. See [Localization](Localization).

## Configuration

Add a `Dashboard` block to your environment config:

```powershell
Dashboard = @{
    OutputPath = '\\pull01\SPSWeather$'              # folder/share the farm servers write to
    Url        = 'https://pull.contoso.com/spsweather' # public IIS base serving that folder
    Cockpit    = $true                               # optional: also write the multi-farm cockpit page
}
```

| Key | Description |
|---|---|
| `OutputPath` | Folder (local or UNC share) that receives `<App>-<Env>-<Farm>-dashboard.html`. Empty = `Results\` (local only). |
| `Url` | Public base URL serving that folder over IIS. The email button links to `<Url>/<App>-<Env>-<Farm>-dashboard.html`. Empty = no button. |
| `Cockpit` | Optional boolean, `$false` by default. `$true` also writes `<App>-<Env>-cockpit.html` into `OutputPath` (`Results\` when it is empty). See below. |

### The cockpit page

With `Cockpit = $true` the run also writes the [Cockpit page](Cockpit-Page), the single page that shows every farm of the environment. Nothing changes
unless the key is set: with the key absent or `$false` a run produces exactly the files, dashboards and emails of the previous version.

- **Where and when.** `<App>-<Env>-cockpit.html`, in `OutputPath` (created when it does not exist; `Results\` when `OutputPath` is empty), at the **end of the run**: after
  the emails, so it never delays an alert, and after the run journal, so it shows the run that has just finished. It is replaced in one step; a reader never sees
  a half-written page.
- **Where it is built.** The page is built by the run, from `Results\` (snapshots, history, run journal), on the machine that runs `SPSWeather.ps1`, and written to the same
  `OutputPath` as the dashboards, so the same share and the same IIS site serve it. The page loads nothing from outside, so it needs no other file on the site.
- **The email.** With `EmailMode = 'Consolidated'` and a `Url`, the consolidated email gets an *Open the cockpit* button under its introduction, pointing to
  `<Url>/<App>-<Env>-cockpit.html`. Without `Url` there is no button, like the farm buttons. As for the farm buttons, the address is built from `Url`: it must serve the folder that `OutputPath` writes to (with `OutputPath` empty the page stays in `Results\`, which no web server serves, so leave `Url` empty then). The per-farm email is unchanged.
- **A failure never fails the run.** If the page cannot be written (a share that is down, a folder that refuses the file), the run goes on, writes the error in
  the transcript and records it in the Event Log (ID **3002**); the dashboards and the emails are already done.
- **A wrong value.** `Cockpit = 'maybe'` (or `$null`, or a number) is reported (transcript, Event ID 2001, readiness `[WARN]`) and the page is not produced; the text `'true'` or
  `'false'` is understood. A value is never cast to a boolean, because the text `'false'` would become `$true`.
- **Readiness.** `Test-SPSWeatherReadiness.ps1` reports the key, the page it will write, whether the folder accepts a file (it writes and removes a small temporary
  file; a folder that does not exist yet is judged by its nearest existing parent and is not created) and the address of the button.

The per-farm history (the bar chart) is built from the JSON snapshots under
`Results\history\<Farm>\`, capped at `JsonHistoryRetentionDays` runs.

Every run also appends a record to the run journal `Results\<App>-<Env>.runs.json` (start, duration, email outcome, and for each farm collected or unreachable, plus the settings in effect: see [Usage](Usage)). A farm that cannot be reached has no snapshot, so the journal is where it shows up over time.

The footer of a dashboard shows the configuration file the run used and the SQL thresholds it applied
(`SQL backup max age`, `SQL free space minimum`), with `(default)` next to a value that the configuration
does not set. When an alert looks wrong, this is the first thing to read.

## Hosting the dashboard on IIS

Provision the hosting target once with the standalone, idempotent helper
`New-SPSDashboardSite.ps1` (run elevated on the IIS / pull server). It creates the folder,
an SMB share (so every farm server can publish to it), NTFS permissions, a static-file
`web.config` (avoids HTTP 404.17), and either a dedicated IIS site, a virtual directory,
or an application under an existing site.

Dedicated site:

```powershell
.\New-SPSDashboardSite.ps1 -Path 'E:\inetpub\spsweather' -ShareName 'SPSWeather$' `
    -WriteAccounts 'CONTOSO\svcspsfarm' -SiteName 'SPSWeatherDashboard' -Port 8081
```

Virtual directory under an existing site (e.g. the SPSConfigKit pull server) — **recommended**
when hosting under a pull-server site, because a virtual directory is served by the parent
site's application pool like static content (an IIS *application* nested under the pull server
returns **HTTP 403.18** for the static dashboard):

```powershell
.\New-SPSDashboardSite.ps1 -Path 'C:\inetpub\PSDSCPullServer\SPSWeather' -ShareName 'SPSWeather$' `
    -WriteAccounts 'CONTOSO\svcspsfarm' -ParentSite 'PSDSCPullServer' -AppAlias 'SPSWeather' -AsVirtualDirectory
```

Omit `-AsVirtualDirectory` to create an IIS application instead (only if the alias needs its
own application pool).

The script is deliberately standalone (no module dependency) and supports `-WhatIf`,
`-SkipShare`, `-SkipNtfs` and `-SkipIis`. When it finishes it prints the exact
`Dashboard.OutputPath` and `Dashboard.Url` values to set in your config.
