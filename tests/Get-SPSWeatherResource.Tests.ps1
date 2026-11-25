# Behavioural tests for the Get-SPSWeatherResource private loader: the English reference is always
# loaded first and the resolved culture is laid over it.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:sourceModule = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
    Import-Module -Name (Join-Path -Path $script:sourceModule -ChildPath 'SPSWeather.Common.psd1') -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherResource' {
    It 'returns the English strings by default and for an unknown language' {
        # 'qaa-QM' is in the ISO 639 range reserved for private use (qaa-qtz): it can never be a shipped language.
        foreach ($language in $null, '', 'en-US', 'qaa-QM') {
            $text = InModuleScope SPSWeather.Common -Parameters @{ Language = $language } { param($Language) Get-SPSWeatherResource -Language $Language }
            $text.Culture | Should -Be 'en-US'
            $text.AllClearTitle | Should -Be 'All clear.'
        }
    }

    It 'returns the French strings for fr-FR and for a French region' {
        foreach ($language in 'fr-FR', 'fr', 'fr-BE') {
            $text = InModuleScope SPSWeather.Common -Parameters @{ Language = $language } { param($Language) Get-SPSWeatherResource -Language $Language }
            $text.Culture | Should -Be 'fr-FR'
            $text.AllClearTitle | Should -Be 'Tout est en ordre.'
        }
    }

    It 'returns a table with every English key whatever the language' {
        $english = InModuleScope SPSWeather.Common { Get-SPSWeatherResource -Language 'en-US' }
        $french = InModuleScope SPSWeather.Common { Get-SPSWeatherResource -Language 'fr-FR' }
        $french.Keys.Count | Should -Be $english.Keys.Count
        $english.Keys.Count | Should -BeGreaterThan 50
    }

    Context 'a translation that is incomplete' {
        BeforeAll {
            # Work on a copy of the module so the shipped files are never touched.
            $script:copy = Join-Path -Path $TestDrive -ChildPath 'SPSWeather.Common'
            Copy-Item -Path $script:sourceModule -Destination $script:copy -Recurse
            $frenchFile = Join-Path -Path $script:copy -ChildPath 'fr-FR/SPSWeather.Common.Strings.psd1'
            $kept = @(Get-Content -Path $frenchFile -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*(AllClearTitle|KpiChecksOk)\s*=' })
            # Keep the BOM: Windows PowerShell 5.1 reads a data file without it as ANSI.
            [System.IO.File]::WriteAllLines($frenchFile, $kept, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))
            Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path -Path $script:copy -ChildPath 'SPSWeather.Common.psd1') -Force
        }
        AfterAll {
            Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path -Path $script:sourceModule -ChildPath 'SPSWeather.Common.psd1') -Force
        }

        It 'shows the English text for a missing key and keeps the translated others' {
            $text = InModuleScope SPSWeather.Common { Get-SPSWeatherResource -Language 'fr-FR' }
            $text.Culture | Should -Be 'fr-FR'
            $text.AllClearTitle | Should -Be 'All clear.'
            $text.KpiChecksOk | Should -Be 'Checks OK'
            $text.KpiFailures | Should -Be 'Échecs'
        }
    }

    Context 'a module without the English reference file' {
        BeforeAll {
            $script:broken = Join-Path -Path $TestDrive -ChildPath 'broken/SPSWeather.Common'
            Copy-Item -Path $script:sourceModule -Destination $script:broken -Recurse
            Remove-Item -Path (Join-Path -Path $script:broken -ChildPath 'en-US') -Recurse -Force
            Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path -Path $script:broken -ChildPath 'SPSWeather.Common.psd1') -Force
        }
        AfterAll {
            Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path -Path $script:sourceModule -ChildPath 'SPSWeather.Common.psd1') -Force
        }

        It 'fails with a message naming the missing reference file' {
            { InModuleScope SPSWeather.Common { Get-SPSWeatherResource -Language 'fr-FR' } } | Should -Throw "*reference resource file*en-US*"
        }
    }
}

Describe 'Get-SPSWeatherResource with a value that is not text' {
    BeforeAll {
        $script:sourceModule = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common'
        $script:copy = Join-Path -Path $TestDrive -ChildPath 'SPSWeather.Common'
        Copy-Item -Path $script:sourceModule -Destination $script:copy -Recurse
        $frenchFile = Join-Path -Path $script:copy -ChildPath 'fr-FR/SPSWeather.Common.Strings.psd1'
        $content = [System.IO.File]::ReadAllText($frenchFile)
        $edited = $content -replace "(AllClearTitle\s*=\s*)'[^']*'", '${1}42'
        [System.IO.File]::WriteAllText($frenchFile, $edited, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))
        Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $script:copy -ChildPath 'SPSWeather.Common.psd1') -Force
    }
    AfterAll {
        Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path -Path $script:sourceModule -ChildPath 'SPSWeather.Common.psd1') -Force
    }

    It 'never lets the number replace the English text, even if the resolver had accepted the file' {
        $text = InModuleScope SPSWeather.Common {
            Mock -CommandName Resolve-SPSWeatherLanguage -MockWith { [PSCustomObject]@{ Culture = 'fr-FR' } }
            Get-SPSWeatherResource -Language 'fr-FR'
        }
        $text.AllClearTitle | Should -Be 'All clear.'
        $text.KpiFailures | Should -Be 'Échecs'
    }

    It 'shows the whole English page, with the reason reported, when the resolver sees the file' {
        $text = InModuleScope SPSWeather.Common { Get-SPSWeatherResource -Language 'fr-FR' }
        $text.Culture | Should -Be 'en-US'
        $text.AllClearTitle | Should -Be 'All clear.'
    }
}

