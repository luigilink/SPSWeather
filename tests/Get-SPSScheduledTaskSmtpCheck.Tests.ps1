# Tests for the check of the scheduled task (Get-SPSScheduledTaskSmtpCheck): 4.0.0 removes the -EnableSMTP switch, so
# the readiness check warns when the task of an environment still carries it. The decision is tested with a fake reader
# of the Task Scheduler; the reader itself only runs for real on Windows.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
    $script:entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
    $script:readinessPath = Join-Path -Path $repoRoot -ChildPath 'src/Test-SPSWeatherReadiness.ps1'

    # The reader is mocked: it returns what the Task Scheduler would give for a task
    function Invoke-Check {
        param($Task, [switch]$ConfigDefinesEnabled)
        $global:SPSWeatherTaskTest = $Task
        InModuleScope SPSWeather.Common -Parameters @{ Defined = [bool]$ConfigDefinesEnabled } {
            param($Defined)
            Mock Read-SPSScheduledTask {
                if ($global:SPSWeatherTaskTest -is [scriptblock]) { & $global:SPSWeatherTaskTest } else { $global:SPSWeatherTaskTest }
            }
            Get-SPSScheduledTaskSmtpCheck -Application 'contoso' -Environment 'PROD' -ConfigDefinesEnabled:$Defined
        }
    }
    function New-TaskResult {
        param([string]$Arguments, [bool]$Found = $true, [bool]$Readable = $true, [bool]$Supported = $true, [string]$Error = '')
        [PSCustomObject]@{ Supported = $Supported; Found = $Found; Readable = $Readable; Arguments = $Arguments; Error = $Error }
    }
}

AfterAll {
    Remove-Variable -Name SPSWeatherTaskTest -Scope Global -ErrorAction SilentlyContinue
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherTaskName' {
    It 'builds SPSWeather-<Application>-<Environment>' {
        Get-SPSWeatherTaskName -Application 'contoso' -Environment 'PROD' | Should -Be 'SPSWeather-contoso-PROD'
    }

    It 'is the only place that builds the name: the entry script calls it and no longer builds the string itself' {
        $source = Get-Content -Path $entryPath -Raw
        $source | Should -Match 'Get-SPSWeatherTaskName\s+-Application\s+\$Application\s+-Environment\s+\$Environment'
        $source | Should -Not -Match '"SPSWeather-\$\(\$Application\)-\$\(\$Environment\)"'
    }

    It 'is what the check asks the reader for' {
        $global:SPSWeatherTaskTest = New-TaskResult -Arguments ''
        InModuleScope SPSWeather.Common {
            Mock Read-SPSScheduledTask { $global:SPSWeatherTaskTest }
            $null = Get-SPSScheduledTaskSmtpCheck -Application 'contoso' -Environment 'PROD'
            Should -Invoke Read-SPSScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'SPSWeather-contoso-PROD' }
        }
    }
}

Describe 'Get-SPSScheduledTaskSmtpCheck' {
    Context 'a task that still carries the switch' {
        It 'warns for <Name>' -ForEach @(
            @{ Name = 'the switch at the end'; Arguments = '-Execution Bypass F:\SCRIPTS\SPSWeather\SPSWeather.ps1 -ConfigFile F:\SCRIPTS\SPSWeather\Config\CONTOSO-PROD.psd1 -EnableSMTP' }
            @{ Name = 'the switch in the middle'; Arguments = '-Execution Bypass F:\S\SPSWeather.ps1 -EnableSMTP -ConfigFile F:\S\Config\c.psd1' }
            @{ Name = 'another case'; Arguments = '-File F:\S\SPSWeather.ps1 -enablesmtp' }
            @{ Name = 'the usual case of the parameter'; Arguments = '-File F:\S\SPSWeather.ps1 -EnableSmtp' }
            @{ Name = 'an explicit value'; Arguments = '-File F:\S\SPSWeather.ps1 -EnableSMTP:$false' }
            @{ Name = 'a quoted switch'; Arguments = '-File F:\S\SPSWeather.ps1 "-EnableSMTP"' }
            @{ Name = 'tabs and several blanks'; Arguments = "-File  F:\S\SPSWeather.ps1`t-EnableSMTP" }
        ) {
            $r = Invoke-Check -Task (New-TaskResult -Arguments $Arguments)
            $r.Status | Should -Be 'WARN'
            $r.State | Should -Be 'HasSwitch'
            $r.TaskName | Should -Be 'SPSWeather-contoso-PROD'
            $r.Detail | Should -Match '-EnableSMTP'
            $r.Detail | Should -Match '4\.0\.0'
        }

        It 'asks to run -Action Install again when SMTPEnabled is already defined' {
            $r = Invoke-Check -Task (New-TaskResult -Arguments '-File F:\S\SPSWeather.ps1 -EnableSMTP') -ConfigDefinesEnabled
            $r.Detail | Should -Match 'SMTPEnabled is defined'
            $r.Detail | Should -Match '-Action Install again'
            $r.Detail | Should -Not -Match 'add SMTPEnabled'
        }

        It 'asks to add SMTPEnabled first when it is not defined, because the switch still decides' {
            $r = Invoke-Check -Task (New-TaskResult -Arguments '-File F:\S\SPSWeather.ps1 -EnableSMTP')
            $r.Detail | Should -Match 'SMTPEnabled is not defined'
            $r.Detail | Should -Match 'add SMTPEnabled = \$true \(or \$false\)'
            $r.Detail | Should -Match '-Action Install again'
        }
    }

    Context 'a task that does not carry the switch' {
        It 'passes for <Name>' -ForEach @(
            @{ Name = 'the arguments of 3.5.0'; Arguments = '-Execution Bypass F:\SCRIPTS\SPSWeather\SPSWeather.ps1 -ConfigFile F:\SCRIPTS\SPSWeather\Config\CONTOSO-PROD.psd1' }
            @{ Name = 'no arguments'; Arguments = '' }
            @{ Name = 'a quoted path that holds the text'; Arguments = '-File "F:\S\-EnableSMTP\SPSWeather.ps1" -ConfigFile "F:\S\c.psd1"' }
            @{ Name = 'a longer parameter name'; Arguments = '-File F:\S\SPSWeather.ps1 -EnableSmtpExtra' }
            @{ Name = 'an abbreviation of the parameter (the script writes the task itself)'; Arguments = '-File F:\S\SPSWeather.ps1 -EnableS' }
            @{ Name = 'the text in a value'; Arguments = '-File F:\S\SPSWeather.ps1 -ConfigFile F:\S\EnableSMTP.psd1' }
        ) {
            $r = Invoke-Check -Task (New-TaskResult -Arguments $Arguments)
            $r.Status | Should -Be 'PASS'
            $r.State | Should -Be 'Clean'
        }
    }

    Context 'a task that cannot be judged is information, never a warning or a failure' {
        It 'skips a task that does not exist' {
            $r = Invoke-Check -Task (New-TaskResult -Arguments '' -Found $false)
            $r.Status | Should -Be 'SKIP'
            $r.State | Should -Be 'NotFound'
            $r.Detail | Should -Match 'SPSWeather-contoso-PROD'
        }

        It 'skips a task that cannot be read and says to run as an administrator' {
            $r = Invoke-Check -Task (New-TaskResult -Arguments '' -Readable $false -Error 'Access is denied.')
            $r.Status | Should -Be 'SKIP'
            $r.State | Should -Be 'Unreadable'
            $r.Detail | Should -Match 'Access is denied'
            $r.Detail | Should -Match 'administrator'
        }

        It 'skips a host that is not Windows' {
            $r = Invoke-Check -Task (New-TaskResult -Arguments '' -Supported $false -Found $false)
            $r.Status | Should -Be 'SKIP'
            $r.State | Should -Be 'NotSupported'
        }

        It 'skips, and does not throw, when the reader throws' {
            $r = Invoke-Check -Task { throw 'the Task Scheduler is not available' }
            $r.Status | Should -Be 'SKIP'
            $r.State | Should -Be 'Unreadable'
            $r.Detail | Should -Match 'the Task Scheduler is not available'
        }

        It 'skips, and does not throw, when the reader returns nothing' {
            $r = Invoke-Check -Task $null
            $r.Status | Should -Be 'SKIP'
        }
    }

    It 'accepts an empty application or environment without throwing' {
        { InModuleScope SPSWeather.Common {
                Mock Read-SPSScheduledTask { [PSCustomObject]@{ Supported = $true; Found = $false; Readable = $true; Arguments = ''; Error = '' } }
                Get-SPSScheduledTaskSmtpCheck -Application $null -Environment '' } } | Should -Not -Throw
    }
}

Describe 'Read-SPSScheduledTask' {
    It 'is not exported (the check is)' {
        Get-Command -Name Read-SPSScheduledTask -Module SPSWeather.Common -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Name Get-SPSScheduledTaskSmtpCheck -Module SPSWeather.Common | Should -Not -BeNullOrEmpty
    }

    It 'only reads: it never registers, changes or deletes a task or a folder' {
        $path = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SPSWeather.Common/Private/Read-SPSScheduledTask.ps1'
        $source = Get-Content -Path $path -Raw
        $source | Should -Not -Match 'RegisterTask|DeleteTask|DeleteFolder|CreateFolder|Register-ScheduledTask|Set-ScheduledTask|Unregister-ScheduledTask'
    }

    It 'says that it is not supported off Windows' -Skip:($IsWindows) {
        $r = InModuleScope SPSWeather.Common { Read-SPSScheduledTask -TaskName 'SPSWeather-contoso-PROD' }
        $r.Supported | Should -BeFalse
        $r.Found | Should -BeFalse
    }

    It 'finds nothing for a task that does not exist, and that is not an error' -Skip:(-not $IsWindows) {
        $r = InModuleScope SPSWeather.Common { Read-SPSScheduledTask -TaskName ('SPSWeather-test-' + [guid]::NewGuid().ToString('N')) }
        $r.Supported | Should -BeTrue
        $r.Found | Should -BeFalse
        $r.Readable | Should -BeTrue
    }
}

Describe 'Readiness script: scheduled task section' {
    BeforeAll {
        $script:hostExe = (Get-Process -Id $PID).Path
        $cfgPath = Join-Path -Path $TestDrive -ChildPath 'cfg.psd1'
        Set-Content -Path $cfgPath -Encoding UTF8 -Value @"
@{
    ConfigurationName = 'PROD'
    ApplicationName   = 'lab'
    Domain            = 'contoso.com'
    CredentialKey     = 'svc'
    SMTPEnabled       = `$false
    Farms             = @( @{ Name = 'CONTENT'; Server = 'app1' } )
}
"@
        $out = & $script:hostExe -NoProfile -ExecutionPolicy Bypass -File $script:readinessPath -ConfigFile $cfgPath -SkipNetwork -SkipSharePoint 2>&1 | Out-String
        $script:lines = $out -split "`r?`n"
    }

    It 'has a Scheduled task section with a line for the task of the configuration' {
        ($lines -join "`n") | Should -Match '== Scheduled task =='
        @($lines | Where-Object { $_ -match "Task 'SPSWeather-lab-PROD'" }).Count | Should -Be 1
    }

    It 'never fails or warns on a host where the task is not there (the test host)' {
        $line = @($lines | Where-Object { $_ -match "Task 'SPSWeather-lab-PROD'" })[0]
        $line | Should -Match '^\[SKIP\]'
    }

    It 'maps the status of the check to the line, with no other decision of its own' {
        $source = Get-Content -Path $readinessPath -Raw
        $source | Should -Match 'Get-SPSScheduledTaskSmtpCheck\s+-Application'
        $source.Contains('-Status $taskCheck.Status -Detail $taskCheck.Detail') | Should -BeTrue
        $source | Should -Not -Match "Add-CheckResult -Section 'Scheduled task'[^\r\n]*-Status 'FAIL'"
    }

    It 'comes before the network check and does not change the other sections' {
        $source = Get-Content -Path $readinessPath -Raw
        $source.IndexOf("Write-Section -Title 'Secrets'") | Should -BeLessThan $source.IndexOf("Write-Section -Title 'Scheduled task'")
        $source.IndexOf("Write-Section -Title 'Scheduled task'") | Should -BeLessThan $source.IndexOf("Write-Section -Title 'Privileges'")
    }
}
