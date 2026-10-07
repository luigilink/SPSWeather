# SPSWeather - Release Notes

## [3.1.0] - 2026-10-07

### Added

- New cards dashboard: `Export-SPSWeatherReport` now renders a modern per-farm
  dashboard (overall-health donut, 30-run history bar chart with trend arrows,
  functional-area cards (up to nine) with collapsible detail tables) in place of the
  legacy table report. One `<App>-<Env>-<Farm>-dashboard.html` per farm, meant
  to be hosted on an IIS site like SPSUpdate.
- `ConvertTo-SPSWeatherEmailBody`: short, Outlook-safe alert email that lists
  only the items needing attention, grouped by area, with a KPI strip and a CTA
  button linking to the hosted dashboard.
- `New-SPSDashboardSite.ps1`: standalone, idempotent, `-WhatIf`-aware helper that
  provisions the IIS hosting target (folder + SMB share + NTFS + static-file
  `web.config` + dedicated site or sub-application) for the dashboard.
- Config: new `Dashboard = @{ OutputPath; Url }` block — `OutputPath` is where the
  per-farm HTML is written (fallback `Results\`), `Url` is the public IIS base used
  to build the email CTA link.
- `Set-SPSCredSSPClient`: configures the CredSSP **client** role and fresh-credentials
  delegation (scoped to the farm FQDNs) so SPSWeather can run from a non-SharePoint
  host (orchestration/PULL server). Called automatically by `-Action Install`; the
  CredSSP server role stays owned by DSC on the farms. A pre-existing (possibly
  GPO-enforced) delegation policy is detected and preserved.
- A single shared severity model classifies rows for the dashboard, email, history and
  per-farm outcome, so unreachable servers and advisory recommendations are counted
  consistently.
- `Invoke-SPSCommand -AllowFallback`: optional Negotiate fallback when CredSSP cannot be
  established, with a clear warning and an aggregated error when all methods fail.

### Fixed

- `Start-Transcript` no longer fails on a fresh host — the `Logs\` folder is created
  before transcription starts.
- Only farms actually reached are published/emailed (an unreachable farm is no longer
  reported as healthy); per-farm failures are isolated by a `try/catch` instead of a
  broad trap; the history chart shows the latest 30 runs regardless of the day-based
  retention; the per-farm subject/outcome reflects warnings as well as failures.

### Changed

- The entry script now produces one dashboard and one short email per farm:
  the aggregate report is sliced by farm, and each farm gets its own dashboard
  file, JSON snapshot, history folder and alert email.

### Removed

- The legacy full-table HTML report (`Join-HtmlBodyFromPSo` / `Join-HtmlTable`)
  is replaced by the dashboard and the short email.

### Setup

Provision the IIS hosting target once with `New-SPSDashboardSite.ps1`, then set
`Dashboard.OutputPath` (the folder/share it writes to) and `Dashboard.Url` (its
browse URL) in your environment config. SPSWeather must run as a local administrator;
`-Action Install` configures the CredSSP client automatically. See the wiki
Prerequisites and Dashboard pages.

A full list of changes can be found in the [change log](CHANGELOG.md).
