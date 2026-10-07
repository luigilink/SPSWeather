# Module-level tests for SPSWeather.Common: manifest, exports and file conventions.
# Cross-platform by design (no SharePoint / no Windows-only dependency).

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
$modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSWeather.Common.psd1'

$publicFiles = @(Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Public')  -Filter *.ps1)
$privateFiles = @(Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Private') -Filter *.ps1)
$functionFiles = @($publicFiles + $privateFiles)
$psFiles = @(
    $functionFiles
    Get-Item -Path $modulePath
    Get-Item -Path (Join-Path -Path $moduleDir -ChildPath 'SPSWeather.Common.psm1')
)

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
    $modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'SPSWeather.Common module' {
    It 'imports without error' {
        Get-Module -Name SPSWeather.Common | Should -Not -BeNullOrEmpty
    }

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $modulePath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'manifest version is 3.1.0 or higher' {
        (Test-ModuleManifest -Path $modulePath).Version | Should -BeGreaterOrEqual ([version]'3.1.0')
    }

    It 'exports exactly the expected public functions' {
        $expected = @(
            'Add-SPSSheduledTask'
            'Add-SPSWeatherEvent'
            'Backup-SPSWeatherJsonFile'
            'Clear-SPSLog'
            'Compare-SPSWeatherSnapshots'
            'ConvertTo-SPSWeatherReport'
            'Export-SPSWeatherReport'
            'Get-AppFabricStatus'
            'Get-SPSAPIHttpStatus'
            'Get-SPSContentDBStatus'
            'Get-SPSFailedTimerJob'
            'Get-SPSHealthStatusFromCA'
            'Get-SPSInstalledProductVersion'
            'Get-SPSSearchEntCrawlLogs'
            'Get-SPSSearchEntCrawlStatus'
            'Get-SPSSearchEntTopology'
            'Get-SPSSecret'
            'Get-SPSServer'
            'Get-SPSSiteHttpStatus'
            'Get-SPSSolutionStatus'
            'Get-SPSSqlStatus'
            'Get-SPSUpgradeStatus'
            'Get-SPSVersion'
            'Get-SPWeatherListInfo'
            'Get-SYSDiskUsageStatus'
            'Get-SYSDOTNETVersion'
            'Get-SYSEvtAppErrors'
            'Get-SYSIISAppPoolStatus'
            'Get-SYSIISSiteCertStatus'
            'Get-SYSIISW3WPEXEStatus'
            'Get-SYSLastRebootStatus'
            'Get-USPAudienceStatus'
            'Import-SPSSharePointCommand'
            'ConvertTo-SPSWeatherEmailBody'
            'Remove-SPSSheduledTask'
            'Resolve-SPSSqlAlias'
            'Set-SPSCredSSPClient'
            'Set-SPSSecret'
        )
        $actual = (Get-Command -Module SPSWeather.Common).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'does not export the private helpers' {
        foreach ($name in @('Invoke-SPSCommand', 'ConvertFrom-SPSSqlAliasValue', 'Get-SPSWeatherHistory', 'Get-SPSConfigRoot')) {
            Get-Command -Name $name -Module SPSWeather.Common -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty
        }
    }

    It 'manifest FunctionsToExport matches the Public folder exactly' {
        $declared = (Import-PowerShellDataFile -Path $modulePath).FunctionsToExport | Sort-Object
        $files = (Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Public') -Filter *.ps1).BaseName |
            Sort-Object
        $declared | Should -Be $files
    }

    It 'every exported function uses an approved verb' {
        $approved = (Get-Verb).Verb
        foreach ($command in Get-Command -Module SPSWeather.Common) {
            $approved | Should -Contain $command.Verb
        }
    }
}

Describe 'Module file conventions' {
    It '<Name> defines exactly one function named after the file' -ForEach $functionFiles {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs)
        $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $fns.Count | Should -Be 1
        $fns[0].Name | Should -Be $_.BaseName
    }

    It '<Name> parses without errors' -ForEach $functionFiles {
        $tokens = $null; $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs) | Out-Null
        $errs | Should -BeNullOrEmpty
    }

    It '<Name> is stored as UTF-8 with BOM' -ForEach $psFiles {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }
}
