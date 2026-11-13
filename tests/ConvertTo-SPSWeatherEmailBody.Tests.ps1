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
