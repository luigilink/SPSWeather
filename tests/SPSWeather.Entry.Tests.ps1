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
        $entrySource | Should -Match '(?s)Export-SPSWeatherReport -InputObject.*?-Language \$languageSetting\.Culture [`\)]'
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

        It 'builds the list of entries from the real expression, whatever the shape of Farms (array, bare hashtable, several)' {
            $line = [regex]::Match($entrySource, '\$consolidatedInput = (@\(\$spFarms \| ForEach-Object[^\r\n]+\))').Groups[1].Value
            $line | Should -Not -BeNullOrEmpty
            $build = [scriptblock]::Create('param($spFarms, $consolidatedEntries) ' + $line)
            $entries = @{ A = 'entry A'; B = 'entry B' }

            $one = & $build @(@{ Name = 'A'; Server = 'sa' }) $entries
            @($one).Count | Should -Be 1
            @($one)[0] | Should -Be 'entry A'

            $bare = & $build @{ Name = 'A'; Server = 'sa' } $entries
            @($bare).Count | Should -Be 1
            @($bare)[0] | Should -Be 'entry A'

            $two = & $build @(@{ Name = 'B' }, @{ Name = 'A' }) $entries
            (@($two) -join ',') | Should -Be 'entry B,entry A'

            $missing = & $build @(@{ Name = 'A' }, @{ Name = 'Z' }) $entries
            (@($missing) -join ',') | Should -Be 'entry A'
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

Describe 'Entry script run journal' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
        $script:entrySource = Get-Content -Path $entryPath -Raw
    }

    It 'writes one record per run, into Results\<App>-<Env>.runs.json, before the log cleanup' {
        $call = $entrySource.IndexOf('Add-SPSWeatherRunJournalEntry -Path (Join-Path -Path $pathResultsFolder -ChildPath "$($Application)-$($Environment).runs.json")')
        $cleanup = $entrySource.IndexOf('Clear-SPSLog -path $pathLogsFolder')
        $call | Should -BeGreaterThan 0
        $cleanup | Should -BeGreaterThan $call
        ([regex]::Matches($entrySource, 'Add-SPSWeatherRunJournalEntry')).Count | Should -Be 1
    }

    It 'passes the run facts to the journal and keeps its size in line with the history retention' {
        $entrySource | Should -Match '(?s)Add-SPSWeatherRunJournalEntry .*?-Started \$DateStarted.*?-Version \$spsWeatherVersion.*?-Language \$languageSetting\.Culture.*?-EmailMode \$smtpSetting\.Mode.*?-Mail \$mailOutcome.*?-Farm \$journalFarms.*?-RetentionDays \(\[uint32\]\[math\]::Max\(0, \$jsonHistoryRetentionDays\)\)'
    }

    It 'lists every configured farm, the unreachable ones included, in configuration order' {
        $entrySource | Should -Match '\$journalFarms = @\(\$spFarms \| ForEach-Object -Process \{ \$consolidatedEntries\["\$\(\$_\.Name\)"\] \}'
        $entrySource | Should -Match "Outcome = 'unreachable'"
        $entrySource | Should -Match "Outcome = 'ok'; Ok = \`$_\.Summary\.Ok; Warn = \`$_\.Summary\.Warn; Fail = \`$_\.Summary\.Fail"
    }

    It 'names the journal so that no farm snapshot can ever have the same file name' -ForEach @('runs', 'RUNS', 'Runs', 'a.b', 'x y', 'runs.json') {
        # The snapshot of a farm is <App>-<Env>-<farm with every character outside A-Za-z0-9_- replaced by _>.json
        $entrySource | Should -Match ([regex]::Escape("`$safeFarm = (`$farmName -replace '[^A-Za-z0-9_-]', '_')"))
        $safeFarm = $_ -replace '[^A-Za-z0-9_-]', '_'
        "zebes-PROD-$safeFarm.json".ToLowerInvariant() | Should -Not -Be 'zebes-prod.runs.json'
    }

    It 'resolves the thresholds once, through Get-SPSWeatherRunSetting, so the run and its journal record agree' {
        ([regex]::Matches($entrySource, 'Get-SPSWeatherRunSetting')).Count | Should -Be 1
        $entrySource | Should -Match '\$runSetting = Get-SPSWeatherRunSetting -Config \$envCfg -ConfigFile \$ConfigFile'
        foreach ($pair in @(
                @{ Variable = 'sqlDiskThreshold'; Key = 'SQLDiskFreeThresholdPercent' }
                @{ Variable = 'sqlBackupMaxAge'; Key = 'SQLBackupMaxAgeDays' }
                @{ Variable = 'jsonHistoryRetentionDays'; Key = 'JsonHistoryRetentionDays' }
                @{ Variable = 'emailMaxItemsPerArea'; Key = 'EmailMaxItemsPerArea' }
                @{ Variable = 'logRetentionDays'; Key = 'LogRetentionDays' })) {
            $entrySource | Should -Match ('\$' + $pair.Variable + ' = \$runSetting\.Value\.' + $pair.Key + '\r?\n')
            # No second, inline reading of the same key: the journal could then record another value than the one used.
            $entrySource | Should -Not -Match ('\$envCfg\.' + $pair.Key)
        }
    }

    It 'shows the threshold messages in the transcript and records them in the Event Log (ID 2001)' {
        $entrySource | Should -Match 'foreach \(\$settingMessage in \$runSetting\.Messages\) \{ Write-Warning -Message \$settingMessage \}'
        $entrySource | Should -Match '(?s)foreach \(\$settingMessage in \$runSetting\.Messages\) \{\s*Add-SPSWeatherEvent -Message "SPSWeather configuration: \$settingMessage" -EntryType ''Warning'' -EventID 2001'
    }

    It 'also hands the record of the settings to the dashboard, which shows the SQL thresholds in its footer' {
        $entrySource | Should -Match '(?s)Export-SPSWeatherReport -InputObject.*?-Setting \$runSetting\.Record\b'
    }

    It 'hands the record of the settings, not the configuration, to the run journal' {
        $entrySource | Should -Match '(?s)Add-SPSWeatherRunJournalEntry .*?-Setting \$runSetting\.Record'
        $entrySource | Should -Not -Match '-Setting \$envCfg'
    }

    It 'reads the bars of a farm from the archives of its own application and environment only' {
        $entrySource | Should -Match 'Get-SPSWeatherHistory -HistoryFolder \$farmHistFolder -NamePrefix "\$farmStem-" -Max \$historyBars'
        $entrySource | Should -Match '\$farmStem = "\$\(\$Application\)-\$\(\$Environment\)-\$\(\$safeFarm\)"'
    }

    It 'counts an email as sent only after Send-MailMessage succeeded' {
        ([regex]::Matches($entrySource, '(?s)-ea stop\s+\$mailsSent\+\+\s+Write-Output "Email sent successfully')).Count | Should -Be 2
    }

    Context 'mail outcome' {
        BeforeAll {
            $match = [regex]::Match($entrySource, '(?s)(\$mailExpected = .*?)\r?\n\s*\$journalFarms')
            $script:outcomeSnippet = $match.Groups[1].Value
            function script:Get-Outcome {
                param ($Setting, $Probed, $Entries, $Sent)
                & {
                    param ($smtpSetting, $probedFarms, $consolidatedEntries, $mailsSent, $snippet)
                    Invoke-Expression -Command $snippet
                    $mailOutcome
                } $Setting $Probed $Entries $Sent $outcomeSnippet
            }
        }

        It 'finds the outcome logic in the entry script' {
            $outcomeSnippet | Should -Match '\$mailOutcome = '
        }

        It 'reports <Expected> for <Name>' -ForEach @(
            @{ Name = 'email disabled'; Setting = @{ Send = $false; Preview = $false; Mode = 'PerFarm' }; Probed = @('A', 'B'); Entries = @{ A = 1; B = 1 }; Sent = 0; Expected = 'disabled' }
            @{ Name = 'preview only'; Setting = @{ Send = $false; Preview = $true; Mode = 'PerFarm' }; Probed = @('A'); Entries = @{ A = 1 }; Sent = 0; Expected = 'preview' }
            @{ Name = 'every farm unreachable in PerFarm (no email to send)'; Setting = @{ Send = $true; Preview = $false; Mode = 'PerFarm' }; Probed = @(); Entries = @{ A = 1 }; Sent = 0; Expected = 'none' }
            @{ Name = 'one email per farm, all sent'; Setting = @{ Send = $true; Preview = $false; Mode = 'PerFarm' }; Probed = @('A', 'B', 'C'); Entries = @{ A = 1; B = 1; C = 1 }; Sent = 3; Expected = 'sent' }
            @{ Name = 'one email per farm, one missing'; Setting = @{ Send = $true; Preview = $false; Mode = 'PerFarm' }; Probed = @('A', 'B', 'C'); Entries = @{ A = 1; B = 1; C = 1 }; Sent = 2; Expected = 'failed' }
            @{ Name = 'one consolidated email, sent (unreachable farms included)'; Setting = @{ Send = $true; Preview = $false; Mode = 'Consolidated' }; Probed = @('A'); Entries = @{ A = 1; B = 1; C = 1 }; Sent = 1; Expected = 'sent' }
            @{ Name = 'one consolidated email, not sent'; Setting = @{ Send = $true; Preview = $false; Mode = 'Consolidated' }; Probed = @('A'); Entries = @{ A = 1; B = 1 }; Sent = 0; Expected = 'failed' }
            @{ Name = 'send and preview together, sent'; Setting = @{ Send = $true; Preview = $true; Mode = 'PerFarm' }; Probed = @('A'); Entries = @{ A = 1 }; Sent = 1; Expected = 'sent' }
            @{ Name = 'sending requested but a relay setting is missing (Send turned off)'; Setting = @{ Send = $false; SendRequested = $true; Preview = $false; Mode = 'PerFarm' }; Probed = @('A'); Entries = @{ A = 1 }; Sent = 0; Expected = 'failed' }
            @{ Name = 'sending requested but a relay setting is missing, with a preview'; Setting = @{ Send = $false; SendRequested = $true; Preview = $true; Mode = 'Consolidated' }; Probed = @('A'); Entries = @{ A = 1 }; Sent = 0; Expected = 'failed' }
            @{ Name = 'sending not requested, preview only'; Setting = @{ Send = $false; SendRequested = $false; Preview = $true; Mode = 'PerFarm' }; Probed = @('A'); Entries = @{ A = 1 }; Sent = 0; Expected = 'preview' }
        ) {
            Get-Outcome -Setting ([PSCustomObject]$Setting) -Probed $Probed -Entries $Entries -Sent $Sent | Should -Be $Expected
        }
    }
}

Describe 'Entry script cockpit page (Dashboard.Cockpit)' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
        $script:entrySource = Get-Content -Path $entryPath -Raw
        $script:call = $entrySource.IndexOf('Export-SPSWeatherCockpit -OutputFile')
    }

    It 'resolves the setting once, through Resolve-SPSCockpitSetting, with the other settings and shows its messages in the transcript' {
        ([regex]::Matches($entrySource, 'Resolve-SPSCockpitSetting')).Count | Should -Be 1
        $entrySource | Should -Match '\$cockpitSetting = Resolve-SPSCockpitSetting -Config \$envCfg -Application \$Application -Environment \$Environment -ResultsFolder \$pathResultsFolder'
        $entrySource | Should -Match 'foreach \(\$cockpitMessage in \$cockpitSetting\.Messages\) \{ Write-Warning -Message \$cockpitMessage \}'
        $entrySource.IndexOf('Resolve-SPSCockpitSetting') | Should -BeGreaterThan $entrySource.IndexOf('Get-SPSWeatherRunSetting -Config')
    }

    It 'records an invalid value in the Event Log (ID 2001), like the other configuration warnings' {
        $entrySource | Should -Match '(?s)foreach \(\$cockpitMessage in \$cockpitSetting\.Messages\) \{\s*Add-SPSWeatherEvent -Message "SPSWeather cockpit configuration: \$cockpitMessage" -EntryType ''Warning'' -EventID 2001'
    }

    It 'produces the page once, and only when the key is on' {
        ([regex]::Matches($entrySource, 'Export-SPSWeatherCockpit')).Count | Should -Be 1
        $entrySource | Should -Match '(?s)if \(\$cockpitSetting\.Enabled\) \{\s*try \{\s*\$cockpitFile = Export-SPSWeatherCockpit'
    }

    It 'produces the page after the emails and after the run journal (so that it shows this run and never delays an alert), before the log cleanup' {
        $mails = $entrySource.IndexOf('Sending the consolidated Email')
        $perFarmMail = $entrySource.IndexOf('Send-MailMessage')
        $journal = $entrySource.IndexOf('Add-SPSWeatherRunJournalEntry -Path')
        $cleanup = $entrySource.IndexOf('Clear-SPSLog -path $pathLogsFolder')
        $mails | Should -BeGreaterThan 0
        $call | Should -BeGreaterThan $perFarmMail
        $call | Should -BeGreaterThan $mails
        $call | Should -BeGreaterThan $journal
        $cleanup | Should -BeGreaterThan $call
    }

    It 'gives the function the facts of the run: the page path, Results, the names, the configured farms, the retention, the language and the version' {
        $block = $entrySource.Substring($call, 700)
        $block | Should -Match '-OutputFile \$cockpitSetting\.Path'
        $block | Should -Match '-ResultsFolder \$pathResultsFolder'
        $block | Should -Match '-Application \$Application'
        $block | Should -Match '-Environment \$Environment'
        $block | Should -Match '-FarmName @\(\$spFarms \| ForEach-Object -Process \{ "\$\(\$_\.Name\)" \}\)'
        $block | Should -Match '-RetentionDays \(\[uint32\]\[math\]::Max\(0, \$jsonHistoryRetentionDays\)\)'
        $block | Should -Match '-Language \$languageSetting\.Culture'
        $block | Should -Match '-Version \$spsWeatherVersion'
    }

    It 'never fails the run: an error is written and recorded in the Event Log (ID 3002) and the run goes on' {
        $entrySource | Should -Match '(?s)catch \{\s*Write-Output \$_\s*Add-SPSWeatherEvent -Message "SPSWeather failed to produce the cockpit page for \$Application/\$Environment\. Exception: \$\(\$_\.Exception\.Message\)" -EntryType ''Error'' -EventID 3002'
        $afterCatch = $entrySource.Substring($entrySource.IndexOf('-EventID 3002'), 200)
        $afterCatch | Should -Match 'Clear-SPSLog'
    }

    It 'gives the consolidated email the address of the page only when the page is produced' {
        $entrySource | Should -Match '-CockpitUrl \$\(if \(\$cockpitSetting\.Enabled\) \{ \$cockpitSetting\.Url \} else \{ '''' \}\)'
    }

    It 'leaves the per-farm email without any mention of the cockpit, and gives the dashboard only the link arguments' {
        $perFarm = $entrySource.Substring($entrySource.IndexOf('# --- Per-farm reporting'), $entrySource.IndexOf('# EmailMode = ''Consolidated'': one email for all the farms of the environment, built from the') - $entrySource.IndexOf('# --- Per-farm reporting'))
        # What the dashboard gets (the comment, the arguments and their use) is the one mention allowed; the email gets none
        $withoutDashboardLink = [regex]::Replace($perFarm, '(?im)^[^\r\n]*(?:dashboardCockpitLink|link to the cockpit only)[^\r\n]*\r?\n', '')
        $withoutDashboardLink | Should -Not -Match '(?i)cockpit'
    }

    It 'produces nothing for the default configuration: the page call sits under the opt-in test only' {
        $before = $entrySource.Substring(0, $call)
        $lastIf = $before.LastIndexOf('if (')
        $before.Substring($lastIf) | Should -Match '^if \(\$cockpitSetting\.Enabled\)'
    }

    Context 'the run does what the entry script says' {
        BeforeAll {
            # The real block of the entry script, run against a Results folder: it must write the page, name it, and survive a failure
            $match = [regex]::Match($entrySource, '(?s)(if \(\$cockpitSetting\.Enabled\) \{\s*try \{\s*\$cockpitFile = Export-SPSWeatherCockpit.*?-EventID 3002\r?\n\s*\}\r?\n\s*\})')
            $script:pageBlock = $match.Groups[1].Value
            Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
            function script:Invoke-PageBlock {
                param($Setting, $Results, $Farms = @(@{ Name = 'CONTENT' }), [scriptblock]$OnEvent)
                $events = New-Object -TypeName System.Collections.ArrayList
                & {
                    param($cockpitSetting, $pathResultsFolder, $spFarms, $block, $events)
                    $Application = 'zebes'; $Environment = 'PROD'; $jsonHistoryRetentionDays = 30; $spsWeatherVersion = '3.5.0'
                    $languageSetting = [PSCustomObject]@{ Culture = 'en-US' }
                    function Add-SPSWeatherEvent { param($Message, $EntryType, $EventID) [void]$events.Add([PSCustomObject]@{ Message = $Message; EntryType = $EntryType; EventID = $EventID }) }
                    $output = & ([scriptblock]::Create($block)) 6>&1
                    $output
                } $Setting $Results $Farms $pageBlock $events | Out-Null
                @($events)
            }
        }
        AfterAll { Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue }

        It 'finds the block' {
            $pageBlock | Should -Match 'Export-SPSWeatherCockpit'
            $pageBlock | Should -Match '-EventID 3002'
        }

        It 'writes nothing when the key is off' {
            $results = Join-Path -Path $TestDrive -ChildPath 'off'
            New-Item -Path $results -ItemType Directory | Out-Null
            $setting = Resolve-SPSCockpitSetting -Config @{ Dashboard = @{ OutputPath = $results } } -Application 'zebes' -Environment 'PROD' -ResultsFolder $results
            @(Invoke-PageBlock -Setting $setting -Results $results).Count | Should -Be 0
            @(Get-ChildItem -Path $results).Count | Should -Be 0
        }

        It 'writes <App>-<Env>-cockpit.html into Results when the key is on and OutputPath is empty' {
            $results = Join-Path -Path $TestDrive -ChildPath 'on-results'
            New-Item -Path $results -ItemType Directory | Out-Null
            $setting = Resolve-SPSCockpitSetting -Config @{ Dashboard = @{ Cockpit = $true } } -Application 'zebes' -Environment 'PROD' -ResultsFolder $results
            @(Invoke-PageBlock -Setting $setting -Results $results).Count | Should -Be 0
            $page = Join-Path -Path $results -ChildPath 'zebes-PROD-cockpit.html'
            Test-Path -LiteralPath $page | Should -BeTrue
            [System.IO.File]::ReadAllText($page) | Should -Match '^<!DOCTYPE html>'
        }

        It 'writes the page next to the dashboards when OutputPath is set, and creates that folder' {
            $results = Join-Path -Path $TestDrive -ChildPath 'on-results2'
            $dashboards = Join-Path -Path $TestDrive -ChildPath 'shared/dashboards'
            New-Item -Path $results -ItemType Directory | Out-Null
            $setting = Resolve-SPSCockpitSetting -Config @{ Dashboard = @{ Cockpit = 'true'; OutputPath = $dashboards } } -Application 'zebes' -Environment 'PROD' -ResultsFolder $results
            [void](Invoke-PageBlock -Setting $setting -Results $results)
            Test-Path -LiteralPath (Join-Path -Path $dashboards -ChildPath 'zebes-PROD-cockpit.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $results -ChildPath 'zebes-PROD-cockpit.html') | Should -BeFalse
        }

        It 'does not stop the run and records ID 3002 when the page cannot be written' {
            $results = Join-Path -Path $TestDrive -ChildPath 'fail-results'
            New-Item -Path $results -ItemType Directory | Out-Null
            $blocker = Join-Path -Path $TestDrive -ChildPath 'a-file'
            Set-Content -Path $blocker -Value 'not a folder'
            $setting = Resolve-SPSCockpitSetting -Config @{ Dashboard = @{ Cockpit = $true; OutputPath = (Join-Path -Path $blocker -ChildPath 'sub') } } -Application 'zebes' -Environment 'PROD' -ResultsFolder $results
            $recorded = @(Invoke-PageBlock -Setting $setting -Results $results)
            $recorded.Count | Should -Be 1
            $recorded[0].EventID | Should -Be 3002
            $recorded[0].EntryType | Should -Be 'Error'
            $recorded[0].Message | Should -Match 'failed to produce the cockpit page for zebes/PROD'
        }

        It 'does not stop the run when the Results folder holds a damaged journal and a farm that left nothing' {
            $results = Join-Path -Path $TestDrive -ChildPath 'damaged'
            New-Item -Path $results -ItemType Directory | Out-Null
            Set-Content -Path (Join-Path -Path $results -ChildPath 'zebes-PROD.runs.json') -Value '{ not json'
            $setting = Resolve-SPSCockpitSetting -Config @{ Dashboard = @{ Cockpit = $true } } -Application 'zebes' -Environment 'PROD' -ResultsFolder $results
            $recorded = @(Invoke-PageBlock -Setting $setting -Results $results -Farms @(@{ Name = 'CONTENT' }, @{ Name = 'SEARCH' }))
            $recorded.Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path -Path $results -ChildPath 'zebes-PROD-cockpit.html') | Should -BeTrue
        }
    }
}

Describe 'Entry script supported limits' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:entrySource = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1') -Raw
    }

    It 'resolves the limits before the run setting, which records them, and shows the messages in the transcript' {
        $limit = $entrySource.IndexOf('$limitSetting = Get-SPSWeatherLimitSetting -Config $envCfg')
        $run = $entrySource.IndexOf('$runSetting = Get-SPSWeatherRunSetting -Config $envCfg -ConfigFile $ConfigFile -LimitSetting $limitSetting')
        $limit | Should -BeGreaterThan 0
        $run | Should -BeGreaterThan $limit
        ([regex]::Matches($entrySource, 'Get-SPSWeatherLimitSetting')).Count | Should -Be 1
        $entrySource | Should -Match 'foreach \(\$limitMessage in \$limitSetting\.Messages\) \{ Write-Warning -Message \$limitMessage \}'
    }

    It 'records the messages of the limits in the Event Log (ID 2001), like the other configuration warnings' {
        $entrySource | Should -Match '(?s)foreach \(\$limitMessage in \$limitSetting\.Messages\) \{\s*Add-SPSWeatherEvent -Message "SPSWeather limits configuration: \$limitMessage" -EntryType ''Warning'' -EventID 2001'
    }

    It 'checks the limits of each farm after the SQL block (whose databases it needs) and never before the sections it judges' {
        $sql = $entrySource.IndexOf('$sqlStatus = Get-SPSSqlStatus')
        $limits = $entrySource.IndexOf('Get-SPSLimitStatus -Server')
        $sql | Should -BeGreaterThan 0
        $limits | Should -BeGreaterThan $sql
        foreach ($table in '$tbSPSContentDBStatus', '$tbAppFabricStatus', '$tbIISApplicationPoolStatus', '$tbSPSSearchEntTopology') {
            $entrySource.LastIndexOf("$table +=", $limits) | Should -BeGreaterThan 0 -Because "$table is collected before the limits are judged"
        }
    }

    It 'resets the SQL result for every farm, so that a farm never judges the databases of the previous one' {
        $entrySource | Should -Match '(?s)\$sqlStatus = \$null\r?\n.*?\$sqlStatus = Get-SPSSqlStatus'
    }

    It 'can be turned off with the LimitStatus exclusion, and adds the section to the report' {
        $entrySource | Should -Match 'if \(-not \$ExclusionRules\.Contains\(''LimitStatus''\)\) \{\s*Write-Output "Checking the supported limits'
        $entrySource | Should -Match '\$tbSPSLimitStatus = @\(\)'
        $entrySource | Should -Match 'SPSLimitStatus\s+= \$tbSPSLimitStatus'
    }

    Context 'the block that runs the checks' {
        BeforeAll {
            $match = [regex]::Match($entrySource, '(?s)(if \(-not \$ExclusionRules\.Contains\(''LimitStatus''\)\) \{.*?-SearchTopology @\(.*?\r?\n\s*\})')
            $script:limitBlock = $match.Groups[1].Value
            function script:Invoke-LimitBlock {
                param($Exclusions = @('None'), $Sql = $null)
                $captured = @{ Calls = (New-Object -TypeName System.Collections.ArrayList) }
                $rows = & {
                    param($ExclusionRules, $block, $captured, $sqlStatus)
                    $spFarm = @{ Name = 'CONTENT' }; $spTargetServer = 'APP1.contoso.com'; $ADM = 'credential'; $limitSetting = 'setting'
                    $tbSPSLimitStatus = @('already')
                    $tbSPSContentDBStatus = @([PSCustomObject]@{ Farm = 'CONTENT'; DatabaseName = 'A' }, [PSCustomObject]@{ Farm = 'OTHER'; DatabaseName = 'B' })
                    $tbAppFabricStatus = @([PSCustomObject]@{ Farm = 'OTHER'; Server = 'W1' })
                    $tbIISApplicationPoolStatus = @([PSCustomObject]@{ Farm = 'CONTENT'; ApplicationPool = 'P' })
                    $tbSPSSearchEntTopology = @()
                    function Write-Output { param($InputObject) }
                    function Get-SPSLimitStatus {
                        param($Server, $InstallAccount, $Farm, $Setting, $SqlDatabase, $ContentDatabaseStatus, $DistributedCache, $ApplicationPool, $SearchTopology)
                        [void]$captured.Calls.Add(@{ Server = $Server; Farm = $Farm; Setting = $Setting; Sql = @($SqlDatabase); Content = @($ContentDatabaseStatus); Cache = @($DistributedCache); Pools = @($ApplicationPool); Search = @($SearchTopology) })
                        [PSCustomObject]@{ Limit = 'ContentDatabaseSize' }
                    }
                    . ([scriptblock]::Create($block)) | Out-Null
                    $tbSPSLimitStatus
                } $Exclusions $limitBlock $captured $Sql
                [PSCustomObject]@{ Rows = @($rows); Calls = @($captured.Calls) }
            }
        }

        It 'finds the block' {
            $limitBlock | Should -Match 'Get-SPSLimitStatus -Server \$spTargetServer'
        }

        It 'adds the rows to the table of the report without losing the ones of the other farms' {
            $r = Invoke-LimitBlock
            $r.Rows.Count | Should -Be 2
            $r.Rows[0] | Should -Be 'already'
            $r.Rows[1].Limit | Should -Be 'ContentDatabaseSize'
        }

        It 'calls the check once, for the farm, with the resolved setting and only the rows of this farm' {
            $sql = @([PSCustomObject]@{ Farm = 'CONTENT'; Name = 'A' }, [PSCustomObject]@{ Farm = 'OTHER'; Name = 'B' })
            $r = Invoke-LimitBlock -Sql ([PSCustomObject]@{ Databases = $sql })
            $r.Calls.Count | Should -Be 1
            $r.Calls[0].Server | Should -Be 'APP1.contoso.com'
            $r.Calls[0].Farm | Should -Be 'CONTENT'
            $r.Calls[0].Setting | Should -Be 'setting'
            $r.Calls[0].Sql.Count | Should -Be 1
            $r.Calls[0].Sql[0].Name | Should -Be 'A'
            $r.Calls[0].Content.Count | Should -Be 1
            $r.Calls[0].Content[0].DatabaseName | Should -Be 'A'
            $r.Calls[0].Cache.Count | Should -Be 0
            $r.Calls[0].Pools.Count | Should -Be 1
        }

        It 'still runs, without any database, when the SQL block did not run for this farm' {
            $r = Invoke-LimitBlock -Sql $null
            $r.Calls.Count | Should -Be 1
            $r.Calls[0].Sql.Count | Should -Be 0
        }

        It 'does nothing when LimitStatus is excluded' {
            $r = Invoke-LimitBlock -Exclusions @('LimitStatus')
            $r.Calls.Count | Should -Be 0
            $r.Rows.Count | Should -Be 1
        }

        It 'is not turned off by the other exclusions' {
            (Invoke-LimitBlock -Exclusions @('SQLDatabaseStatus', 'WSPStatus')).Calls.Count | Should -Be 1
        }
    }
}
