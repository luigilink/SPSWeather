# Behavioural tests for Export-SPSWeatherCockpit (public) and ConvertTo-SPSWeatherCockpitHtml (private): the multi-farm page,
# one self-contained file built from the files that the runs leave in Results.

$node = Get-Command -Name node -ErrorAction SilentlyContinue

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
    $script:nodePath = (Get-Command -Name node -ErrorAction SilentlyContinue).Source

    $script:hostileFarm = '</script><script>window.__pwned=1</script>'
    $script:hostileItem = '<img src=x onerror=window.__pwned=2>'
    $script:hostileCause = '<!-- "quoted" & {{SCRIPT}} ' + [char]0x2028 + ' end'

    function script:New-Results {
        $root = Join-Path -Path $TestDrive -ChildPath ('res-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $root
    }

    function script:New-Snap {
        param([int]$Fail = 0, [int]$Ok = 0, [string]$Name = 'DB', [string]$Cause = 'last full backup 4.5 d ago')
        $rows = @()
        foreach ($i in 1..$Fail) { if ($Fail -gt 0) { $rows += [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = "$Name$i"; Recommendation = $Cause; IsInfo = $false } } }
        $snap = [PSCustomObject]@{}
        if ($rows.Count -gt 0) { $snap | Add-Member -MemberType NoteProperty -Name SQLDatabaseStatus -Value $rows }
        $oks = @()
        foreach ($i in 1..$Ok) { if ($Ok -gt 0) { $oks += [PSCustomObject]@{ Farm = 'F'; Server = "S$i"; Status = 'OK'; IsInfo = $true } } }
        if ($oks.Count -gt 0) { $snap | Add-Member -MemberType NoteProperty -Name SPUpgradeStatus -Value $oks }
        $snap
    }

    function script:Add-Snap {
        param($Results, [string]$Farm, [datetime]$When, $Snapshot)
        $safe = $Farm -replace '[^A-Za-z0-9_-]', '_'
        $folder = Join-Path -Path $Results -ChildPath "history/$safe"
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $file = Join-Path -Path $folder -ChildPath ("zebes-PROD-$safe-" + $When.ToString('yyyyMMdd-HHmm') + '.json')
        [System.IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Snapshot -Depth 6))
        (Get-Item -LiteralPath $file).LastWriteTime = $When
    }

    function script:Get-Block {
        param([string]$Html, [string]$Id)
        $m = [regex]::Match($Html, '<script type="application/json" id="' + $Id + '">(.*?)</script>', 'Singleline')
        if (-not $m.Success) { return $null }
        $m.Groups[1].Value | ConvertFrom-Json
    }

    # A results folder with two farms, one of which has hostile names, and a run in the journal.
    function script:New-Fixture {
        $res = New-Results
        $when = (Get-Date).AddDays(-2)
        Add-Snap -Results $res -Farm 'CONTENT' -When $when -Snapshot (New-Snap -Fail 2 -Ok 8)
        Add-Snap -Results $res -Farm 'CONTENT' -When $when.AddDays(1) -Snapshot (New-Snap -Fail 1 -Ok 9)
        Add-Snap -Results $res -Farm $script:hostileFarm -When $when.AddDays(1) -Snapshot (New-Snap -Fail 1 -Ok 3 -Name $script:hostileItem -Cause $script:hostileCause)
        [void](Add-SPSWeatherRunJournalEntry -Path (Join-Path -Path $res -ChildPath 'zebes-PROD.runs.json') -Started $when.AddDays(1) -Duration ([timespan]::FromSeconds(90)) -Version '3.5.0' -Language 'en-US' -EmailMode 'Consolidated' -Mail 'preview' -Farm @(
                [PSCustomObject]@{ Name = 'CONTENT'; Outcome = 'ok'; Ok = 9; Warn = 0; Fail = 1 }
                [PSCustomObject]@{ Name = $script:hostileFarm; Outcome = 'unreachable' }))
        $res
    }

    function script:Export-Page {
        param($Results, [string]$Out, [string]$Language = 'en-US', [string[]]$Farm = @('CONTENT', $script:hostileFarm), [uint32]$Retention = 30)
        Export-SPSWeatherCockpit -OutputFile $Out -ResultsFolder $Results -Application 'zebes' -Environment 'PROD' -FarmName $Farm -RetentionDays $Retention -Language $Language -Version '9.9.9' | Out-Null
        [System.IO.File]::ReadAllText($Out)
    }

    $script:results = New-Fixture
    $script:file = Join-Path -Path $TestDrive -ChildPath 'out/zebes-PROD-cockpit.html'
    $script:html = Export-Page -Results $script:results -Out $script:file -Language 'fr-FR'
    $script:data = Get-Block -Html $script:html -Id 'spsw-data'
    $script:page = Get-Block -Html $script:html -Id 'spsw-page'

    # The script and style of the file: everything except the two data blocks
    $script:code = [regex]::Replace($script:html, '<script type="application/json" id="spsw-(?:data|page)">.*?</script>', '', 'Singleline')

    # Keys the script asks for: t('Key') and hasKey('Key'); a trailing underscore is a family built at run time
    $js = [System.IO.File]::ReadAllText((Join-Path -Path $script:moduleDir -ChildPath 'Assets/Cockpit.js'))
    $script:requested = @([regex]::Matches($js, "\b(?:t|hasKey)\('(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value } | Where-Object -FilterScript { -not $_.EndsWith('_') } | Sort-Object -Unique)
    $script:families = @([regex]::Matches($js, "'(\w+_)'\s*\+") | ForEach-Object -Process { $_.Groups[1].Value } | Sort-Object -Unique)
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Export-SPSWeatherCockpit' {
    Context 'the file' {
        It 'writes the page where asked, creates its folder and returns the full path' {
            Test-Path -LiteralPath $script:file | Should -BeTrue
            $returned = Export-SPSWeatherCockpit -OutputFile (Join-Path -Path $TestDrive -ChildPath 'new/deeper/page.html') -ResultsFolder $script:results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT'
            $returned | Should -Be ([System.IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath 'new/deeper/page.html')))
            Test-Path -LiteralPath $returned | Should -BeTrue
        }

        It 'is UTF-8 without a BOM, with LF line endings, and starts with the doctype' {
            $bytes = [System.IO.File]::ReadAllBytes($script:file)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
            $script:html | Should -Match '^<!DOCTYPE html>'
            $script:html.Contains("`r") | Should -BeFalse
        }

        It 'replaces an existing page in one step and leaves no temporary file' {
            $folder = Join-Path -Path $TestDrive -ChildPath 'replace'
            $target = Join-Path -Path $folder -ChildPath 'page.html'
            New-Item -Path $folder -ItemType Directory | Out-Null
            Set-Content -Path $target -Value 'old'
            Export-SPSWeatherCockpit -OutputFile $target -ResultsFolder $script:results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT' | Out-Null
            [System.IO.File]::ReadAllText($target) | Should -Match '^<!DOCTYPE html>'
            @(Get-ChildItem -Path $folder).Name | Should -Be @('page.html')
        }

        It 'fails when the file cannot be written, and leaves no temporary file behind' {
            $blocker = Join-Path -Path $TestDrive -ChildPath 'blocker'
            Set-Content -Path $blocker -Value 'a file, not a folder'
            { Export-SPSWeatherCockpit -OutputFile (Join-Path -Path $blocker -ChildPath 'x/page.html') -ResultsFolder $script:results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT' -ErrorAction Stop } | Should -Throw
            @(Get-ChildItem -Path $TestDrive -Filter '*.tmp' -Recurse).Count | Should -Be 0
        }

        It 'resolves a relative path against the PowerShell location, not the working directory of the process' {
            $dir = Join-Path -Path $TestDrive -ChildPath 'location'
            New-Item -Path $dir -ItemType Directory | Out-Null
            Push-Location -Path $dir
            try { $returned = Export-SPSWeatherCockpit -OutputFile '.\relative.html' -ResultsFolder $script:results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT' }
            finally { Pop-Location }
            Test-Path -LiteralPath (Join-Path -Path $dir -ChildPath 'relative.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path ([System.Environment]::CurrentDirectory) -ChildPath 'relative.html') | Should -BeFalse
            [System.IO.Path]::GetFileName($returned) | Should -Be 'relative.html'
            [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($returned)) | Should -Be 'location'
        }

        It 'raises a terminating error, even without -ErrorAction Stop, when the destination cannot take the page, and leaves nothing behind' {
            $folder = Join-Path -Path $TestDrive -ChildPath 'a-folder'
            New-Item -Path $folder -ItemType Directory | Out-Null
            $threw = $false
            try { Export-SPSWeatherCockpit -OutputFile $folder -ResultsFolder $script:results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT' | Out-Null }
            catch { $threw = $true }
            $threw | Should -BeTrue
            @(Get-ChildItem -Path $folder -Force).Count | Should -Be 0
            @(Get-ChildItem -Path $TestDrive -Filter '*.tmp').Count | Should -Be 0
        }

        It 'reads Results and never writes to it' {
            $before = @(Get-ChildItem -Path $script:results -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTime.Ticks)" })
            Export-SPSWeatherCockpit -OutputFile (Join-Path -Path $TestDrive -ChildPath 'ro/page.html') -ResultsFolder $script:results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT' | Out-Null
            $after = @(Get-ChildItem -Path $script:results -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTime.Ticks)" })
            $after | Should -Be $before
        }

        It 'still gives a complete page when Results holds nothing yet' {
            $empty = New-Results
            $html = Export-Page -Results $empty -Out (Join-Path -Path $TestDrive -ChildPath 'empty/page.html') -Farm 'CONTENT'
            $empty = Get-Block -Html $html -Id 'spsw-data'
            $empty.schemaVersion | Should -Be 1
            @($empty.farms.daily | Where-Object -FilterScript { $null -ne $_ }).Count | Should -Be 0
            @($empty.runs).Count | Should -Be 0
        }
    }

    Context 'self-contained and read-only' {
        It 'has no placeholder left' {
            $script:code | Should -Not -Match '\{\{(?:HTMLLANG|TITLE|STYLE|SCRIPT|PAGE|DATA)\}\}'
        }

        It 'loads nothing from outside the file' {
            $script:code | Should -Not -Match 'https?://'
            $script:code | Should -Not -Match '(?i)@import|url\(|<iframe|<object|<embed|<form|<base\b|rel="stylesheet"|<script[^>]+\bsrc='
            $script:code | Should -Not -Match '\b(?:fetch|XMLHttpRequest|WebSocket|importScripts|sendBeacon|EventSource)\b'
            $script:code | Should -Not -Match '\beval\(|new Function|document\.write|localStorage|sessionStorage|document\.cookie'
        }

        It 'has the three script elements and no other (two data blocks and the page script)' {
            [regex]::Matches($script:html, '<script').Count | Should -Be 3
            [regex]::Matches($script:html, '</script>').Count | Should -Be 3
        }

        It 'has a visible error banner and a message when scripts are off' {
            $script:html | Should -Match 'id="spsw-error"[^>]*role="alert"'
            $script:html | Should -Match '<noscript>'
        }
    }

    Context 'the embedded data' {
        It 'holds the dataset as valid JSON' {
            $script:data.schemaVersion | Should -Be 1
            $script:data.environment.application | Should -Be 'zebes'
            @($script:data.farms).Count | Should -Be 2
            @($script:data.runs).Count | Should -Be 1
        }

        It 'holds the version, the language of the page and the strings of every shipped language' {
            $script:page.version | Should -Be '9.9.9'
            $script:page.language | Should -Be 'fr-FR'
            $script:page.fallback | Should -Be 'en-US'
            @($script:page.cultures.PSObject.Properties.Name | Sort-Object) | Should -Be @('en-US', 'fr-FR')
            $script:page.cultures.'fr-FR'.htmlLang | Should -Be 'fr'
        }

        It 'sets the language of the document and a title that carries the environment' {
            $script:html | Should -Match '<html lang="fr">'
            $script:html | Should -Match '<title>SPSWeather (?:\u00B7|&#183;) zebes / PROD</title>'
        }

        It 'opens in English for an unknown or a not shipped language (the fallback)' {
            foreach ($language in 'xx-YY', 'ja-JP', '', 'en-US') {
                $html = Export-Page -Results $script:results -Out (Join-Path -Path $TestDrive -ChildPath 'lang/page.html') -Language $language
                (Get-Block -Html $html -Id 'spsw-page').language | Should -Be 'en-US'
                $html | Should -Match '<html lang="en">'
            }
        }

        It 'follows the retention for the periods offered' {
            $html = Export-Page -Results $script:results -Out (Join-Path -Path $TestDrive -ChildPath 'ret/page.html') -Retention 14
            @((Get-Block -Html $html -Id 'spsw-data').period.offered) | Should -Be @(7, 14)
        }

        It 'carries every key the script asks for, in every shipped language' {
            $script:requested.Count | Should -BeGreaterThan 100
            foreach ($culture in $script:page.cultures.PSObject.Properties) {
                $keys = @($culture.Value.text.PSObject.Properties.Name)
                @($script:requested | Where-Object -FilterScript { $keys -notcontains $_ }) | Should -BeNullOrEmpty -Because "the page would show the key name in $($culture.Name)"
                foreach ($prefix in $script:families) { @($keys | Where-Object -FilterScript { $_.StartsWith($prefix) }).Count | Should -BeGreaterThan 0 -Because "$($culture.Name) has no key of the family $prefix" }
            }
        }

        It 'has no value left empty in the strings of a language' {
            foreach ($culture in $script:page.cultures.PSObject.Properties) {
                foreach ($entry in $culture.Value.text.PSObject.Properties) { [string]::IsNullOrWhiteSpace([string]$entry.Value) | Should -BeFalse -Because "$($culture.Name) $($entry.Name)" }
            }
        }
    }

    Context 'values that come from the farms' {
        It 'keeps hostile names intact in the data and cannot close the script element or open a comment' {
            @($script:data.farms | ForEach-Object -Process { $_.name }) | Should -Contain $script:hostileFarm
            $item = @($script:data.farms | Where-Object -FilterScript { $_.name -eq $script:hostileFarm }).attention[0]
            $item.name | Should -BeLike "*$($script:hostileItem)*"
            $item.cause | Should -Match '\{\{SCRIPT\}\}'
            foreach ($id in 'spsw-data', 'spsw-page') {
                $m = [regex]::Match($script:html, '<script type="application/json" id="' + $id + '">(.*?)</script>', 'Singleline')
                $m.Groups[1].Value | Should -Not -Match '[<>&]'
                $m.Groups[1].Value.Contains([string][char]0x2028) | Should -BeFalse
            }
        }

        It 'does not expand a placeholder found in the data' {
            ($script:html -split '\{\{SCRIPT\}\}').Count | Should -BeGreaterThan 1
            $script:code | Should -Not -Match '\{\{SCRIPT\}\}'
        }

        It 'puts no hostile value in the markup of the page outside the data blocks' {
            $script:code | Should -Not -Match 'window\.__pwned'
            $script:code | Should -Not -Match 'onerror='
        }
    }

    Context 'the style' {
        It 'draws the figure of a card in an ink colour that reads on the card (WCAG 3:1 for large text, 4.5:1 required here), in both themes' {
            $css = [System.IO.File]::ReadAllText((Join-Path -Path $script:moduleDir -ChildPath 'Assets/Cockpit.css'))
            foreach ($tone in 'ok', 'warn', 'fail') { $css | Should -Match "\.kpi\.$tone \.v \{ color: var\(--$tone-ink\); \}" }

            function Get-Luminance([string]$hex) {
                $channels = foreach ($i in 1, 3, 5) { $c = [Convert]::ToInt32($hex.Substring($i, 2), 16) / 255.0; if ($c -le 0.03928) { $c / 12.92 } else { [Math]::Pow(($c + 0.055) / 1.055, 2.4) } }
                0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
            }
            function Get-Contrast([string]$a, [string]$b) { $x = Get-Luminance $a; $y = Get-Luminance $b; ([Math]::Max($x, $y) + 0.05) / ([Math]::Min($x, $y) + 0.05) }
            $light = [regex]::Match($css, ':root \{(.*?)\}', 'Singleline').Groups[1].Value
            $dark = [regex]::Match($css, 'html\[data-theme="dark"\] \{(.*?)\}', 'Singleline').Groups[1].Value
            foreach ($theme in @{ Name = 'light'; Text = $light }, @{ Name = 'dark'; Text = $dark }) {
                $card = [regex]::Match($theme.Text, '--card:\s*(#[0-9a-fA-F]{6})').Groups[1].Value
                $card | Should -Not -BeNullOrEmpty
                foreach ($tone in 'ok', 'warn', 'fail') {
                    $ink = [regex]::Match($theme.Text, "--$tone-ink:\s*(#[0-9a-fA-F]{6})").Groups[1].Value
                    $ink | Should -Not -BeNullOrEmpty
                    (Get-Contrast $ink $card) | Should -BeGreaterOrEqual 4.5 -Because "--$tone-ink on the card, $($theme.Name) theme"
                }
            }
        }
    }

    Context 'the script' {
        It 'documents the state kept in the URL and the five tabs' {
            $js = [System.IO.File]::ReadAllText((Join-Path -Path $script:moduleDir -ChildPath 'Assets/Cockpit.js'))
            $js | Should -Match "const TABS = \['direction', 'it', 'quality', 'runs', 'method'\]"
            $keys = [regex]::Match($js, 'const DEFAULTS = \{(.*?)\};', 'Singleline').Groups[1].Value
            foreach ($key in 'lang', 'theme', 'p', 'tab') { $keys | Should -Match "\b$key\b" }
            $wiki = [System.IO.File]::ReadAllText((Join-Path -Path $repoRoot -ChildPath 'wiki/Cockpit-Page.md'))
            foreach ($key in 'lang', 'theme', 'p', 'tab') { $wiki | Should -Match ('\|\s*`' + $key + '`\s*\|') }
        }

        It 'is plain ASCII so that no server or editor can alter it' {
            $js = [System.IO.File]::ReadAllText((Join-Path -Path $script:moduleDir -ChildPath 'Assets/Cockpit.js'))
            $js | Should -Not -Match '[^\x00-\x7F]'
            $js | Should -Not -Match '</script|<!--'
        }

        It 'is valid JavaScript' -Skip:(-not $node) {
            $source = Join-Path -Path $TestDrive -ChildPath 'cockpit-check.js'
            [System.IO.File]::WriteAllText($source, [System.IO.File]::ReadAllText((Join-Path -Path $script:moduleDir -ChildPath 'Assets/Cockpit.js')))
            & $script:nodePath --check $source
            $LASTEXITCODE | Should -Be 0
        }

        It 'counts the days by their snapshots, lists the unreachable runs next to a snapshot, tells where the settings come from and cuts the changes to the period' -Skip:(-not $node) {
            $harness = Join-Path -Path $TestDrive -ChildPath 'cockpit-review.js'
            [System.IO.File]::WriteAllText($harness, @'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const block = id => new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>').exec(html)[1];
const code = /<script>\n([\s\S]*)\n<\/script>\s*<\/body>/.exec(html)[1];
const END = Date.UTC(2026, 10, 26);
const iso = i => new Date(END - i * 86400000).toISOString().slice(0, 10);
const cell = (ok, warn, fail, down) => ({ ok, warn, fail, weather: 'sunny', snapshots: 1, unreachable: down || 0 });
const DOWN = { ok: null, warn: null, fail: null, weather: null, snapshots: 0, unreachable: 1 };
const OK = cell(10, 0, 0);
const rep = (n, c) => Array.from({ length: n }, () => c);
const farm = (name, daily) => ({ name, daily, latestSnapshot: '2026-11-26T06:00:00+01:00', snapshotsTruncated: false, attention: [], attentionTotal: 0, attentionTruncated: false });
const thresholds = { SQLDiskFreeThresholdPercent: { value: 15, source: 'default' }, SQLBackupMaxAgeDays: { value: 8, source: 'config' }, JsonHistoryRetentionDays: { value: 30, source: 'config' }, EmailMaxItemsPerArea: { value: 10, source: 'default' }, LogRetentionDays: { value: 180, source: 'default' } };
const settings = { configFile: 'A.psd1', thresholds, exclusionRules: [] };
const runAt = (day, withSettings) => Object.assign({ started: day + 'T06:00:00+01:00', durationSeconds: 60, version: '3.5.0', language: 'en-US', emailMode: 'PerFarm', mail: 'sent', farms: [{ name: 'A', outcome: 'ok', ok: 10, warn: 0, fail: 0 }] }, withSettings ? { settings } : {});
function render(mutate, hash) {
  const d = JSON.parse(block('spsw-data'));
  const n = 14;
  Object.assign(d, { days: Array.from({ length: n }, (_, i) => iso(n - 1 - i)), weekend: rep(n, false), runs: [], kpi: null, skipped: [], farms: [farm('A', rep(n, OK))], settings: { current: null, changes: [] } });
  d.period = { retentionDays: 0, offered: [7, 14], maxDays: n, firstDay: d.days[0], lastDay: d.days[n - 1] };
  mutate(d);
  const els = { 'spsw-data': { textContent: JSON.stringify(d) }, 'spsw-page': { textContent: block('spsw-page') }, 'spsw-error': { textContent: '', hidden: true }, 'spsw-header': { innerHTML: '' }, 'spsw-main': { innerHTML: '' }, 'spsw-footer': { innerHTML: '' } };
  const doc = { getElementById: id => els[id], querySelector: () => null, addEventListener() {}, title: '', documentElement: { setAttribute() {}, lang: '' } };
  const win = { addEventListener() {}, innerWidth: 1320, matchMedia: () => ({ matches: false }), scrollTo() {} };
  new Function('document', 'window', 'location', 'history', code)(doc, win, { hash: hash + '&lang=en-US' }, { replaceState() {} });
  return { html: els['spsw-main'].innerHTML, text: els['spsw-main'].innerHTML.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' '), error: els['spsw-error'].hidden ? '' : els['spsw-error'].textContent };
}
const out = {};
// 2: the last day has only an unreachable run, so it is not a day with a snapshot
const onlyDown = render(d => { d.farms[0].daily = [...rep(13, OK), DOWN]; }, '#tab=direction&p=14');
out.cleanDenominator = /Days without failure\s+13 \/ 13\b/.test(onlyDown.text);
out.qualityDays = /Days with data\s+13\b/.test(render(d => { d.farms[0].daily = [...rep(13, OK), DOWN]; }, '#tab=quality&p=14').text);
// 3: a healthy snapshot and an unreachable run the same day is not a day without failure
out.unreachableRunNotClean = /Days without failure\s+13 \/ 14\b/.test(render(d => { d.farms[0].daily = [...rep(13, OK), cell(10, 0, 0, 1)]; }, '#tab=direction&p=14').text);
// 5: Data quality counts that day as unreachable, and as a day with a snapshot
const q = render(d => { d.farms[0].daily = [...rep(13, OK), cell(10, 0, 0, 1)]; }, '#tab=quality&p=14');
const row = /<tr><td><b>A<\/b><\/td><td class="num">[^<]*<\/td><td class="r num">(\d+)<\/td><td class="r num">(\d+)<\/td>/.exec(q.html);
out.qualityRow = row ? row[1] + '/' + row[2] : 'no row';
// 4: the strip is described in words and its days are in a table
const it = render(d => { d.farms[0].daily = [...rep(10, OK), cell(9, 0, 1), DOWN, null, OK]; }, '#tab=it&p=14');
out.stripLabel = (/<div class="strip" role="img" aria-label="([^"]*)"/.exec(it.html) || [])[1] || '';
out.stripRows = (it.html.match(/<details class="fold" style="margin:4px 0 10px">[\s\S]*?<\/details>/) || [''])[0].split('<tr>').length - 2;
out.stripHasDay = /Wed, Nov 25/.test(it.text) && /Unreachable runs/.test(it.text);
// 6: the settings come from an older run
const older = render(d => { d.runs = [runAt('2026-11-24', true), runAt('2026-11-26', false)]; d.settings.current = settings; }, '#tab=method&p=14');
out.olderHint = /last recorded, by the run of 11\/24 06:00/.test(older.text);
const same = render(d => { d.runs = [runAt('2026-11-24', false), runAt('2026-11-26', true)]; d.settings.current = settings; }, '#tab=method&p=14');
out.sameHint = /at the last run/.test(same.text) && !/last recorded/.test(same.text);
// 7: the changes of the period only
const change = (day, name) => ({ started: day + 'T06:00:00+01:00', name, from: '3', to: '8', fromSource: 'default', toSource: 'config' });
const changes = d => { d.runs = [runAt('2026-11-26', true)]; d.settings.current = settings; d.settings.changes = [change('2026-11-14', 'OldSetting'), change('2026-11-25', 'NewSetting')]; };
const p7 = render(changes, '#tab=method&p=7'), p14 = render(changes, '#tab=method&p=14');
out.changes7 = p7.text.includes('NewSetting') && !p7.text.includes('OldSetting');
out.changes14 = p14.text.includes('NewSetting') && p14.text.includes('OldSetting');
out.errors = [onlyDown, older, same, p7, p14, q, it].map(r => r.error).filter(Boolean);
console.log(JSON.stringify(out));
'@)
            $result = & $script:nodePath $harness $script:file | ConvertFrom-Json
            $result.errors | Should -BeNullOrEmpty
            $result.cleanDenominator | Should -BeTrue -Because 'a day with only an unreachable run has no snapshot, so it is not counted among the days with a snapshot'
            $result.qualityDays | Should -BeTrue
            $result.unreachableRunNotClean | Should -BeTrue -Because 'the method says: a day without failure has no unreachable farm'
            $result.qualityRow | Should -Be '14/1' -Because 'a snapshot and an unreachable run on the same day are both counted'
            $result.stripLabel | Should -Match '^A: \d+ healthy, \d+ warning, \d+ alert, \d+ unreachable, \d+ without snapshot$'
            $result.stripLabel | Should -Be 'A: 11 healthy, 0 warning, 1 alert, 1 unreachable, 1 without snapshot'
            $result.stripRows | Should -Be 14
            $result.stripHasDay | Should -BeTrue
            $result.olderHint | Should -BeTrue
            $result.sameHint | Should -BeTrue
            $result.changes7 | Should -BeTrue
            $result.changes14 | Should -BeTrue
        }

        It 'renders every tab in every language, period and theme without an error, and escapes the hostile names' -Skip:(-not $node) {
            $harness = Join-Path -Path $TestDrive -ChildPath 'cockpit-smoke.js'
            [System.IO.File]::WriteAllText($harness, @'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const block = id => new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>').exec(html)[1];
const code = /<script>\n([\s\S]*)\n<\/script>\s*<\/body>/.exec(html)[1];
const results = [];
function run(hash, width) {
  const els = {
    'spsw-data': { textContent: block('spsw-data') },
    'spsw-page': { textContent: block('spsw-page') },
    'spsw-error': { textContent: '', hidden: true },
    'spsw-header': { innerHTML: '' }, 'spsw-main': { innerHTML: '' }, 'spsw-footer': { innerHTML: '' }
  };
  const doc = { getElementById: id => els[id], querySelector: () => null, addEventListener() {}, title: '', documentElement: { setAttribute() {}, lang: '' } };
  const win = { addEventListener() {}, innerWidth: width, matchMedia: () => ({ matches: false }), scrollTo() {} };
  new Function('document', 'window', 'location', 'history', code)(doc, win, { hash }, { replaceState() {} });
  const all = els['spsw-header'].innerHTML + els['spsw-main'].innerHTML + els['spsw-footer'].innerHTML;
  results.push({ hash, width, error: els['spsw-error'].hidden ? '' : els['spsw-error'].textContent, length: els['spsw-main'].innerHTML.length,
    rawHostile: /<img src=x|<script>window|<!--|<\/script>/.test(all), escaped: all.includes('&lt;img src=x onerror=window.__pwned=2&gt;') });
}
for (const width of [390, 1320]) for (const lang of ['en-US', 'fr-FR']) for (const tab of ['direction', 'it', 'quality', 'runs', 'method']) for (const p of ['7', '14', '30']) for (const theme of ['light', 'dark'])
  run('#tab=' + tab + '&lang=' + lang + '&p=' + p + '&theme=' + theme, width);
run('#tab=nonsense&lang=zz&p=999&theme=pink', 1320);
console.log(JSON.stringify(results));
'@)
            $out = & $script:nodePath $harness $script:file | ConvertFrom-Json
            @($out).Count | Should -BeGreaterThan 100
            @($out | Where-Object -FilterScript { $_.error }) | Should -BeNullOrEmpty
            @($out | Where-Object -FilterScript { $_.length -lt 300 }) | Should -BeNullOrEmpty
            @($out | Where-Object -FilterScript { $_.rawHostile }) | Should -BeNullOrEmpty
            @($out | Where-Object -FilterScript { $_.hash -like '#tab=it&lang=en-US&p=30*' -and -not $_.escaped }).Count | Should -Be 0
        }

        It 'shows a dash, never NaN or undefined, for a snapshot that holds no check, and for a farm with no data' -Skip:(-not $node) {
            $harness = Join-Path -Path $TestDrive -ChildPath 'cockpit-empty.js'
            [System.IO.File]::WriteAllText($harness, @'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const block = id => new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>').exec(html)[1];
const code = /<script>\n([\s\S]*)\n<\/script>\s*<\/body>/.exec(html)[1];
const variants = {
  zeroChecks: d => { d.farms.forEach(f => f.daily.forEach((c, i) => { if (c && c.ok !== null) f.daily[i] = Object.assign(c, { ok: 0, warn: 0, fail: 0, weather: 'sunny' }); })); },
  noData: d => { d.farms.forEach(f => { f.daily = f.daily.map(() => null); f.latestSnapshot = null; f.attention = []; f.attentionTotal = 0; }); d.runs = []; },
  noFarm: d => { d.farms = []; d.runs = []; },
  noSettings: d => { d.settings = { current: null, changes: [] }; }
};
const results = [];
for (const [name, change] of Object.entries(variants)) for (const tab of ['direction', 'it', 'quality', 'runs', 'method']) for (const lang of ['en-US', 'fr-FR']) {
  const data = JSON.parse(block('spsw-data')); change(data);
  const els = { 'spsw-data': { textContent: JSON.stringify(data) }, 'spsw-page': { textContent: block('spsw-page') }, 'spsw-error': { textContent: '', hidden: true }, 'spsw-header': { innerHTML: '' }, 'spsw-main': { innerHTML: '' }, 'spsw-footer': { innerHTML: '' } };
  const doc = { getElementById: id => els[id], querySelector: () => null, addEventListener() {}, title: '', documentElement: { setAttribute() {}, lang: '' } };
  const win = { addEventListener() {}, innerWidth: 1320, matchMedia: () => ({ matches: false }), scrollTo() {} };
  let thrown = '';
  try { new Function('document', 'window', 'location', 'history', code)(doc, win, { hash: '#tab=' + tab + '&lang=' + lang }, { replaceState() {} }); } catch (e) { thrown = String(e); }
  const all = els['spsw-header'].innerHTML + els['spsw-main'].innerHTML + els['spsw-footer'].innerHTML;
  results.push({ name, tab, lang, thrown, banner: els['spsw-error'].hidden ? '' : els['spsw-error'].textContent, bad: /NaN|undefined|Infinity|\[object/.test(all), empty: els['spsw-main'].innerHTML.length < 50 });
}
console.log(JSON.stringify(results));
'@)
            $out = & $script:nodePath $harness $script:file | ConvertFrom-Json
            @($out).Count | Should -Be 40
            @($out | Where-Object -FilterScript { $_.thrown -or $_.banner }) | Should -BeNullOrEmpty
            @($out | Where-Object -FilterScript { $_.bad }) | Should -BeNullOrEmpty
            @($out | Where-Object -FilterScript { $_.empty }) | Should -BeNullOrEmpty
        }
    }
}
