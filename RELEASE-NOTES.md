# SPSWeather - Release Notes

## [2.4.0] - 2026-11-26

Maintenance release of the **2.x line** for SharePoint Server **2016 and 2019**, which left support on 14 July 2026, and still
compatible with **Subscription Edition**. It is built on the code of 3.4.1 and keeps the SharePoint 2016/2019 code path that 3.0.0
removed (the `Microsoft.SharePoint.PowerShell` snap-in, the AppFabric Distributed Cache check, the detection of the product version),
so the work of 3.1.0 to 3.4.1 is available on these versions too.

### What you get since 2.3.7

- A **cards dashboard** and a **short alert email** for each farm: the email lists only what needs attention, with a button to the
  dashboard of the farm. `New-SPSDashboardSite.ps1` hosts the dashboards on IIS (a dedicated site, a virtual directory or an
  application).
- **One consolidated email for all the farms** of an environment (`EmailMode = 'Consolidated'`): totals on top, one card per farm,
  and a card for a farm that cannot be reached instead of silence.
- A new check: **every Timer service instance of the farm must be `Online`**. One instance in another state breaks the
  communication between the servers, which notably blocks the deployment of a WSP.
- A **French translation** of the dashboard and of the email (`Language = 'fr-FR'`) and the machinery to add other languages.
- `SMTPEnabled` and `SMTPPreview` in the configuration (`-EnableSmtp` still works but is deprecated), the cap `EmailMaxItemsPerArea`,
  the CredSSP client set-up for a host that is not a SharePoint server (`-Action Install`), and the fixes of 3.1.0 to 3.4.1, among
  them the **View detail** link of the dashboard.

### What changes for a 2.3.7 installation

- **One dashboard and one email per farm**, not one report for the environment. The subject is now
  `[ALERT] <App>/<Env>/<Farm> - SPSWeather` (`[WARN]` and `[OK]` also), or `[ALERT] <App>/<Env> - 3 farms (...) - SPSWeather` in
  `Consolidated` mode. **Update the inbox rules that filter on the old subject** (`[ALERT]<App>_<Env> - Meteo SharePoint <date>`).
- The files of a run change: `Results\<App>-<Env>-<Farm>.json`, the history in `Results\history\<Farm>\`, and the dashboards in
  `Dashboard.OutputPath` (`Results\` when it is empty). The old `<App>-<Env>-<date>.html` and `.json` are no longer written.
- To get the dashboard link in the email, host the dashboards once with `New-SPSDashboardSite.ps1`, then set `Dashboard.OutputPath`
  and `Dashboard.Url` in the environment configuration. SPSWeather must run as a local administrator.
- **No configuration key is required**: every new key is optional and an existing configuration keeps working. To review the
  email without an SMTP relay, set `SMTPEnabled = $false` and `SMTPPreview = $true`, run, and open `Results\*-mail.html`.
- Replace the `Modules` folder and the scripts with the ones of this archive and keep `Config\` and `Results\`. See the example
  configuration `Config\CONTOSO-PROD.example.psd1` for the new keys.

### What has been tested

- The whole test suite of 3.4.1 passes on this branch, on PowerShell 7 and on Windows PowerShell 5.1 (continuous integration), and the
  code analysis is clean.
- On the servers of a **Subscription Edition** lab, the `Microsoft.SharePoint.PowerShell` snap-in is registered and loads next to the
  `SharePointServer` module, which is what the restored loading code relies on (a Subscription Edition farm is still supported by
  this line).
- **This release was not run on a real SharePoint 2016 or 2019 farm**: the lab has none. The code path for those versions is the one of
  2.3.7, restored unchanged. If you run it on 2016 or 2019, a report of what worked and what did not is very welcome
  (https://github.com/luigilink/SPSWeather/issues).

### About the versions

The 3.x line (`main`) is for Subscription Edition only and gets the new features. This 2.x line is maintained from 3.4.1 for 2016 and
2019 and will get the fixes that are asked for.

A full list of changes can be found in the [change log](CHANGELOG.md).
