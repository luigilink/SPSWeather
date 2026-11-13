# Tests for the example environment config and secrets templates.

Describe 'Example configuration (config.psd1)' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $cfgPath = Join-Path -Path $repoRoot -ChildPath 'src/Config/CONTOSO-PROD.example.psd1'
        $cfg = Import-PowerShellDataFile -Path $cfgPath
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

Describe 'Example secrets file (secrets.example.psd1)' {
    BeforeAll {
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
