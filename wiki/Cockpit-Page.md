# Cockpit page

The multi-farm page of an environment, the *cockpit*: **one self-contained HTML file** that shows every farm of the configuration, for
management and for the IT team. It describes version **3.5.0**. The page is read-only: it is built from the files that
the runs leave in `Results\` (see [Cockpit data](Cockpit-Data)) and nothing is collected from the farms for it.

## Producing the page

### From the run

Set `Dashboard.Cockpit = $true` in the environment configuration (see [Dashboard](Dashboard#the-cockpit-page)). The run then writes `<App>-<Env>-cockpit.html` next to the dashboards
(`Dashboard.OutputPath`, or `Results\`), at the **end of the run**, after the emails and the run journal. The key is optional and `$false` by default: nothing changes unless it is set.
With `EmailMode = 'Consolidated'` and a `Dashboard.Url`, the consolidated email carries an *Open the cockpit* button. A failure to write the page is recorded (Event ID 3002) and never fails the run.

### From a console

The function `Export-SPSWeatherCockpit` builds the dataset and writes the file:

```powershell
Import-Module .\Modules\SPSWeather.Common\SPSWeather.Common.psd1
Export-SPSWeatherCockpit -OutputFile .\Results\contoso-PROD-cockpit.html -ResultsFolder .\Results `
    -Application contoso -Environment PROD -FarmName CONTENT, SEARCH -RetentionDays 30 -Language en-US
```

The file is written through a temporary file that replaces the page in one step, so a reader never sees a half-written page.

## One file, nothing loaded

Style, script, data and display strings are all inside the file. It opens from a file share, from a SharePoint library or by a
double-click, and it never asks for anything else: no CDN, no font, no image, no network request.

If the script fails, a red banner at the top of the page says why instead of leaving a blank page. With scripts turned off, a message
says that JavaScript is required.

## Tabs

| Tab | Content |
|---|---|
| **Executive** | Four cards: **health** (share of OK rows in the latest snapshot of each farm), **days without failure** (among the days that have a snapshot; a day with an unreachable run is not one of them), **open attention items** (and how many are new at the latest snapshot), **collection** (share of days with a snapshot). Then one card for each farm, the daily trend of all the farms, the weather, and the list of items that need attention (the ten oldest failures first, the others behind a fold). |
| **IT** | The **causes grouped** (same section and same cause across items and farms; `#` stands for a number), the farms by section, a **stability** strip with one square for each day and farm (described in words for a screen reader, with the day by day detail in a table under each strip), and the items of each farm with their detail. |
| **Data quality** | Freshness of the latest snapshots, days with data, history kept, files that could not be read, a table for each farm, and notes: days without a snapshot, "since" dates that are only a lower bound, lists that are capped, checks excluded by the configuration. |
| **Collection tracking** | The [run journal](Cockpit-Data#run-journal): number of runs, runs that reached every farm, average and last duration, duration chart, the last 50 runs (farms reached, email outcome, version) and the days when a farm was unreachable. |
| **Settings & method** | The settings in effect with their origin (configuration or default, and invalid), the configuration file, the excluded checks, the changes between two runs **in the selected period**, and the method: how health, severity, weather and "since" are computed. |

The settings shown are the last ones the run journal recorded. When the latest runs did not record any (a journal written before 3.5.0), the page says which run they come from instead of attributing them to the newest run.

Each card gives its figure, the change against the previous period (when the history covers it), an "as of" label and a button to the
place where the detail is.

The card of each farm on the *Executive* tab, and its detail on the *IT* tab, have an *Open the farm dashboard* link to the dashboard of the farm (`<App>-<Env>-<Farm>-dashboard.html`),
and the dashboard has a link back to the page. The links are relative: the dashboards and the page are written to the same folder (`Dashboard.OutputPath`), so they work from IIS, a file
share or a folder. A farm whose dashboard is not in that folder has no link.

The period (7, 14, 30 or 60 days) is limited by `JsonHistoryRetentionDays`: the page never offers more days
than the history keeps.

## Insight sentences

Each card of the Executive tab (health, days without failure, open attention items, collection) and the weather card carry **one
sentence** that says what the figure means. The sentences follow **fixed rules** on the data of the page: no external service, no
estimate, and the same data always gives the same text (ties are broken by date, severity, farm name and item name, never by the
locale of the machine).

| Card | The first rule that applies | Sentence |
|---|---|---|
| **Health** | The latest snapshot is compared with the **average** of the previous period of the same length. A change of 1 point or more is "down" or "up", less is "stable". Without a previous period, it counts the failures (or the warnings) of the latest snapshot. | "Down 10.0 pts against the average of the previous period." |
| | Added when two or more checks fail, the list is complete, and **more than half** of the failing items are in one section. | "Most of the failures are in: SQL - Databases." |
| **Days without failure** | The latest day with a snapshot has no failure. Otherwise the last day that had none, and how long before. Otherwise none in the period. | "Last day without failure: 11/23, 3 day(s) before the latest snapshot." |
| **Open attention items** | The list is complete, at least two items share the **same cause** (same section and same text, numbers replaced by `#`) and they are at least half of the items. | "3 of the 4 items share one cause: no full backup found." |
| | Otherwise the **oldest** item: its name and how long it has been open **up to the latest snapshot of its own farm**, or "since 11/13 or before" when the history starts there. "Every item appeared at the latest snapshot" is said only when that holds for every item. | "The oldest item is itemA, open for 5 day(s), since 11/21." |
| **Collection** | A farm was unreachable in the period (including a day on which it also has a snapshot): the most recent one and how many farm-days were lost. Otherwise farm-days without a snapshot. Otherwise "every farm was collected on every day". | "FarmB could not be reached on 11/25." |
| **Weather** | The farm with the most failures at its latest snapshot, and since when **every snapshot** of that farm has had failures: the dataset reads it from all the snapshots, so a clean one in the morning breaks a streak even when the last snapshot of the day has failures (days without a snapshot or unreachable do not break the series). Otherwise the warnings, or "nothing to report". | "A has had failures at every snapshot since 11/23." |

When a list is capped, the page does not claim a share or a common cause (it cannot know them), and says nothing in place of a guess.
A value that comes from a farm (an item name, a cause) is escaped like everywhere else in the page. The sentences are resource strings,
`CockpitInsight...` keys, translated like the labels (see [Localization](Localization)).

## State in the URL

The period, the language, the theme and the tab are kept in the part of the address after `#`, so a link opens the page the way you
left it. Values that are not valid are ignored.

| Key | Values | Default |
|---|---|---|
| `tab` | `direction`, `it`, `quality`, `runs`, `method` | `direction` |
| `p` | the period in days, one of those offered | `30`, or the longest one offered |
| `lang` | a language that ships with SPSWeather, for example `fr-FR` | the `Language` of the configuration |
| `theme` | `light` or `dark` | follows the system setting |

For example: `contoso-PROD-cockpit.html#tab=it&p=14&lang=fr-FR&theme=dark`. A value equal to the default is not written. Some browsers
do not let a page change the address of a file opened from disk: the state then lives in memory only and a refresh starts again from
the defaults.

## Languages

Every label comes from the resource files (see [Localization](Localization)), keys `Cockpit...` and a few shared ones. The page holds
the strings of **every** language that ships with SPSWeather and opens in the configured one; a switch changes it without a new run. A
key that a translation lacks shows the English text. Dates and numbers follow the language of the page, never the setting of the
machine that opens it. Values that come from the checks (item names, causes, details) stay as the collectors wrote them. Only the
messages of the error banner and of the "scripts are off" notice are English.

## Security

The farms' names, item names, URLs and messages reach the page as data. Every value that goes into the markup is **HTML-escaped by
default**: the page builds its markup with a helper that escapes anything that is not explicitly marked as markup. The data itself is
embedded as JSON in which `<`, `>`, `&` and the two Unicode line separators are written as escapes, so a value can neither close the
script element nor open a comment. The tests build a page from hostile names (`</script>`, `<img onerror>`, quotes, `<!--`) and check that
nothing runs and that nothing is left unescaped.

## Limits

- The page shows what the runs recorded. An item that was resolved is no longer in the latest snapshot, so the page lists what is open,
  not what was fixed.
- "Since" is the first snapshot of the unbroken series in which the item needed attention. At the start of the history it is a lower
  bound: the page says "since ... or before".
- The lists are capped (300 items and 400 snapshots for each farm): the page says so when a list is cut.
- The health figure adds up the **latest snapshot of each farm**, even when one farm's is older than the others'; the farm card then says how many days it has been since its last snapshot. A farm with no check in its snapshot shows a dash instead of a percentage.
- The activity figures (users, sites, storage) are not part of this version.
