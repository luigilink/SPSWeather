# Behavioural tests for Get-SPSWeatherWeatherKey (private): the weather rule of the dashboard.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherWeatherKey' {
    It 'gives <Expected> for <Warn> warning(s) and <Fail> failure(s)' -ForEach @(
        @{ Warn = 0; Fail = 0; Expected = 'sunny' }
        @{ Warn = 1; Fail = 0; Expected = 'fair' }
        @{ Warn = 40; Fail = 0; Expected = 'fair' }
        @{ Warn = 0; Fail = 1; Expected = 'cloudy' }
        @{ Warn = 3; Fail = 5; Expected = 'cloudy' }
        @{ Warn = 0; Fail = 6; Expected = 'stormy' }
        @{ Warn = 0; Fail = 33; Expected = 'stormy' }
    ) {
        InModuleScope SPSWeather.Common -Parameters @{ W = $Warn; F = $Fail } { param($W, $F) Get-SPSWeatherWeatherKey -Warn $W -Fail $F } | Should -Be $Expected
    }

    It 'moves the limit of a storm with -StormyAbove' {
        InModuleScope SPSWeather.Common { Get-SPSWeatherWeatherKey -Warn 0 -Fail 8 -StormyAbove 10 } | Should -Be 'cloudy'
        InModuleScope SPSWeather.Common { Get-SPSWeatherWeatherKey -Warn 0 -Fail 11 -StormyAbove 10 } | Should -Be 'stormy'
    }

    # The dashboard has its own copy of the rule: this keeps the page and the dashboard saying the same thing.
    It 'agrees with the weather shown by the dashboard for <Warn> warning(s) and <Fail> failure(s)' -ForEach @(
        @{ Warn = 0; Fail = 0 }
        @{ Warn = 2; Fail = 0 }
        @{ Warn = 0; Fail = 1 }
        @{ Warn = 0; Fail = 5 }
        @{ Warn = 1; Fail = 6 }
        @{ Warn = 0; Fail = 30 }
    ) {
        $rows = @()
        foreach ($i in 1..$Fail) { if ($Fail -gt 0) { $rows += [PSCustomObject]@{ Farm = 'F'; Server = "S$i"; Status = 'Failed'; IsInfo = $false } } }
        foreach ($i in 1..$Warn) { if ($Warn -gt 0) { $rows += [PSCustomObject]@{ Farm = 'F'; Server = "W$i"; Status = 'OK'; Recommendation = 'x'; IsInfo = $true } } }
        $rows += [PSCustomObject]@{ Farm = 'F'; Server = 'OK1'; Status = 'OK'; IsInfo = $true }
        $report = [PSCustomObject]@{ SPUpgradeStatus = $rows }
        $file = Join-Path -Path $TestDrive -ChildPath ('wx-' + [guid]::NewGuid().ToString('N') + '.html')
        [void](Export-SPSWeatherReport -InputObject $report -OutputFile $file -Farm 'F' -Application 'a' -Environment 'e' -Version 'v' -ExecutedBy 'x' -Duration 'd' -Language 'en-US')
        $html = Get-Content -Path $file -Raw
        $shown = [regex]::Match($html, '<div class="lbl">(\w+)<small>').Groups[1].Value
        $key = InModuleScope SPSWeather.Common -Parameters @{ W = $Warn; F = $Fail } { param($W, $F) Get-SPSWeatherWeatherKey -Warn $W -Fail $F }
        $label = @{ sunny = 'Sunny'; fair = 'Fair'; cloudy = 'Cloudy'; stormy = 'Stormy' }[$key]
        $shown | Should -Be $label
    }
}
