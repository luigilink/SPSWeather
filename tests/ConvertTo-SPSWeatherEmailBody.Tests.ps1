# Behavioural tests for ConvertTo-SPSWeatherEmailBody (short, Outlook-safe alert email):
# structure, per-section detail mappings and the per-area item cap (-MaxItemsPerArea).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force

    function New-DbRow {
        param([int]$Index)
        [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Name = ('DB_{0:00}' -f $Index); State = 'ONLINE'; Recommendation = 'no full backup found'; IsInfo = $false }
    }
    function New-Report {
        param([int]$Failures, [int]$Warnings = 0)
        $report = [PSCustomObject]@{}
        # Warnings are listed first in the source so the cap must reorder to keep failures visible.
        if ($Warnings -gt 0) {
            $report | Add-Member -MemberType NoteProperty -Name SQLInstanceStatus -Value @(
                1..$Warnings | ForEach-Object { [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = "SQLW$_"; Recommendation = 'MAXDOP should be 1'; IsInfo = $true } })
        }
        $report | Add-Member -MemberType NoteProperty -Name SQLDatabaseStatus -Value @(1..$Failures | ForEach-Object { New-DbRow -Index $_ })
        $report
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Short alert email (ConvertTo-SPSWeatherEmailBody)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPAPIHttpStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }
        )
        $report | Add-Member -MemberType NoteProperty -Name SPHealthAnalyzer -Value @(
            [PSCustomObject]@{ farm = 'CONTENT'; title = 'STS not available'; severity = '2 - Warning'; category = 'Availability' }
        )
        $summary = [PSCustomObject]@{ Ok = 10; Alert = 2 }
        $html = ConvertTo-SPSWeatherEmailBody -InputObject $report -Summary $summary -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Version '3.1.0' -ExecutedBy 'DOM\jc' -Duration '00:04:31' -DashboardUrl 'https://pull/sp/zebes-PROD-CONTENT-dashboard.html'
    }

    It 'returns a single self-contained HTML document string' {
        $html | Should -BeOfType ([System.String])
        $html.StartsWith('<!DOCTYPE html>') | Should -BeTrue
        $html.TrimEnd().EndsWith('</html>') | Should -BeTrue
    }

    It 'keeps the Outlook MSO conditional comment' {
        $html | Should -Match '\[if mso\]'
    }

    It 'lists only the items needing attention, grouped by area' {
        $html | Should -Match 'Search'
        $html | Should -Match 'Health Analyzer'
        $html | Should -Match 'Search REST'
    }

    It 'omits healthy rows from the alert list' {
        $html | Should -Not -Match '>Root<'
    }

    It 'renders the CTA button pointing at the dashboard URL' {
        $html | Should -Match 'zebes-PROD-CONTENT-dashboard\.html'
        $html | Should -Match 'Open full dashboard'
    }

    It 'does not double-encode the middot separator' {
        $html | Should -Not -Match '&amp;middot;'
    }
}

Describe 'Alert email detail mappings (ConvertTo-SPSWeatherEmailBody)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SYSDiskUsageStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'SRV1'; DriveLetter = 'C'; Size = 100; FreeSpace = 8; Status = 'Less than 10 %'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'SRV2'; DriveLetter = ''; Size = ''; FreeSpace = ''; Status = 'Unreachable'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'SRV3'; DriveLetter = 'D'; Size = 0; FreeSpace = 0; Status = 'Less than 10 %'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'SRV4'; DriveLetter = 'E'; Size = 200; FreeSpace = 150; Status = 'OK'; IsInfo = $true }
        )
        $report | Add-Member -MemberType NoteProperty -Name SPUpgradeStatus -Value @(
            [PSCustomObject]@{ farm = 'CONTENT'; server = 'APP1'; SPBuildVersion = '16.0.18526.20424'; SPRegVersion = '16.0.18526.20424'; UpgradeStatus = 'UpgradeRequired'; IsInfo = $false }
        )
        $report | Add-Member -MemberType NoteProperty -Name SPFailedTimerJobs -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'WFE1'; JobDefinitionTitle = 'Config Refresh'; Status = 'Failed'; IsInfo = $false }
        )
        $report | Add-Member -MemberType NoteProperty -Name SQLInstanceStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL<1>'; Recommendation = 'max server memory > 90% & TempDB has 1 data file'; IsInfo = $true }
        )
        $report | Add-Member -MemberType NoteProperty -Name SQLDiskStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Volume = 'G:\'; TotalGB = 500; FreeGB = 25; FreePercent = 5.25; IsInfo = $false }
        )
        $html = ConvertTo-SPSWeatherEmailBody -InputObject $report -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD'
    }

    It 'computes the disk free percentage from Size and FreeSpace' {
        $html | Should -Match 'SRV1 / C'
        $html | Should -Match '&mdash; 8% free &#183; Less than 10 %'
    }

    It 'does not invent a percentage for an unreachable disk' {
        $html | Should -Match 'SRV2'
        $html | Should -Match 'Unreachable'
        $html | Should -Not -Match 'SRV2[^<]*</b>[^<]*<span[^>]*>&mdash; [^<]*% free'
    }

    It 'does not divide by a zero-sized disk' {
        $html | Should -Match 'SRV3 / D'
        $html | Should -Not -Match 'SRV3[^<]*</b>[^<]*<span[^>]*>&mdash; [^<]*% free'
    }

    It 'omits healthy disks from the alert list' {
        $html | Should -Not -Match 'SRV4'
    }

    It 'renders the upgrade server and status (lower-case producer field)' {
        $html | Should -Match 'APP1'
        $html | Should -Match 'UpgradeRequired'
    }

    It 'keeps the server in failed timer job labels' {
        $html | Should -Match 'WFE1 / Config Refresh'
    }

    It 'renders the SQL disk free percentage with a percent unit' {
        $html | Should -Match 'SQL1 / G:\\'
        $html | Should -Match '&mdash; 5\.25% free'
    }

    It 'formats percentages with the invariant culture whatever the host culture' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
            $frHtml = ConvertTo-SPSWeatherEmailBody -InputObject $report -Farm 'CONTENT'
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
        $frHtml | Should -Match '5\.25% free'
        $frHtml | Should -Not -Match '5,25% free'
    }

    It 'HTML-encodes labels and details' {
        $html | Should -Match 'SQL&lt;1&gt;'
        $html | Should -Match 'max server memory &gt; 90% &amp; TempDB has 1 data file'
        $html | Should -Not -Match 'SQL<1>'
    }
}

Describe 'ConvertTo-SPSWeatherEmailBody -MaxItemsPerArea' {
    Context 'default cap (10)' {
        BeforeAll {
            $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-Report -Failures 15) -DashboardUrl 'https://pull/d.html'
        }

        It 'lists only the first 10 items of the area' {
            $html | Should -Match '<b>DB_01</b>'
            $html | Should -Match '<b>DB_10</b>'
            $html | Should -Not -Match '<b>DB_11</b>'
        }

        It 'summarizes the hidden items in a final row' {
            $html | Should -Match '\+ 5 more \(5 failures\) &mdash; see the dashboard for the full list'
        }

        It 'keeps every counter exact (KPI, intro, area header)' {
            $html | Should -Match '>15</div><div[^>]*>Failures<'
            $html | Should -Match '<b>15 items</b> need your attention'
            $html | Should -Match 'SQL Server &nbsp;&middot;&nbsp; 15 items'
        }
    }

    It 'does not add a summary row when the area fits under the cap' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-Report -Failures 10)
        $html | Should -Match '<b>DB_10</b>'
        $html | Should -Not -Match ' more \('
    }

    It 'lists failures before warnings so the cap never hides a failure behind warnings' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-Report -Failures 12 -Warnings 3)
        # 15 items, cap 10: the 10 shown are failures; hidden = 2 failures + 3 warnings.
        $html | Should -Match '<b>DB_10</b>'
        $html | Should -Not -Match '<b>SQLW1</b>'
        $html | Should -Match '\+ 5 more \(2 failures, 3 warnings\)'
    }

    It 'uses the singular form for a single hidden item' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-Report -Failures 4) -MaxItemsPerArea 3
        $html | Should -Match '\+ 1 more \(1 failure\)'
    }

    It 'disables the cap with 0 (previous behavior)' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-Report -Failures 15) -MaxItemsPerArea 0
        $html | Should -Match '<b>DB_15</b>'
        $html | Should -Not -Match ' more \('
    }

    It 'applies the cap to each area independently' {
        $report = New-Report -Failures 12
        $report | Add-Member -MemberType NoteProperty -Name SPFailedTimerJobs -Value @(
            1..12 | ForEach-Object { [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'WFE1'; JobDefinitionTitle = ('Job {0:00}' -f $_); Status = 'Failed'; IsInfo = $false } })
        $html = ConvertTo-SPSWeatherEmailBody -InputObject $report
        ([regex]::Matches($html, '\+ 2 more \(2 failures\)')).Count | Should -Be 2
    }

    It 'rejects a negative cap' {
        { ConvertTo-SPSWeatherEmailBody -InputObject (New-Report -Failures 1) -MaxItemsPerArea -1 } | Should -Throw
    }
}

Describe 'EmailMaxItemsPerArea configuration' {
    It 'is read from the environment config and passed to the email renderer by the entry script' {
        $entry = Get-Content -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/SPSWeather.ps1') -Raw
        $entry | Should -Match '\$envCfg\.EmailMaxItemsPerArea'
        $entry | Should -Match '-MaxItemsPerArea \$emailMaxItemsPerArea'
    }

    It 'is documented in the example environment config with its default' {
        $examplePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Config/CONTOSO-PROD.example.psd1'
        (Import-PowerShellDataFile -Path $examplePath).EmailMaxItemsPerArea | Should -Be 10
    }
}

Describe 'Alert email language (ConvertTo-SPSWeatherEmailBody -Language)' {
    BeforeAll {
        function New-LanguageReport {
            param([int]$Failures = 13)
            $report = [PSCustomObject]@{}
            $report | Add-Member -MemberType NoteProperty -Name SQLInstanceStatus -Value @(
                [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Recommendation = 'MAXDOP should be 1'; IsInfo = $true })
            $report | Add-Member -MemberType NoteProperty -Name SQLDatabaseStatus -Value @(
                1..$Failures | ForEach-Object { [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Name = ('DB_{0:00}' -f $_); State = 'ONLINE'; Recommendation = 'no full backup found'; IsInfo = $false } })
            $report | Add-Member -MemberType NoteProperty -Name SQLDiskStatus -Value @(
                [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Volume = 'G:\'; TotalGB = 500; FreeGB = 25; FreePercent = 5.25; IsInfo = $false })
            $report | Add-Member -MemberType NoteProperty -Name SPFailedTimerJobs -Value @(
                [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'WFE1'; JobDefinitionTitle = 'Config Refresh'; Status = 'Failed'; IsInfo = $false })
            $report
        }
        function Get-Mail {
            param($Report, [string]$Language, [int]$Cap = 10)
            $arguments = @{ InputObject = $Report; Farm = 'CONTENT'; Application = 'zebes'; Environment = 'PROD'; Version = '3.4.0'; ExecutedBy = 'DOM\jc'; Duration = '00:04:31'; DashboardUrl = 'https://pull/sp/d.html'; MaxItemsPerArea = $Cap }
            if ($PSBoundParameters.ContainsKey('Language')) { $arguments['Language'] = $Language }
            $html = ConvertTo-SPSWeatherEmailBody @arguments
            [PSCustomObject]@{ Raw = $html; Text = [System.Net.WebUtility]::HtmlDecode($html) }
        }

        $script:report = New-LanguageReport
        $script:default = Get-Mail -Report $report
        $script:english = Get-Mail -Report $report -Language 'en-US'
        $script:french = Get-Mail -Report $report -Language 'fr-FR'
        $script:unknown = Get-Mail -Report $report -Language 'de-DE'
        $script:uncapped = @{ French = (Get-Mail -Report $report -Language 'fr-FR' -Cap 0); English = (Get-Mail -Report $report -Language 'en-US' -Cap 0) }
        $script:clear = Get-Mail -Report ([PSCustomObject]@{ SPAPIHttpStatus = @([PSCustomObject]@{ Farm = 'C'; Title = 'Root'; Url = 'u'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }) }) -Language 'fr-FR'
    }

    It 'exposes -Language with en-US as the default' {
        $cmd = Get-Command -Name ConvertTo-SPSWeatherEmailBody
        $cmd.Parameters.Keys | Should -Contain 'Language'
        $cmd.Parameters['Language'].ParameterType | Should -Be ([System.String])
    }

    It 'keeps English when no language is given, and en-US gives the same email (timestamps aside)' {
        $normalize = { param($t) $t -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}', '<TS>' }
        (& $normalize $default.Raw) | Should -BeExactly (& $normalize $english.Raw)
        $default.Text | Should -Match '<html lang="en"'
        $default.Text | Should -Match 'need your attention on'
        $uncapped.English.Text | Should -Match '5\.25% free'
    }

    It 'falls back to English for a language that is not available' {
        $unknown.Text | Should -Match '<html lang="en"'
        $unknown.Text | Should -Match 'need your attention on'
    }

    Context 'fr-FR' {
        It 'declares the language and translates the header, the KPI strip and the call to action' {
            $french.Text | Should -Match '<html lang="fr"'
            foreach ($expected in 'Ferme CONTENT', 'Météo', 'Échecs', 'Avertissements', 'Contrôles OK', 'Ouvrir le tableau de bord complet') {
                $french.Text | Should -Match ([regex]::Escape($expected))
            }
        }

        It 'translates the intro sentence around the bold values' {
            $french.Text | Should -Match '<b>\d+ éléments</b> à examiner sur <b>zebes / PROD</b>\. Le détail complet est dans le tableau de bord\.'
        }

        It 'translates the area names and uses the plural form of the count' {
            $french.Text | Should -Match 'Travaux du minuteur\s+·\s+1 élément<'
            $french.Text | Should -Match 'SQL Server\s+·\s+15 éléments<'
        }

        It 'translates the hidden-items row with singular and plural forms' {
            # 15 SQL items, cap 10, failures first: hidden = 4 failures + 1 warning.
            $french.Text | Should -Match '\+ 5 de plus \(4 échecs, 1 avertissement\) — voir le tableau de bord pour la liste complète'
            $oneHidden = Get-Mail -Report (New-LanguageReport -Failures 10) -Language 'fr-FR' -Cap 10
            $oneHidden.Text | Should -Match '\+ 2 de plus \(1 échec, 1 avertissement\)'
        }

        It 'translates the footer' {
            $french.Text | Should -Match 'exécuté par DOM\\jc'
            $french.Text | Should -Match 'durée 00:04:31'
            $french.Text | Should -Match '\d+ OK / \d+ avert\. / \d+ échec\(s\)\.'
        }

        It 'translates the all-clear message and the weather' {
            $clear.Text | Should -Match 'Tout est en ordre\.'
            $clear.Text | Should -Match 'Aucun élément à examiner sur cette ferme\.'
            $clear.Text | Should -Match 'Aucun élément à examiner sur <b>zebes / PROD</b>\.'
            $clear.Text | Should -Match 'Ensoleillé'
        }

        It 'no longer shows the English chrome' {
            foreach ($english in 'need your attention', 'Open full dashboard', 'executed by', 'Checks OK', 'see the dashboard', '>Weather<') {
                $french.Text | Should -Not -Match ([regex]::Escape($english))
            }
        }

        It 'leaves the collected values untouched' {
            $french.Text | Should -Match 'no full backup found'
            $french.Text | Should -Match '<b>WFE1 / Config Refresh</b>'
            $french.Text | Should -Match '— Failed<'
        }

        It 'keeps the counters of the English email' {
            foreach ($pattern in '>(\d+)</div><div[^>]*>Échecs<', '>(\d+)</div><div[^>]*>Avertissements<') {
                $french.Text | Should -Match $pattern
            }
            $english.Text -match '>(\d+)</div><div[^>]*>Failures<' | Should -BeTrue
            $failuresEn = $Matches[1]
            $french.Text -match '>(\d+)</div><div[^>]*>Échecs<' | Should -BeTrue
            $Matches[1] | Should -Be $failuresEn
        }
    }

    Context 'numbers follow the chosen language, not the culture of the machine' {
        BeforeAll {
            $script:previousCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        }
        AfterAll {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:previousCulture
        }

        It 'writes 5,25 % d''espace libre in French and 5.25% free in English whatever the host culture' {
            foreach ($hostCulture in 'en-US', 'fr-FR', 'de-DE') {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($hostCulture)
                (Get-Mail -Report $report -Language 'fr-FR' -Cap 0).Text | Should -Match "5,25$([char]0xA0)% d'espace libre" -Because "host culture $hostCulture"
                (Get-Mail -Report $report -Language 'en-US' -Cap 0).Text | Should -Match '5\.25% free' -Because "host culture $hostCulture"
            }
        }
    }
}

