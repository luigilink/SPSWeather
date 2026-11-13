# Tests for the per-area item cap of ConvertTo-SPSWeatherEmailBody (-MaxItemsPerArea).

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
