# Behavioural tests for the DPAPI secret store (Set-SPSSecret / Get-SPSSecret).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Secret store (DPAPI secrets.psd1)' {
    It 'writes a credential and reads the same password back' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'cfg-roundtrip'
        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            $sec = ConvertTo-SecureString 'S3cr3t-P@ss!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc_spsweather', $sec)
            Set-SPSSecret -CredentialKey 'PROD-ADM' -Credential $cred -ConfigPath $Folder

            $file = Join-Path -Path $Folder -ChildPath 'secrets.psd1'
            Test-Path -Path $file | Should -BeTrue

            $got = Get-SPSSecret -CredentialKey 'PROD-ADM' -ConfigPath $Folder
            $got | Should -BeOfType ([System.Management.Automation.PSCredential])
            $got.UserName | Should -Be 'CONTOSO\svc_spsweather'
            $got.GetNetworkCredential().Password | Should -Be 'S3cr3t-P@ss!'
        }
    }

    It 'returns $null when secrets.psd1 is missing' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'cfg-empty'
        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            Get-SPSSecret -CredentialKey 'PROD-ADM' -ConfigPath $Folder | Should -BeNullOrEmpty
        }
    }

    It 'preserves other keys when writing and removing entries' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'cfg-multi'
        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            $mk = {
                param($u, $p)
                [System.Management.Automation.PSCredential]::new($u, (ConvertTo-SecureString $p -AsPlainText -Force))
            }
            Set-SPSSecret -CredentialKey 'PROD-ADM' -Credential (& $mk 'CONTOSO\a' 'A1!') -ConfigPath $Folder
            Set-SPSSecret -CredentialKey 'PPRD-ADM' -Credential (& $mk 'CONTOSO\b' 'B1!') -ConfigPath $Folder

            $file = Join-Path -Path $Folder -ChildPath 'secrets.psd1'
            ((Import-PowerShellDataFile $file).Keys | Sort-Object) | Should -Be @('PPRD-ADM', 'PROD-ADM')

            Set-SPSSecret -CredentialKey 'PROD-ADM' -ConfigPath $Folder -Remove
            ((Import-PowerShellDataFile $file).Keys | Sort-Object) | Should -Be @('PPRD-ADM')
            # the surviving entry still decrypts
            (Get-SPSSecret -CredentialKey 'PPRD-ADM' -ConfigPath $Folder).GetNetworkCredential().Password |
                Should -Be 'B1!'
        }
    }

    It 'throws when the PasswordSecure value is still a placeholder' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'cfg-placeholder'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        @"
@{
    'PROD-ADM' = @{
        Username       = 'CONTOSO\svc'
        PasswordSecure = 'PASTE-ConvertFrom-SecureString-OUTPUT-HERE'
    }
}
"@ | Set-Content -Path (Join-Path -Path $folder -ChildPath 'secrets.psd1')
        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            { Get-SPSSecret -CredentialKey 'PROD-ADM' -ConfigPath $Folder } | Should -Throw '*PasswordSecure*'
        }
    }
}
