# Contract + delegation/resilience tests for the SharePoint/system collectors.
# Each collector reaches a farm server through the private Invoke-SPSCommand
# helper (mocked here, so no remoting occurs).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

# All collectors share the -Server (mandatory) / -InstallAccount contract.
$allCollectors = @(
    'Get-AppFabricStatus', 'Get-SPSAPIHttpStatus', 'Get-SPSContentDBStatus', 'Get-SPSFailedTimerJob',
    'Get-SPSHealthStatusFromCA', 'Get-SPSSearchEntCrawlLogs', 'Get-SPSSearchEntCrawlStatus',
    'Get-SPSSearchEntTopology', 'Get-SPSServer', 'Get-SPSSiteHttpStatus', 'Get-SPSSolutionStatus',
    'Get-SPSUpgradeStatus', 'Get-USPAudienceStatus', 'Get-SYSDiskUsageStatus', 'Get-SYSDOTNETVersion',
    'Get-SYSEvtAppErrors', 'Get-SYSIISAppPoolStatus', 'Get-SYSIISSiteCertStatus',
    'Get-SYSIISW3WPEXEStatus', 'Get-SYSLastRebootStatus'
)

# Pass-through collectors return the Invoke-SPSCommand result directly and target
# the farm entry point once.
$passThrough = @(
    'Get-SPSAPIHttpStatus', 'Get-SPSContentDBStatus', 'Get-SPSFailedTimerJob', 'Get-SPSHealthStatusFromCA',
    'Get-SPSSearchEntCrawlLogs', 'Get-SPSSearchEntCrawlStatus', 'Get-SPSSearchEntTopology', 'Get-SPSServer',
    'Get-SPSSiteHttpStatus', 'Get-SPSSolutionStatus', 'Get-SPSUpgradeStatus', 'Get-USPAudienceStatus'
)

# Per-server collectors loop over the farm's servers, resolve DNS per host, and
# fall back to an "Unreachable" row on failure (resilient by design).
$perServer = @(
    'Get-SYSDiskUsageStatus', 'Get-SYSDOTNETVersion', 'Get-SYSEvtAppErrors', 'Get-SYSIISAppPoolStatus',
    'Get-SYSIISSiteCertStatus', 'Get-SYSIISW3WPEXEStatus', 'Get-SYSLastRebootStatus'
)

Describe 'Collector contract' {
    It '<_> declares a mandatory -Server and an -InstallAccount credential' -ForEach $allCollectors {
        $cmd = Get-Command -Name $_ -Module SPSWeather.Common
        $server = $cmd.Parameters['Server']
        $server | Should -Not -BeNullOrEmpty
        $server.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters.Keys | Should -Contain 'InstallAccount'
        $cmd.Parameters['InstallAccount'].ParameterType.Name | Should -Be 'PSCredential'
    }

    It '<_> uses an approved verb' -ForEach $allCollectors {
        (Get-Command -Name $_ -Module SPSWeather.Common).Verb | Should -BeIn (Get-Verb).Verb
    }
}

Describe 'Pass-through collector delegation (Invoke-SPSCommand mocked)' {
    It '<_> delegates to the requested server and returns the remote result' -ForEach $passThrough {
        $name = $_
        InModuleScope SPSWeather.Common -Parameters @{ Name = $name } {
            param($Name)
            Mock Invoke-SPSCommand { 'remote-result' }
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))

            $result = & $Name -Server 'APP1.contoso.com' -InstallAccount $cred

            @($result) | Should -Contain 'remote-result'
            Should -Invoke Invoke-SPSCommand -Times 1 -Exactly -ParameterFilter { $Server -eq 'APP1.contoso.com' }
        }
    }
}

Describe 'Per-server collector resilience' {
    It '<_> returns rows without throwing when a server is unreachable' -ForEach $perServer {
        $name = $_
        InModuleScope SPSWeather.Common -Parameters @{ Name = $name } {
            param($Name)
            # Force the remote path to fail so the resilient catch is exercised.
            Mock Invoke-SPSCommand { throw 'unreachable' }
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))

            $result = $null
            { $result = & $Name -Server 'SRV1.contoso.com' -InstallAccount $cred -Servers @('SRV1.contoso.com') } |
                Should -Not -Throw
            @($result).Count | Should -BeGreaterThan 0
        }
    }
}
