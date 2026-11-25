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

    It 'shows the email configuration warnings after Start-Transcript so an unattended run keeps them' {
        $transcript = $entrySource.IndexOf('Start-Transcript -Path')
        $resolve = $entrySource.IndexOf('$smtpSetting = Resolve-SPSSmtpSetting')
        $transcript | Should -BeGreaterThan 0
        $resolve | Should -BeGreaterThan $transcript
    }

    It 'records the email configuration warnings in the Event Log (ID 2001) on runs' {
        $entrySource | Should -Match '(?s)foreach \(\$smtpMessage in \$smtpSetting\.Messages\) \{\s*Add-SPSWeatherEvent -Message "SPSWeather email configuration: \$smtpMessage" -EntryType ''Warning'' -EventID 2001'
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
        $entrySource | Should -Match '(?s)if \(\$smtpSetting\.Preview -and \$smtpSetting\.Mode -eq ''PerFarm''\) \{.*?-mail\.html.*?Set-Content -Path \$mailPreviewFile -Value \$mailHTMLBody.*?\}.*?if \(\$smtpSetting\.Send -and \$smtpSetting\.Mode -eq ''PerFarm''\)'
        $entrySource | Should -Match '\$mailPreviewFile = Join-Path -Path \$pathResultsFolder -ChildPath \(\$farmStem \+ ''-mail\.html''\)'
    }

    It 'resolves the display language after Start-Transcript and shows its warnings' {
        $transcript = $entrySource.IndexOf('Start-Transcript -Path')
        $resolve = $entrySource.IndexOf('$languageSetting = Resolve-SPSWeatherLanguage -Language $envCfg.Language')
        $transcript | Should -BeGreaterThan 0
        $resolve | Should -BeGreaterThan $transcript
        $entrySource | Should -Match 'foreach \(\$languageMessage in \$languageSetting\.Messages\) \{ Write-Warning -Message \$languageMessage \}'
    }

    It 'records an unavailable language in the Event Log (ID 2001) on runs' {
        $entrySource | Should -Match '(?s)foreach \(\$languageMessage in \$languageSetting\.Messages\) \{\s*Add-SPSWeatherEvent -Message "SPSWeather language configuration: \$languageMessage" -EntryType ''Warning'' -EventID 2001'
    }

    It 'passes the resolved culture to the dashboard and to the email' {
        $entrySource | Should -Match '(?s)Export-SPSWeatherReport -InputObject.*?-Language \$languageSetting\.Culture\)'
        $entrySource | Should -Match '(?s)ConvertTo-SPSWeatherEmailBody -InputObject.*?-Language \$languageSetting\.Culture'
    }

    It 'keeps the English severity tags in the email subject (inbox rules filter on them)' {
        $entrySource | Should -Match '\$farmAlert = ''ALERT''; \$farmPriority = ''High'''
        $entrySource | Should -Match '\$farmAlert = ''WARN''; \$farmPriority = ''Normal'''
        $entrySource | Should -Match '\$farmAlert = ''OK''; \$farmPriority = ''Normal'''
        $entrySource | Should -Match '\$mailSubject = "\[\$farmAlert\] \$Application/\$Environment/\$farmName - SPSWeather"'
    }

    Context 'EmailMode = Consolidated (one email for all the farms)' {
        It 'only builds, previews and sends the per-farm email in the PerFarm mode' {
            $entrySource | Should -Match '(?s)if \(\$smtpSetting\.Mode -eq ''PerFarm''\) \{\s*\$mailHTMLBody = ConvertTo-SPSWeatherEmailBody'
            $entrySource | Should -Match 'if \(\$smtpSetting\.Preview -and \$smtpSetting\.Mode -eq ''PerFarm''\)'
            $entrySource | Should -Match 'if \(\$smtpSetting\.Send -and \$smtpSetting\.Mode -eq ''PerFarm''\)'
        }

        It 'keeps the outcome and the Event Log entries of every farm in both modes' {
            $perFarm = $entrySource.IndexOf('if ($smtpSetting.Mode -eq ''PerFarm'') {')
            $events = $entrySource.IndexOf('EventID 2000')
            $events | Should -BeGreaterThan $perFarm
            $entrySource | Should -Match '(?s)if \(\$farmResult\.IsAlert\) \{\s*Add-SPSWeatherEvent -Message "SPSWeather outcome'
        }

        It 'registers an entry for a farm that cannot be reached, before skipping it, so it is not left out' {
            $entrySource | Should -Match '(?s)-EventID 3001\s*\$consolidatedEntries\["\$\(\$spFarm\.Name\)"\] = \[PSCustomObject\]@\{ Name = "\$\(\$spFarm\.Name\)"; Server = "\$\(\$spFarm\.Server\)"; Reachable = \$false \}\s*continue'
        }

        It 'registers an entry for each farm that was reached, before rendering, so a render failure cannot drop it' {
            $entry = $entrySource.IndexOf('$consolidatedEntries[$farmName] = [PSCustomObject]@{ Name = $farmName')
            $try = $entrySource.IndexOf('try {', $entry)
            $entry | Should -BeGreaterThan 0
            $try | Should -BeGreaterThan $entry
            $entrySource | Should -Match 'Reachable = \$true; Report = \$farmJson; Summary = \$farmResult\.Summary; DashboardUrl = \$dashUrl'
        }

        It 'computes the dashboard URL once, before the entry and the per-farm email use it' {
            ([regex]::Matches($entrySource, '\$dashUrl = if \(\$dashBaseUrl\)')).Count | Should -Be 1
            $entrySource.IndexOf('$dashUrl = if ($dashBaseUrl)') | Should -BeLessThan $entrySource.IndexOf('$consolidatedEntries[$farmName]')
        }

        It 'builds the single email after the loop over the farms and before the log cleanup' {
            $loop = $entrySource.IndexOf('foreach ($farmName in @($probedFarms))')
            $block = $entrySource.IndexOf('ConvertTo-SPSWeatherConsolidatedEmail -FarmResult $consolidatedInput')
            $clean = $entrySource.IndexOf('Clear-SPSLog -path')
            $loop | Should -BeGreaterThan 0
            $block | Should -BeGreaterThan $loop
            $clean | Should -BeGreaterThan $block
        }

        It 'follows the order of the configuration and passes the display language' {
            $entrySource | Should -Match '\$consolidatedInput = @\(\$spFarms \| ForEach-Object -Process \{ \$consolidatedEntries\["\$\(\$_\.Name\)"\] \}'
            $entrySource | Should -Match '(?s)ConvertTo-SPSWeatherConsolidatedEmail -FarmResult \$consolidatedInput.*?-Language \$languageSetting\.Culture'
        }

        It 'only runs when the mode is Consolidated and an email is wanted (preview or send)' {
            $entrySource | Should -Match 'if \(\$smtpSetting\.Mode -eq ''Consolidated'' -and \(\$smtpSetting\.Preview -or \$smtpSetting\.Send\)\)'
        }

        It 'writes the preview to Results\<App>-<Env>-mail.html, before any send attempt' {
            $entrySource | Should -Match '\$mailPreviewFile = Join-Path -Path \$pathResultsFolder -ChildPath \("\$\(\$Application\)-\$\(\$Environment\)-mail\.html"\)'
            $entrySource | Should -Match '(?s)if \(\$smtpSetting\.Preview\) \{\s*\$mailPreviewFile = Join-Path -Path \$pathResultsFolder -ChildPath \("\$\(\$Application\)-\$\(\$Environment\)-mail\.html"\).*?Set-Content -Path \$mailPreviewFile -Value \$consolidatedMail\.Body.*?if \(\$smtpSetting\.Send\) \{\s*\$SmtpToAddress'
        }

        It 'sends the single email with the subject and the priority computed by the function' {
            $entrySource | Should -Match '(?s)Send-MailMessage -To \$SmtpToAddress `\s*-From \$SmtpFromAddress `\s*-Subject \$consolidatedMail\.Subject `\s*-Body \$consolidatedMail\.Body `.*?-Priority \$consolidatedMail\.Priority'
        }

        It 'records a failure to build or send the email in the Event Log (ID 3000) without stopping the run' {
            $entrySource | Should -Match '(?s)catch \{\s*Write-Output \$_\s*Add-SPSWeatherEvent -Message "SPSWeather failed to produce the consolidated email.*?-EventID 3000'
        }
    }
}
