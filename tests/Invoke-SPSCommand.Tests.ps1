# Behavioural tests for the Invoke-SPSCommand private remoting helper.
# The real remoting cmdlets are mocked via InModuleScope; no remoting occurs.

# Discovery-time Windows detection: $IsWindows is undefined on Windows PowerShell 5.1,
# so derive it from the edition to keep the -Skip guard correct under the 5.1 CI job.
$script:onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-SPSCommand remoting' {
    It 'throws and never runs the command locally when the session cannot be opened' -Skip:(-not $onWindows) {
        InModuleScope SPSWeather.Common {
            Mock New-PSSession { throw 'CredSSP not configured' }
            Mock Invoke-Command { 'SHOULD-NOT-RUN' }
            Mock Remove-PSSession {}

            $cred = [System.Management.Automation.PSCredential]::new(
                'CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))

            { Invoke-SPSCommand -Credential $cred -Server 'SRV1' -ScriptBlock { 1 } } |
                Should -Throw "*Failed to open a CredSSP PSSession to 'SRV1'*"

            # The bug being guarded: Invoke-Command must NOT run without a session.
            Should -Invoke Invoke-Command -Times 0 -Exactly
        }
    }
}

Describe 'Invoke-SPSCommand Negotiate fallback' {
    It 'does not attempt Negotiate when fallback is off (CredSSP-only error)' {
        InModuleScope SPSWeather.Common {
            Mock New-PSSession { throw 'CredSSP not configured' }
            Mock Invoke-Command { 'SHOULD-NOT-RUN' }
            Mock Remove-PSSession {}
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            { Invoke-SPSCommand -Credential $cred -Server 'SRV1' -ScriptBlock { 1 } -WarningAction SilentlyContinue } |
                Should -Throw "*Failed to open a CredSSP PSSession to 'SRV1'*"
            Should -Invoke New-PSSession -Times 0 -Exactly -ParameterFilter { $Authentication -eq 'Negotiate' }
        }
    }

    It 'falls back to Negotiate and warns when CredSSP fails and -AllowFallback is set' {
        InModuleScope SPSWeather.Common {
            Mock New-PSSession {
                if ($Authentication -eq 'CredSSP') { throw 'CredSSP not configured' }
                New-MockObject -Type ([System.Management.Automation.Runspaces.PSSession])
            }
            Mock Invoke-Command { 'remote-output' }
            Mock Remove-PSSession {}
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            $warn = $null
            $result = Invoke-SPSCommand -Credential $cred -Server 'SRV1' -ScriptBlock { 1 } -AllowFallback -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -Be 'remote-output'
            Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'CredSSP' }
            Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'Negotiate' }
            (@($warn) -join "`n") | Should -Match 'Negotiate'
        }
    }

    It 'aggregates every authentication error when all methods fail with fallback on' {
        InModuleScope SPSWeather.Common {
            Mock New-PSSession {
                if ($Authentication -eq 'CredSSP') { throw 'credssp-down' }
                throw 'negotiate-down'
            }
            Mock Invoke-Command { 'x' }
            Mock Remove-PSSession {}
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            try {
                Invoke-SPSCommand -Credential $cred -Server 'SRV1' -ScriptBlock { 1 } -AllowFallback -WarningAction SilentlyContinue
                throw 'should have thrown'
            }
            catch {
                $_.Exception.Message | Should -Match 'using any of: CredSSP, Negotiate'
                $_.Exception.Message | Should -Match 'credssp-down'
                $_.Exception.Message | Should -Match 'negotiate-down'
            }
        }
    }
}
