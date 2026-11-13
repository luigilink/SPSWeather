# Contract tests for the SPSWeather.ps1 entry script parameters.

Describe 'Entry script -Action contract' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errs)
        $script:entryParams = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
    }

    It 'parses without errors (a malformed string would only fail at run time)' {
        $tokens = $null; $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errs) | Out-Null
        @($errs).Count | Should -Be 0
    }

    It 'exposes an -Action parameter' {
        $entryParams | Should -Contain 'Action'
    }

    It 'no longer exposes -Install or -Uninstall switches' {
        $entryParams | Should -Not -Contain 'Install'
        $entryParams | Should -Not -Contain 'Uninstall'
    }
}

Describe 'Entry script email settings (SMTPEnabled / SMTPPreview)' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
        $script:entrySource = Get-Content -Path $entryPath -Raw
        $tokens = $null; $errs = $null
        $script:entryAst = [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errs)
    }

    It 'keeps -EnableSmtp as a switch for backward compatibility' {
        $param = $entryAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'EnableSmtp' }
        $param | Should -Not -BeNullOrEmpty
        $param.StaticType.Name | Should -Be 'SwitchParameter'
    }

    It 'documents -EnableSmtp as deprecated in favor of SMTPEnabled' {
        $entrySource | Should -Match '(?s)\.PARAMETER EnableSmtp\s+DEPRECATED.*SMTPEnabled'
    }

    It 'resolves the email behavior once through Resolve-SPSSmtpSetting and shows its messages' {
        $entrySource | Should -Match '\$smtpSetting = Resolve-SPSSmtpSetting -Config \$envCfg -EnableSmtp:\$EnableSmtp'
        $entrySource | Should -Match 'foreach \(\$smtpMessage in \$smtpSetting\.Messages\)'
    }

    It 'no longer lets the switch drive the sending directly' {
        $entrySource | Should -Match 'if \(\$smtpSetting\.Send\)'
        $entrySource | Should -Not -Match 'if \(\$EnableSmtp\)'
    }

    It 'only appends the deprecated -EnableSMTP switch to the scheduled task when SMTPEnabled is not defined' {
        $entrySource | Should -Match "(?s)if \(-not \`$smtpSetting\.ConfigDefinesEnabled\) \{\s*\`$taskArguments \+= ' -EnableSMTP'"
        $entrySource | Should -Match 'Add-SPSSheduledTask .*-ActionArguments \$taskArguments'
        $entrySource | Should -Not -Match 'ConfigFile \$\(\$ConfigFile\) -EnableSMTP"'
    }

    It 'writes the email preview next to the JSON snapshot, before any send attempt' {
        $entrySource | Should -Match '(?s)if \(\$smtpSetting\.Preview\) \{.*?-mail\.html.*?Set-Content -Path \$mailPreviewFile -Value \$mailHTMLBody.*?\}.*?if \(\$smtpSetting\.Send\)'
        $entrySource | Should -Match '\$mailPreviewFile = Join-Path -Path \$pathResultsFolder -ChildPath \(\$farmStem \+ ''-mail\.html''\)'
    }
}

