# Tests for the Test-SPSWeatherReadiness.ps1 standalone script.

# Whether this host has a way to make a folder refuse a new file (decided when the tests are discovered, as -Skip needs it then)
$canDenyWrite = $false
if (-not $IsWindows -and (Get-Command -Name chmod -ErrorAction SilentlyContinue)) {
    $denyProbe = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('deny-probe-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $denyProbe -ItemType Directory)
    & chmod 555 $denyProbe
    try { [System.IO.File]::WriteAllText((Join-Path -Path $denyProbe -ChildPath 'x.tmp'), 'x') } catch { $canDenyWrite = $true }
    & chmod 755 $denyProbe
    Remove-Item -Path $denyProbe -Recurse -Force -ErrorAction SilentlyContinue
}

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

    Context 'EmailMode' {
        BeforeAll {
            $script:modeConsolidated = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    EmailMode = 'Consolidated'"
            $script:modePerFarm = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    EmailMode = 'perfarm'"
            $script:modeInvalid = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    EmailMode = 'Single'"
            $script:modeAbsent = Invoke-Readiness -Extra "    SMTPEnabled = `$false"
        }

        It 'reports the mode it resolves to' {
            (Get-CheckLine -Lines $modeConsolidated -Key 'EmailMode') | Should -Match '^\[ OK \].*Consolidated'
            (Get-CheckLine -Lines $modePerFarm -Key 'EmailMode') | Should -Match '^\[ OK \].*PerFarm'
        }

        It 'warns, never fails, for a mode that does not exist' {
            $line = Get-CheckLine -Lines $modeInvalid -Key 'EmailMode'
            $line | Should -Match '^\[WARN\]'
            $line | Should -Match "EmailMode must be 'PerFarm' or 'Consolidated' \(got 'Single'\)"
            ($modeInvalid -join "`n") | Should -Not -Match "\[FAIL\]\s+Key 'EmailMode'"
        }

        It 'says nothing when no mode is configured' {
            (Get-CheckLine -Lines $modeAbsent -Key 'EmailMode') | Should -BeNullOrEmpty
        }
    }

    Context 'Language' {
        BeforeAll {
            $script:langFr = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'fr-FR'"
            $script:langRegion = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'fr-BE'"
            # 'qaa-QM' is in the ISO 639 range reserved for private use (qaa-qtz): it can never be a shipped language.
            $script:langUnknown = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'qaa-QM'"
            $script:langAuto = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = 'auto'"
            $script:langAbsent = Invoke-Readiness -Extra "    SMTPEnabled = `$false"
            $script:langList = Invoke-Readiness -Extra "    SMTPEnabled = `$false`n    Language = @('fr', 'en-US')"
        }

        It 'reports an available language with the culture it resolves to' {
            (Get-CheckLine -Lines $langFr -Key 'Language') | Should -Match '^\[ OK \].*fr-FR'
            (Get-CheckLine -Lines $langRegion -Key 'Language') | Should -Match '^\[ OK \].*fr-FR'
        }

        It 'resolves a list the way the run does (first item), not as one joined text' {
            $line = Get-CheckLine -Lines $langList -Key 'Language'
            $line | Should -Match '^\[ OK \].*fr-FR'
            $line | Should -Not -Match 'not available'
        }

        It 'warns, never fails, for a language that is not available' {
            $line = Get-CheckLine -Lines $langUnknown -Key 'Language'
            $line | Should -Match '^\[WARN\]'
            $line | Should -Match "Language 'qaa-QM' is not available"
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

Describe 'Readiness script cockpit page (Dashboard.Cockpit)' {
    BeforeAll {
        $script:hostExe = (Get-Process -Id $PID).Path

        function Invoke-Readiness {
            param([string]$Dashboard)
            $cfgPath = Join-Path -Path $TestDrive -ChildPath ('cfg-' + [guid]::NewGuid().ToString('N') + '.psd1')
            $block = if ($Dashboard) { "    Dashboard = @{`n$Dashboard`n    }" } else { '' }
            $body = @"
@{
    ConfigurationName = 'PROD'
    ApplicationName   = 'lab'
    Domain            = 'contoso.com'
    CredentialKey     = 'svc'
    SMTPEnabled       = `$false
    Farms             = @( @{ Name = 'CONTENT'; Server = 'app1' } )
$block
}
"@
            Set-Content -Path $cfgPath -Value $body -Encoding UTF8
            $out = & $script:hostExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ConfigFile $cfgPath -SkipNetwork -SkipSharePoint 2>&1 | Out-String
            $out -split "`r?`n"
        }
        function Get-CheckLine {
            param([string[]]$Lines, [string]$Pattern)
            @($Lines | Where-Object { $_ -match $Pattern })[0]
        }

        $script:folder = Join-Path -Path $TestDrive -ChildPath 'dash'
        New-Item -Path $script:folder -ItemType Directory | Out-Null
        $script:absent = Invoke-Readiness
        $script:noKey = Invoke-Readiness -Dashboard "        OutputPath = ''`n        Url = ''"
        $script:off = Invoke-Readiness -Dashboard "        Cockpit = `$false"
        $script:onWritable = Invoke-Readiness -Dashboard "        Cockpit = `$true`n        OutputPath = '$script:folder'`n        Url = 'https://h/SPSWeather/'"
        $script:onNoUrl = Invoke-Readiness -Dashboard "        Cockpit = `$true`n        OutputPath = '$script:folder'"
        $script:onNewFolder = Invoke-Readiness -Dashboard "        Cockpit = `$true`n        OutputPath = '$(Join-Path -Path $script:folder -ChildPath 'not\yet\there')'"
        $blocker = Join-Path -Path $TestDrive -ChildPath 'a-file'
        Set-Content -Path $blocker -Value 'x'
        $script:onBlocked = Invoke-Readiness -Dashboard "        Cockpit = `$true`n        OutputPath = '$(Join-Path -Path $blocker -ChildPath 'sub')'"
        # A folder that refuses a new file (a read-only mode on the Unix hosts of the test; a share that denies Modify is the Windows case)
        $script:readOnly = Join-Path -Path $TestDrive -ChildPath 'readonly'
        New-Item -Path $script:readOnly -ItemType Directory | Out-Null
        # The guard computed at discovery is not visible here (Pester 5 runs this block later): decide again
        $script:denies = $false
        if (-not $IsWindows -and (Get-Command -Name chmod -ErrorAction SilentlyContinue)) {
            & chmod 555 $script:readOnly
            try { [System.IO.File]::WriteAllText((Join-Path -Path $script:readOnly -ChildPath 'x.tmp'), 'x') } catch { $script:denies = $true }
        }
        $script:onDenied = Invoke-Readiness -Dashboard "        Cockpit = `$true`n        OutputPath = '$script:readOnly'"
        $script:onDeniedNew = Invoke-Readiness -Dashboard "        Cockpit = `$true`n        OutputPath = '$(Join-Path -Path $script:readOnly -ChildPath 'sub')'"
        $script:onResults = Invoke-Readiness -Dashboard "        Cockpit = `$true"
        $script:text = Invoke-Readiness -Dashboard "        Cockpit = 'true'"
        $script:invalidMaybe = Invoke-Readiness -Dashboard "        Cockpit = 'maybe'"
        $script:invalidNull = Invoke-Readiness -Dashboard "        Cockpit = `$null"
        $script:invalidNumber = Invoke-Readiness -Dashboard "        Cockpit = 1"
    }

    It 'says nothing when the key is not written (the readiness output is what it was)' {
        (Get-CheckLine -Lines $absent -Pattern 'Cockpit') | Should -BeNullOrEmpty
        (Get-CheckLine -Lines $noKey -Pattern 'Cockpit') | Should -BeNullOrEmpty
    }

    It 'reports $false as a pass and does not look at any folder' {
        (Get-CheckLine -Lines $off -Pattern "Key 'Dashboard.Cockpit'") | Should -Match '^\[ OK \].*False'
        (Get-CheckLine -Lines $off -Pattern 'Cockpit page folder') | Should -BeNullOrEmpty
    }

    It 'reports $true and the page it will write, a writable folder and the address of the button' {
        (Get-CheckLine -Lines $onWritable -Pattern "Key 'Dashboard.Cockpit'") | Should -Match '^\[ OK \].*True: .*lab-PROD-cockpit\.html'
        (Get-CheckLine -Lines $onWritable -Pattern 'Cockpit page folder') | Should -Match '^\[ OK \].*Writable'
        (Get-CheckLine -Lines $onWritable -Pattern 'Cockpit page link') | Should -Match '^\[ OK \].*https://h/SPSWeather/lab-PROD-cockpit\.html'
    }

    It 'says that the email has no button when Dashboard.Url is empty' {
        (Get-CheckLine -Lines $onNoUrl -Pattern 'Cockpit page link') | Should -Match 'has no cockpit button'
    }

    It 'accepts the text true like the run does' {
        (Get-CheckLine -Lines $text -Pattern "Key 'Dashboard.Cockpit'") | Should -Match '^\[ OK \].*True'
    }

    It 'judges a folder that does not exist yet by its nearest existing parent and creates nothing' {
        (Get-CheckLine -Lines $onNewFolder -Pattern 'Cockpit page folder') | Should -Match '^\[ OK \].*Writable.*will be created by the run'
        Test-Path -LiteralPath (Join-Path -Path $script:folder -ChildPath 'not') | Should -BeFalse
    }

    It 'leaves no file behind in the folder it probed' {
        @(Get-ChildItem -Path $script:folder -Force).Count | Should -Be 0
    }

    It 'warns, never fails, when the folder cannot take the page' {
        $line = Get-CheckLine -Lines $onBlocked -Pattern 'Cockpit page folder'
        $line | Should -Match '^\[WARN\]'
        ($onBlocked -join "`n") | Should -Not -Match '\[FAIL\]\s+Cockpit'
    }

    It 'warns, never fails, when the folder refuses the file, whether it exists or has still to be created under one that refuses' -Skip:(-not $canDenyWrite) {
        foreach ($lines in $onDenied, $onDeniedNew) {
            $line = Get-CheckLine -Lines $lines -Pattern 'Cockpit page folder'
            $line | Should -Match '^\[WARN\].*Not writable by this account'
            ($lines -join "`n") | Should -Not -Match '\[FAIL\]\s+Cockpit'
        }
    }

    It 'checks Results when OutputPath is empty' {
        (Get-CheckLine -Lines $onResults -Pattern 'Cockpit page folder') | Should -Match '^\[(\s*OK\s*|WARN)\]'
        (Get-CheckLine -Lines $onResults -Pattern "Key 'Dashboard.Cockpit'") | Should -Match 'Results'
    }

    It 'warns, never fails, for a value that is not a boolean, with the message of the run' -ForEach @(
        @{ Name = 'maybe'; Var = 'invalidMaybe'; Shown = "got 'maybe'" }
        @{ Name = '$null'; Var = 'invalidNull'; Shown = 'got \$null' }
        @{ Name = '1'; Var = 'invalidNumber'; Shown = 'got a value of type Int32' }
    ) {
        $lines = Get-Variable -Name $Var -ValueOnly -Scope Script
        $line = Get-CheckLine -Lines $lines -Pattern "Key 'Dashboard.Cockpit'"
        $line | Should -Match '^\[WARN\]'
        $line | Should -Match 'Dashboard\.Cockpit must be \$true or \$false'
        $line | Should -Match $Shown
        ($lines -join "`n") | Should -Not -Match "\[FAIL\]\s+Key 'Dashboard.Cockpit'"
        (Get-CheckLine -Lines $lines -Pattern 'Cockpit page folder') | Should -BeNullOrEmpty
    }

    AfterAll {
        if ($script:denies -and (Test-Path -LiteralPath $script:readOnly)) { & chmod 755 $script:readOnly }
    }

    It 'only writes a temporary probe file, removed at once, and says so in its help' {
        $help = Get-Content -Path $scriptPath -Raw
        $help | Should -Match 'temporary file, removed at once'
        $help | Should -Not -Match '(?i)Set-Content|Out-File|New-Item'
    }
}
