# Tests for the Timer service instances check (Get-SPSTimerServiceStatus): the logic of the remote
# script block is run locally against a fake Get-SPFarm, then the rows are rendered in the
# dashboard and in both emails. Every instance must be Online.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    # The remote script block calls Get-SPFarm, which only exists on a SharePoint server.
    function global:Get-SPFarm {
        if ($global:SPSWeatherTimerTest.Throw) { throw 'The SharePoint farm is not reachable' }
        [PSCustomObject]@{ TimerService = [PSCustomObject]@{ Instances = $global:SPSWeatherTimerTest.Instances } }
    }
    function New-Instance {
        param([string]$Server, $Status)
        [PSCustomObject]@{ Server = [PSCustomObject]@{ Name = $Server }; Status = $Status }
    }
    function Invoke-TimerCollector {
        param($Instances, [switch]$Throw)
        $global:SPSWeatherTimerTest = @{ Instances = $Instances; Throw = [bool]$Throw }
        InModuleScope SPSWeather.Common {
            Mock Invoke-SPSCommand { & $ScriptBlock @($Arguments) }
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            @(Get-SPSTimerServiceStatus -Server 'APP1.contoso.com' -InstallAccount $cred -Farm 'CONTENT')
        }
    }
    function Get-Severity {
        param($Row)
        InModuleScope SPSWeather.Common -Parameters @{ Row = $Row } { param($Row) Get-SPSWeatherRowSeverity -Row $Row }
    }
    function Get-Text {
        param([string]$Html)
        $plain = $Html -replace '</?(b|span|a)\b[^>]*>', '' -replace '<[^>]+>', ' '
        # A non-breaking space (the "&nbsp;·&nbsp;" separators) reads as a space here.
        ([System.Net.WebUtility]::HtmlDecode($plain) -replace [string][char]0xA0, ' ') -replace '[ \t\r\n]+', ' '
    }
}

AfterAll {
    Remove-Item -Path Function:\global:Get-SPFarm -ErrorAction SilentlyContinue
    Remove-Variable -Name SPSWeatherTimerTest -Scope Global -ErrorAction SilentlyContinue
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSTimerServiceStatus' {
    Context 'contract' {
        It 'is exported with a mandatory -Server, an -InstallAccount credential and a -Farm label' {
            $cmd = Get-Command -Name Get-SPSTimerServiceStatus -Module SPSWeather.Common
            $cmd.Parameters['Server'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
            $cmd.Parameters['InstallAccount'].ParameterType.Name | Should -Be 'PSCredential'
            $cmd.Parameters.Keys | Should -Contain 'Farm'
        }

        It 'queries the farm entry point once' {
            $global:SPSWeatherTimerTest = @{ Instances = @(New-Instance 'WFE1' 'Online'); Throw = $false }
            InModuleScope SPSWeather.Common {
                Mock Invoke-SPSCommand { 'remote-result' }
                $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
                $null = Get-SPSTimerServiceStatus -Server 'APP1.contoso.com' -InstallAccount $cred
                Should -Invoke Invoke-SPSCommand -Times 1 -Exactly -ParameterFilter { $Server -eq 'APP1.contoso.com' }
            }
        }

        It 'never changes the farm: no Update(), no Status assignment, no Set-* cmdlet' {
            $source = Get-Content -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Public/Get-SPSTimerServiceStatus.ps1') -Raw
            $source | Should -Not -Match '\.Update\(\)'
            $source | Should -Not -Match '\$\w+\.Status\s*='
            $source | Should -Not -Match '\bSet-SP\w+|\bEnable-SP\w+|\bStart-SP\w+|\bRestart-Service|\bStart-Service'
        }
    }

    Context 'every instance is Online' {
        BeforeAll {
            $script:rows = Invoke-TimerCollector -Instances @((New-Instance 'WFE2' 'Online'), (New-Instance 'APP1' 'Online'), (New-Instance 'WFE1' 'Online'))
        }

        It 'returns one healthy row per server, sorted by server name' {
            $rows.Count | Should -Be 3
            ($rows.Server -join ',') | Should -Be 'APP1,WFE1,WFE2'
            @($rows | Where-Object { $_.IsInfo }).Count | Should -Be 3
            $rows | ForEach-Object { $_.Status | Should -Be 'Online'; $_.Farm | Should -Be 'CONTENT'; $_.Note | Should -BeNullOrEmpty }
        }

        It 'is healthy for the severity model of every renderer' {
            $rows | ForEach-Object { Get-Severity -Row $_ | Should -Be 'ok' }
        }
    }

    Context 'an instance that is not Online' {
        It 'is a failure: <Status>' -ForEach @(
            @{ Status = 'Disabled' }
            @{ Status = 'Offline' }
            @{ Status = 'Unprovisioning' }
            @{ Status = 'Provisioning' }
            @{ Status = 'Upgrading' }
            @{ Status = 'online ' }
            @{ Status = '' }
        ) {
            $rows = Invoke-TimerCollector -Instances @((New-Instance 'WFE1' 'Online'), (New-Instance 'WFE2' $Status))
            $bad = @($rows | Where-Object { $_.Server -eq 'WFE2' })
            $bad.Count | Should -Be 1
            $bad[0].IsInfo | Should -BeFalse
            $bad[0].Status | Should -Be $Status
            $bad[0].Note | Should -Match 'Not Online'
            Get-Severity -Row $bad[0] | Should -Be 'fail'
            Get-Severity -Row (@($rows | Where-Object { $_.Server -eq 'WFE1' })[0]) | Should -Be 'ok'
        }

        It 'lists the failing instances first' {
            $rows = Invoke-TimerCollector -Instances @((New-Instance 'APP1' 'Online'), (New-Instance 'WFE9' 'Disabled'), (New-Instance 'WFE1' 'Online'), (New-Instance 'WFE2' 'Offline'))
            ($rows.Server -join ',') | Should -Be 'WFE2,WFE9,APP1,WFE1'
        }

        It 'reads the status of a real enumeration (SPObjectStatus is an enum on a farm)' {
            if (-not ('SPSWeatherTestObjectStatus' -as [type])) {
                Add-Type -TypeDefinition 'public enum SPSWeatherTestObjectStatus { Online, Disabled, Offline }'
            }
            $rows = Invoke-TimerCollector -Instances @((New-Instance 'WFE1' ([SPSWeatherTestObjectStatus]::Online)), (New-Instance 'WFE2' ([SPSWeatherTestObjectStatus]::Disabled)))
            ($rows | Where-Object { $_.Server -eq 'WFE1' }).IsInfo | Should -BeTrue
            ($rows | Where-Object { $_.Server -eq 'WFE2' }).Status | Should -Be 'Disabled'
            ($rows | Where-Object { $_.Server -eq 'WFE2' }).IsInfo | Should -BeFalse
        }

        It 'still names the server when the instance does not carry a server object' {
            $odd = [PSCustomObject]@{ Server = 'WFE7'; Status = 'Disabled' }
            $rows = Invoke-TimerCollector -Instances @($odd)
            $rows[0].Server | Should -Be 'WFE7'
            $rows[0].IsInfo | Should -BeFalse
        }
    }

    Context 'a farm that cannot answer' {
        It 'reports a failure, never a healthy farm, when no instance is returned' -ForEach @(
            @{ Name = '$null'; Instances = $null }
            @{ Name = 'an empty list'; Instances = @() }
        ) {
            $rows = Invoke-TimerCollector -Instances $Instances
            $rows.Count | Should -Be 1
            $rows[0].Status | Should -Be 'No instance'
            $rows[0].IsInfo | Should -BeFalse
            $rows[0].Farm | Should -Be 'CONTENT'
            Get-Severity -Row $rows[0] | Should -Be 'fail'
        }

        It 'reports an Unreachable failure with the reason when the query fails' {
            $rows = Invoke-TimerCollector -Instances @() -Throw
            $rows.Count | Should -Be 1
            $rows[0].Status | Should -Be 'Unreachable'
            $rows[0].Note | Should -Be 'The SharePoint farm is not reachable'
            $rows[0].IsInfo | Should -BeFalse
            Get-Severity -Row $rows[0] | Should -Be 'fail'
        }
    }
}

Describe 'Timer service instances in the report, the dashboard and the emails' {
    BeforeAll {
        function New-TimerRow {
            param([string]$Server, [string]$Status)
            $online = ($Status -eq 'Online')
            [PSCustomObject]@{ Farm = 'CONTENT'; Server = $Server; Status = $Status; Note = $(if ($online) { '' } else { 'Not Online: timer jobs (including the WSP deployment) do not run on this server.' }); IsInfo = $online }
        }
        $script:healthy = [PSCustomObject]@{ SPTimerServiceStatus = @((New-TimerRow 'WFE1' 'Online'), (New-TimerRow 'WFE2' 'Online')) }
        $script:broken = [PSCustomObject]@{ SPTimerServiceStatus = @((New-TimerRow 'WFE2' 'Disabled'), (New-TimerRow 'WFE1' 'Online')) }
        function Get-Dashboard {
            param($Report, [string]$Language = 'en-US')
            $file = Join-Path -Path $TestDrive -ChildPath ('d-' + [guid]::NewGuid().ToString('N') + '.html')
            [void](Export-SPSWeatherReport -InputObject $Report -OutputFile $file -Farm 'CONTENT' -Application 'a' -Environment 'e' -Version 'v' -ExecutedBy 'x' -Duration 'd' -Language $Language)
            Get-Content -Path $file -Raw -Encoding UTF8
        }
        $script:enMail = ConvertTo-SPSWeatherEmailBody -InputObject $broken -Farm 'CONTENT' -Application 'a' -Environment 'e' -Language 'en-US'
        $script:frMail = ConvertTo-SPSWeatherEmailBody -InputObject $broken -Farm 'CONTENT' -Application 'a' -Environment 'e' -Language 'fr-FR'
    }

    It 'counts the instances as checks and a failing one as a failure in the report summary' {
        $good = ConvertTo-SPSWeatherReport -Section ([ordered]@{ SPTimerServiceStatus = $healthy.SPTimerServiceStatus })
        $good.Summary.Ok | Should -Be 2
        $good.Summary.Fail | Should -Be 0
        $good.IsAlert | Should -BeFalse
        $bad = ConvertTo-SPSWeatherReport -Section ([ordered]@{ SPTimerServiceStatus = $broken.SPTimerServiceStatus })
        $bad.Summary.Ok | Should -Be 1
        $bad.Summary.Fail | Should -Be 1
        $bad.IsAlert | Should -BeTrue
    }

    It 'shows a section named after the check, in the Timer Jobs card of the dashboard' {
        $html = Get-Dashboard -Report $broken
        $html | Should -Match 'Timer Service - Instances'
        $html | Should -Match 'Timer Jobs &amp; Solutions'
        $html | Should -Match 'WFE2'
        $html | Should -Match 'Disabled'
    }

    It 'shows the same section in French' {
        (Get-Dashboard -Report $broken -Language 'fr-FR') | Should -Match 'Service de minuteur - Instances'
    }

    It 'shows nothing alarming in the dashboard when every instance is Online' {
        $html = Get-Dashboard -Report $healthy
        $html | Should -Match 'Timer Service - Instances'
        $html | Should -Not -Match 'class="pill f"'
    }

    It 'lists a failing instance under Timer Jobs in the per-farm alert email, with its status' {
        $t = Get-Text -Html $enMail
        $t | Should -Match 'Timer Jobs · 1 item'
        $t | Should -Match 'WFE2 — Disabled'
        $t | Should -Not -Match 'WFE1 — Online'
    }

    It 'says nothing about the instances in the alert email when every one is Online' {
        $mail = ConvertTo-SPSWeatherEmailBody -InputObject $healthy -Farm 'CONTENT' -Application 'a' -Environment 'e'
        (Get-Text -Html $mail) | Should -Not -Match 'Timer Jobs'
        (Get-Text -Html $mail) | Should -Match 'No item needs attention'
    }

    It 'lists it under the French area name too' {
        (Get-Text -Html $frMail) | Should -Match 'Travaux du minuteur · 1 élément'
        (Get-Text -Html $frMail) | Should -Match 'WFE2 — Disabled'
    }

    It 'counts it under Timer Jobs on the farm card of the consolidated email' {
        $result = ConvertTo-SPSWeatherReport -Section ([ordered]@{ SPTimerServiceStatus = $broken.SPTimerServiceStatus })
        $farm = [PSCustomObject]@{ Name = 'CONTENT'; Server = 'srvcontent'; Reachable = $true; Report = $result.Report; Summary = $result.Summary; DashboardUrl = '' }
        $mail = ConvertTo-SPSWeatherConsolidatedEmail -FarmResult @($farm) -Application 'a' -Environment 'e'
        $mail.Alert | Should -Be 'ALERT'
        (Get-Text -Html $mail.Body) | Should -Match 'Timer Jobs 1 failure'
    }
}

Describe 'Timer service check in the entry script' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:entry = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1') -Raw
    }

    It 'runs by default and is disabled by the TimerServiceStatus exclusion value' {
        $entry | Should -Match 'if \(-not\(\$ExclusionRules\.Contains\(''TimerServiceStatus''\)\)\) \{\s*Write-Output ''Getting SharePoint Timer Service Instances Status''\s*\$tbSPTimerService \+= Get-SPSTimerServiceStatus -Server \$spTargetServer `\s*-InstallAccount \$ADM `\s*-Farm "\$\(\$spFarm\.Name\)"'
    }

    It 'starts from an empty list, so an excluded check leaves an empty section like the others' {
        $entry | Should -Match '\$tbSPTimerService = @\(\)'
    }

    It 'puts the section in the report, before the failed timer jobs' {
        $entry | Should -Match 'SPTimerServiceStatus\s+= \$tbSPTimerService'
        $entry.IndexOf('SPTimerServiceStatus     = $tbSPTimerService') | Should -BeLessThan $entry.IndexOf('SPFailedTimerJobs        = $tbSPSfailedJobs')
    }
}
