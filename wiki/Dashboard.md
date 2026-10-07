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
- **One short email per farm** (with `-EnableSmtp`): only the items needing attention,
  grouped by area, a KPI strip, and an **Open full dashboard** button pointing at the
  hosted URL.

The dashboard replaces the legacy full-table HTML report; data collection is unchanged.

## Configuration

Add a `Dashboard` block to your environment config:

```powershell
Dashboard = @{
    OutputPath = '\\pull01\SPSWeather$'              # folder/share the farm servers write to
    Url        = 'https://pull.contoso.com/spsweather' # public IIS base serving that folder
}
```

| Key | Description |
|---|---|
| `OutputPath` | Folder (local or UNC share) that receives `<App>-<Env>-<Farm>-dashboard.html`. Empty = `Results\` (local only). |
| `Url` | Public base URL serving that folder over IIS. The email button links to `<Url>/<App>-<Env>-<Farm>-dashboard.html`. Empty = no button. |

The per-farm history (the bar chart) is built from the JSON snapshots under
`Results\history\<Farm>\`, capped at `JsonHistoryRetentionDays` runs.

## Hosting the dashboard on IIS

Provision the hosting target once with the standalone, idempotent helper
`New-SPSDashboardSite.ps1` (run elevated on the IIS / pull server). It creates the folder,
an SMB share (so every farm server can publish to it), NTFS permissions, a static-file
`web.config` (avoids HTTP 404.17), and either a dedicated IIS site or a sub-application.

Dedicated site:

```powershell
.\New-SPSDashboardSite.ps1 -Path 'E:\inetpub\spsweather' -ShareName 'SPSWeather$' `
    -WriteAccounts 'CONTOSO\svcspsfarm' -SiteName 'SPSWeatherDashboard' -Port 8081
```

Sub-application under an existing site (e.g. the SPSConfigKit pull server):

```powershell
.\New-SPSDashboardSite.ps1 -Path 'C:\inetpub\PSDSCPullServer\SPSWeather' -ShareName 'SPSWeather$' `
    -WriteAccounts 'CONTOSO\svcspsfarm' -ParentSite 'PSDSCPullServer' -AppAlias 'SPSWeather'
```

The script is deliberately standalone (no module dependency) and supports `-WhatIf`,
`-SkipShare`, `-SkipNtfs` and `-SkipIis`. When it finishes it prints the exact
`Dashboard.OutputPath` and `Dashboard.Url` values to set in your config.
