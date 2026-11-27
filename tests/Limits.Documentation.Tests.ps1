# Tests that keep the documentation of the limits (wiki page, example configuration) in step with the code.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Documentation of the limits' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:wiki = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'wiki/Limits.md') -Raw
        $script:example = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/Config/CONTOSO-PROD.example.psd1') -Raw
        $script:defaults = Get-SPSWeatherLimitSetting -Config @{}
    }

    It 'gives, in the table of the wiki, the thresholds that the code uses, for <Name>' -ForEach @(
        'ContentDatabaseSize', 'SiteCountPerDatabase', 'ContentDatabasesPerFarm', 'WebApplicationsPerFarm', 'ManagedPaths', 'DistributedCacheSize', 'ApplicationPoolsPerServer'
    ) {
        $name = $_
        $row = [regex]::Match($wiki, '(?m)^\| `' + $name + '` \|(?<cells>.*)$').Groups['cells'].Value
        $row | Should -Not -BeNullOrEmpty
        $cells = @($row.TrimEnd().TrimEnd('|') -split '\|' | ForEach-Object { $_.Trim() })
        $check = $defaults.Checks[$name]
        $expectedWarning = if ($null -eq $check.Warning) { 'none' } else { "$($check.Warning)" }
        $expectedFailure = if ($null -eq $check.Failure) { 'none' } else { "$($check.Failure)" }
        $cells[1] | Should -Be $expectedWarning
        $cells[2] | Should -Be $expectedFailure
    }

    It 'names every check of the code, and only those, in the wiki table' {
        $inWiki = @([regex]::Matches($wiki, '(?m)^\| `(\w+)` \| ') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $defaults.Checks.Contains($_) } | Sort-Object -Unique)
        $inWiki | Should -Be @($defaults.Checks.Keys | Sort-Object)
    }

    It 'lists in the example configuration the defaults of the code, and is understood without a message' {
        $config = Import-PowerShellDataFile -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Config/CONTOSO-PROD.example.psd1')
        $resolved = Get-SPSWeatherLimitSetting -Config $config
        @($resolved.Messages).Count | Should -Be 0
        foreach ($name in $defaults.Checks.Keys) {
            if ($name -eq 'SearchTopology') { continue }
            $resolved.Checks[$name].Warning | Should -Be $defaults.Checks[$name].Warning -Because "the example gives the default warning of $name"
            $resolved.Checks[$name].Failure | Should -Be $defaults.Checks[$name].Failure -Because "the example gives the default failure of $name"
            $resolved.Checks[$name].Enabled | Should -BeTrue
        }
        @($resolved.Exceptions).Count | Should -Be 0
    }

    It 'keeps the example configuration plain ASCII, as the other examples' {
        $example | Should -Not -Match '[^\x00-\x7F]'
    }

    It 'documents LimitStatus where the other exclusions are listed' {
        $example | Should -Match 'SQLAliasStatus, LimitStatus\.'
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        (Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'wiki/Health-Checks.md') -Raw) | Should -Match '`LimitStatus`'
        (Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'wiki/Configuration.md') -Raw) | Should -Match '`LimitStatus`'
    }

    It 'is in the sidebar of the wiki, and links the source of the limits' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        (Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'wiki/_Sidebar.md') -Raw) | Should -Match '\(Limits\)'
        $wiki | Should -Match 'learn\.microsoft\.com/en-us/sharepoint/install/software-boundaries-limits-2019'
    }
}
