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
            'Get-SPSWeatherHistory'
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
        foreach ($name in @('Invoke-SPSCommand', 'ConvertFrom-SPSSqlAliasValue', 'Get-SPSWeatherRowSeverity')) {
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

    It 'Add-SPSSheduledTask exposes an optional -Description parameter' {
        $param = (Get-Command -Name Add-SPSSheduledTask -Module SPSWeather.Common).Parameters['Description']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeFalse
    }

    It 'Add-SPSSheduledTask creates or updates the task (mode 6, no silent skip)' {
        $src = (Get-Command -Name Add-SPSSheduledTask -Module SPSWeather.Common).Definition
        $src | Should -Match 'RegisterTaskDefinition\([^)]*6,'
        $src | Should -Not -Match 'already exists - skipping'
        $src | Should -Match 'throw'
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

    It 'Add-SPSWeatherEvent self-heals a misrouted source instead of returning silently' {
        $src = (Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common).Definition
        $src | Should -Match 'DeleteEventSource'
        $src | Should -Not -Match '\[ERROR\] Specified source'
    }

    It 'Get-SPSInstalledProductVersion returns null off a SharePoint server' -Skip:($IsWindows -and (Test-Path 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions')) {
        Get-SPSInstalledProductVersion | Should -BeNullOrEmpty
    }

    It 'Import-SPSSharePointCommand throws when SharePoint is not installed' -Skip:($IsWindows -and (Test-Path 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions')) {
        { Import-SPSSharePointCommand -ErrorAction Stop } | Should -Throw '*SharePoint is not installed*'
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

Describe 'Readiness script (Test-SPSWeatherReadiness.ps1)' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'src/Test-SPSWeatherReadiness.ps1'
    }

    It 'exists next to the entry script' {
        Test-Path -Path $scriptPath | Should -BeTrue
    }

    It 'parses without errors' {
        $tokens = $null; $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs) | Out-Null
        $errs | Should -BeNullOrEmpty
    }

    It 'declares a mandatory -ConfigFile parameter' {
        $cmd = Get-Command -Name $scriptPath
        $cmd.Parameters.Keys | Should -Contain 'ConfigFile'
        $cmd.Parameters['ConfigFile'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters.Keys | Should -Contain 'SkipNetwork'
        $cmd.Parameters.Keys | Should -Contain 'SkipSharePoint'
        $cmd.Parameters.Keys | Should -Contain 'TimeoutSeconds'
    }

    It 'is stored as UTF-8 with BOM' {
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
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

Describe 'SQL alias parsing (ConvertFrom-SPSSqlAliasValue)' {
    It 'parses a TCP alias with instance and port' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPSQL' -RawValue 'DBMSSOCN,SQLPROD01\SP,1433'
            $r.Protocol | Should -Be 'TCP'
            $r.Server   | Should -Be 'SQLPROD01'
            $r.Instance | Should -Be 'SP'
            $r.Port     | Should -Be '1433'
        }
    }

    It 'parses a default-instance TCP alias without a port' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPDEF' -RawValue 'DBMSSOCN,SQLPROD02'
            $r.Protocol | Should -Be 'TCP'
            $r.Server   | Should -Be 'SQLPROD02'
            $r.Instance | Should -BeNullOrEmpty
            $r.Port     | Should -BeNullOrEmpty
        }
    }

    It 'parses a named-pipes alias' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPNP' -RawValue 'DBNMPNTW,\\SQLPROD03\pipe\MSSQL$SP\sql\query'
            $r.Protocol | Should -Be 'NamedPipes'
            $r.Server   | Should -Be 'SQLPROD03'
            $r.Instance | Should -Be 'SP'
        }
    }

    It 'does not throw on an empty value' {
        InModuleScope SPSWeather.Common {
            $r = ConvertFrom-SPSSqlAliasValue -AliasName 'SPBAD' -RawValue ''
            $r.Alias    | Should -Be 'SPBAD'
            $r.Protocol | Should -Be 'Unknown'
        }
    }
}

Describe 'Report assembly (ConvertTo-SPSWeatherReport)' {    It 'adds every non-null section as a property, preserving order' {
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

Describe 'Short alert email (ConvertTo-SPSWeatherEmailBody)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPAPIHttpStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }
        )
        $report | Add-Member -MemberType NoteProperty -Name SPHealthAnalyzer -Value @(
            [PSCustomObject]@{ farm = 'CONTENT'; title = 'STS not available'; severity = '2 - Warning'; category = 'Availability' }
        )
        $summary = [PSCustomObject]@{ Ok = 10; Alert = 2 }
        $html = ConvertTo-SPSWeatherEmailBody -InputObject $report -Summary $summary -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Version '3.1.0' -ExecutedBy 'DOM\jc' -Duration '00:04:31' -DashboardUrl 'https://pull/sp/zebes-PROD-CONTENT-dashboard.html'
    }

    It 'returns a single self-contained HTML document string' {
        $html | Should -BeOfType ([System.String])
        $html.StartsWith('<!DOCTYPE html>') | Should -BeTrue
        $html.TrimEnd().EndsWith('</html>') | Should -BeTrue
    }

    It 'keeps the Outlook MSO conditional comment' {
        $html | Should -Match '\[if mso\]'
    }

    It 'lists only the items needing attention, grouped by area' {
        $html | Should -Match 'Search'
        $html | Should -Match 'Health Analyzer'
        $html | Should -Match 'Search REST'
    }

    It 'omits healthy rows from the alert list' {
        $html | Should -Not -Match '>Root<'
    }

    It 'renders the CTA button pointing at the dashboard URL' {
        $html | Should -Match 'zebes-PROD-CONTENT-dashboard\.html'
        $html | Should -Match 'Open full dashboard'
    }

    It 'does not double-encode the middot separator' {
        $html | Should -Not -Match '&amp;middot;'
    }
}

Describe 'Dashboard renderer (Export-SPSWeatherReport)' {
    BeforeAll {
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPAPIHttpStatus -Value @(
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }
            [PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true }
        )
        $history = @(
            [PSCustomObject]@{ Date = '06-01'; Ok = 12; Warn = 0; Fail = 1 }
            [PSCustomObject]@{ Date = '06-02'; Ok = 11; Warn = 1; Fail = 2 }
        )
        $tmp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsw-" + [guid]::NewGuid().ToString('N') + '.html')
        $result = Export-SPSWeatherReport -InputObject $report -OutputFile $tmp -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Version '3.1.0' -ExecutedBy 'DOM\jc' -Duration '00:04:31' -History $history
        $dash = Get-Content -Path $tmp -Raw
    }

    It 'returns the output file path and writes an HTML document' {
        $result | Should -Match 'spsw-.*\.html$'
        $dash.StartsWith('<!DOCTYPE html>') | Should -BeTrue
    }

    It 'renders the history chart bars (past runs + current)' {
        ([regex]::Matches($dash, 'class="bcol')).Count | Should -BeGreaterOrEqual 3
        $dash | Should -Match 'class="bcol now"'
    }

    It 'renders an area card for the failing section' {
        $dash | Should -Match 'Trust Farm'
    }
}


Describe 'CredSSP client setup (Set-SPSCredSSPClient)' {
    It 'is Windows-only: returns $false and warns off Windows' -Skip:($IsWindows) {
        $warn = $null
        $result = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com' -WarningVariable warn -WarningAction SilentlyContinue
        $result | Should -BeFalse
        $warn | Should -Not -BeNullOrEmpty
    }

    Context 'on Windows' -Skip:(-not $IsWindows) {
        BeforeAll {
            Mock -ModuleName SPSWeather.Common -CommandName Get-Item -MockWith { [PSCustomObject]@{ Value = 'false'; SourceOfValue = '' } }
            Mock -ModuleName SPSWeather.Common -CommandName Set-Item -MockWith { }
            Mock -ModuleName SPSWeather.Common -CommandName Test-Path -MockWith { $true }
            Mock -ModuleName SPSWeather.Common -CommandName New-Item -MockWith { }
            Mock -ModuleName SPSWeather.Common -CommandName Get-ItemProperty -MockWith { $null }
            Mock -ModuleName SPSWeather.Common -CommandName New-ItemProperty -MockWith { }
        }

        It 'enables CredSSP client authentication' {
            $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com'
            Should -Invoke -ModuleName SPSWeather.Common -CommandName Set-Item -Times 1 -ParameterFilter { $Value -eq $true }
        }

        It 'adds a WSMAN/<fqdn> delegation SPN for each server' {
            $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com', 'app2.contoso.com'
            Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -ParameterFilter { $Value -eq 'WSMAN/app1.contoso.com' }
            Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -ParameterFilter { $Value -eq 'WSMAN/app2.contoso.com' }
        }

        It 'does not write anything under -WhatIf' {
            $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com' -WhatIf
            Should -Invoke -ModuleName SPSWeather.Common -CommandName Set-Item -Times 0
            Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -Times 0
        }
    }
}


Describe 'History series (Get-SPSWeatherHistory) callable from outside the module' {
    It 'is exported and resolves when called in the caller scope (not InModuleScope)' {
        # Regression guard: the entry script calls this from outside the module, so it
        # must be exported (it was previously private and threw "not recognized").
        Get-Command -Name Get-SPSWeatherHistory -Module SPSWeather.Common -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'builds the Ok/Warn/Fail series from snapshots when called directly' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'hist-ext'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        ([PSCustomObject]@{ S = @([PSCustomObject]@{ IsInfo = $true }, [PSCustomObject]@{ IsInfo = $false }) }) |
            ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path -Path $folder -ChildPath 'a-20260101-0000.json')
        $series = @(Get-SPSWeatherHistory -HistoryFolder $folder)
        $series.Count | Should -Be 1
        $series[0].Ok | Should -Be 1
        $series[0].Fail | Should -Be 1
    }
}


Describe 'Severity model (Get-SPSWeatherRowSeverity)' {
    It 'classifies IsInfo = $false as fail' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $false }) | Should -Be 'fail'
        }
    }

    It 'classifies a healthy IsInfo = $true row as ok' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true }) | Should -Be 'ok'
        }
    }

    It 'treats an IsInfo = $true row carrying an advisory Recommendation as warn' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true; Recommendation = 'MAXDOP should be 1' }) | Should -Be 'warn'
        }
    }

    It 'treats an IsInfo = $true alias row with a Note as warn' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true; Note = 'alias defined only in 64-bit' }) | Should -Be 'warn'
        }
    }

    It 'maps Health Analyzer severity strings (no IsInfo) to warn/fail' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ severity = '2 - Warning' }) | Should -Be 'warn'
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ severity = '1 - Error' }) | Should -Be 'fail'
        }
    }

    It 'treats an Unreachable row with no IsInfo as fail' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ Server = 'SRV1'; OSName = 'Unreachable' }) | Should -Be 'fail'
        }
    }

    It 'returns ok for a pure info row and for $null' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ Server = 'SRV1'; Version = '4.8' }) | Should -Be 'ok'
            Get-SPSWeatherRowSeverity -Row $null | Should -Be 'ok'
        }
    }
}

Describe 'Report outcome via shared severity (ConvertTo-SPSWeatherReport)' {
    It 'reports Ok/Warn/Fail counts and raises IsAlert on warnings only' {
        $sections = [ordered]@{
            Health = @([PSCustomObject]@{ severity = '2 - Warning' })
            Disk   = @([PSCustomObject]@{ IsInfo = $true })
        }
        $r = ConvertTo-SPSWeatherReport -Section $sections
        $r.Summary.Warn | Should -Be 1
        $r.Summary.Fail | Should -Be 0
        $r.Summary.Ok | Should -Be 1
        $r.IsAlert | Should -BeTrue
    }

    It 'counts an advisory IsInfo = $true row as a warning' {
        $sections = [ordered]@{
            Sql = @([PSCustomObject]@{ IsInfo = $true; Recommendation = 'MAXDOP should be 1' })
        }
        $r = ConvertTo-SPSWeatherReport -Section $sections
        $r.Summary.Warn | Should -Be 1
        $r.Summary.Ok | Should -Be 0
    }

    It 'does not count pure info rows toward Ok' {
        $sections = [ordered]@{
            SYSLastRebootStatus = @([PSCustomObject]@{ Server = 'SRV1'; LastRebootTime = '2026-06-28' })
        }
        $r = ConvertTo-SPSWeatherReport -Section $sections
        $r.Summary.Ok | Should -Be 0
        $r.IsAlert | Should -BeFalse
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

Describe 'CredSSP GPO conflict detection (Set-SPSCredSSPClient)' -Skip:(-not (($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows)) {
    It 'does not overwrite the policy switches when a delegation policy is already enabled' {
        Mock -ModuleName SPSWeather.Common -CommandName Get-Item -MockWith { [PSCustomObject]@{ Value = 'false'; SourceOfValue = '' } }
        Mock -ModuleName SPSWeather.Common -CommandName Set-Item -MockWith { }
        Mock -ModuleName SPSWeather.Common -CommandName Test-Path -MockWith { $true }
        Mock -ModuleName SPSWeather.Common -CommandName New-Item -MockWith { }
        Mock -ModuleName SPSWeather.Common -CommandName Get-ItemProperty -MockWith { [PSCustomObject]@{ AllowFreshCredentials = 1 } }
        Mock -ModuleName SPSWeather.Common -CommandName New-ItemProperty -MockWith { }

        $warn = $null
        $null = Set-SPSCredSSPClient -DelegateComputer 'app1.contoso.com' -WarningVariable warn -WarningAction SilentlyContinue
        # The AllowFreshCredentials / ConcatenateDefaults switches must NOT be rewritten.
        Should -Invoke -ModuleName SPSWeather.Common -CommandName New-ItemProperty -Times 0 -ParameterFilter { $Name -eq 'AllowFreshCredentials' }
        (@($warn) -join "`n") | Should -Match 'already configured'
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

    It 'exposes the Dashboard block with OutputPath and Url keys' {
        $cfg.Keys | Should -Contain 'Dashboard'
        $cfg.Dashboard.Keys | Should -Contain 'OutputPath'
        $cfg.Dashboard.Keys | Should -Contain 'Url'
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

Describe 'Entry script -Action contract' {
    BeforeAll {
        $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
        $entryPath  = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errs)
        $script:entryParams = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
    }

    It 'exposes an -Action parameter' {
        $entryParams | Should -Contain 'Action'
    }

    It 'no longer exposes -Install or -Uninstall switches' {
        $entryParams | Should -Not -Contain 'Install'
        $entryParams | Should -Not -Contain 'Uninstall'
    }
}
