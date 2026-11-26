# Behavioural tests for Export-SPSWeatherReport (per-farm cards dashboard renderer).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Dashboard renderer (Export-SPSWeatherReport)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPAPIHttpStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }
        )
        $history = @(
            [PSCustomObject]@{ Date = '06-01'; Ok = 12; Warn = 0; Fail = 1 }
            [PSCustomObject]@{ Date = '06-02'; Ok = 11; Warn = 1; Fail = 2 }
        )
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsw-" + [guid]::NewGuid().ToString('N') + '.html')
        $result = Export-SPSWeatherReport -InputObject $report -OutputFile $tmp -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Version '3.1.0' -ExecutedBy 'DOM\jc' -Duration '00:04:31' -History $history
        $dash = Get-Content -Path $tmp -Raw
    }

    It 'returns the output file path and writes an HTML document' {
        $result | Should -Match 'spsw-.*\.html$'
        $dash.StartsWith('<!DOCTYPE html>') | Should -BeTrue
    }

    It 'renders the history chart bars (past runs + current)' {
        ([regex]::Matches($dash, 'class="bcol')).Count | Should -BeGreaterOrEqual 3
        $dash | Should -Match 'class="bcol now"'
    }

    It 'renders an area card for the failing section' {
        $dash | Should -Match 'Trust Farm'
    }

    It 'counts OK consistently with the report Summary (excludes pure-info rows)' {
        $r = [PSCustomObject]@{}
        $r | Add-Member -MemberType NoteProperty -Name SYSLastRebootStatus -Value @(
            [PSCustomObject]@{ Server = 'S1'; LastRebootTime = 'x' })               # pure info
        $r | Add-Member -MemberType NoteProperty -Name SYSDiskUsageStatus -Value @(
            [PSCustomObject]@{ Server = 'S1'; DriveLetter = 'C'; Status = 'OK'; IsInfo = $true }
            [PSCustomObject]@{ Server = 'S2'; DriveLetter = 'C'; Status = 'Low'; IsInfo = $false })
        $sections = [ordered]@{}
        foreach ($p in $r.PSObject.Properties) { $sections[$p.Name] = $p.Value }
        $summary = (ConvertTo-SPSWeatherReport -Section $sections).Summary

        $tmp2 = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsw-" + [guid]::NewGuid().ToString('N') + '.html')
        [void](Export-SPSWeatherReport -InputObject $r -OutputFile $tmp2 -Farm 'F' -Application 'a' -Environment 'e' -Version 'v' -ExecutedBy 'x' -Duration 'd' -History @())
        $html2 = Get-Content -Path $tmp2 -Raw

        # The donut legend OK must equal the report Summary Ok (1), not inflate with the info row.
        [regex]::Match($html2, 'dot ok"></i>OK (\d+)').Groups[1].Value | Should -Be ([string]$summary.Ok)
        $summary.Ok | Should -Be 1
    }

    Context 'View detail links' {
        BeforeAll {
            $script:cardLinks = @([regex]::Matches($dash, '<div class="foot"><a href="#(d-[A-Za-z0-9_-]+)">') | ForEach-Object { $_.Groups[1].Value })
            $script:sectionIds = @([regex]::Matches($dash, '<details class="sec" id="(d-[A-Za-z0-9_-]+)"') | ForEach-Object { $_.Groups[1].Value })
            $script:pageScript = [regex]::Match($dash, '(?s)<script>(.*?)</script>').Groups[1].Value
        }

        It 'gives every area card a link to a section that exists on the page' {
            $cardLinks.Count | Should -BeGreaterThan 0
            foreach ($id in $cardLinks) { $sectionIds | Should -Contain $id }
        }

        It 'opens the targeted <details> when a card link is clicked (a fragment never opens the target itself)' {
            $pageScript | Should -Match "closest\('a\[href\^=`"#d-`"\]'\)"
            $pageScript | Should -Match 'el\.tagName === ''DETAILS'''
            $pageScript | Should -Match 'el\.open = true'
        }

        It 'also opens the section when the page is loaded or navigated with a #d-... fragment' {
            $pageScript | Should -Match "addEventListener\('hashchange', fromLocation\)"
            $pageScript | Should -Match '(?m)^\s*fromLocation\(\);'
            $pageScript | Should -Match 'scrollIntoView'
        }

        It 'does not break on a malformed fragment' {
            $pageScript | Should -Match '(?s)try \{ id = decodeURIComponent.*?catch \(e\) \{ return null; \}'
        }

        It 'carries no unexpanded PowerShell variable in the script' {
            $pageScript | Should -Not -Match '\$\('
            $pageScript.Length | Should -BeGreaterThan 100
        }

        It 'keeps the Expand all and Collapse all buttons' {
            $dash | Should -Match "details\.sec'\)\.forEach\(function\(d\)\{d\.open=true\}\)"
            $dash | Should -Match "details\.sec'\)\.forEach\(function\(d\)\{d\.open=false\}\)"
        }
    }

    It 'does not draw a fully red history bar for an info-only run' {
        $info = [PSCustomObject]@{}
        $info | Add-Member -MemberType NoteProperty -Name SYSLastRebootStatus -Value @(
            [PSCustomObject]@{ Server = 'S1'; LastRebootTime = 'x' })
        $tmp3 = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsw-" + [guid]::NewGuid().ToString('N') + '.html')
        [void](Export-SPSWeatherReport -InputObject $info -OutputFile $tmp3 -Farm 'F' -Application 'a' -Environment 'e' -Version 'v' -ExecutedBy 'x' -Duration 'd' -History @())
        $html3 = Get-Content -Path $tmp3 -Raw
        $html3 | Should -Match 'class="bcol now"'
        $html3 | Should -Not -Match '<i class="f" style="height:100%">'
    }
}

Describe 'Dashboard language (Export-SPSWeatherReport -Language)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPAPIHttpStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }
        )
        $report | Add-Member -MemberType NoteProperty -Name SQLDatabaseStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; SqlServer = 'SQL1'; Name = 'DB_01'; State = 'ONLINE'; Recommendation = 'no full backup found'; IsInfo = $false }
        )
        $report | Add-Member -MemberType NoteProperty -Name SYSLastRebootStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = 'APP1'; OSName = 'Windows Server 2022'; LastRebootTime = '2026-11-01' }
        )
        $history = @([PSCustomObject]@{ Date = '06-01'; Ok = 12; Warn = 0; Fail = 1 })

        function Get-Dashboard {
            param([string]$Language)
            $file = Join-Path -Path $TestDrive -ChildPath ('dash-' + [guid]::NewGuid().ToString('N') + '.html')
            $arguments = @{ InputObject = $report; OutputFile = $file; Farm = 'CONTENT'; Application = 'zebes'; Environment = 'PROD'; Version = '3.4.0'; ExecutedBy = 'DOM\jc'; Duration = '00:04:31'; History = $history }
            if ($PSBoundParameters.ContainsKey('Language')) { $arguments['Language'] = $Language }
            [void](Export-SPSWeatherReport @arguments)
            # The renderer HTML-encodes accented characters; compare the decoded text.
            $html = Get-Content -Path $file -Raw -Encoding UTF8
            [PSCustomObject]@{ Raw = $html; Text = [System.Net.WebUtility]::HtmlDecode($html) }
        }

        $script:default = Get-Dashboard
        $script:english = Get-Dashboard -Language 'en-US'
        $script:french = Get-Dashboard -Language 'fr-FR'
        # 'qaa-QM' is in the ISO 639 range reserved for private use (qaa-qtz): it can never be a shipped language.
        $script:unknown = Get-Dashboard -Language 'qaa-QM'
        $script:frenchRegion = Get-Dashboard -Language 'fr-BE'
    }

    It 'exposes -Language with en-US as the default' {
        $cmd = Get-Command -Name Export-SPSWeatherReport
        $cmd.Parameters.Keys | Should -Contain 'Language'
        $cmd.Parameters['Language'].ParameterType | Should -Be ([System.String])
    }

    It 'keeps English when no language is given, and en-US gives the same page (timestamps aside)' {
        $normalize = { param($t) ($t -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}', '<TS>') -replace '\d{2}-\d{2}(?= \(now\))', '<MD>' -replace '<b>\d{2}-\d{2}</b>', '<b><MD></b>' }
        (& $normalize $default.Raw) | Should -BeExactly (& $normalize $english.Raw)
        $default.Text | Should -Match '<html lang="en">'
        $default.Text | Should -Match 'Overall health'
        $default.Text | Should -Match 'Health by area'
    }

    It 'falls back to English for a language that is not available' {
        $unknown.Text | Should -Match '<html lang="en">'
        $unknown.Text | Should -Match 'Overall health'
    }

    Context 'fr-FR' {
        It 'declares the page language' {
            $french.Text | Should -Match '<html lang="fr">'
        }

        It 'translates the header, the donut, the history and the section titles' {
            foreach ($expected in 'Tableau de bord SPSWeather', 'Santé globale', 'Historique', 'Santé par composant', 'Détail', 'Tout développer', 'Tout réduire', 'Voir le détail', 'Exécuté par', 'Généré le') {
                $french.Text | Should -Match ([regex]::Escape($expected))
            }
        }

        It 'translates the area cards and the section labels' {
            foreach ($expected in 'Ferme approuvée \(REST\)', '<h4>Système</h4>', '<h4>SQL Server</h4>', 'SQL - Bases de données', 'Système - Dernier redémarrage') {
                $french.Text | Should -Match $expected
            }
        }

        It 'translates the counters and the pills with their numbers' {
            $french.Text | Should -Match '\d+ élément\(s\) à examiner'
            $french.Text | Should -Match '\d+ en échec'
            $french.Text | Should -Match '\d+ alerte\(s\)'
            $french.Text | Should -Match 'dernières exécutions'
        }

        It 'no longer shows the English chrome' {
            foreach ($english in 'Overall health', 'Health by area', 'Expand all', 'Collapse all', 'View detail', 'Executed by', 'Run history', 'hover a bar') {
                $french.Text | Should -Not -Match ([regex]::Escape($english))
            }
        }

        It 'leaves the collected values and the column headers untouched' {
            # Values and headers are data: translating them would break the severity model and the history.
            $french.Text | Should -Match '<td>Failed</td>'
            $french.Text | Should -Match 'no full backup found'
            $french.Text | Should -Match '<th>Server</th>'
            $french.Text | Should -Match '<th>HTTPCode</th>'
        }

        It 'keeps the numbers and the verdict of the English page' {
            $english.Text | Should -Match '<div class="big">\d+%</div>'
            $french.Text | Should -Match '<div class="big">\d+\u00A0%</div>'
            foreach ($pattern in 'class="bcol now"') {
                $english.Text | Should -Match $pattern
                $french.Text | Should -Match $pattern
            }
            ([regex]::Matches($french.Text, '<div class="card">')).Count | Should -Be ([regex]::Matches($english.Text, '<div class="card">')).Count
            ([regex]::Matches($french.Text, '<details class="sec"')).Count | Should -Be ([regex]::Matches($english.Text, '<details class="sec"')).Count
        }

        It 'is also reached through a French region' {
            $frenchRegion.Text | Should -Match '<html lang="fr">'
            $frenchRegion.Text | Should -Match 'Santé globale'
        }
    }

    Context 'a translation that would break the formatting (defence in depth)' {
        It 'never lets a label stop the dashboard or the email' {
            # Even if a defective table reaches a renderer (the resolver normally rejects it first),
            # formatting falls back to the English text instead of throwing.
            $report = [PSCustomObject]@{
                SPAPIHttpStatus = @([PSCustomObject]@{ Farm = 'C'; Title = 'Root'; Url = 'u'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false })
            }
            $file = Join-Path -Path $TestDrive -ChildPath 'broken-dash.html'
            $reference = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/en-US/SPSWeather.Common.Strings.psd1'
            $body = [scriptblock]::Create(@"
param(`$Language)
`$table = Import-PowerShellDataFile -Path '$reference'
if (`$Language -eq 'broken') {
    `$table['PillFailed'] = '{0} {5} en echec'
    `$table['IntroAttention'] = '{0} {7} a examiner'
}
`$table
"@)
            Mock -ModuleName SPSWeather.Common -CommandName Get-SPSWeatherResource -MockWith $body
            { Export-SPSWeatherReport -InputObject $report -OutputFile $file -Farm 'C' -Language 'broken' } | Should -Not -Throw
            (Get-Content -Path $file -Raw) | Should -Match '1 failed'
            { ConvertTo-SPSWeatherEmailBody -InputObject $report -Farm 'C' -Language 'broken' } | Should -Not -Throw
            (ConvertTo-SPSWeatherEmailBody -InputObject $report -Farm 'C' -Language 'broken') | Should -Match 'need your attention on'
        }
    }

    Context 'history title and dates' {
        BeforeAll {
            function Get-HistoryDashboard {
                param([string]$Language, $History)
                $file = Join-Path -Path $TestDrive -ChildPath ('hist-' + [guid]::NewGuid().ToString('N') + '.html')
                $report = [PSCustomObject]@{ SPAPIHttpStatus = @([PSCustomObject]@{ Farm = 'C'; Title = 'Root'; Url = 'u'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }) }
                [void](Export-SPSWeatherReport -InputObject $report -OutputFile $file -Farm 'C' -Application 'a' -Environment 'e' -Version 'v' -ExecutedBy 'x' -Duration 'd' -History $History -Language $Language)
                [System.Net.WebUtility]::HtmlDecode((Get-Content -Path $file -Raw -Encoding UTF8))
            }
            $script:march4 = [datetime]'2026-03-04T10:00:00'
            $script:past = @(
                [PSCustomObject]@{ Date = '03-04'; When = $script:march4; Ok = 5; Warn = 1; Fail = 0 }
                [PSCustomObject]@{ Date = '03-05'; When = $script:march4.AddDays(1); Ok = 5; Warn = 0; Fail = 1 }
            )
        }

        It 'uses the singular title for the first run and the plural afterwards, in both languages' {
            (Get-HistoryDashboard -Language 'en-US' -History @()) | Should -Match 'Run history — last run<'
            (Get-HistoryDashboard -Language 'en-US' -History $past) | Should -Match 'Run history — last 3 runs<'
            (Get-HistoryDashboard -Language 'fr-FR' -History @()) | Should -Match 'Historique — dernière exécution<'
            (Get-HistoryDashboard -Language 'fr-FR' -History $past) | Should -Match 'Historique — 3 dernières exécutions<'
        }

        It 'writes the date of a past run month first in English and day first in French' {
            $en = Get-HistoryDashboard -Language 'en-US' -History $past
            $fr = Get-HistoryDashboard -Language 'fr-FR' -History $past
            $en | Should -Match 'title="03-04: 5 OK / 1 warn / 0 fail"'
            $fr | Should -Match 'title="04/03 : 5 OK / 1 avert\. / 0 échec\(s\)"'
            $fr | Should -Not -Match 'title="03-04'
        }

        It 'still accepts a past run that only has the Date text (callers and old objects)' {
            $legacy = @([PSCustomObject]@{ Date = '06-01'; Ok = 12; Warn = 0; Fail = 1 })
            (Get-HistoryDashboard -Language 'fr-FR' -History $legacy) | Should -Match 'title="06-01 : 12 OK'
        }

        It 'stamps the run date and the generation time in Gregorian digits whatever the host calendar' {
            $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                foreach ($hostCulture in 'th-TH', 'ar-SA', 'fa-IR') {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($hostCulture)
                    $html = Get-HistoryDashboard -Language 'en-US' -History @()
                    $year = (Get-Date).Year.ToString([System.Globalization.CultureInfo]::InvariantCulture)
                    $html | Should -Match ('<b>' + $year + '-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}</b>') -Because "host culture $hostCulture"
                    $html | Should -Match 'title="[0-9]{2}-[0-9]{2} ' -Because "host culture $hostCulture"
                }
            }
            finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous }
        }

        It 'writes the percentage with a non-breaking space in French (never a lone % on a line)' {
            (Get-HistoryDashboard -Language 'fr-FR' -History @()) | Should -Match '<div class="big">\d+\u00A0%</div>'
        }
    }
}
