# Tests for the Test-SPSWeatherReadiness.ps1 standalone script.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $scriptPath = Join-Path -Path $repoRoot -ChildPath 'src/Test-SPSWeatherReadiness.ps1'
}

Describe 'Readiness script (Test-SPSWeatherReadiness.ps1)' {
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

Describe 'Readiness script SMTP settings (SMTPEnabled / SMTPPreview)' {
    BeforeAll {
        # The script ends with `exit`, so it runs in a child process of the same PowerShell
        # edition, exactly like on the VM. Only the configuration checks are read.
        $script:hostExe = (Get-Process -Id $PID).Path

        function Invoke-Readiness {
            param([string]$Extra)
            $cfgPath = Join-Path -Path $TestDrive -ChildPath ('cfg-' + [guid]::NewGuid().ToString('N') + '.psd1')
            $body = @"
@{
    ConfigurationName = 'PROD'
    ApplicationName   = 'lab'
    Domain            = 'contoso.com'
    CredentialKey     = 'svc'
    Farms             = @( @{ Name = 'CONTENT'; Server = 'app1' } )
$Extra
}
"@
            Set-Content -Path $cfgPath -Value $body -Encoding UTF8
            $out = & $script:hostExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ConfigFile $cfgPath -SkipNetwork -SkipSharePoint 2>&1 | Out-String
            $out -split "`r?`n"
        }
        function Get-CheckLine {
            param([string[]]$Lines, [string]$Key)
            @($Lines | Where-Object { $_ -match "Key '$Key'" })[0]
        }

        $script:disabled = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    SMTPPreview = `$true"
        $script:enabledNoKeys = Invoke-Readiness -Extra "    SMTPEnabled = `$true"
        $script:invalid = Invoke-Readiness -Extra "    SMTPEnabled = 'maybe'"
        $script:legacy = Invoke-Readiness -Extra ''
        $script:emptyValues = Invoke-Readiness -Extra "    SMTPEnabled = `$true`n    SMTPToAddress = @()`n    SMTPFromAddress = '  '`n    SMTPServer = ''"
        $script:full = Invoke-Readiness -Extra "    SMTPEnabled = `$true`n    SMTPToAddress = @('a@b.c')`n    SMTPFromAddress = 'n@b.c'`n    SMTPServer = 'smtp'"
    }

    It 'does not require the SMTP relay settings when SMTPEnabled = $false (lab without relay)' {
        foreach ($key in 'SMTPToAddress', 'SMTPFromAddress', 'SMTPServer') {
            (Get-CheckLine -Lines $disabled -Key $key) | Should -Match '^\[SKIP\]'
        }
    }

    It 'reports both boolean keys as valid' {
        (Get-CheckLine -Lines $disabled -Key 'SMTPEnabled') | Should -Match '^\[ OK \]'
        (Get-CheckLine -Lines $disabled -Key 'SMTPPreview') | Should -Match '^\[ OK \]'
    }

    It 'requires the SMTP relay settings when SMTPEnabled = $true' {
        foreach ($key in 'SMTPToAddress', 'SMTPFromAddress', 'SMTPServer') {
            (Get-CheckLine -Lines $enabledNoKeys -Key $key) | Should -Match '^\[FAIL\]'
            (Get-CheckLine -Lines $full -Key $key) | Should -Match '^\[ OK \]'
        }
    }

    It 'treats empty SMTP values like the runtime does: missing' {
        foreach ($key in 'SMTPToAddress', 'SMTPFromAddress', 'SMTPServer') {
            (Get-CheckLine -Lines $emptyValues -Key $key) | Should -Match '^\[FAIL\]'
        }
    }

    It 'fails a non-boolean SMTPEnabled and keeps requiring the relay settings' {
        (Get-CheckLine -Lines $invalid -Key 'SMTPEnabled') | Should -Match '^\[FAIL\].*Must be'
        (Get-CheckLine -Lines $invalid -Key 'SMTPServer') | Should -Match '^\[FAIL\]'
    }

    It 'keeps requiring the relay settings for a legacy config without SMTPEnabled' {
        (Get-CheckLine -Lines $legacy -Key 'SMTPServer') | Should -Match '^\[FAIL\]'
        (Get-CheckLine -Lines $legacy -Key 'SMTPEnabled') | Should -BeNullOrEmpty
    }
}

