# The dashboard and the cockpit link to each other (#141): the dashboard of a farm links to the cockpit when the run produces it, and
# the cockpit links to the dashboard of each farm that has one. The links are relative, as the pages share a folder.

# The platform of the tests that need node is decided when they are discovered
$node = Get-Command -Name node -ErrorAction SilentlyContinue

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
    $script:entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
    $script:nodePath = (Get-Command -Name node -ErrorAction SilentlyContinue).Source

    # SHA-256 of the dashboard that 3.5.0 produces for the fixture below: the page must not change by a byte when no link is asked for.
    # Only what depends on the machine or on the day is masked (see Get-Hash): the time of the run in the header and the footer, the date
    # of the run on the chart, the number of the donut offsets (the runtimes print the same double differently) and the line endings and
    # the end of the file (they follow the source file and the host).
    $script:reference = @{
        'en-US' = '00d7217e2461708c158a5f00095f1b9987a3125bbd1d2edfe67b97e82fa95d90'
        'fr-FR' = '6433f32d158384fec67d4851c3846bb0c98c0b219db86449906d3f5cc66aa438'
    }

    function script:Get-DashboardHtml {
        param([string]$Language = 'en-US', [hashtable]$Extra = @{})
        $report = [PSCustomObject]@{}
        $report | Add-Member -NotePropertyName SPAPIHttpStatus -NotePropertyValue @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true })
        $report | Add-Member -NotePropertyName SYSDiskUsageStatus -NotePropertyValue @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'S1'; DriveLetter = 'C'; Size = 100; FreeSpace = 10; Status = 'Low'; IsInfo = $false })
        $history = @(
            [PSCustomObject]@{ Date = '06-01'; Ok = 12; Warn = 0; Fail = 1 }
            [PSCustomObject]@{ Date = '06-02'; Ok = 11; Warn = 1; Fail = 2 })
        $file = Join-Path -Path $TestDrive -ChildPath ('dash-' + [guid]::NewGuid().ToString('N') + '.html')
        $arguments = @{ InputObject = $report; OutputFile = $file; Farm = 'CONTENT'; Application = 'zebes'; Environment = 'PROD'; Version = '3.5.0'; ExecutedBy = 'DOM\svc'; Duration = '00:01:02'; History = $history; Language = $Language }
        foreach ($key in $Extra.Keys) { $arguments[$key] = $Extra[$key] }
        [void](Export-SPSWeatherReport @arguments)
        [System.IO.File]::ReadAllText($file)
    }

    function script:Get-Hash {
        param([string]$Html)
        $masked = $Html.Replace("`r`n", "`n")
        $masked = [regex]::Replace($masked, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}', 'STAMP')
        # the date of the run on the chart is written MM-dd in English and dd/MM in French
        $today = Get-Date
        foreach ($format in @('MM-dd', 'dd/MM')) { $masked = $masked.Replace($today.ToString($format, [System.Globalization.CultureInfo]::InvariantCulture), 'MD') }
        $masked = [regex]::Replace($masked, 'stroke-dashoffset="[^"]*"', 'stroke-dashoffset="OFFSET"').TrimEnd()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($masked))) -replace '-', '').ToLowerInvariant()
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Dashboard to cockpit link (Export-SPSWeatherReport -CockpitFile)' {
    Context 'no link asked for: the page is the one of 3.5.0' {
        It 'is identical byte for byte (<Name>)' -ForEach @(
            @{ Name = 'en-US'; Language = 'en-US'; Extra = @{} }
            @{ Name = 'fr-FR'; Language = 'fr-FR'; Extra = @{} }
            @{ Name = 'en-US, an empty file name'; Language = 'en-US'; Extra = @{ CockpitFile = '' } }
            @{ Name = 'fr-FR, an empty file name'; Language = 'fr-FR'; Extra = @{ CockpitFile = '' } }
            @{ Name = 'en-US, a blank file name'; Language = 'en-US'; Extra = @{ CockpitFile = '   ' } }
        ) {
            $html = Get-DashboardHtml -Language $Language -Extra $Extra
            Get-Hash -Html $html | Should -Be $script:reference[$Language]
            $html | Should -Not -Match 'cockpit'
        }
    }

    Context 'a link' {
        BeforeAll {
            $script:linked = Get-DashboardHtml -Extra @{ CockpitFile = 'zebes-PROD-cockpit.html' }
        }

        It 'is in the header, once, and relative' {
            $link = '<a class="cockpit-link" href="zebes-PROD-cockpit.html">Open the cockpit &rarr;</a>'
            ([regex]::Matches($linked, [regex]::Escape($link))).Count | Should -Be 1
            $start = $linked.IndexOf('<div class="top-right">')
            $end = $linked.IndexOf('</header>')
            $position = $linked.IndexOf($link)
            $position | Should -BeGreaterThan $start
            $position | Should -BeLessThan $end
            # the last child of the block on the right of the header, next to the date of the run
            $linked | Should -Match '<b>[^<]*</b><br>[^<]*&middot; v3\.5\.0</div><a class="cockpit-link" href="zebes-PROD-cockpit\.html">Open the cockpit &rarr;</a></div>\r?\n</header>'
            $linked | Should -Not -Match 'href="(?:https?:)?//[^"]*cockpit'
        }

        It 'is the only difference: without the link and its style, the page is the one of 3.5.0' {
            $link = '<a class="cockpit-link" href="zebes-PROD-cockpit.html">Open the cockpit &rarr;</a>'
            $css = [regex]::Match($linked, '\.cockpit-link\{.*?\.cockpit-link:focus-visible\{[^}]*\}').Value
            $css | Should -Not -BeNullOrEmpty
            Get-Hash -Html $linked.Replace($link, '').Replace($css, '') | Should -Be $script:reference['en-US']
        }

        It 'is translated' {
            $fr = Get-DashboardHtml -Language 'fr-FR' -Extra @{ CockpitFile = 'zebes-PROD-cockpit.html' }
            $fr | Should -Match '>Ouvrir le cockpit &rarr;</a>'
            $fr | Should -Not -Match 'Open the cockpit'
        }

        It 'has a style that keeps the contrast of the header and a visible keyboard focus' {
            $linked | Should -Match '\.cockpit-link\{color:#fff;'
            $linked | Should -Match '\.cockpit-link:focus-visible\{outline:'
        }

        It 'encodes the file name, so that it can never read as a scheme, a path or markup' -ForEach @(
            @{ Name = 'blanks and punctuation'; File = 'zebes PROD&cockpit #1.html'; Expected = 'zebes%20PROD%26cockpit%20%231.html' }
            @{ Name = 'markup and quotes'; File = 'a"b<c>d''e.html'; Expected = 'a%22b%3Cc%3Ed%27e.html' }
            @{ Name = 'a colon'; File = 'javascript:alert(1).html'; Expected = 'javascript%3Aalert%281%29.html' }
            @{ Name = 'path separators'; File = '..\..\a/b.html'; Expected = '..%5C..%5Ca%2Fb.html' }
            @{ Name = 'accents'; File = 'été.html'; Expected = '%C3%A9t%C3%A9.html' }
        ) {
            $html = Get-DashboardHtml -Extra @{ CockpitFile = $File }
            $href = [regex]::Match($html, '<a class="cockpit-link" href="([^"]*)"').Groups[1].Value
            $href | Should -Be $Expected
            $href | Should -Not -Match '[/\\:<>"]'
        }

        It 'trims the file name' {
            (Get-DashboardHtml -Extra @{ CockpitFile = '  zebes-PROD-cockpit.html  ' }) | Should -Match 'href="zebes-PROD-cockpit.html"'
        }
    }
}

Describe 'The entry script gives the link only when the run produces the cockpit' {
    BeforeAll {
        $script:source = [System.IO.File]::ReadAllText($entryPath)
        $m = [regex]::Match($source, '(?m)^\s*\$dashboardCockpitLink = (.+)$')
        $script:expression = $m.Groups[1].Value
    }

    It 'builds the link arguments from the cockpit setting, before the farm loop' {
        $expression | Should -Not -BeNullOrEmpty
        $source.IndexOf('$dashboardCockpitLink =') | Should -BeLessThan $source.IndexOf('foreach ($farmName in @($probedFarms))')
    }

    It 'gives the file name of the cockpit when it is enabled' {
        $cockpitSetting = [PSCustomObject]@{ Enabled = $true; FileName = 'zebes-PROD-cockpit.html' }
        $arguments = Invoke-Expression -Command $expression
        $arguments.Keys | Should -Be @('CockpitFile')
        $arguments['CockpitFile'] | Should -Be 'zebes-PROD-cockpit.html'
    }

    It 'gives nothing when it is not enabled' {
        $cockpitSetting = [PSCustomObject]@{ Enabled = $false; FileName = 'zebes-PROD-cockpit.html' }
        $arguments = Invoke-Expression -Command $expression
        $arguments.Count | Should -Be 0
    }

    It 'hands them to the dashboard of every farm, and only to the dashboard (not to the emails)' {
        $call = [regex]::Match($source, 'Export-SPSWeatherReport -InputObject \$farmJson[^)]*\)', 'Singleline').Value
        $call | Should -Match '@dashboardCockpitLink'
        ([regex]::Matches($source, '@dashboardCockpitLink')).Count | Should -Be 1
    }
}

Describe 'Cockpit to dashboard link' {
    BeforeAll {
        function script:New-Results {
            $root = Join-Path -Path $TestDrive -ChildPath ('res-' + [guid]::NewGuid().ToString('N'))
            New-Item -Path $root -ItemType Directory -Force | Out-Null
            $root
        }
        function script:Add-Snap {
            param($Results, [string]$Farm, [datetime]$When, [int]$Fail = 1)
            $safe = $Farm -replace '[^A-Za-z0-9_-]', '_'
            $folder = Join-Path -Path $Results -ChildPath "history/$safe"
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            $rows = @(foreach ($i in 1..$Fail) { [PSCustomObject]@{ Farm = $Farm; SqlServer = 'SQL1'; Name = "DB$i"; Recommendation = 'no full backup found'; IsInfo = $false } })
            $snap = [PSCustomObject]@{ SQLDatabaseStatus = $rows }
            $file = Join-Path -Path $folder -ChildPath ("zebes-PROD-$safe-" + $When.ToString('yyyyMMdd-HHmm') + '.json')
            [System.IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $snap -Depth 6))
            (Get-Item -LiteralPath $file).LastWriteTime = $When
        }
        function script:Get-Data {
            param($Results, [string[]]$Farm, [string]$DashboardFolder)
            $arguments = @{ ResultsFolder = $Results; Application = 'zebes'; Environment = 'PROD'; FarmName = $Farm; RetentionDays = 30 }
            if ($PSBoundParameters.ContainsKey('DashboardFolder')) { $arguments['DashboardFolder'] = $DashboardFolder }
            InModuleScope SPSWeather.Common -Parameters @{ Arguments = $arguments } { param($Arguments) Get-SPSWeatherCockpitData @Arguments }
        }

        $script:hostile = '</script><script>window.__pwned=1</script>'
        $script:results = New-Results
        $script:when = (Get-Date).AddDays(-1)
        Add-Snap -Results $results -Farm 'CONTENT' -When $when
        Add-Snap -Results $results -Farm 'SEARCH' -When $when
        Add-Snap -Results $results -Farm $hostile -When $when
        $script:folder = Join-Path -Path $TestDrive -ChildPath 'pages'
        New-Item -Path $folder -ItemType Directory | Out-Null
        $hostileSafe = $hostile -replace '[^A-Za-z0-9_-]', '_'
        foreach ($name in @('zebes-PROD-CONTENT-dashboard.html', "zebes-PROD-$hostileSafe-dashboard.html", 'zebes-QUAL-SEARCH-dashboard.html', 'zebes-PROD-cockpit.html')) {
            [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath $name), '<html></html>')
        }
    }

    Context 'the dataset' {
        It 'gives a farm the file name of its dashboard when it is in the folder of the page' {
            $data = Get-Data -Results $results -Farm 'CONTENT', 'SEARCH' -DashboardFolder $folder
            @($data.farms | Where-Object -FilterScript { $_.name -eq 'CONTENT' })[0].dashboard | Should -Be 'zebes-PROD-CONTENT-dashboard.html'
        }

        It 'gives nothing to a farm without a dashboard there, and ignores the dashboard of another environment' {
            $data = Get-Data -Results $results -Farm 'CONTENT', 'SEARCH' -DashboardFolder $folder
            @($data.farms | Where-Object -FilterScript { $_.name -eq 'SEARCH' })[0].dashboard | Should -BeNullOrEmpty
        }

        It 'builds the name of a farm that has special characters the way the run does' {
            $data = Get-Data -Results $results -Farm 'CONTENT', $hostile -DashboardFolder $folder
            $safe = $hostile -replace '[^A-Za-z0-9_-]', '_'
            @($data.farms | Where-Object -FilterScript { $_.name -eq $hostile })[0].dashboard | Should -Be "zebes-PROD-$safe-dashboard.html"
        }

        It 'accepts a folder written with a trailing separator' {
            $data = Get-Data -Results $results -Farm 'CONTENT' -DashboardFolder ($folder + [System.IO.Path]::DirectorySeparatorChar)
            @($data.farms)[0].dashboard | Should -Be 'zebes-PROD-CONTENT-dashboard.html'
        }

        It 'gives nothing without a folder, with an empty one or with one that does not exist, and does not throw' -ForEach @(
            @{ Name = 'no folder'; Folder = $null }
            @{ Name = 'an empty folder'; Folder = '' }
            @{ Name = 'a folder that does not exist'; Folder = 'Q:\no\such\folder' }
        ) {
            $data = if ($null -eq $Folder) { Get-Data -Results $results -Farm 'CONTENT' } else { Get-Data -Results $results -Farm 'CONTENT' -DashboardFolder $Folder }
            @($data.farms)[0].Contains('dashboard') | Should -BeTrue
            @($data.farms)[0].dashboard | Should -BeNullOrEmpty
        }

        It 'is read from the folder of the page when the page is exported' {
            $out = Join-Path -Path $folder -ChildPath 'zebes-PROD-cockpit.html'
            [void](Export-SPSWeatherCockpit -OutputFile $out -ResultsFolder $results -Application 'zebes' -Environment 'PROD' -FarmName 'CONTENT', 'SEARCH' -RetentionDays 30 -Language 'en-US' -Version '9.9.9')
            $html = [System.IO.File]::ReadAllText($out)
            $block = [regex]::Match($html, '<script type="application/json" id="spsw-data">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
            @($block.farms | Where-Object -FilterScript { $_.name -eq 'CONTENT' })[0].dashboard | Should -Be 'zebes-PROD-CONTENT-dashboard.html'
            @($block.farms | Where-Object -FilterScript { $_.name -eq 'SEARCH' })[0].dashboard | Should -BeNullOrEmpty
        }
    }

    Context 'the page' {
        BeforeAll {
            $script:pagePath = Join-Path -Path $folder -ChildPath 'zebes-PROD-cockpit.html'
            $script:pageCode = [System.IO.File]::ReadAllText((Join-Path -Path $moduleDir -ChildPath 'Assets/Cockpit.js'))
            $script:harness = Join-Path -Path $TestDrive -ChildPath 'links-harness.js'
            [System.IO.File]::WriteAllText($harness, @'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const hash = process.argv[3];
const block = id => new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>').exec(html)[1];
const code = /<script>\n([\s\S]*)\n<\/script>\s*<\/body>/.exec(html)[1];
const d = JSON.parse(block('spsw-data'));
for (const f of d.farms) { if (f.name === 'CONTENT') f.dashboard = 'zebes PROD&CONTENT #1.html'; else f.dashboard = null; }
const els = { 'spsw-data': { textContent: JSON.stringify(d) }, 'spsw-page': { textContent: block('spsw-page') }, 'spsw-error': { textContent: '', hidden: true }, 'spsw-header': { innerHTML: '' }, 'spsw-main': { innerHTML: '' }, 'spsw-footer': { innerHTML: '' } };
const doc = { getElementById: id => els[id], querySelector: () => null, addEventListener() {}, title: '', documentElement: { setAttribute() {}, lang: '' } };
const win = { addEventListener() {}, innerWidth: 1320, matchMedia: () => ({ matches: false }), scrollTo() {} };
new Function('document', 'window', 'location', 'history', code)(doc, win, { hash: hash + '&lang=en-US' }, { replaceState() {} });
process.stdout.write(JSON.stringify({ html: els['spsw-main'].innerHTML, error: els['spsw-error'].hidden ? '' : els['spsw-error'].textContent }));
'@)
        }

        It 'is valid JavaScript, still ASCII only, and the new string exists in both languages' -Skip:(-not $node) {
            $pageCode | Should -Not -Match '[^\x00-\x7F]'
            $source = Join-Path -Path $TestDrive -ChildPath 'links-check.js'
            [System.IO.File]::WriteAllText($source, $pageCode)
            & $script:nodePath --check $source
            $LASTEXITCODE | Should -Be 0
            $en = Import-PowerShellDataFile -Path (Join-Path -Path $moduleDir -ChildPath 'en-US/SPSWeather.Common.Strings.psd1')
            $fr = Import-PowerShellDataFile -Path (Join-Path -Path $moduleDir -ChildPath 'fr-FR/SPSWeather.Common.Strings.psd1')
            $en['CockpitOpenDashboard'] | Should -Be 'Open the farm dashboard'
            $fr['CockpitOpenDashboard'] | Should -Be 'Ouvrir le tableau de bord de la ferme'
        }

        It 'puts a link on the card of a farm that has a dashboard, and on no other, with the file name encoded' -Skip:(-not $node) {
            $result = & $script:nodePath $script:harness $script:pagePath '#tab=direction&p=14' | ConvertFrom-Json
            $result.error | Should -BeNullOrEmpty
            ([regex]::Matches($result.html, 'class="cta" href="zebes%20PROD%26CONTENT%20%231\.html">Open the farm dashboard')).Count | Should -Be 1
            ([regex]::Matches($result.html, 'Open the farm dashboard')).Count | Should -Be 1
        }

        It 'puts the link in the detail of the farm on the IT tab, and nothing in the tabs that list no farm' -Skip:(-not $node) {
            $it = & $script:nodePath $script:harness $script:pagePath '#tab=it&p=14' | ConvertFrom-Json
            $it.error | Should -BeNullOrEmpty
            ([regex]::Matches($it.html, 'class="cta" href="zebes%20PROD%26CONTENT%20%231\.html">Open the farm dashboard')).Count | Should -Be 1
            $it.html | Should -Not -Match 'href="[^"#][^"]*\.html"[^>]*>(?!Open the farm dashboard)'
            $quality = & $script:nodePath $script:harness $script:pagePath '#tab=quality&p=14' | ConvertFrom-Json
            $quality.html | Should -Not -Match 'Open the farm dashboard'
        }

        It 'draws no link for a dataset without the field (a page built before this change keeps working)' -Skip:(-not $node) {
            $old = Join-Path -Path $TestDrive -ChildPath 'links-old.js'
            [System.IO.File]::WriteAllText($old, ([System.IO.File]::ReadAllText($harness)).Replace("for (const f of d.farms) { if (f.name === 'CONTENT') f.dashboard = 'zebes PROD&CONTENT #1.html'; else f.dashboard = null; }", 'for (const f of d.farms) delete f.dashboard;'))
            $result = & $script:nodePath $old $script:pagePath '#tab=direction&p=14' | ConvertFrom-Json
            $result.error | Should -BeNullOrEmpty
            $result.html | Should -Not -Match 'Open the farm dashboard'
        }
    }
}
