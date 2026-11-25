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
        $script:nullFlags = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    SMTPPreview = `$null"
        $script:nullEnabled = Invoke-Readiness -Extra "    SMTPEnabled = `$null"
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

    It 'fails a key written with a $null value instead of treating it as omitted' {
        (Get-CheckLine -Lines $nullFlags -Key 'SMTPPreview') | Should -Match '^\[FAIL\].*Must be'
        (Get-CheckLine -Lines $nullEnabled -Key 'SMTPEnabled') | Should -Match '^\[FAIL\].*Must be'
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

    Context 'Language' {
        BeforeAll {
            $script:langFr = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'fr-FR'"
            $script:langRegion = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'fr-BE'"
            $script:langUnknown = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'de-DE'"
            $script:langAuto = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'auto'"
            $script:langAbsent = Invoke-Readiness -Extra "    SMTPEnabled = `$false"
        }

        It 'reports an available language with the culture it resolves to' {
            (Get-CheckLine -Lines $langFr -Key 'Language') | Should -Match '^\[ OK \].*fr-FR'
            (Get-CheckLine -Lines $langRegion -Key 'Language') | Should -Match '^\[ OK \].*fr-FR'
        }

        It 'warns, never fails, for a language that is not available' {
            $line = Get-CheckLine -Lines $langUnknown -Key 'Language'
            $line | Should -Match '^\[WARN\]'
            $line | Should -Match "Language 'de-DE' is not available"
            ($langUnknown -join "`n") | Should -Not -Match "\[FAIL\]\s+Key 'Language'"
        }

        It "tells that 'auto' depends on the account that runs the task" {
            (Get-CheckLine -Lines $langAuto -Key 'Language') | Should -Match '^\[ OK \].*auto ->.*may differ'
        }

        It 'says nothing when no language is configured' {
            (Get-CheckLine -Lines $langAbsent -Key 'Language') | Should -BeNullOrEmpty
        }
    }
}
