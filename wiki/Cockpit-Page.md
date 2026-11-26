# Cockpit page

The multi-farm page of an environment, the *cockpit*: **one self-contained HTML file** that shows every farm of the configuration, for
management and for the IT team. It describes version **3.5.0** (in preparation). The page is read-only: it is built from the files that
the runs leave in `Results\` (see [Cockpit data](Cockpit-Data)) and nothing is collected from the farms for it.

## Producing the page

The function `Export-SPSWeatherCockpit` builds the dataset and writes the file:

```powershell
Import-Module .\Modules\SPSWeather.Common\SPSWeather.Common.psd1
Export-SPSWeatherCockpit -OutputFile .\Results\contoso-PROD-cockpit.html -ResultsFolder .\Results `
    -Application contoso -Environment PROD -FarmName CONTENT, SEARCH -RetentionDays 30 -Language en-US
```

The file is written through a temporary file that replaces the page in one step, so a reader never sees a half-written page. The run
does not call the function yet: the opt-in key that produces the page after every run comes in the same version.

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

The period (7, 14, 30 or 60 days) is limited by `JsonHistoryRetentionDays`: the page never offers more days
than the history keeps.

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
