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

        It 'shows the thresholds of the limit checks as plain numbers, with a dash for no threshold, and the checks that are turned off' -Skip:(-not $node) {
            $harness = Join-Path -Path $TestDrive -ChildPath 'cockpit-limits.js'
            [System.IO.File]::WriteAllText($harness, @'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const block = id => new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>').exec(html)[1];
const code = /<script>\n([\s\S]*)\n<\/script>\s*<\/body>/.exec(html)[1];
const END = Date.UTC(2026, 10, 26);
const iso = i => new Date(END - i * 86400000).toISOString().slice(0, 10);
const OK = { ok: 10, warn: 0, fail: 0, weather: 'sunny', snapshots: 1, unreachable: 0 };
const thresholds = {
  SQLDiskFreeThresholdPercent: { value: 15, source: 'default' },
  'Limits.ContentDatabaseSize.Warning': { value: 120.5, source: 'config' },
  'Limits.ContentDatabaseSize.Failure': { value: 1500, source: 'config' },
  'Limits.ManagedPaths.Warning': { value: 15, source: 'default' },
  'Limits.ManagedPaths.Failure': { value: 20, source: 'default' },
  'Limits.ApplicationPoolsPerServer.Failure': { value: null, source: 'default' },
  'Limits.Exceptions': { value: 2, source: 'config' }
};
const d = JSON.parse(block('spsw-data'));
const n = 14;
Object.assign(d, { days: Array.from({ length: n }, (_, i) => iso(n - 1 - i)), weekend: Array.from({ length: n }, () => false), runs: [], kpi: null, skipped: [], farms: [{ name: 'A', daily: Array.from({ length: n }, () => OK), latestSnapshot: '2026-11-26T06:00:00+01:00', snapshotsTruncated: false, attention: [], attentionTotal: 0, attentionTruncated: false }], settings: { current: { configFile: 'A.psd1', thresholds, exclusionRules: ['Limits.ManagedPaths'] }, changes: [] } });
d.period = { retentionDays: 0, offered: [7, 14], maxDays: n, firstDay: d.days[0], lastDay: d.days[n - 1] };
const els = { 'spsw-data': { textContent: JSON.stringify(d) }, 'spsw-page': { textContent: block('spsw-page') }, 'spsw-error': { textContent: '', hidden: true }, 'spsw-header': { innerHTML: '' }, 'spsw-main': { innerHTML: '' }, 'spsw-footer': { innerHTML: '' }, 'spsw-live': { textContent: '' } };
const doc = { getElementById: id => els[id], querySelector: () => null, addEventListener() {}, title: '', documentElement: { setAttribute() {}, lang: '' } };
const win = { addEventListener() {}, innerWidth: 1320, matchMedia: () => ({ matches: false }), scrollTo() {} };
const text = {};
for (const lang of ['en-US', 'fr-FR']) {
  els['spsw-error'].hidden = true; els['spsw-error'].textContent = '';
  new Function('document', 'window', 'location', 'history', code)(doc, win, { hash: '#tab=method&p=14&lang=' + lang }, { replaceState() {} });
  text[lang] = els['spsw-main'].innerHTML.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ') + (els['spsw-error'].hidden ? '' : ' ERROR ' + els['spsw-error'].textContent);
}
console.log(JSON.stringify({ error: text['en-US'].includes(' ERROR ') || text['fr-FR'].includes(' ERROR ') ? 'error' : '', text: text['en-US'], french: text['fr-FR'] }));
'@)
            $result = & $script:nodePath $harness $script:file | ConvertFrom-Json
            $result.error | Should -BeNullOrEmpty
            $result.text | Should -Match 'Limits\.ContentDatabaseSize\.Warning 120\.5 ' -Because 'a threshold that has decimals is shown with them'
            $result.french | Should -Match 'Limits\.ContentDatabaseSize\.Warning 120,5 ' -Because 'and in the decimal mark of the language'
            $result.text | Should -Match 'Limits\.ContentDatabaseSize\.Failure 1,?500 '
            $result.text | Should -Match 'Limits\.ManagedPaths\.Warning 15 '
            $result.text | Should -Match 'Limits\.ManagedPaths\.Failure 20 '
            $result.text | Should -Match 'Limits\.ApplicationPoolsPerServer\.Failure \u2014 '
            $result.text | Should -Match 'Limits\.Exceptions 2 '
            $result.text | Should -Match 'Limits\.ManagedPaths\b'
            $result.text | Should -Match 'SQLDiskFreeThresholdPercent 15 ?%'
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

Describe 'The insight sentences of the cockpit page' {
    It 'follow fixed rules: each rule gives its sentence, in both languages, escaped, and the same data gives the same text' -Skip:(-not $node) {
        $harness = Join-Path -Path $TestDrive -ChildPath 'cockpit-insights.js'
        [System.IO.File]::WriteAllText($harness, @'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const block = id => new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>').exec(html)[1];
const code = /<script>\n([\s\S]*)\n<\/script>\s*<\/body>/.exec(html)[1];
const END = Date.UTC(2026, 10, 26);
const iso = i => new Date(END - i * 86400000).toISOString().slice(0, 10);
const cell = (ok, warn, fail, down) => ({ ok, warn, fail, weather: fail > 5 ? 'stormy' : fail > 0 ? 'cloudy' : warn > 0 ? 'fair' : 'sunny', snapshots: 1, unreachable: down || 0 });
const DOWN = { ok: null, warn: null, fail: null, weather: null, snapshots: 0, unreachable: 1 };
const OK = cell(10, 0, 0), BAD = cell(9, 0, 1), WARN = cell(9, 2, 0);
const att = (farm, section, name, cause, since, o) => Object.assign({ farm, section, id: section + '|' + name, name, severity: 'fail', cause, detail: cause, count: 1, since: since, sinceIsLowerBound: false }, o || {});
const rep = (n, c) => Array.from({ length: n }, () => c);
function streak(daily) {
  let first = -1;
  for (let i = daily.length - 1; i >= 0; i--) { const c = daily[i]; if (!c || c.ok === null) continue; if (c.fail > 0) first = i; else break; }
  if (first < 0) return { failingSince: null, failingSinceIsLowerBound: false };
  const firstData = daily.findIndex(c => c && c.ok !== null);
  return { failingSince: iso(daily.length - 1 - first), failingSinceIsLowerBound: first === firstData };
}
function farm(name, daily, attention, o) { return Object.assign({ name, daily, latestSnapshot: '2026-11-26T06:00:00+01:00', snapshotsTruncated: false, attention: attention || [], attentionTotal: (attention || []).length, attentionTruncated: false }, streak(daily), o || {}); }
function run(data, hash) {
  const els = { 'spsw-data': { textContent: JSON.stringify(data) }, 'spsw-page': { textContent: block('spsw-page') }, 'spsw-error': { textContent: '', hidden: true }, 'spsw-header': { innerHTML: '' }, 'spsw-main': { innerHTML: '' }, 'spsw-footer': { innerHTML: '' } };
  const doc = { getElementById: id => els[id], querySelector: () => null, addEventListener() {}, title: '', documentElement: { setAttribute() {}, lang: '' } };
  const win = { addEventListener() {}, innerWidth: 1320, matchMedia: () => ({ matches: false }), scrollTo() {} };
  new Function('document', 'window', 'location', 'history', code)(doc, win, { hash }, { replaceState() {} });
  const main = els['spsw-main'].innerHTML;
  const sentences = [...main.matchAll(/<div class="insight ([a-z]*)">(.*?)<\/div>/g)].map(m => m[1] + '|' + m[2].replace(/<[^>]+>/g, ''));
  return { sentences, html: main, error: els['spsw-error'].hidden ? '' : els['spsw-error'].textContent };
}
function data(farms, p, n) {
  const d = JSON.parse(block('spsw-data'));
  n = n || farms[0].daily.length;
  Object.assign(d, { days: Array.from({ length: n }, (_, i) => iso(n - 1 - i)), weekend: rep(n, false), farms, runs: [], kpi: null, skipped: [] });
  d.period = { retentionDays: 0, offered: p === n ? [n] : [p, n], maxDays: n, firstDay: d.days[0], lastDay: d.days[n - 1] };
  d.settings = { current: null, changes: [] };
  return d;
}
const SQL = 'SQLDatabaseStatus', UP = 'SPUpgradeStatus';
const sqlItems = (n, cause, since, o) => Array.from({ length: n }, (_, i) => att('A', SQL, 'db' + i, cause, since || '2026-11-20', o));
const cases = [
  ['health down', () => data([farm('A', [...rep(14, OK), ...rep(14, BAD)])], 14), /Down 10\.0 pts against the average of the previous period\./],
  ['health up', () => data([farm('A', [...rep(14, BAD), ...rep(14, OK)])], 14), /Up 10\.0 pts against the average of the previous period\./],
  ['health stable', () => data([farm('A', rep(28, BAD))], 14), /Stable against the average of the previous period\./],
  ['a drop of exactly one point is a drop', () => data([farm('A', [...rep(14, cell(1000, 0, 0)), ...rep(14, cell(990, 0, 10))])], 14), /Down 1\.0 pts against the average/],
  ['a drop of half a point is stable', () => data([farm('A', [...rep(14, cell(1000, 0, 0)), ...rep(14, cell(995, 0, 5))])], 14), /Stable against the average/],
  ['a rise of exactly one point is a rise', () => data([farm('A', [...rep(14, cell(990, 0, 10)), ...rep(14, cell(1000, 0, 0))])], 14), /Up 1\.0 pts against the average/],
  ['no previous period, failures', () => data([farm('A', [...rep(13, OK), BAD])], 14), /1 check\(s\) failing at the latest snapshot\./],
  ['no previous period, warnings', () => data([farm('A', [...rep(13, OK), WARN])], 14), /2 warning\(s\) at the latest snapshot, no failure\./],
  ['no previous period, clear', () => data([farm('A', rep(14, OK))], 14), /Nothing to report at the latest snapshot\./],
  ['most failures in one section', () => data([farm('A', [...rep(13, OK), cell(6, 0, 4)], [...sqlItems(3, 'x'), att('A', UP, 'srv', 'y', '2026-11-20')])], 14), /Most of the failures are in: SQL - Databases\./],
  ['half of the failures is not most', () => data([farm('A', [...rep(13, OK), cell(6, 0, 4)], [...sqlItems(2, 'x'), att('A', UP, 's1', 'y', '2026-11-20'), att('A', UP, 's2', 'z', '2026-11-20')])], 14), null, /Most of the failures/],
  ['capped list claims nothing about the share', () => data([farm('A', [...rep(13, OK), cell(6, 0, 4)], sqlItems(3, 'x'), { attentionTruncated: true, attentionTotal: 9 })], 14), /The oldest item is/, /Most of the failures|share one cause/],
  ['one cause shared by most items', () => data([farm('A', [...rep(13, OK), cell(6, 0, 4)], [...sqlItems(3, 'no full backup found'), att('A', UP, 's', 'other', '2026-11-20')])], 14), /3 of the 4 items share one cause: no full backup found\./],
  ['equal causes: the first in order wins', () => data([farm('A', [...rep(13, OK), cell(6, 0, 4)], [att('A', SQL, 'a1', 'b cause', '2026-11-20'), att('A', SQL, 'a2', 'b cause', '2026-11-20'), att('A', SQL, 'a3', 'a cause', '2026-11-20'), att('A', SQL, 'a4', 'a cause', '2026-11-20')])], 14), /2 of the 4 items share one cause: a cause\./],
  ['oldest item', () => data([farm('A', [...rep(13, OK), cell(6, 0, 3)], [att('A', SQL, 'itemA', 'c1', '2026-11-21'), att('A', SQL, 'itemB', 'c2', '2026-11-23'), att('A', SQL, 'itemC', 'c3', '2026-11-25')])], 14), /The oldest item is itemA, open for 5 day\(s\), since 11\/21\./],
  ['every item is new only when each is new in its own farm (a farm that stopped being collected earlier does not hide an older item)', () => {
    const a = farm('A', [...rep(7, OK), BAD, ...rep(6, null)], [att('A', SQL, 'itemA', 'c1', '2026-11-20')], { latestSnapshot: '2026-11-20T06:00:00+01:00' });
    const b = farm('B', [...rep(8, OK), ...rep(6, BAD)], [att('B', SQL, 'itemB', 'c2', '2026-11-21')]);
    return data([a, b], 14);
  }, /The oldest item is itemB, open for 5 day\(s\), since 11\/21\./, /Every item appeared/],
  ['every item is new in its own farm, on different days', () => {
    const a = farm('A', [...rep(7, OK), BAD, ...rep(6, null)], [att('A', SQL, 'itemA', 'c1', '2026-11-20')], { latestSnapshot: '2026-11-20T06:00:00+01:00' });
    const b = farm('B', [...rep(13, OK), BAD], [att('B', SQL, 'itemB', 'c2', '2026-11-26')]);
    return data([a, b], 14);
  }, /Every item appeared at the latest snapshot\./],
  ['a farm unreachable in the morning and collected later the same day is not collected every day', () => data([farm('A', [...rep(12, OK), cell(10, 0, 0, 1), OK])], 14), /A could not be reached on 11\/25\./, /Every farm was collected/],
  ['failures since the date of the dataset, not since the walk back through the days', () => data([farm('A', rep(14, BAD), [], { failingSince: '2026-11-26', failingSinceIsLowerBound: false })], 14), /A has had failures at every snapshot since 11\/26\./, /since 11\/13/],
  ['failures since the dataset says it is only a lower bound', () => data([farm('A', rep(14, BAD), [], { failingSince: '2026-11-13', failingSinceIsLowerBound: true })], 14), /A has had failures at every snapshot since 11\/13 or before\./],
  ['failures and no streak in the dataset: the sentence does not guess', () => data([farm('A', rep(14, BAD), [], { failingSince: null, failingSinceIsLowerBound: false })], 14), /1 check\(s\) failing at the latest snapshot\./, /every snapshot since/],
  ['oldest item: equal dates are told apart by name, whatever the input order', () => data([farm('A', [...rep(13, OK), cell(6, 0, 3)], [att('A', SQL, 'itemB', 'c2', '2026-11-21'), att('A', SQL, 'itemA', 'c1', '2026-11-21'), att('A', SQL, 'itemC', 'c3', '2026-11-25')])], 14), /The oldest item is itemA, open for 5 day/],
  ['oldest item: equal dates, a failure comes before a warning', () => data([farm('A', [...rep(13, OK), cell(6, 0, 3)], [att('A', SQL, 'itemA', 'c1', '2026-11-21', { severity: 'warn' }), att('A', SQL, 'itemB', 'c2', '2026-11-21'), att('A', SQL, 'itemC', 'c3', '2026-11-25')])], 14), /The oldest item is itemB, open for 5 day/],
  ['oldest item, lower bound', () => data([farm('A', [...rep(13, OK), cell(6, 0, 2)], [att('A', SQL, 'itemA', 'c1', '2026-11-13', { sinceIsLowerBound: true }), att('A', SQL, 'itemB', 'c2', '2026-11-23')])], 14), /The oldest item is itemA, open since 11\/13 or before\./],
  ['every item is new', () => data([farm('A', [...rep(13, OK), cell(6, 0, 2)], [att('A', SQL, 'i1', 'c1', '2026-11-26'), att('A', SQL, 'i2', 'c2', '2026-11-26')])], 14), /Every item appeared at the latest snapshot\./],
  ['nothing open', () => data([farm('A', rep(14, OK))], 14), /Nothing needs attention at the latest snapshot\./],
  ['latest day clean', () => data([farm('A', [...rep(13, BAD), OK])], 14), /No failure on 11\/26, the latest day with a snapshot\./],
  ['the latest day with a snapshot is not a day with only an unreachable run', () => data([farm('A', [...rep(13, OK), DOWN])], 14), /No failure on 11\/25, the latest day with a snapshot\./],
  ['last clean day earlier', () => data([farm('A', [...rep(10, BAD), OK, ...rep(3, BAD)])], 14), /Last day without failure: 11\/23, 3 day\(s\) before the latest snapshot\./],
  ['no clean day', () => data([farm('A', rep(14, BAD))], 14), /No day without failure in this period\./],
  ['a farm unreachable once', () => data([farm('A', rep(14, OK)), farm('FarmB', [...rep(12, OK), DOWN, OK])], 14), /FarmB could not be reached on 11\/25\./],
  ['a farm unreachable several times', () => data([farm('A', rep(14, OK)), farm('FarmB', [...rep(11, OK), DOWN, DOWN, OK])], 14), /Last unreachable farm: FarmB, on 11\/25; 2 farm-days unreachable in this period\./],
  ['days without a snapshot', () => data([farm('A', [...rep(5, OK), null, null, null, ...rep(6, OK)])], 14), /3 of 14 farm-days have no snapshot\./],
  ['every farm collected', () => data([farm('A', rep(14, OK)), farm('B', rep(14, OK))], 14), /Every farm was collected on every day\./],
  ['failures at every snapshot since a day', () => data([farm('A', [...rep(10, OK), ...rep(4, BAD)])], 14), /A has had failures at every snapshot since 11\/23\./],
  ['the series skips days without a snapshot', () => data([farm('A', [...rep(10, OK), BAD, null, DOWN, BAD])], 14), /A has had failures at every snapshot since 11\/23\./],
  ['failures since the start of the history', () => data([farm('A', rep(14, BAD))], 14), /A has had failures at every snapshot since 11\/13 or before\./],
  ['warnings only on the weather card', () => data([farm('A', [...rep(13, OK), WARN])], 14), /2 warning\(s\) at the latest snapshot, no failure\./],
  ['French', () => data([farm('A', [...rep(13, OK), cell(6, 0, 4)], [...sqlItems(3, 'x'), att('A', UP, 'srv', 'y', '2026-11-20')])], 14), /La plupart des .checs sont dans : SQL - Bases de donn.es\./, null, 'fr-FR']
];
const results = [];
for (const [name, build, expect, forbid, lang] of cases) {
  const hash = '#tab=direction&p=14&lang=' + (lang || 'en-US');
  const a = run(build(), hash), b = run(build(), hash);
  const text = a.sentences.join('\n');
  results.push({ name, error: a.error, text, ok: !a.error && (!expect || expect.test(text)) && (!forbid || !forbid.test(text)) && JSON.stringify(a.sentences) === JSON.stringify(b.sentences) });
}
const hostile = '<img src=x onerror=1>';
const h = run(data([farm('A', [...rep(13, OK), cell(6, 0, 1)], [att('A', SQL, hostile, 'c', '2026-11-20')])], 14), '#tab=direction&p=14&lang=en-US');
results.push({ name: 'a name from the farm is escaped in a sentence', error: h.error, text: h.sentences.join('\n'), ok: !h.error && h.sentences.join('').includes('&lt;img src=x onerror=1&gt;') && !h.html.includes('<img src=x') });
console.log(JSON.stringify(results));
'@)
        # Windows PowerShell 5.1 hands a JSON array over as one object: assign first, then count
        $out = & $script:nodePath $harness $script:file | ConvertFrom-Json
        $out = @($out)
        $out.Count | Should -BeGreaterOrEqual 39
        $failed = @($out | Where-Object -FilterScript { -not $_.ok } | ForEach-Object -Process { "$($_.name) => $($_.error) $($_.text -replace "`n", ' / ')" })
        $failed | Should -BeNullOrEmpty
    }

    It 'do not depend on the machine: no clock, no random number, no locale-dependent comparison in the script' {
        $js = [System.IO.File]::ReadAllText((Join-Path -Path $script:moduleDir -ChildPath 'Assets/Cockpit.js'))
        $js | Should -Not -Match '\bnew Date\(\)|Date\.now|Math\.random|localeCompare|toLocaleLowerCase|toLocaleUpperCase'
        $js | Should -Match "'CockpitInsight"
    }
}

Describe 'The cockpit page with a language that is added, partial or broken' {
    BeforeAll {
        $script:source = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common'
        $copy = Join-Path -Path $TestDrive -ChildPath 'lang/SPSWeather.Common'
        Copy-Item -Path $script:source -Destination $copy -Recurse
        $bom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
        $french = [System.IO.File]::ReadAllText((Join-Path -Path $copy -ChildPath 'fr-FR/SPSWeather.Common.Strings.psd1'))

        # A translation that stops halfway: every Cockpit key after the first thirty is removed (the file stays valid)
        $folder = Join-Path -Path $copy -ChildPath 'de-DE'
        New-Item -Path $folder -ItemType Directory | Out-Null
        $lines = @($french -replace "(Culture\s*=\s*)'fr-FR'", "`$1'de-DE'" -replace "(HtmlLang\s*=\s*)'fr'", "`$1'de'" -split "`r?`n")
        $seen = 0
        $kept = foreach ($line in $lines) {
            if ($line -match '^\s*Cockpit\w+\s*=') { $seen++; if ($seen -gt 30) { continue } }
            $line
        }
        [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'SPSWeather.Common.Strings.psd1'), ($kept -join "`r`n"), $bom)

        # A file whose Culture key is wrong: the module refuses it and falls back to English
        $broken = Join-Path -Path $copy -ChildPath 'xx-XX'
        New-Item -Path $broken -ItemType Directory | Out-Null
        [System.IO.File]::WriteAllText((Join-Path -Path $broken -ChildPath 'SPSWeather.Common.Strings.psd1'), ($french -replace "(Culture\s*=\s*)'fr-FR'", "`$1'not-this'"), $bom)

        Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $copy -ChildPath 'SPSWeather.Common.psd1') -Force
        $script:langResults = Join-Path -Path $TestDrive -ChildPath 'langres'
        New-Item -Path $script:langResults -ItemType Directory | Out-Null
        $script:langPage = Join-Path -Path $TestDrive -ChildPath 'lang/page.html'
        $script:langHtml = { param($Language) Export-SPSWeatherCockpit -OutputFile $script:langPage -ResultsFolder $script:langResults -Application a -Environment e -Language $Language | Out-Null; [System.IO.File]::ReadAllText($script:langPage) }
    }
    AfterAll {
        Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $script:source -ChildPath 'SPSWeather.Common.psd1') -Force
    }

    It 'lists the added language, and opens in it when asked' {
        $html = & $script:langHtml 'de-DE'
        $page = Get-Block -Html $html -Id 'spsw-page'
        @($page.cultures.PSObject.Properties.Name | Sort-Object) | Should -Be @('de-DE', 'en-US', 'fr-FR')
        $page.language | Should -Be 'de-DE'
        $html | Should -Match '<html lang="de">'
    }

    It 'gives a partial translation every key, the missing ones in English, so the page never shows a key name' {
        $page = Get-Block -Html (& $script:langHtml 'de-DE') -Id 'spsw-page'
        $german = $page.cultures.'de-DE'.text
        $english = $page.cultures.'en-US'.text
        @($english.PSObject.Properties.Name | Where-Object -FilterScript { $german.PSObject.Properties.Name -notcontains $_ }) | Should -BeNullOrEmpty
        $german.CockpitTabDirection | Should -Be (Get-Block -Html (& $script:langHtml 'fr-FR') -Id 'spsw-page').cultures.'fr-FR'.text.CockpitTabDirection
        $german.CockpitMethodLimits2 | Should -Be $english.CockpitMethodLimits2
    }

    It 'leaves out a language whose file the module refuses, instead of offering a button that shows English' {
        $page = Get-Block -Html (& $script:langHtml 'xx-XX') -Id 'spsw-page'
        $page.cultures.PSObject.Properties.Name | Should -Not -Contain 'xx-XX'
        $page.language | Should -Be 'en-US'
    }

    It 'opens in English for a language that is not shipped, with the page complete' {
        foreach ($language in 'qaa-QM', 'ja-JP', 'auto-ish') {
            $page = Get-Block -Html (& $script:langHtml $language) -Id 'spsw-page'
            $page.language | Should -Be 'en-US'
            $page.cultures.'en-US'.text.CockpitTabDirection | Should -Be 'Executive'
        }
    }
}
