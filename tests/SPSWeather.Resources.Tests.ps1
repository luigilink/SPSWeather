# Guard rails on the resource files themselves (src/Modules/SPSWeather.Common/<culture>/*.Strings.psd1):
# every culture must stay in step with the en-US reference, whoever edits it.

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
$resourceName = 'SPSWeather.Common.Strings.psd1'
$allCultures = @(Get-ChildItem -Path $moduleDir -Directory |
        Where-Object -FilterScript { Test-Path -Path (Join-Path -Path $_.FullName -ChildPath $resourceName) } |
        ForEach-Object -Process { @{ Culture = $_.Name; Path = (Join-Path -Path $_.FullName -ChildPath $resourceName) } })
$translations = @($allCultures | Where-Object -FilterScript { $_.Culture -ne 'en-US' })

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:referencePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/en-US/SPSWeather.Common.Strings.psd1'
    $script:reference = Import-PowerShellDataFile -Path $script:referencePath
    $script:cultureNames = @(Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common') -Directory |
            Where-Object -FilterScript { Test-Path -Path (Join-Path -Path $_.FullName -ChildPath 'SPSWeather.Common.Strings.psd1') } |
            ForEach-Object -Process { $_.Name })

    function Get-Placeholder {
        param([string]$Value)
        @([regex]::Matches($Value, '\{(\d+)\}') | ForEach-Object -Process { $_.Groups[1].Value } | Sort-Object -Unique)
    }
}

Describe 'Resource files' {
    It 'ships the English reference and at least one translation' {
        $script:cultureNames | Should -Contain 'en-US'
        @($script:cultureNames | Where-Object -FilterScript { $_ -ne 'en-US' }).Count | Should -BeGreaterThan 0
    }

    It '<Culture> is stored as UTF-8 with a BOM and CRLF line endings' -ForEach $allCultures {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        $text = [System.IO.File]::ReadAllText($Path)
        ([regex]::Matches($text, "(?<!`r)`n")).Count | Should -Be 0
    }

    It '<Culture> loads as a data file whose Culture key is its folder name' -ForEach $allCultures {
        $table = Import-PowerShellDataFile -Path $Path
        $table.Culture | Should -Be $Culture
    }

    It '<Culture> contains no typographic apostrophe that would close a PowerShell string' -ForEach $allCultures {
        $text = [System.IO.File]::ReadAllText($Path)
        foreach ($char in [char]0x2018, [char]0x2019, [char]0x201A, [char]0x201B) {
            $text.Contains([string]$char) | Should -BeFalse -Because "U+$('{0:X4}' -f [int]$char) is read as a single quote by PowerShell"
        }
    }

    Context 'a translation compared with the en-US reference' {
        It '<Culture> defines exactly the same keys' -ForEach $translations {
            $table = Import-PowerShellDataFile -Path $Path
            $missing = @($script:reference.Keys | Where-Object -FilterScript { -not $table.ContainsKey($_) })
            $extra = @($table.Keys | Where-Object -FilterScript { -not $script:reference.ContainsKey($_) })
            $missing | Should -BeNullOrEmpty -Because 'a missing key falls back to English'
            $extra | Should -BeNullOrEmpty -Because 'an unknown key is never displayed'
        }

        It '<Culture> uses the same placeholders as the reference for every key' -ForEach $translations {
            $table = Import-PowerShellDataFile -Path $Path
            foreach ($key in $script:reference.Keys) {
                $expected = (Get-Placeholder -Value $script:reference[$key]) -join ','
                $actual = (Get-Placeholder -Value $table[$key]) -join ','
                $actual | Should -Be $expected -Because "key '$key' must keep its placeholders"
            }
        }
    }

    Context 'every value' {
        It '<Culture> has no empty value' -ForEach $allCultures {
            $table = Import-PowerShellDataFile -Path $Path
            foreach ($key in $table.Keys) {
                [string]::IsNullOrWhiteSpace([string]$table[$key]) | Should -BeFalse -Because "key '$key' is empty"
            }
        }

        It '<Culture> has no HTML in a value (the renderers encode the text)' -ForEach $allCultures {
            $table = Import-PowerShellDataFile -Path $Path
            foreach ($key in $table.Keys) {
                [string]$table[$key] | Should -Not -Match '[<>]|&#?\w+;' -Because "key '$key' must be plain text"
            }
        }

        It '<Culture> has no brace that is not a {n} placeholder (String.Format would fail)' -ForEach $allCultures {
            $table = Import-PowerShellDataFile -Path $Path
            foreach ($key in $table.Keys) {
                ([string]$table[$key] -replace '\{\d+\}', '') | Should -Not -Match '[{}]' -Because "key '$key' has a stray brace"
            }
        }
    }
}
