# Contract + behavioural tests for the SharePoint collectors Get-SPSVersion,
# Get-SPSSqlStatus, Get-SPSInstalledProductVersion and Import-SPSSharePointCommand.

# $IsWindows is undefined on Windows PowerShell 5.1; derive it from the edition.
$script:onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows
$script:onSharePoint = $onWindows -and (Test-Path 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions')

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSVersion' {
    It 'requires a mandatory -Server' {
        $param = (Get-Command -Name Get-SPSVersion -Module SPSWeather.Common).Parameters['Server']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }
}

Describe 'Get-SPSSqlStatus' {
    It 'requires Server and InstallAccount and has threshold defaults' {
        $cmd = Get-Command -Name Get-SPSSqlStatus -Module SPSWeather.Common
        $cmd.Parameters['Server'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters['InstallAccount'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters['InstallAccount'].ParameterType.Name | Should -Be 'PSCredential'
        $cmd.Parameters.Keys | Should -Contain 'DiskFreeThresholdPercent'
        $cmd.Parameters.Keys | Should -Contain 'BackupMaxAgeDays'
    }
}

Describe 'Get-SPSInstalledProductVersion' {
    It 'returns null off a SharePoint server' -Skip:($onSharePoint) {
        Get-SPSInstalledProductVersion | Should -BeNullOrEmpty
    }
}

Describe 'Import-SPSSharePointCommand' {
    It 'throws when SharePoint is not installed' -Skip:($onSharePoint) {
        { Import-SPSSharePointCommand -ErrorAction Stop } | Should -Throw '*SharePoint is not installed*'
    }
}
