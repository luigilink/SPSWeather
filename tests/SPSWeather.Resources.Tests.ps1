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

Describe 'Resource keys versus the renderers' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $publicDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/Public'
        $script:dashboard = Get-Content -Path (Join-Path -Path $publicDir -ChildPath 'Export-SPSWeatherReport.ps1') -Raw
        $script:email = Get-Content -Path (Join-Path -Path $publicDir -ChildPath 'ConvertTo-SPSWeatherEmailBody.ps1') -Raw
        $script:consolidated = Get-Content -Path (Join-Path -Path $publicDir -ChildPath 'ConvertTo-SPSWeatherConsolidatedEmail.ps1') -Raw
        $script:areaMap = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/Private/Get-SPSWeatherEmailAreaMap.ps1') -Raw
        $script:both = $script:dashboard + "`n" + $script:email + "`n" + $script:consolidated

        # The cockpit page reads its labels in its script: t('Key'), hasKey('Key'), or a key kept in a table of the script
        $script:cockpitScript = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/Assets/Cockpit.js') -Raw
        $script:cockpitQuoted = @([regex]::Matches($script:cockpitScript, "'([A-Z]\w*)'") | ForEach-Object -Process { $_.Groups[1].Value } | Sort-Object -Unique)
        $script:cockpitRequested = @([regex]::Matches($script:cockpitScript, "\b(?:t|hasKey)\('(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value } | Where-Object -FilterScript { -not $_.EndsWith('_') } | Sort-Object -Unique)
        $script:cockpitFamilies = @([regex]::Matches($script:cockpitScript, "'(\w+_)'\s*\+") | ForEach-Object -Process { $_.Groups[1].Value } | Sort-Object -Unique)

        # Keys written literally: _t 'Key' / _th 'Key'.
        $literal = @([regex]::Matches($script:both, "\b_th?\s+'(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value })
        # Counted nouns: _count $n 'Base' uses BaseOne and BaseMany.
        $counted = @([regex]::Matches($script:both, "\b_count\s+\S+\s+'(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value + 'One'; $_.Groups[1].Value + 'Many' })
        # Families built from an identifier: Area_<id> and Section_<section>.
        $areaIds = @(@([regex]::Matches($script:dashboard, "Id = '(\w+)'")) | ForEach-Object -Process { $_.Groups[1].Value })
        $areaOrder = [regex]::Match($script:areaMap, '\$areaOrder = @\(([^)]*)\)').Groups[1].Value
        $areaIds += @([regex]::Matches($areaOrder, "'(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value })
        $sectionLists = @([regex]::Matches($script:dashboard, 'Sections = @\(([^)]*)\)') | ForEach-Object -Process { $_.Groups[1].Value })
        $sections = @($sectionLists | ForEach-Object -Process { [regex]::Matches($_, "'(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value } })

        # Keys read directly from the table (not through _t): $text['Key'].
        $direct = @([regex]::Matches($script:both, '\$text\[''(\w+)''\]') | ForEach-Object -Process { $_.Groups[1].Value })

        # Keys kept in a lookup table of the renderer: Key = 'Name'.
        $tabled = @([regex]::Matches($script:both, "\bKey = '(\w+)'") | ForEach-Object -Process { $_.Groups[1].Value })

        $script:literalKeys = @($literal + $counted + $direct + $tabled | Sort-Object -Unique)
        $script:familyKeys = @(($areaIds | Sort-Object -Unique | ForEach-Object -Process { "Area_$_" }) + ($sections | Sort-Object -Unique | ForEach-Object -Process { "Section_$_" }))
        $script:areaIds = @($areaIds | Sort-Object -Unique)
        $script:sections = @($sections | Sort-Object -Unique)
    }

    It 'finds the keys the renderers use' {
        $script:literalKeys.Count | Should -BeGreaterThan 40
        $script:areaIds.Count | Should -BeGreaterOrEqual 11
        $script:sections.Count | Should -Be 25
    }

    It 'defines every key the renderers use' {
        $missing = @(($script:literalKeys + $script:familyKeys) | Where-Object -FilterScript { -not $script:reference.ContainsKey($_) })
        $missing | Should -BeNullOrEmpty -Because 'a key that is used but not defined would be displayed as its name'
    }

    It 'has no dead key' {
        # 'Culture' is read by the loaders, not by the renderers' templates.
        $used = @($script:literalKeys + $script:familyKeys + $script:cockpitQuoted + 'Culture')
        $dead = @($script:reference.Keys | Where-Object -FilterScript {
                $key = $_
                ($used -notcontains $key) -and -not @($script:cockpitFamilies | Where-Object -FilterScript { $key.StartsWith($_) })
            })
        $dead | Should -BeNullOrEmpty -Because 'a key that nothing uses is a translation effort for nothing'
    }

    It 'defines every key that the cockpit script asks for' {
        $script:cockpitRequested.Count | Should -BeGreaterThan 100
        $missing = @($script:cockpitRequested | Where-Object -FilterScript { -not $script:reference.ContainsKey($_) })
        $missing | Should -BeNullOrEmpty -Because 'a label that is not defined would show its key name in the page'
    }

    It 'defines the keys of every family that the cockpit script builds' {
        $script:cockpitFamilies | Should -Contain 'Section_'
        foreach ($prefix in $script:cockpitFamilies) {
            @($script:reference.Keys | Where-Object -FilterScript { $_.StartsWith($prefix) }).Count | Should -BeGreaterThan 0 -Because "no key starts with '$prefix'"
        }
    }

    It '<Culture> has a date format that formats a date without throwing' -ForEach $allCultures {
        $table = Import-PowerShellDataFile -Path $Path
        $table.HistoryDateFormat | Should -Not -BeNullOrEmpty
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($table.Culture)
        { (Get-Date -Year 2026 -Month 3 -Day 4).ToString($table.HistoryDateFormat, $culture) } | Should -Not -Throw
    }

    It 'writes 4 March as 03-04 in English and 04/03 in French (no month-first date for a French reader)' {
        $date = Get-Date -Year 2026 -Month 3 -Day 4
        $en = Import-PowerShellDataFile -Path (Join-Path -Path (Split-Path -Path $script:referencePath -Parent) -ChildPath 'SPSWeather.Common.Strings.psd1')
        $fr = Import-PowerShellDataFile -Path (Join-Path -Path (Join-Path -Path (Split-Path -Path (Split-Path -Path $script:referencePath -Parent) -Parent) -ChildPath 'fr-FR') -ChildPath 'SPSWeather.Common.Strings.psd1')
        $date.ToString($en.HistoryDateFormat, [System.Globalization.CultureInfo]::GetCultureInfo('en-US')) | Should -Be '03-04'
        $date.ToString($fr.HistoryDateFormat, [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')) | Should -Be '04/03'
    }

    It 'never builds a label from a hard-coded English area or section name any more' {
        $script:dashboard | Should -Not -Match '\$sectionLabel'
        $script:dashboard | Should -Not -Match "Name = '(Farm & Upgrade|Trust Farm|Search|SQL Server)"
        $script:email | Should -Not -Match "'Farm & Upgrade'|'Trust Farm \(REST\)'|'SQL Server'"
    }
}

