# Behavioural tests for Resolve-SPSWeatherLanguage: how the Language configuration value maps to
# one of the cultures that ship display strings.

# Discovery: a real UI culture whose language is not shipped, whatever languages are added later
# (the data of the -ForEach below is built before the tests run).
$moduleFolder = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common'
$shippedLanguages = @(Get-ChildItem -Path $moduleFolder -Directory |
        Where-Object -FilterScript { Test-Path -Path (Join-Path -Path $_.FullName -ChildPath 'SPSWeather.Common.Strings.psd1') } |
        ForEach-Object -Process { ($_.Name -split '-')[0] })
$unshippedUiCulture = @('ja-JP', 'ko-KR', 'sv-SE', 'pl-PL', 'ru-RU', 'tr-TR') |
    Where-Object -FilterScript { $shippedLanguages -notcontains ($_ -split '-')[0] } | Select-Object -First 1

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
        @{ Language = 'qaa-QM' }
        @{ Language = 'zz' }
        @{ Language = 'not a culture' }
    ) {
        $r = Resolve-SPSWeatherLanguage -Language $Language
        $r.Culture | Should -Be 'en-US'
        $r.IsFallback | Should -BeTrue
        $r.Messages.Count | Should -Be 1
        $r.Messages[0] | Should -Match "Language '$([regex]::Escape($Language))' is not available"
        # The list comes from the folders on disk, so it stays right when a language is added.
        $folders = @(Get-ChildItem -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common') -Directory |
                Where-Object -FilterScript { Test-Path -Path (Join-Path -Path $_.FullName -ChildPath 'SPSWeather.Common.Strings.psd1') } |
                Select-Object -ExpandProperty Name | Sort-Object)
        $r.Messages[0] | Should -Match ([regex]::Escape("(available: $($folders -join ', '))"))
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
            @{ Ui = $unshippedUiCulture; Expected = 'en-US' }
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

    Context 'a language that is added later (a new folder with a resource file, no change in the code)' {
        BeforeAll {
            $script:source = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common'
            $shipped = @(Get-ChildItem -Path $script:source -Directory | ForEach-Object -Process { ($_.Name -split '-')[0] })
            # The first real culture whose language is not shipped yet.
            $script:added = @('de-DE', 'es-ES', 'it-IT', 'pt-BR', 'nl-NL', 'ja-JP', 'ko-KR', 'sv-SE') |
                Where-Object -FilterScript { $shipped -notcontains ($_ -split '-')[0] } | Select-Object -First 1
            $script:addedLanguage = ($script:added -split '-')[0]

            $copy = Join-Path -Path $TestDrive -ChildPath 'added/SPSWeather.Common'
            Copy-Item -Path $script:source -Destination $copy -Recurse
            $folder = Join-Path -Path $copy -ChildPath $script:added
            New-Item -Path $folder -ItemType Directory | Out-Null
            # The new file is the French one relabelled: the point is that a folder is enough.
            $text = [System.IO.File]::ReadAllText((Join-Path -Path $copy -ChildPath 'fr-FR/SPSWeather.Common.Strings.psd1'))
            $text = $text -replace "(Culture\s*=\s*)'fr-FR'", "`$1'$($script:added)'" -replace "(HtmlLang\s*=\s*)'fr'", "`$1'$($script:addedLanguage)'"
            # Keep the BOM: Windows PowerShell 5.1 reads a data file without it as ANSI.
            [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'SPSWeather.Common.Strings.psd1'), $text, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))

            $script:previousUi = [System.Threading.Thread]::CurrentThread.CurrentUICulture
            Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path -Path $copy -ChildPath 'SPSWeather.Common.psd1') -Force
        }
        AfterAll {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $script:previousUi
            Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path -Path $script:source -ChildPath 'SPSWeather.Common.psd1') -Force
        }

        It 'is available as soon as its folder exists, by name, by language and by region' {
            foreach ($value in $script:added, $script:addedLanguage, "$($script:addedLanguage)-XX") {
                $r = Resolve-SPSWeatherLanguage -Language $value
                $r.Culture | Should -Be $script:added -Because "Language = '$value'"
                $r.Messages.Count | Should -Be 0
                $r.IsFallback | Should -BeFalse
            }
        }

        It "follows the UI culture of the process with 'auto'" {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo($script:added)
            (Resolve-SPSWeatherLanguage -Language 'auto').Culture | Should -Be $script:added
        }

        It 'is listed with the other languages in the message for an unknown one' {
            $r = Resolve-SPSWeatherLanguage -Language 'qaa-QM'
            $r.Culture | Should -Be 'en-US'
            $r.Available | Should -Contain $script:added
            $r.Available | Should -Contain 'fr-FR'
            $r.Messages[0] | Should -Match ([regex]::Escape($script:added))
        }

        It 'leaves the other languages as they were' {
            (Resolve-SPSWeatherLanguage -Language 'fr-FR').Culture | Should -Be 'fr-FR'
            (Resolve-SPSWeatherLanguage -Language 'en-GB').Culture | Should -Be 'en-US'
        }

        It 'is used by the dashboard and the email without any other change' {
            $report = [PSCustomObject]@{ SPAPIHttpStatus = @([PSCustomObject]@{ Farm = 'C'; Title = 'Root'; Url = 'u'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }) }
            $file = Join-Path -Path $TestDrive -ChildPath 'added-dashboard.html'
            [void](Export-SPSWeatherReport -InputObject $report -OutputFile $file -Farm 'C' -Application 'a' -Environment 'e' -Language $script:added)
            $dashboard = Get-Content -Path $file -Raw -Encoding UTF8
            $mail = ConvertTo-SPSWeatherEmailBody -InputObject $report -Farm 'C' -Application 'a' -Environment 'e' -Language $script:added
            foreach ($html in $dashboard, $mail) {
                $html | Should -Match "<html lang=""$($script:addedLanguage)"""
                # The renderers HTML-encode the accents (&#201;chec).
                [System.Net.WebUtility]::HtmlDecode($html) | Should -Match 'Échec' -Because 'the new language file is the relabelled French one'
            }
        }
    }

    Context 'a defective translation file' {
        BeforeAll {
            $script:sourceModule = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common'

            # Builds a copy of the module whose fr-FR file is edited by the given script block, loads it,
            # runs the check and always restores the shipped module.
            function Invoke-WithEditedFrench {
                param([scriptblock]$Edit, [scriptblock]$Check)
                $copy = Join-Path -Path $TestDrive -ChildPath ('m-' + [guid]::NewGuid().ToString('N') + '/SPSWeather.Common')
                Copy-Item -Path $script:sourceModule -Destination $copy -Recurse
                $file = Join-Path -Path $copy -ChildPath 'fr-FR/SPSWeather.Common.Strings.psd1'
                $content = [System.IO.File]::ReadAllText($file)
                $edited = & $Edit $content
                # Keep the BOM: Windows PowerShell 5.1 reads a data file without it as ANSI.
                [System.IO.File]::WriteAllText($file, $edited, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))
                try {
                    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
                    Import-Module -Name (Join-Path -Path $copy -ChildPath 'SPSWeather.Common.psd1') -Force
                    & $Check
                }
                finally {
                    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
                    Import-Module -Name (Join-Path -Path $script:sourceModule -ChildPath 'SPSWeather.Common.psd1') -Force
                }
            }
        }

        It 'falls back to English and says why when the file cannot be parsed' {
            Invoke-WithEditedFrench -Edit { param($c) $c -replace "(AllClearTitle\s*=\s*'Tout est en ordre\.)'", '$1' } -Check {
                $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
                $r.Culture | Should -Be 'en-US'
                $r.IsFallback | Should -BeTrue
                $r.Messages.Count | Should -Be 1
                $r.Messages[0] | Should -Match "Language 'fr-FR' cannot be used: the file cannot be read"
                $r.Messages[0] | Should -Match 'using en-US'
            }
        }

        It 'falls back to English and names the key when a value is not text' {
            foreach ($bad in '42', '$true', '$null', '@(''a'', ''b'')') {
                Invoke-WithEditedFrench -Edit { param($c) $c -replace "(AllClearTitle\s*=\s*)'Aucun[^']*'|(AllClearTitle\s*=\s*)'Tout est en ordre\.'", ('${1}${2}' + $bad) } -Check {
                    $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
                    $r.Culture | Should -Be 'en-US'
                    $r.IsFallback | Should -BeTrue
                    $r.Messages[0] | Should -Match "Language 'fr-FR' cannot be used: key 'AllClearTitle' is not text" -Because "value $bad"
                }
            }
        }

        It 'falls back to English when a translation uses a placeholder that the English text does not provide' {
            Invoke-WithEditedFrench -Edit { param($c) $c -replace "(RowOk\s*=\s*')\{0\} OK'", '${1}{0} {1} OK''' } -Check {
                $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
                $r.Culture | Should -Be 'en-US'
                $r.Messages[0] | Should -Match "key 'RowOk' uses \{1\} which the English text does not provide"
            }
        }

        It 'falls back to English when a value contains a stray brace' {
            Invoke-WithEditedFrench -Edit { param($c) $c -replace "(AllClearTitle\s*=\s*')Tout est en ordre\.'", '${1}Tout {est} en ordre.''' } -Check {
                $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
                $r.Culture | Should -Be 'en-US'
                $r.Messages[0] | Should -Match "key 'AllClearTitle' contains a brace"
            }
        }

        It 'falls back to English when the Culture key does not match the folder' {
            Invoke-WithEditedFrench -Edit { param($c) $c -replace "(Culture\s*=\s*')fr-FR'", '${1}fr-CA''' } -Check {
                $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
                $r.Culture | Should -Be 'en-US'
                $r.Messages[0] | Should -Match "its Culture key is 'fr-CA' instead of 'fr-FR'"
            }
        }

        It 'still accepts a translation that simply drops a placeholder or a key' {
            Invoke-WithEditedFrench -Edit { param($c) $c -replace "(?m)^\s*AllClearTitle\s*=.*\r?\n", '' } -Check {
                $r = Resolve-SPSWeatherLanguage -Language 'fr-FR'
                $r.Culture | Should -Be 'fr-FR'
                $r.Messages.Count | Should -Be 0
            }
        }

        It 'gives the English strings, not an error, to the loader for a defective file' {
            Invoke-WithEditedFrench -Edit { param($c) $c -replace "(AllClearTitle\s*=\s*'Tout est en ordre\.)'", '$1' } -Check {
                $text = InModuleScope SPSWeather.Common { Get-SPSWeatherResource -Language 'fr-FR' }
                $text.Culture | Should -Be 'en-US'
                $text.AllClearTitle | Should -Be 'All clear.'
            }
        }
    }

    Context 'a value that is not text' {
        It "does not throw for <Description> and resolves it like text" -ForEach @(
            @{ Description = 'a one-item list'; Value = @('fr-FR'); Expected = 'fr-FR' }
            @{ Description = 'a two-item list (the first one counts)'; Value = @('fr-FR', 'en-US'); Expected = 'fr-FR' }
            @{ Description = 'an empty list'; Value = @(); Expected = 'en-US' }
            @{ Description = 'a number'; Value = 5; Expected = 'en-US' }
            @{ Description = 'a boolean'; Value = $true; Expected = 'en-US' }
        ) {
            { Resolve-SPSWeatherLanguage -Language $Value } | Should -Not -Throw
            (Resolve-SPSWeatherLanguage -Language $Value).Culture | Should -Be $Expected
        }
    }
}
