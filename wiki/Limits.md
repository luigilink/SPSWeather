# Limits

Since **3.6.0**, SPSWeather compares each farm with the **supported limits of SharePoint** and reports the ones that are reached:
a content database that grows toward 200 GB, a web application with too many managed paths, a Distributed Cache host given more
memory than it supports. The limits come from Microsoft's
[Software boundaries and limits](https://learn.microsoft.com/en-us/sharepoint/install/software-boundaries-limits-2019) (they apply to
SharePoint Server 2016, 2019 and Subscription Edition).

The check is **read-only** and **active by default**. A farm that is below every threshold adds **nothing** to the report: the
dashboard, the email and the counts are the ones of before.

> **After an upgrade to 3.6.0**, a farm that is already above a threshold gets a **new alert at its first run** (for example a content
> database of 180 GB raises a warning). That is the check working, not a change in the farm. To adapt the thresholds of your farm, or to
> accept a known case, see [Configuration](#configuration) below.

## What is checked

| Check (`Limits` key) | What is measured | Warning from | Failure above | Limit of Microsoft |
|---|---|---|---|---|
| `ContentDatabaseSize` | GB of **data** of each content database | 150 | 200 | 200 GB per content database (general usage) |
| `SiteCountPerDatabase` | Site collections of each content database | 5000 | 10000 | 5,000 recommended, 10,000 supported |
| `ContentDatabasesPerFarm` | Content databases of the farm | 375 | 500 | 500 per farm |
| `WebApplicationsPerFarm` | Web applications of the farm | 15 | 20 | 20 per farm |
| `ManagedPaths` | Managed paths of each web application, and managed paths for host-named site collections | 15 | 20 | 20 per web application, 20 per farm for host-named site collections |
| `DistributedCacheSize` | GB of memory given to the cache of each Distributed Cache host | none | 16 | 16 GB per cache host (boundary) |
| `ApplicationPoolsPerServer` | IIS application pools of each web server | 11 | none | 10 per web server (threshold) |
| `SearchTopology` | Search components on a server, and in the whole Search service application | none | fixed | See below |

A **warning** is raised from the *Warning from* value (75 % of the supported limit for the sizes and the counts), and a **failure**
above the limit, which Microsoft calls *supported*. The application pools are the exception: Microsoft calls 10 per web server a
*threshold*, a default that can be exceeded with the memory to match, so only a warning exists, raised as soon as it is exceeded.

**Search topology** has fixed limits that cannot be changed: per server, at most 4 index components and 1 crawl, content processing,
query processing and analytics processing component each; for the Search service application, at most 60 index components, 16 crawl
components, 6 analytics processing components and 25 index partitions. Exceeding one is a failure.

### How the size of a content database is measured

The limit is about the **content**, so the **log is never counted**. The check uses, in this order:

1. the **used size of the data** (`FILEPROPERTY(name, 'SpaceUsed')` of the data files), **only for the databases whose allocated size
   already reaches the warning threshold**. A healthy farm never runs this query;
2. the **allocated size of the data files**, from the SQL section of the report. It is an upper bound: if it is below the warning
   threshold, the database is below it too;
3. the size that SharePoint reports, **log included**, only when the two above are not available.

The row says which one it used: `(used)`, `(allocated)` or `(as reported by SharePoint, log included)`. When the used size could not be
read (SQL server not reachable, no permission), the row says so and keeps the allocated size. A database is always matched with the sizes
of **its own SQL server**: two servers that hold a database of the same name never share a size. The reads of the used size have a
**time budget of two minutes** for all the databases together; when it is spent, the databases left are not tried and keep their allocated
size, so that a SQL server that does not answer cannot delay the report.

**Remote BLOB Storage**: Microsoft's limit includes the external BLOBs, which SQL Server cannot see, so the size read here does not
count them. The row of a database that uses RBS is meant to say so in a note, but **that note does not show yet** ([#149](https://github.com/luigilink/SPSWeather/issues/149)):
if you use RBS, keep in mind that the real size is larger than the one shown.

## What a row looks like

Each object at or above a threshold is one row of the section **Supported limits** of the area **Capacity & limits** (*Capacité et
limites* in French):

| Column | Meaning |
|---|---|
| `Farm`, `Limit`, `Object` | The farm, the check, and the database, server or web application concerned |
| `Value`, `Unit` | What was measured |
| `Warning`, `Failure` | The thresholds that applied to this object (exceptions included) |
| `Status` | `Warning` or `Failure` |
| `Recommendation` | A sentence with the value, how it was measured, the thresholds and the reason of the exception, if any |
| `Note` | An additional fact |

A `Failure` row makes the farm **ALERT** (subject tag, High priority, Event ID 2000, like any failed check). A `Warning` row is orange and
does not raise the alert on its own, like the other advisories. The [cockpit](Cockpit-Page) follows each limit from one run to the next by
its check and its object (`ContentDatabaseSize / WSS_Content_A`), so a database that keeps growing stays **one** item, with its age.

## Configuration

The block is **optional**; every key too. The values below are the defaults:

```powershell
Limits = @{
    ContentDatabaseSize       = @{ Warning = 150; Failure = 200 }    # GB of data
    SiteCountPerDatabase      = @{ Warning = 5000; Failure = 10000 }
    ContentDatabasesPerFarm   = @{ Warning = 375; Failure = 500 }
    WebApplicationsPerFarm    = @{ Warning = 15; Failure = 20 }
    ManagedPaths              = @{ Warning = 15; Failure = 20 }
    DistributedCacheSize      = @{ Failure = 16 }                    # GB
    ApplicationPoolsPerServer = @{ Warning = 11 }
    Disabled                  = @()
    Exceptions                = @()
}
```

- A threshold is a **number of 0 or more**, or `$null` for none. A value that cannot be used (a text, a boolean, a negative number, a
  warning above the failure) is **reported and the default of that check is used**: a bad value never stops a run.
- `SearchTopology` has no threshold to set. Use `Disabled` or an exception with `Exempt` for it.
- The block holds plain numbers and lists only, so that it can later move to a JSON configuration as is.

### Turning checks off

- `Disabled = @('ManagedPaths')` turns **one check** off. A name that is not a check is reported and ignored.
- `ExclusionRules = @('LimitStatus')` turns **all** the limit checks off (nothing is read from the farm for them).

### Exceptions

An exception changes the thresholds of **one object**, for one check, so that a known case does not raise the same alert every day:

```powershell
Exceptions = @(
    # A document archive: supported up to 4 TB
    @{ Limit = 'ContentDatabaseSize'; Object = 'WSS_Content_Archive'; Warning = 3072; Failure = 4096; Reason = 'document archive' }
    # A cache host that must not be checked
    @{ Limit = 'DistributedCacheSize'; Object = 'APP2'; Exempt = $true; Reason = 'dedicated cache host, reviewed by the team' }
)
```

| Key | Meaning |
|---|---|
| `Limit` | The check (required) |
| `Object` | The **name** of the database, server or web application, matched **without regard to case** and **exactly** (no wildcard); `host-named site collections` for the managed paths of host-named site collections; the farm name for the checks of the farm (required) |
| `Warning`, `Failure` | The thresholds that replace the ones of the check for this object; `$null` means none |
| `Exempt` | `$true` turns the check off for this object |
| `Reason` | Free text, shown in the recommendation of the row |

An exception must change something (a `Warning`, a `Failure` or `Exempt = $true`); otherwise it is reported and ignored. The first
exception that names the object wins. A threshold that an exception does not give is the one of the check, so the pair is judged as the
object would get it: `Warning = 300` alone is refused when the failure of the check is 200 (give `Failure = $null` too to have none).
**Object names stay on the server**: the run journal and the cockpit only record the number of valid exceptions
(`Limits.Exceptions`), never a name.

### Messages

Every problem of the block is shown in the transcript and recorded in the **Event Log as a Warning, Event ID 2001**. Run
`Test-SPSWeatherReadiness.ps1` to see them before the first run: each one is a `[WARN]` (never a `[FAIL]`) on the line `Key 'Limits'`.

## What is read

| What | How |
|---|---|
| Content databases, with their site count | `Get-SPContentDatabase` on the entry server |
| Web applications and their managed paths, managed paths for host-named site collections | `Get-SPWebApplication`, `Get-SPManagedPath` |
| Used size of the data of a content database | A `SELECT` on `sys.database_files` over a connection of the entry server with **integrated security**, **only** for a database that reaches the warning threshold (the name of the database is the connection's catalog, never a part of the query) |
| Distributed Cache, IIS pools, search topology | The sections that the run has already collected |

Nothing is changed in SharePoint or in SQL Server. The thresholds never travel to the remote side: the facts are read first and
judged afterwards, on the machine that runs the script. A farm that cannot be read gives a **warning in the transcript** and no row
for the checks that need it; it never stops the run.

## In the cockpit and the journal

The thresholds are part of the **settings recorded by each run** (`Limits.ContentDatabaseSize.Warning`, ...), with their origin
(*default* or *configuration*), so the *Settings & method* tab of the [cockpit](Cockpit-Page) shows the ones in use and a change of
threshold appears in the list of changes, and so does a change in the number of exceptions (`Limits.Exceptions`). The checks that are
turned off appear among the excluded names (`Limits.ManagedPaths`).

## See also

- [Health Checks](Health-Checks) — all the checks, and how an ALERT is raised
- [Configuration](Configuration) — the `config.psd1` reference
- [Dashboard](Dashboard) — the area **Capacity & limits**
