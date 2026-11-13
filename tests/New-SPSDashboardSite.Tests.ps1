# Tests for the standalone New-SPSDashboardSite.ps1 IIS provisioning script.
# Parameter/contract + text hygiene only (no SMB/IIS side effects here).

Describe 'New-SPSDashboardSite.ps1' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'src/New-SPSDashboardSite.ps1'
    }

    It 'exists at the src root' {
        Test-Path -Path $scriptPath | Should -BeTrue
    }

    It 'parses without errors' {
        $tokens = $null; $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs) | Out-Null
        $errs | Should -BeNullOrEmpty
    }

    It 'supports ShouldProcess and exposes the expected parameters' {
        $cmd = Get-Command -Name $scriptPath
        $cmd.Parameters.Keys | Should -Contain 'WhatIf'
        foreach ($p in @('Path', 'WriteAccounts', 'ShareName', 'SiteName', 'Port', 'ParentSite', 'AppAlias', 'SkipShare', 'SkipNtfs', 'SkipIis', 'Force')) {
            $cmd.Parameters.Keys | Should -Contain $p
        }
        $cmd.Parameters['Path'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'contains no leftover SPSUpdate references (adapted from the SPSUpdate original)' {
        $raw = Get-Content -Path $scriptPath -Raw
        # The provisioning target and examples must be SPSWeather-specific.
        $raw | Should -Not -Match 'inetpub\\spsupdate'
        $raw | Should -Not -Match "spsupdate\`$"
    }

    It 'is stored as UTF-8 with BOM' {
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }
}
