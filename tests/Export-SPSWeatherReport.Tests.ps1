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
