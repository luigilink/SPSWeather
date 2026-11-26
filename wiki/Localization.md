# Localization

Since **3.4.0**, the dashboard and the alert email can be shown in another language. English
(`en-US`) is the reference and the default; French (`fr-FR`) is included.

## Choosing the language

Add the `Language` key to the environment configuration file:

```powershell
Language = 'fr-FR'
```

| Value | Result |
|---|---|
| not defined, empty, `'en-US'` | English: the output is exactly the one of the previous versions. |
| `'fr-FR'` | French. |
| `'fr'`, `'fr-BE'`, `'fr_CA'` | French: another culture of a shipped language resolves to it. |
| `'auto'` | The UI culture of the account that runs the script (English when that language is not shipped). |
| anything else | English, with a warning that names the available cultures. |

The language is set explicitly rather than read from the machine because the scheduled task runs
under a **service account** whose UI culture is rarely the one of the operators. With `'auto'`,
the readiness check tells which culture it resolves to *for your session*, which may differ from
the one of the task.

The same language applies to the dashboard and to the email. An unavailable language never stops a
run: SPSWeather uses English, writes a warning in the transcript and records it in the `SPSWeather`
Event Log (event ID 2001). The readiness check (`Test-SPSWeatherReadiness.ps1`) shows a `[WARN]`.

## What is translated, and what is not

Only the **display** is translated: titles, area names, section labels, counters, buttons, tooltips,
the sentences and the footer of the email, the `<html lang>` attribute, and the way numbers are
written (`5.25% free` or `5,25 % libres`).

These stay as collected, on purpose:

| Kept in English | Why |
|---|---|
| The **values** of the checks and the notes of the collectors (`Unreachable`, `Failed`, `no full backup found`...) | The severity model and the run history rely on them. Translating them would change what is an alert. |
| The **column headers** of the detail tables | They are the technical names of the collected properties. |
| The email subject tags `[ALERT]`, `[WARN]`, `[OK]` | Mail rules and filters match on them. |
| The Event Log messages and the console output | They are meant for the administrators of the solution. |

## Resource files

The strings live in one data file per culture, inside the module:

```text
Modules\SPSWeather.Common\
  en-US\SPSWeather.Common.Strings.psd1    <- reference
  fr-FR\SPSWeather.Common.Strings.psd1
```

- **Keys** are stable identifiers (`OverallHealth`, `Area_SQL`, `Section_SQLAliasStatus`...).
- **Values** are plain text: never HTML, the renderers encode them.
- **`{0}`, `{1}`...** are placeholders filled by the code (a count, a name, a percentage). Keep all of
  them, in the order the target language needs.
- A key missing from a translation shows the **English text** instead of an empty label: the English
  strings are always loaded first and the chosen culture is laid over them.
- Singular and plural forms are separate keys (`ItemCountOne` / `ItemCountMany`, `LastRunsOne` /
  `LastRunsMany`).
- **`HistoryDateFormat`** is the .NET format of the dates under the history bars (`MM-dd` in English,
  `dd/MM` in French): write the order your readers expect.
- **`Percent`** and **`FreePercent`** place the `%` sign. In French a **non-breaking space**
  (U+00A0) goes before it, so the sign never wraps alone onto the next line.

## The cockpit page

The [cockpit page](Cockpit-Page) uses the same resource files. Its labels, the sentences that explain the figures and the text of
the *Settings & method* tab are the keys that start with `Cockpit`, plus a few shared ones (`Section_...`, `Weather...`,
`CountsSummary`, `Percent`...):

| Keys | Used for |
|---|---|
| `CockpitTab...`, `CockpitSec...` | The tabs and the titles of the sections |
| `CockpitKpi...`, `CockpitCta...`, `CockpitAsOf...` | The four cards, their buttons and their "as of" labels |
| `CockpitInsight...` | The sentences that say what a figure means (fixed rules, see [Cockpit page](Cockpit-Page#insight-sentences)) |
| `CockpitQ...`, `CockpitNote...` | The *Data quality* tab and its notes |
| `CockpitR...`, `CockpitMail_...` | The *Collection tracking* tab and the outcome of the email |
| `CockpitSetting_...`, `CockpitFrom...`, `CockpitMethod...` | The *Settings & method* tab |

- The page holds the strings of **every** shipped language, opens in the configured one and switches without a new run. A language you
  add (a new folder) appears in the page with no change in the code.
- A key that a translation lacks shows the **English text**, as in the dashboard: a partial translation never leaves a key name on the page.
- A language whose file the module refuses (a wrong `Culture` key, a placeholder the English text does not have) is **not offered** in the
  page, and the page opens in English.
- A language that is not shipped (`Language = 'ja-JP'`) gives the English page, complete.
- Dates and numbers follow the language of the page, never the setting of the machine that opens the file.
- Only the red error banner and the "JavaScript is required" notice are in English, because they are shown when the page cannot start.
- The values that come from the checks (item names, causes, details) stay as collected, as in the dashboard.

## Asking for a language

Your language is not shipped yet? Open an issue with the
[Translation Request](https://github.com/luigilink/SPSWeather/issues/new?template=5_translation_request.yml)
form: it asks for the culture name (`de-DE`, `es-ES`, `it-IT`...), whether you can review or translate
the file, and the terminology to align on. Requests are handled in the order the users ask for them, and a
language is only shipped once a **native speaker** has reviewed it, because a wrong word on a dashboard is
worse than an English one.

What a reviewer looks at:

- the **SharePoint terms** (timer jobs, application pools, Search, Distributed Cache...) are the ones of the
  localized SharePoint Server interface that your administrators know;
- numbers, percentages and dates follow the habits of the language (`78 %` with a non-breaking space in
  French, `dd/MM` or `dd.MM` for the history dates);
- the text reads well in the **dashboard** and in the **email** (short labels, singular and plural forms).

## Adding a language

1. Copy `en-US\SPSWeather.Common.Strings.psd1` to a new folder named after the culture, for example
   `de-DE\SPSWeather.Common.Strings.psd1`.
2. Set `Culture` and `HtmlLang` (`'de-DE'`, `'de'`), then translate the values.
3. Save the file as **UTF-8 with BOM**: Windows PowerShell 5.1 reads a file without a BOM as ANSI and
   corrupts accented characters.
4. Write an apostrophe inside a value as `''` (two ASCII apostrophes). A typographic apostrophe
   (`’`) is read by PowerShell as a quote and closes the string, so the file cannot be loaded: the
   run then shows the English text and reports `Language 'de-DE' cannot be used: ...` (transcript,
   Event ID 2001, readiness `[WARN]`). It never stops the report.
5. Run the test suite. It checks that the new file has **exactly the same keys and placeholders**
   as `en-US`, no empty value, no HTML, no stray brace, a date format that works, and that every key
   used by the code is defined. Then set `Language = 'de-DE'` in a configuration and run the
   readiness check: it loads the file and rejects a wrong `Culture`, a placeholder the English text
   does not have, or a stray brace.

## Previewing a language without running a check

The dashboard and the email can be rendered from a previous JSON snapshot:

```powershell
Import-Module .\Modules\SPSWeather.Common\SPSWeather.Common.psd1 -Force

# Dashboard
Export-SPSWeatherReport -InputFile .\Results\contoso-PROD-CONTENT.json `
    -OutputFile .\Results\preview-fr.html -Farm 'CONTENT' -Application 'contoso' -Environment 'PROD' `
    -Language 'fr-FR'

# Email
$json = Get-Content .\Results\contoso-PROD-CONTENT.json -Raw | ConvertFrom-Json
ConvertTo-SPSWeatherEmailBody -InputObject $json -Farm 'CONTENT' -Application 'contoso' `
    -Environment 'PROD' -Language 'fr-FR' |
    Set-Content .\Results\preview-fr-mail.html -Encoding UTF8
```

With `SMTPPreview = $true` the run itself writes `Results\<App>-<Env>-<Farm>-mail.html` (or
`Results\<App>-<Env>-mail.html` with `EmailMode = 'Consolidated'`) in the chosen language (see
[Configuration](Configuration)).
