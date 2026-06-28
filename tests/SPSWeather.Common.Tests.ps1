# Structural tests for the SPSWeather.Common module.
# Cross-platform by design (no SharePoint / no Windows-only dependency) so they run
# on pwsh 7 / macOS locally and on windows-latest in CI.

$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$moduleDir  = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
$modulePath = Join-Path -Path $moduleDir -ChildPath 'SPSWeather.Common.psd1'

$publicFiles  = @(Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Public')  -Filter *.ps1)
$privateFiles = @(Get-ChildItem -Path (Join-Path -Path $moduleDir -ChildPath 'Private') -Filter *.ps1)
$functionFiles = @($publicFiles + $privateFiles)
$psFiles = @(
    $functionFiles
    Get-Item -Path $modulePath
    Get-Item -Path (Join-Path -Path $moduleDir -ChildPath 'SPSWeather.Common.psm1')
)

BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $moduleDir  = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common'
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

    It 'manifest version is 2.0.0 or higher' {
        (Test-ModuleManifest -Path $modulePath).Version | Should -BeGreaterOrEqual ([version]'2.0.0')
    }

    It 'exports exactly the expected public functions' {
        $expected = @(
            'Add-SPSSheduledTask'
            'Clear-SPSLog'
            'Get-AppFabricStatus'
            'Get-SPSAPIHttpStatus'
            'Get-SPSContentDBStatus'
            'Get-SPSFailedTimerJob'
            'Get-SPSHealthStatusFromCA'
            'Get-SPSSearchEntCrawlLogs'
            'Get-SPSSearchEntCrawlStatus'
            'Get-SPSSearchEntTopology'
            'Get-SPSServer'
            'Get-SPSSiteHttpStatus'
            'Get-SPSSolutionStatus'
            'Get-SPSUpgradeStatus'
            'Get-SPSVersion'
            'Get-SPWeatherListInfo'
            'Get-SQLDatabasesStatus'
            'Get-SQLInstancesStatus'
            'Get-SYSDiskUsageStatus'
            'Get-SYSDOTNETVersion'
            'Get-SYSEvtAppErrors'
            'Get-SYSIISAppPoolStatus'
            'Get-SYSIISSiteCertStatus'
            'Get-SYSIISW3WPEXEStatus'
            'Get-SYSLastRebootStatus'
            'Get-USPAudienceStatus'
            'Join-HtmlBodyFromPSo'
            'Remove-SPSSheduledTask'
        )
        $actual = (Get-Command -Module SPSWeather.Common).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'does not export the private helpers' {
        foreach ($name in @('Invoke-SPSCommand', 'Invoke-SPSWebRequestUrl', 'Join-HtmlTable')) {
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

Describe 'Public function contracts' {
    It 'Remove-SPSSheduledTask supports ShouldProcess (WhatIf/Confirm)' {
        (Get-Command -Name Remove-SPSSheduledTask -Module SPSWeather.Common).Parameters.Keys |
            Should -Contain 'WhatIf'
    }

    It '<_> requires a mandatory -TaskName' -ForEach @('Add-SPSSheduledTask', 'Remove-SPSSheduledTask') {
        $param = (Get-Command -Name $_ -Module SPSWeather.Common).Parameters['TaskName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Get-SPSVersion requires a mandatory -Server' {
        $param = (Get-Command -Name Get-SPSVersion -Module SPSWeather.Common).Parameters['Server']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }
}

Describe 'HTML report (Join-HtmlBodyFromPSo)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPSiteHttpStatus -Value @(
            [PSCustomObject]@{ Server = 'SRV1'; Url = 'https://sp'; HTTPCode = 200; Time = 0.4; Status = 'OK' }
            [PSCustomObject]@{ Server = 'SRV2'; Url = 'https://sp2'; HTTPCode = 500; Time = 2.1; Status = 'KO' }
        )
        $html = Join-HtmlBodyFromPSo -PSObjectFromJson $report
    }

    It 'returns a single self-contained HTML document string' {
        $html | Should -BeOfType ([System.String])
        $html.StartsWith('<!DOCTYPE html>') | Should -BeTrue
        $html.TrimEnd().EndsWith('</html>') | Should -BeTrue
    }

    It 'embeds the head, style block and container (regression guard for the dropped CSS)' {
        $html | Should -Match '<head>'
        $html | Should -Match '<style>'
        $html | Should -Match 'id="spweathermain"'
    }

    It 'keeps the Outlook MSO conditional comment' {
        $html | Should -Match '\[if mso\]'
    }

    It 'does not leak an unexpanded caller-scope header/footer variable' {
        $html | Should -Not -Match '\$htmlHEADER'
        $html | Should -Not -Match '\$htmlFOOTER'
    }

    It 'renders a failed status cell for a non-OK row' {
        $html | Should -Match 'tdfailed'
    }
}
