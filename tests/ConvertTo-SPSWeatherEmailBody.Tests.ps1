# Behavioural tests for ConvertTo-SPSWeatherEmailBody (short, Outlook-safe alert email).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
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
