# Behavioural tests for ConvertTo-SPSWeatherConsolidatedEmail: one Outlook-safe email for all the
# farms of an environment (subject, priority, totals, one card per farm, unreachable farm, cap,
# encoding, languages).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    # A farm report with the given numbers of failing and warning timer jobs / SQL databases and of
    # healthy search sources, as the collectors would return them.
    function New-FarmReport {
        param([string]$Farm, [int]$SqlFail = 0, [int]$TimerFail = 0, [int]$IisFail = 0, [int]$SearchWarn = 0, [int]$Ok = 0)
        $report = [ordered]@{}
        if ($SqlFail) { $report.SQLDatabaseStatus = @(1..$SqlFail | ForEach-Object { [PSCustomObject]@{ Farm = $Farm; SqlServer = 'SQL1'; Name = "DB_$_"; State = 'ONLINE'; Recommendation = 'no full backup found'; IsInfo = $false } }) }
        if ($TimerFail) { $report.SPFailedTimerJobs = @(1..$TimerFail | ForEach-Object { [PSCustomObject]@{ Farm = $Farm; Server = 'WFE1'; JobDefinitionTitle = "Job $_"; Status = 'Failed'; IsInfo = $false } }) }
        if ($IisFail) { $report.IISApplicationPoolStatus = @(1..$IisFail | ForEach-Object { [PSCustomObject]@{ Farm = $Farm; Server = 'WFE1'; ApplicationPool = "Pool $_"; Status = 'Stopped'; IsInfo = $false } }) }
        if ($SearchWarn) { $report.SPSearchCrawlLogs = @(1..$SearchWarn | ForEach-Object { [PSCustomObject]@{ Farm = $Farm; ContentSource = "CS$_"; Message = 'error'; ErrorID = '1'; severity = '2 - Warning' } }) }
        if ($Ok) { $report.SPSContentDBStatus = @(1..$Ok | ForEach-Object { [PSCustomObject]@{ Farm = $Farm; DatabaseName = "DB$_"; Status = 'Online'; Upgrade = 'NoActionRequired'; IsInfo = $true } }) }
        [PSCustomObject]$report
    }
    # The entry the entry script collects for a farm that was reached.
    function New-FarmEntry {
        param([string]$Name, [PSCustomObject]$Report, [string]$Url = '', [string]$Server = '', [switch]$NoSummary)
        $section = [ordered]@{}
        foreach ($p in $Report.PSObject.Properties) { $section[$p.Name] = $p.Value }
        $result = & (Get-Module SPSWeather.Common) { param($s) ConvertTo-SPSWeatherReport -Section $s } $section
        $entry = [ordered]@{ Name = $Name; Server = $(if ($Server) { $Server } else { "srv$($Name.ToLower())" }); Reachable = $true; Report = $result.Report; DashboardUrl = $Url }
        if (-not $NoSummary) { $entry.Summary = $result.Summary }
        [PSCustomObject]$entry
    }
    function New-DownEntry {
        param([string]$Name)
        [PSCustomObject]@{ Name = $Name; Server = "srv$($Name.ToLower())"; Reachable = $false }
    }
    function Get-Consolidated {
        param($Farms, [string]$Language = 'en-US', [int]$Max = 3)
        ConvertTo-SPSWeatherConsolidatedEmail -FarmResult $Farms -Application 'contoso' -Environment 'PROD' -Version '3.4.0' -ExecutedBy 'DOM\jc' -Duration '00:11:42' -Language $Language -MaxAttentionPerFarm $Max
    }
    # Decoded text of the email, to match on what a reader sees.
    function Get-Text {
        param($Mail)
        $plain = $Mail.Body -replace '</?(b|span|a)\b[^>]*>', '' -replace '<[^>]+>', ' ' -replace '[ \t\r\n]+', ' '
        [System.Net.WebUtility]::HtmlDecode($plain)
    }
    # Position of a farm card: the farm names are written in bold-size headings.
    function Get-Position {
        param($Mail, [string]$Name)
        $Mail.Body.IndexOf(">$Name</div>")
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Consolidated email (ConvertTo-SPSWeatherConsolidatedEmail)' {
    BeforeAll {
        $base = 'https://dash.contoso.local/SPSWeather'
        $script:farms = @(
            (New-FarmEntry -Name 'SEARCH' -Report (New-FarmReport -Farm 'SEARCH' -SearchWarn 2 -Ok 61) -Url "$base/contoso-PROD-SEARCH-dashboard.html")
            (New-FarmEntry -Name 'SERVICES' -Report (New-FarmReport -Farm 'SERVICES' -Ok 142) -Url "$base/contoso-PROD-SERVICES-dashboard.html")
            (New-FarmEntry -Name 'CONTENT' -Report (New-FarmReport -Farm 'CONTENT' -SqlFail 17 -TimerFail 12 -IisFail 4 -Ok 115) -Url "$base/contoso-PROD-CONTENT-dashboard.html")
        )
        $script:mail = Get-Consolidated -Farms $farms
        $script:text = Get-Text -Mail $mail
    }

    Context 'the result' {
        It 'returns the subject, the priority, the worst alert level and the HTML body' {
            $mail.PSObject.Properties.Name | Should -Contain 'Subject'
            $mail.PSObject.Properties.Name | Should -Contain 'Priority'
            $mail.PSObject.Properties.Name | Should -Contain 'Alert'
            $mail.PSObject.Properties.Name | Should -Contain 'Body'
        }

        It 'returns a single self-contained, Outlook-safe HTML document' {
            $mail.Body.StartsWith('<!DOCTYPE html>') | Should -BeTrue
            $mail.Body.TrimEnd().EndsWith('</html>') | Should -BeTrue
            $mail.Body | Should -Match '\[if mso\]'
        }

        It 'uses no script, no external resource and no CSS that Outlook drops (flex, grid, var)' {
            $mail.Body | Should -Not -Match '<script|<link|@import|display:\s*(flex|grid)|var\(--|url\('
        }
    }

    Context 'subject, priority and alert level' {
        It 'tags the subject with the worst status, in English, and counts the farms of each status' {
            $mail.Subject | Should -Be '[ALERT] contoso/PROD - 3 farms (1 ALERT, 1 WARN, 1 OK) - SPSWeather'
            $mail.Alert | Should -Be 'ALERT'
            $mail.Priority | Should -Be 'High'
        }

        It 'is [WARN] with a normal priority when no farm has a failure' {
            $m = Get-Consolidated -Farms @($farms[0], $farms[1])
            $m.Subject | Should -Be '[WARN] contoso/PROD - 2 farms (1 WARN, 1 OK) - SPSWeather'
            $m.Alert | Should -Be 'WARN'
            $m.Priority | Should -Be 'Normal'
        }

        It 'is [OK] with a normal priority when every farm is healthy' {
            $m = Get-Consolidated -Farms @($farms[1])
            $m.Subject | Should -Be '[OK] contoso/PROD - 1 farm (1 OK) - SPSWeather'
            $m.Alert | Should -Be 'OK'
            $m.Priority | Should -Be 'Normal'
        }

        It 'counts an unreachable farm as ALERT (tag and priority) and names it in the subject' {
            $m = Get-Consolidated -Farms @($farms[1], (New-DownEntry -Name 'SERVICES2'))
            $m.Subject | Should -Be '[ALERT] contoso/PROD - 2 farms (1 UNREACHABLE, 1 OK) - SPSWeather'
            $m.Alert | Should -Be 'ALERT'
            $m.Priority | Should -Be 'High'
        }

        It 'is [ALERT] when every farm is unreachable (the run used to send nothing at all)' {
            $m = Get-Consolidated -Farms @((New-DownEntry -Name 'A'), (New-DownEntry -Name 'B'))
            $m.Subject | Should -Be '[ALERT] contoso/PROD - 2 farms (2 UNREACHABLE) - SPSWeather'
            $m.Priority | Should -Be 'High'
        }

        It 'keeps the subject in English whatever the display language (inbox rules filter on the tag)' {
            (Get-Consolidated -Farms $farms -Language 'fr-FR').Subject | Should -Be $mail.Subject
        }
    }

    Context 'totals across the farms' {
        It 'shows the failures, warnings and checks OK of all the farms together' {
            $mail.Body -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $Matches[1] | Should -Be '33'
            $mail.Body -match '>(\d+)</div><div[^>]*>Warnings<' | Should -BeTrue
            $Matches[1] | Should -Be '2'
            $mail.Body -match '>(\d+)</div><div[^>]*>Checks OK<' | Should -BeTrue
            $Matches[1] | Should -Be '318'
        }

        It 'does not count an unreachable farm (it has no data), and still counts the others' {
            $m = Get-Consolidated -Farms @($farms[2], (New-DownEntry -Name 'SERVICES'))
            $m.Body -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $Matches[1] | Should -Be '33'
            $m.Body -match '>(\d+)</div><div[^>]*>Checks OK<' | Should -BeTrue
            $Matches[1] | Should -Be '115'
        }

        It 'computes the counts from the report when the summary is not given' {
            $noSummary = New-FarmEntry -Name 'CONTENT' -Report (New-FarmReport -Farm 'CONTENT' -SqlFail 5 -Ok 20) -NoSummary
            $m = Get-Consolidated -Farms @($noSummary)
            $m.Body -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $Matches[1] | Should -Be '5'
            $m.Body -match '>(\d+)</div><div[^>]*>Checks OK<' | Should -BeTrue
            $Matches[1] | Should -Be '20'
        }
    }

    Context 'one card per farm' {
        It 'lists every farm with its server' {
            foreach ($name in 'SEARCH', 'SERVICES', 'CONTENT') {
                (Get-Position -Mail $mail -Name $name) | Should -BeGreaterThan 0
                $mail.Body | Should -Match "srv$($name.ToLower())"
            }
        }

        It 'orders the cards worst first: unreachable, alert, warning, healthy' {
            $m = Get-Consolidated -Farms @($farms[1], $farms[0], $farms[2], (New-DownEntry -Name 'DOWN1'))
            $order = @('DOWN1', 'CONTENT', 'SEARCH', 'SERVICES') | ForEach-Object { Get-Position -Mail $m -Name $_ }
            $order | ForEach-Object { $_ | Should -BeGreaterThan 0 }
            $sorted = @($order | Sort-Object)
            ($order -join ',') | Should -Be ($sorted -join ',')
        }

        It 'puts the farm with more failures first among farms in alert, then keeps the configuration order' {
            $a = New-FarmEntry -Name 'A' -Report (New-FarmReport -Farm 'A' -SqlFail 2)
            $b = New-FarmEntry -Name 'B' -Report (New-FarmReport -Farm 'B' -SqlFail 9)
            $c = New-FarmEntry -Name 'C' -Report (New-FarmReport -Farm 'C' -SqlFail 2)
            $m = Get-Consolidated -Farms @($a, $b, $c)
            (Get-Position -Mail $m -Name 'B') | Should -BeLessThan (Get-Position -Mail $m -Name 'A')
            (Get-Position -Mail $m -Name 'A') | Should -BeLessThan (Get-Position -Mail $m -Name 'C')
        }

        It 'shows the status badge of each farm' {
            $text | Should -Match 'ALERT'
            $text | Should -Match 'WARNING'
            $text | Should -Match 'HEALTHY'
        }

        It 'shows the health percentage and the counts of a farm' {
            $text | Should -Match '78% healthy'
            $text | Should -Match '115 OK / 0 warn / 33 fail'
            $text | Should -Match '97% healthy'
            $text | Should -Match '100% healthy'
            $text | Should -Match '142 OK / 0 warn / 0 fail'
        }

        It 'draws a health bar whose widths add up to 100 and show a tiny failure rate as at least 2' {
            $tiny = New-FarmEntry -Name 'TINY' -Report (New-FarmReport -Farm 'TINY' -SqlFail 1 -Ok 4000)
            $m = Get-Consolidated -Farms @($tiny)
            $widths = @([regex]::Matches($m.Body, '<td width="(\d+)%" height="8"') | ForEach-Object { [int]$_.Groups[1].Value })
            $widths.Count | Should -Be 2
            ($widths | Measure-Object -Sum).Sum | Should -Be 100
            ($widths | Measure-Object -Minimum).Minimum | Should -BeGreaterOrEqual 2
        }

        It 'draws no bar and no percentage for a farm that returned no check' {
            $empty = New-FarmEntry -Name 'EMPTY' -Report ([PSCustomObject]@{ SPSContentDBStatus = @() })
            $m = Get-Consolidated -Farms @($empty)
            $m.Body | Should -Not -Match '[0-9]+% healthy'
            $m.Body | Should -Not -Match 'height="8"'
        }

        It 'gives the leftover of the rounding to the widest part, never creating a cell for a zero count' -ForEach @(
            @{ Ok = 17; Warn = 23; Fail = 0 }
            @{ Ok = 23; Warn = 17; Fail = 0 }
            @{ Ok = 34; Warn = 46; Fail = 0 }
            @{ Ok = 91; Warn = 109; Fail = 0 }
            @{ Ok = 0; Warn = 3; Fail = 5 }
            @{ Ok = 1; Warn = 1; Fail = 1 }
            @{ Ok = 5000; Warn = 1; Fail = 1 }
            @{ Ok = 7; Warn = 0; Fail = 0 }
        ) {
            $entry = [PSCustomObject]@{ Name = 'BAR'; Server = 's'; Reachable = $true; Report = [PSCustomObject]@{}; Summary = [PSCustomObject]@{ Ok = $Ok; Warn = $Warn; Fail = $Fail } }
            $m = Get-Consolidated -Farms @($entry)
            $widths = @([regex]::Matches($m.Body, '<td width="(-?\d+)%" height="8" style="background:#([0-9a-f]{6})') | ForEach-Object { [PSCustomObject]@{ W = [int]$_.Groups[1].Value; C = $_.Groups[2].Value } })
            ($widths | Measure-Object -Property W -Sum).Sum | Should -Be 100
            ($widths | Measure-Object -Property W -Minimum).Minimum | Should -BeGreaterOrEqual 1
            @($widths | Where-Object { $_.C -eq 'e24a4a' }).Count | Should -Be ([int]($Fail -gt 0))
            @($widths | Where-Object { $_.C -eq 'e8923a' }).Count | Should -Be ([int]($Warn -gt 0))
            @($widths | Where-Object { $_.C -eq '2fae66' }).Count | Should -Be ([int]($Ok -gt 0))
        }

        It 'never reads 100% healthy next to a failure or a warning, even among thousands of checks' {
            $big = New-FarmEntry -Name 'BIG' -Report (New-FarmReport -Farm 'BIG' -SqlFail 1 -Ok 4000)
            (Get-Text -Mail (Get-Consolidated -Farms @($big))) | Should -Match '99% healthy'
            $warnOnly = [PSCustomObject]@{ Name = 'W'; Server = 's'; Reachable = $true; Report = [PSCustomObject]@{}; Summary = [PSCustomObject]@{ Ok = 4000; Warn = 1; Fail = 0 } }
            (Get-Text -Mail (Get-Consolidated -Farms @($warnOnly))) | Should -Match '99% healthy'
            $clean = New-FarmEntry -Name 'CLEAN' -Report (New-FarmReport -Farm 'CLEAN' -Ok 4000)
            (Get-Text -Mail (Get-Consolidated -Farms @($clean))) | Should -Match '100% healthy'
        }

        It 'uses the summary of the farm when it is given, not a recount of the report' {
            $entry = New-FarmEntry -Name 'SUM' -Report (New-FarmReport -Farm 'SUM' -SqlFail 2 -Ok 3)
            $entry.Summary = [PSCustomObject]@{ Ok = 40; Warn = 3; Fail = 7 }
            $m = Get-Consolidated -Farms @($entry)
            (Get-Text -Mail $m) | Should -Match '40 OK / 3 warn / 7 fail'
            $m.Body -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $Matches[1] | Should -Be '7'
        }
    }

    Context 'the areas that need attention' {
        It 'lists the areas with the most failures first, with their counts' {
            $text | Should -Match 'SQL Server 17 failures'
            $text | Should -Match 'Timer Jobs 12 failures'
            $text | Should -Match 'IIS 4 failures'
            (Get-Position -Mail $mail -Name 'CONTENT') | Should -BeGreaterThan 0
            $mail.Body.IndexOf('SQL Server') | Should -BeLessThan $mail.Body.IndexOf('Timer Jobs')
            $mail.Body.IndexOf('Timer Jobs') | Should -BeLessThan $mail.Body.IndexOf('>IIS<')
        }

        It 'uses the singular and the plural of failures and warnings' {
            $one = New-FarmEntry -Name 'ONE' -Report (New-FarmReport -Farm 'ONE' -SqlFail 1 -SearchWarn 1)
            $t = Get-Text -Mail (Get-Consolidated -Farms @($one))
            $t | Should -Match 'SQL Server 1 failure(?!s)'
            $t | Should -Match 'Search 1 warning(?!s)'
            $text | Should -Match 'Search 2 warnings'
        }

        It 'caps the list at three areas and summarizes the rest as "+ N more"' {
            $many = New-FarmEntry -Name 'MANY' -Report (New-FarmReport -Farm 'MANY' -SqlFail 9 -TimerFail 8 -IisFail 7 -SearchWarn 2)
            $t = Get-Text -Mail (Get-Consolidated -Farms @($many))
            $t | Should -Match 'SQL Server 9 failures'
            $t | Should -Match 'Timer Jobs 8 failures'
            $t | Should -Match 'IIS 7 failures'
            $t | Should -Match '\+ 2 more \(2 warnings\)'
            $t | Should -Not -Match 'Search 2 warnings'
        }

        It 'lists every area with -MaxAttentionPerFarm 0' {
            $many = New-FarmEntry -Name 'MANY' -Report (New-FarmReport -Farm 'MANY' -SqlFail 9 -TimerFail 8 -IisFail 7 -SearchWarn 2)
            $t = Get-Text -Mail (Get-Consolidated -Farms @($many) -Max 0)
            $t | Should -Match 'Search 2 warnings'
            $t | Should -Not -Match 'more'
        }

        It 'says there is nothing to review for a healthy farm, and lists no area' {
            $healthy = New-FarmEntry -Name 'HEALTHY1' -Report (New-FarmReport -Farm 'HEALTHY1' -Ok 10)
            $m = Get-Consolidated -Farms @($healthy)
            (Get-Text -Mail $m) | Should -Match 'No item needs attention on this farm\.'
            $m.Body | Should -Not -MatchExactly 'Needs attention'
        }

        It 'counts a check of a section outside the area table in the totals but lists no area for it' {
            $odd = [PSCustomObject]@{ SomethingNew = @([PSCustomObject]@{ Farm = 'ODD'; Name = 'x'; Status = 'Failed'; IsInfo = $false }) }
            $m = Get-Consolidated -Farms @((New-FarmEntry -Name 'ODD' -Report $odd))
            $m.Body -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $Matches[1] | Should -Be '1'
            $m.Alert | Should -Be 'ALERT'
            $m.Body | Should -Not -MatchExactly 'Needs attention'
        }
    }

    Context 'the dashboard button' {
        It 'points each farm to its own dashboard' {
            $mail.Body | Should -Match 'href="https://dash\.contoso\.local/SPSWeather/contoso-PROD-CONTENT-dashboard\.html"'
            $mail.Body | Should -Match 'href="https://dash\.contoso\.local/SPSWeather/contoso-PROD-SEARCH-dashboard\.html"'
            $mail.Body | Should -Match 'href="https://dash\.contoso\.local/SPSWeather/contoso-PROD-SERVICES-dashboard\.html"'
            @([regex]::Matches($mail.Body, 'Open full dashboard')).Count | Should -Be 3
        }

        It 'has no button when the dashboard is not hosted (no URL), and the card is still closed properly' {
            $noUrl = New-FarmEntry -Name 'NOURL' -Report (New-FarmReport -Farm 'NOURL' -SqlFail 1)
            $m = Get-Consolidated -Farms @($noUrl)
            $m.Body | Should -Not -Match 'Open full dashboard'
            $m.Body | Should -Not -Match '<a href='
            ([regex]::Matches($m.Body, '<table')).Count | Should -Be ([regex]::Matches($m.Body, '</table>')).Count
        }
    }

    Context 'an unreachable farm' {
        BeforeAll {
            $script:down = Get-Consolidated -Farms @($farms[0], (New-DownEntry -Name 'SERVICES'), $farms[2])
            $script:downText = Get-Text -Mail $down
        }

        It 'gets a card of its own, first, instead of being left out' {
            (Get-Position -Mail $down -Name 'SERVICES') | Should -BeGreaterThan 0
            (Get-Position -Mail $down -Name 'SERVICES') | Should -BeLessThan (Get-Position -Mail $down -Name 'CONTENT')
            $downText | Should -Match 'UNREACHABLE'
            $downText | Should -Match 'The farm could not be reached\.'
            $downText | Should -Match 'No check was run\. See the SPSWeather Event Log \(ID 3001\)\.'
        }

        It 'has no health bar and no button' {
            $m = Get-Consolidated -Farms @((New-DownEntry -Name 'SERVICES'))
            $m.Body | Should -Not -Match 'height:8px'
            $m.Body | Should -Not -Match 'Open full dashboard'
        }

        It 'says how many farms were queried' {
            $downText | Should -Match 'farms queried: 2 of 3'
            $text | Should -Match 'farms queried: 3 of 3'
        }

        It 'is counted among the farms that need attention' {
            $downText | Should -Match '3 farms of 3 need your attention on contoso / PROD'
        }

        It 'turns the weather to at least cloudy even when the other farms are healthy' {
            $m = Get-Consolidated -Farms @($farms[1], (New-DownEntry -Name 'SERVICES2'))
            (Get-Text -Mail $m) | Should -Match 'Cloudy'
        }
    }

    Context 'header, introduction and weather' {
        It 'names the environment and counts the farms' {
            $text | Should -Match 'SPSWeather — contoso / PROD'
            $text | Should -Match '3 farms'
            (Get-Text -Mail (Get-Consolidated -Farms @($farms[1]))) | Should -Match '1 farm(?!s)'
        }

        It 'says how many farms need attention, with the right singular or plural' {
            $text | Should -Match '2 farms of 3 need your attention on contoso / PROD\. Full detail is in the dashboard of each farm\.'
            $one = Get-Text -Mail (Get-Consolidated -Farms @($farms[2], $farms[1]))
            $one | Should -Match '1 farm of 2 needs your attention on contoso / PROD'
        }

        It 'says all is clear when no farm needs attention' {
            (Get-Text -Mail (Get-Consolidated -Farms @($farms[1]))) | Should -Match 'No item needs attention on contoso / PROD\.'
        }

        It 'shows the weather of the whole environment: stormy, cloudy, fair, sunny' {
            $text | Should -Match 'Stormy'
            $few = New-FarmEntry -Name 'FEW' -Report (New-FarmReport -Farm 'FEW' -SqlFail 2)
            (Get-Text -Mail (Get-Consolidated -Farms @($few))) | Should -Match 'Cloudy'
            (Get-Text -Mail (Get-Consolidated -Farms @($farms[0]))) | Should -Match 'Fair'
            (Get-Text -Mail (Get-Consolidated -Farms @($farms[1]))) | Should -Match 'Sunny'
        }

        It 'shows the footer with the version, the account and the duration' {
            $text | Should -Match 'SPSWeather 3\.4\.0 · executed by DOM\\jc · run 00:11:42'
        }

        It 'stamps the generation time in Gregorian digits whatever the host calendar' {
            $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                foreach ($hostCulture in 'th-TH', 'ar-SA', 'fa-IR') {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($hostCulture)
                    $m = Get-Consolidated -Farms @($farms[1])
                    $year = (Get-Date).Year.ToString([System.Globalization.CultureInfo]::InvariantCulture)
                    $m.Body | Should -Match ('3 farms|1 farm') -Because "host culture $hostCulture"
                    $m.Body | Should -Match ('&middot; ' + $year + '-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}') -Because "host culture $hostCulture"
                }
            }
            finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous }
        }
    }

    Context 'untrusted text' {
        It 'HTML-encodes the farm name, the server and the dashboard URL' {
            $evil = New-FarmEntry -Name '<img src=x onerror=alert(1)>' -Server 'srv"><b>x</b>' -Url 'https://h/a?x=1&y="2"><script>' -Report (New-FarmReport -Farm 'E' -SqlFail 1)
            $m = Get-Consolidated -Farms @($evil)
            $m.Body | Should -Not -Match '<img src=x'
            $m.Body | Should -Not -Match '<script'
            $m.Body | Should -Not -Match 'srv"><b>'
            $m.Body | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
            $m.Body | Should -Match 'href="https://h/a\?x=1&amp;y=&quot;2&quot;&gt;&lt;script&gt;"'
        }

        It 'encodes the application and environment names' {
            $m = ConvertTo-SPSWeatherConsolidatedEmail -FarmResult @($farms[1]) -Application '<b>app</b>' -Environment 'P&D'
            $m.Body | Should -Not -Match '<b>app</b>'
            $m.Body | Should -Match '&lt;b&gt;app&lt;/b&gt; / P&amp;D'
        }

        It 'encodes the version, the account and the duration of the footer' {
            $m = ConvertTo-SPSWeatherConsolidatedEmail -FarmResult @($farms[1]) -Application 'a' -Environment 'e' -Version '1<i>.0' -ExecutedBy 'DOM\<u>jc</u>' -Duration '0<s>1</s>'
            $m.Body | Should -Not -Match '<i>\.0|<u>jc|<s>1'
            $m.Body | Should -Match '1&lt;i&gt;\.0'
            $m.Body | Should -Match 'DOM\\&lt;u&gt;jc&lt;/u&gt;'
            $m.Body | Should -Match '0&lt;s&gt;1&lt;/s&gt;'
        }
    }

    Context 'an environment with a single farm' {
        It 'reads naturally in English, in alert and healthy' {
            $alert = Get-Consolidated -Farms @($farms[2])
            $alert.Subject | Should -Be '[ALERT] contoso/PROD - 1 farm (1 ALERT) - SPSWeather'
            $alert.Priority | Should -Be 'High'
            $t = Get-Text -Mail $alert
            $t | Should -Match '1 farm · '
            $t | Should -Match '1 farm of 1 needs your attention on contoso / PROD'
            $t | Should -Match 'farms queried: 1 of 1'
            $t | Should -Match 'SQL Server 17 failures'
            $ok = Get-Consolidated -Farms @($farms[1])
            $ok.Subject | Should -Be '[OK] contoso/PROD - 1 farm (1 OK) - SPSWeather'
            (Get-Text -Mail $ok) | Should -Match 'No item needs attention on contoso / PROD'
        }

        It 'reads naturally in French, in alert and healthy' {
            $t = Get-Text -Mail (Get-Consolidated -Farms @($farms[2]) -Language 'fr-FR')
            $t | Should -Match '1 ferme · '
            $t | Should -Match '1 ferme sur 1 nécessite votre attention sur contoso / PROD'
            $t | Should -Match 'fermes interrogées.: 1 sur 1'
            (Get-Text -Mail (Get-Consolidated -Farms @($farms[1]) -Language 'fr-FR')) | Should -Match 'Aucun élément à examiner sur contoso / PROD'
        }

        It 'shows one card and one totals strip that agree with the card' {
            $m = Get-Consolidated -Farms @($farms[2])
            ([regex]::Matches($m.Body, 'border-left:5px solid')).Count | Should -Be 1
            $m.Body -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $Matches[1] | Should -Be '33'
            (Get-Text -Mail $m) | Should -Match '115 OK / 0 warn / 33 fail'
        }

        It 'works for a single unreachable farm' {
            $m = Get-Consolidated -Farms @((New-DownEntry -Name 'ONLY'))
            $m.Subject | Should -Be '[ALERT] contoso/PROD - 1 farm (1 UNREACHABLE) - SPSWeather'
            (Get-Text -Mail $m) | Should -Match 'farms queried: 0 of 1'
        }
    }

    Context 'parameters' {
        It 'refuses an empty list of farms' {
            { ConvertTo-SPSWeatherConsolidatedEmail -FarmResult @() } | Should -Throw
        }

        It 'refuses a negative cap' {
            { Get-Consolidated -Farms $farms -Max -1 } | Should -Throw
        }

        It 'accepts a farm entry without a server, a URL or a report' {
            $bare = [PSCustomObject]@{ Name = 'BARE' }
            { Get-Consolidated -Farms @($bare) } | Should -Not -Throw
            (Get-Text -Mail (Get-Consolidated -Farms @($bare))) | Should -Match 'BARE'
        }
    }
}

Describe 'Consolidated email in French' {
    BeforeAll {
        $base = 'https://dash.contoso.local/SPSWeather'
        $script:frFarms = @(
            (New-FarmEntry -Name 'SEARCH' -Report (New-FarmReport -Farm 'SEARCH' -SearchWarn 2 -Ok 61) -Url "$base/s.html")
            (New-FarmEntry -Name 'CONTENT' -Report (New-FarmReport -Farm 'CONTENT' -SqlFail 17 -TimerFail 12 -IisFail 4 -SearchWarn 1 -Ok 115) -Url "$base/c.html")
            (New-FarmEntry -Name 'SERVICES' -Report (New-FarmReport -Farm 'SERVICES' -Ok 142) -Url "$base/v.html")
        )
        $script:fr = Get-Consolidated -Farms $frFarms -Language 'fr-FR'
        $script:frText = Get-Text -Mail $fr
        $script:nb = [string][char]0xA0
        $script:frDown = Get-Text -Mail (Get-Consolidated -Farms @($frFarms[0], (New-DownEntry -Name 'DOWN1')) -Language 'fr-FR')
    }

    It 'declares the page as French' {
        $fr.Body | Should -Match '<html lang="fr"'
    }

    It 'translates the labels' {
        foreach ($label in 'Échecs', 'Avertissements', 'Contrôles OK', 'ALERTE', 'AVERTISSEMENT', 'SAINE', "Points d'attention", 'Orageux', 'Ouvrir le tableau de bord complet') {
            $frText | Should -Match ([regex]::Escape($label))
        }
        $frText | Should -Not -Match 'Failures|Warnings|Needs attention|HEALTHY|Open full dashboard'
    }

    It 'agrees the introduction and the footer in French' {
        $frText | Should -Match '2 fermes sur 3 nécessitent votre attention sur contoso / PROD\. Le détail complet est dans le tableau de bord de chaque ferme\.'
        $frText | Should -Match "fermes interrogées$nb`: 3 sur 3"
        $frText | Should -Match '3 fermes'
        $frDown | Should -Match "fermes interrogées$nb`: 1 sur 2"
        $frDown | Should -Match 'INJOIGNABLE'
        $frDown | Should -Match "La ferme n'a pas pu être interrogée\."
        (Get-Text -Mail (Get-Consolidated -Farms @($frFarms[1], $frFarms[2]) -Language 'fr-FR')) | Should -Match '1 ferme sur 2 nécessite votre attention'
    }

    It 'writes the percentage with a non-breaking space, as in French' {
        $frText | Should -Match "77$nb% sain"
        $frText | Should -Match "100$nb% sain"
    }

    It 'uses the French plural forms' {
        $frText | Should -Match 'SQL Server 17 échecs'
        $frText | Should -Match 'Recherche 2 avertissements'
        $frText | Should -Match '\+ 1 de plus \(1 avertissement\)'
    }

    It 'shows the English text for an unknown language instead of failing' {
        $m = Get-Consolidated -Farms $frFarms -Language 'zz-ZZ'
        (Get-Text -Mail $m) | Should -Match 'Failures'
        $m.Body | Should -Match '<html lang="en"'
    }

    It 'never lets a label that cannot be formatted stop the email' {
        # Even if a defective table reaches the renderer (the resolver normally rejects it first),
        # formatting falls back to the English text instead of throwing.
        $reference = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/en-US/SPSWeather.Common.Strings.psd1'
        $body = [scriptblock]::Create(@"
param(`$Language)
`$table = Import-PowerShellDataFile -Path '$reference'
if (`$Language -eq 'broken') {
    `$table['FarmHealth'] = '{0} {5} sain'
    `$table['IntroFarmsMany'] = '{0} {7} a examiner'
}
`$table
"@)
        Mock -ModuleName SPSWeather.Common -CommandName Get-SPSWeatherResource -MockWith $body
        { Get-Consolidated -Farms $frFarms -Language 'broken' } | Should -Not -Throw
        $t = Get-Text -Mail (Get-Consolidated -Farms $frFarms -Language 'broken')
        $t | Should -Match '77% healthy'
        $t | Should -Match 'need your attention on contoso / PROD'
    }
}
