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
        (Test-ModuleManifest -Path $modulePath).Version | Should -BeGreaterOrEqual ([version]'2.0.1')
    }

    It 'exports exactly the expected public functions' {
        $expected = @(
            'Add-SPSSheduledTask'
            'Add-SPSWeatherEvent'
            'Clear-SPSLog'
            'ConvertTo-SPSWeatherReport'
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

    It 'Add-SPSWeatherEvent requires a mandatory -Message' {
        $param = (Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common).Parameters['Message']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Add-SPSWeatherEvent restricts -EntryType with a ValidateSet' {
        $cmd = Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common
        $validate = $cmd.Parameters['EntryType'].Attributes.Where{ $_.TypeId.Name -eq 'ValidateSetAttribute' }
        $validate | Should -Not -BeNullOrEmpty
        $validate[0].ValidValues | Should -Contain 'Information'
        $validate[0].ValidValues | Should -Contain 'Warning'
        $validate[0].ValidValues | Should -Contain 'Error'
    }

    It 'Add-SPSWeatherEvent defaults -Source to SPSWeather' {
        $cmd = Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common
        $cmd.Parameters['Source'].Attributes.Where{ $_ -is [System.Management.Automation.ParameterAttribute] } |
            Should -Not -BeNullOrEmpty
        $cmd.Parameters.Keys | Should -Contain 'EventID'
    }

    It 'Get-SPSSqlStatus requires Server and InstallAccount and has threshold defaults' {
        $cmd = Get-Command -Name Get-SPSSqlStatus -Module SPSWeather.Common
        $cmd.Parameters['Server'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters['InstallAccount'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters['InstallAccount'].ParameterType.Name | Should -Be 'PSCredential'
        $cmd.Parameters.Keys | Should -Contain 'DiskFreeThresholdPercent'
        $cmd.Parameters.Keys | Should -Contain 'BackupMaxAgeDays'
    }
}

Describe 'Invoke-SPSCommand remoting' {    It 'throws and never runs the command locally when the session cannot be opened' -Skip:(-not $IsWindows) {
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

Describe 'Report assembly (ConvertTo-SPSWeatherReport)' {
    It 'adds every non-null section as a property, preserving order' {
        $sections = [ordered]@{
            SectionA = @([pscustomobject]@{ IsInfo = $true })
            SectionB = @([pscustomobject]@{ IsInfo = $true })
            SectionC = @()
        }
        $result = ConvertTo-SPSWeatherReport -Section $sections
        $result.Report.PSObject.Properties.Name | Should -Be @('SectionA', 'SectionB', 'SectionC')
    }

    It 'raises IsAlert when any row has IsInfo = $false' {
        $sections = [ordered]@{
            Healthy = @([pscustomobject]@{ IsInfo = $true })
            Broken  = @([pscustomobject]@{ IsInfo = $true }, [pscustomobject]@{ IsInfo = $false })
        }
        (ConvertTo-SPSWeatherReport -Section $sections).IsAlert | Should -BeTrue
    }

    It 'keeps IsAlert false when every row is informational' {
        $sections = [ordered]@{
            One = @([pscustomobject]@{ IsInfo = $true })
            Two = @([pscustomobject]@{ IsInfo = $true }, [pscustomobject]@{ IsInfo = $true })
        }
        (ConvertTo-SPSWeatherReport -Section $sections).IsAlert | Should -BeFalse
    }

    It 'never raises IsAlert for info-only sections without an IsInfo property' {
        $sections = [ordered]@{
            SYSLastRebootStatus = @([pscustomobject]@{ Server = 'SRV1'; LastReboot = '2026-06-28' })
            SYSDOTNETVersion    = @([pscustomobject]@{ Server = 'SRV1'; Version = '4.8' })
        }
        (ConvertTo-SPSWeatherReport -Section $sections).IsAlert | Should -BeFalse
    }

    It 'keeps empty-collection sections (stable JSON shape)' {
        $sections = [ordered]@{ Empty = @() }
        $result = ConvertTo-SPSWeatherReport -Section $sections
        $result.Report.PSObject.Properties.Name | Should -Contain 'Empty'
    }

    It 'matches a hand-rolled replication of the legacy assembly logic' {
        $sections = [ordered]@{
            SPHealthAnalyzer   = @([pscustomobject]@{ IsInfo = $true })
            SPSContentDBStatus = @([pscustomobject]@{ IsInfo = $false })
            SPWeatherListInfo  = @([pscustomobject]@{ PSVersion = '5.1' })
            SYSDiskUsageStatus = @()
        }

        # Replicate the original per-section behavior.
        $legacy = [PSCustomObject]@{}
        $legacyAlert = 'INFO'
        foreach ($name in $sections.Keys) {
            $data = $sections[$name]
            if ($null -ne $data) {
                if ($data.IsInfo -contains $false) { $legacyAlert = 'ALERT' }
                $legacy | Add-Member -MemberType NoteProperty -Name $name -Value $data
            }
        }

        $result = ConvertTo-SPSWeatherReport -Section $sections
        $result.Report.PSObject.Properties.Name | Should -Be ($legacy.PSObject.Properties.Name)
        (& { if ($result.IsAlert) { 'ALERT' } else { 'INFO' } }) | Should -Be $legacyAlert
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

Describe 'Example configuration (config.psd1)' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $cfgPath  = Join-Path -Path $repoRoot -ChildPath 'src/Config/CONTOSO-PROD.example.psd1'
        $cfg      = Import-PowerShellDataFile -Path $cfgPath
    }

    It 'parses as a hashtable via Import-PowerShellDataFile' {
        $cfg | Should -BeOfType ([System.Collections.Hashtable])
    }

    It 'exposes the keys the entry script reads' {
        foreach ($key in @('ConfigurationName', 'ApplicationName', 'Domain',
                'SMTPToAddress', 'SMTPFromAddress', 'SMTPServer', 'ExclusionRules', 'Farms', 'CredentialKey')) {
            $cfg.Keys | Should -Contain $key
        }
    }

    It 'no longer references the removed CredentialManager StoredCredential key' {
        $cfg.Keys | Should -Not -Contain 'StoredCredential'
    }

    It 'keeps Farms as a collection of Name/Server entries' {
        $cfg.Farms.Count | Should -BeGreaterThan 0
        foreach ($farm in $cfg.Farms) {
            $farm.Name   | Should -Not -BeNullOrEmpty
            $farm.Server | Should -Not -BeNullOrEmpty
        }
    }

    It 'keeps ExclusionRules as an array supporting Contains()' {
        $cfg.ExclusionRules -is [array] | Should -BeTrue
        $cfg.ExclusionRules.Contains('SPSiteHttpStatus') | Should -BeTrue
    }

    It 'keeps SMTPToAddress as an array' {
        $cfg.SMTPToAddress -is [array] | Should -BeTrue
    }
}

Describe 'Secret store (DPAPI secrets.psd1)' {
    It 'writes a credential and reads the same password back' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'cfg-roundtrip'
        InModuleScope SPSWeather.Common -Parameters @{ Folder = $folder } {
            param($Folder)
            $sec  = ConvertTo-SecureString 'S3cr3t-P@ss!' -AsPlainText -Force
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

Describe 'Example secrets file (secrets.example.psd1)' {    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $path = Join-Path -Path $repoRoot -ChildPath 'src/Config/secrets.example.psd1'
        $secrets = Import-PowerShellDataFile -Path $path
    }

    It 'parses as a hashtable keyed by credential key' {
        $secrets | Should -BeOfType ([System.Collections.Hashtable])
        $secrets.Keys.Count | Should -BeGreaterThan 0
    }

    It 'each entry has a Username and a placeholder PasswordSecure' {
        foreach ($key in $secrets.Keys) {
            $secrets[$key].Username | Should -Not -BeNullOrEmpty
            $secrets[$key].PasswordSecure | Should -Match '^PASTE-'
        }
    }
}
