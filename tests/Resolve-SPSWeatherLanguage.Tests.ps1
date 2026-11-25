# Behavioural tests for Resolve-SPSWeatherLanguage: how the Language configuration value maps to
# one of the cultures that ship display strings.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-SPSWeatherLanguage' {
    It "resolves '<Language>' to <Expected> without any message" -ForEach @(
        @{ Language = $null; Expected = 'en-US' }
        @{ Language = ''; Expected = 'en-US' }
        @{ Language = '   '; Expected = 'en-US' }
        @{ Language = 'en-US'; Expected = 'en-US' }
        @{ Language = 'EN-us'; Expected = 'en-US' }
        @{ Language = 'fr-FR'; Expected = 'fr-FR' }
        @{ Language = 'FR-fr'; Expected = 'fr-FR' }
        @{ Language = ' fr-FR '; Expected = 'fr-FR' }
    ) {
        $r = Resolve-SPSWeatherLanguage -Language $Language
        $r.Culture | Should -Be $Expected
        $r.IsFallback | Should -BeFalse
        $r.Messages.Count | Should -Be 0
    }

    It "maps another culture of a shipped language, '<Language>', to <Expected>" -ForEach @(
        @{ Language = 'fr'; Expected = 'fr-FR' }
        @{ Language = 'fr-BE'; Expected = 'fr-FR' }
        @{ Language = 'fr_CA'; Expected = 'fr-FR' }
        @{ Language = 'en'; Expected = 'en-US' }
        @{ Language = 'en-GB'; Expected = 'en-US' }
    ) {
        $r = Resolve-SPSWeatherLanguage -Language $Language
        $r.Culture | Should -Be $Expected
        $r.IsFallback | Should -BeFalse
        $r.Messages.Count | Should -Be 0
    }

    It "falls back to en-US with a message naming the available cultures for '<Language>'" -ForEach @(
        @{ Language = 'de-DE' }
        @{ Language = 'zz' }
        @{ Language = 'not a culture' }
    ) {
        $r = Resolve-SPSWeatherLanguage -Language $Language
        $r.Culture | Should -Be 'en-US'
        $r.IsFallback | Should -BeTrue
        $r.Messages.Count | Should -Be 1
        $r.Messages[0] | Should -Match "Language '$([regex]::Escape($Language))' is not available"
        $r.Messages[0] | Should -Match 'en-US, fr-FR'
        $r.Messages[0] | Should -Match 'using en-US'
    }

    It 'reports the requested value and the available cultures' {
        $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
        $r.Requested | Should -Be 'fr-FR'
        $r.Available | Should -Contain 'en-US'
        $r.Available | Should -Contain 'fr-FR'
    }

    Context "'auto' follows the UI culture of the process" {
        BeforeAll {
            $script:previousUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
        }
        AfterAll {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $script:previousUiCulture
        }

        It "resolves 'auto' with the UI culture <Ui> to <Expected> and never warns" -ForEach @(
            @{ Ui = 'fr-FR'; Expected = 'fr-FR' }
            @{ Ui = 'fr-CA'; Expected = 'fr-FR' }
            @{ Ui = 'en-GB'; Expected = 'en-US' }
            @{ Ui = 'de-DE'; Expected = 'en-US' }
        ) {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo($Ui)
            $r = Resolve-SPSWeatherLanguage -Language 'auto'
            $r.Culture | Should -Be $Expected
            $r.Messages.Count | Should -Be 0
        }

        It "accepts 'AUTO' in any case" {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
            (Resolve-SPSWeatherLanguage -Language 'AUTO').Culture | Should -Be 'fr-FR'
        }
    }
}
