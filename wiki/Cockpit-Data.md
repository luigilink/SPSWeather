# Cockpit data

What a run leaves in `Results\` for the multi-farm page (the *cockpit*), and how it is read. The page itself comes in a later
version; this page documents the data it is built from. Everything here is **read-only**: nothing is collected from the farms for it.

## Run journal

`Results\<App>-<Env>.runs.json` holds one record per run. The name has a dot (`.runs.json`) so that it can never be the name of the
snapshot of a farm (`<App>-<Env>-<Farm>.json`, where a farm name only keeps letters, digits, `_` and `-`).

| Field | Content |
|---|---|
| `started`, `durationSeconds` | When the run started (ISO 8601 with the offset) and how long it took. |
| `version`, `language`, `emailMode` | Version of SPSWeather, display language, `PerFarm` or `Consolidated`. |
| `mail` | `sent`, `preview`, `disabled`, `failed` (an email was expected and none went out, including a missing relay setting) or `none` (nothing to send, for example every farm unreachable). |
| `farms` | For each configured farm: `name`, `outcome` (`ok` or `unreachable`) and, when it was reached, `ok`, `warn` and `fail`. A farm that cannot be reached leaves no JSON snapshot, so this is its only trace over time. |
| `settings` | The settings in effect, see below. Absent in a journal written before 3.5.0. |

How it is written:

- Through a temporary file that replaces the journal in one step, so a crash never leaves a truncated file.
- Under an exclusive lock on `<name>.lock` (an empty file that stays next to the journal), so that a manual run and the scheduled task
  cannot drop each other's record. A run that cannot get the lock within 20 seconds gives up with a warning.
- Pruned with `JsonHistoryRetentionDays` (0 keeps everything) and never more than 1000 records.
- A journal that cannot be read (not valid JSON, the root is not an object, `runs` is not a list, a newer schema) is kept aside as
  `<name>.corrupt` and a new one starts. A file that exists but cannot be opened (a lock, access denied) is **not** treated as corrupt.
- Fields that this version does not know are kept when the journal is rewritten.
- A failure to write the journal is a warning, never a failed run.

## Settings in effect

Each record of the journal says which thresholds the run really used, so that "which threshold applied?" has an answer:

- `configFile`: the file name of the configuration, without its folder.
- `thresholds`: for `SQLDiskFreeThresholdPercent`, `SQLBackupMaxAgeDays`, `JsonHistoryRetentionDays`, `EmailMaxItemsPerArea` and
  `LogRetentionDays`, the `value` and its `source`: `config`, or `default` when the file does not set it (`invalid: true` when it held
  a value that could not be used).
- `exclusionRules`: the exclusions that the run really applies. They are asked the same question as the entry script does
  (`Contains('Name')`), so a list matches exact names and a single string matches as a substring; a typo or a path typed there
  excludes nothing and is not recorded.

Nothing else of the configuration is recorded: no server, address, credential key, URL or path. The list of keys is fixed in
`Get-SPSWeatherRunSetting`, which is also the only place that resolves these thresholds.

A threshold must be a whole number of 0 or more. Anything else (`abc`, a blank, `-1`) is reported (transcript, Event ID 2001) and the
default is used. `EmailMaxItemsPerArea` keeps its rule that a negative number counts as 0.

The footer of the per-farm dashboard shows the configuration file and the SQL thresholds applied, with `(default)` next to a value
that the file does not set.

## The dataset

`Get-SPSWeatherCockpitData` (private) reads the snapshots of each farm, the journal and the settings, and returns one structure
(`schemaVersion` 1) ready for `ConvertTo-Json`.

| Section | Content |
|---|---|
| `period` | The periods offered, `firstDay`, `lastDay`. |
| `days`, `weekend` | One entry per calendar day, from the first day with data to today. |
| `farms[].daily` | For each day, aligned with `days`: `ok`, `warn`, `fail`, `weather`, `snapshots` (files of the day), `unreachable` (runs of the day, from the journal); `null` when nothing is known. |
| `farms[].attention` | What needs attention in the last snapshot: `section`, `id`, `name`, `severity`, `cause`, `detail`, `count`, `since`, `sinceIsLowerBound`. |
| `runs`, `settings` | The journal records of the period, the settings of the last record that has some, and what changed between two records. |
| `skipped` | The files that were not used, by name (at most 20). |
| `kpi` | `null`: reserved for the nightly activity run. |

Rules:

- **Periods.** 7, 14, 30 and 60 days, limited by `JsonHistoryRetentionDays` (a retention of 0 offers all of them). The retention is
  never changed and nothing is deleted.
- **A day** is described by its last usable snapshot. The date of a snapshot is the time its file was written, which the archive keeps.
  Nothing dated after today is read.
- **Since when.** Every usable snapshot counts: the `since` of an item is the day of the first snapshot of the unbroken series of
  snapshots in which it also needed attention, so an item fixed and back the same day starts again. A day without snapshot (the farm was
  not reached) does not break the series. `sinceIsLowerBound` is true when the series starts at the oldest snapshot read.
- **Identity of an item.** An item is recognised from one run to the next by the columns that name the thing (the server, the database, the
  application pool, the volume...), never by the columns that describe its state or its figures. The role of an availability group
  replica (`PRIMARY` / `SECONDARY`) is a state, so a failover does not restart `since`. A section that is not listed uses every column
  except the noise of remoting and the state columns.
- **Cause.** The detail of an item with its numbers replaced by `#`, so that "last full backup 4.5 d ago" and "last full backup 6 d ago" group together.
- **Weather.** No failure and no warning is `sunny`, no failure is `fair`, up to 5 failures is `cloudy`, more is `stormy` (the rule of the
  per-farm dashboard).
- **Counting.** One function counts a snapshot (OK, warnings, failures) for the bars of the dashboard and for the page, so they cannot disagree.
- **Several environments.** The archive folder of a farm is shared by the environments of an installation that name a farm the same;
  only the files named `<App>-<Env>-<Farm>-*.json` are read, and the retention of one environment only removes its own archives.
- **Limits.** At most 400 snapshots are read for a farm (the most recent ones, flagged with `snapshotsTruncated`) and 300 items are listed
  for a farm (`attentionTruncated`).
- **Files that cannot be used** (missing, empty, not valid JSON, the root is not an object, a list of one object) are skipped with a warning
  and listed in `skipped`. A journal that cannot be read is ignored. The dataset never makes a run fail.

Speed: with 4 farms, 60 days and about 460 rows per snapshot, one run a day, building the dataset takes about 6 seconds in PowerShell 7
and about 40 seconds in Windows PowerShell 5.1 (mostly the severity model applied to every row and `ConvertFrom-Json`). A typical farm is several times faster.
