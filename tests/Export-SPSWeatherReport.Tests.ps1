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
}
