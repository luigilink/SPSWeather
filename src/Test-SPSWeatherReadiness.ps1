<#
    .SYNOPSIS
    Pre-flight readiness check for SPSWeather.

    .DESCRIPTION
    Validates, before running SPSWeather.ps1, that the environment is ready:
    the SPSWeather.Common module imports, the environment configuration parses
    and exposes the required keys, the service credential exists in secrets.psd1
    and decrypts under the current account (DPAPI), the scheduled task does not use
    the -EnableSMTP switch that 4.0.0 removes, the session is elevated, and each farm
    server is reachable for CredSSP remoting.

    Read-only: it never changes configuration, credentials or the farm. The only thing it writes is a small
    temporary file, removed at once, to prove that the folder of the cockpit page accepts a file and lets it
    be removed (when Dashboard.Cockpit is on). A relative folder is made absolute like the run does.

    .PARAMETER ConfigFile
    Path to the environment configuration .psd1 file (same one passed to
    SPSWeather.ps1). secrets.psd1 is looked up in the same folder.

    .PARAMETER SkipNetwork
    Skip the per-farm WinRM/CredSSP reachability probe (useful off-server).

    .EXAMPLE
    .\Test-SPSWeatherReadiness.ps1 -ConfigFile 'Config\contoso-PROD.psd1'

    .NOTES
    FileName:   Test-SPSWeatherReadiness.ps1
    Author:     luigilink (Jean-Cyril DROUHIN)
    Project:    https://github.com/luigilink/SPSWeather
#>

#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'This is an interactive, operator-facing readiness tool whose purpose is colored console output.')]
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $ConfigFile,

    [Parameter()]
    [switch]
    $SkipNetwork,

    [Parameter()]
    [switch]
    $SkipSharePoint,

    [Parameter()]
    [System.Int32]
    $TimeoutSeconds = 5
)

$script:results = New-Object System.Collections.Generic.List[object]

function Add-CheckResult {
    param
    (
        [Parameter(Mandatory = $true)] [System.String] $Section,
        [Parameter(Mandatory = $true)] [System.String] $Name,
        [Parameter(Mandatory = $true)] [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')] [System.String] $Status,
        [Parameter()] [System.String] $Detail = ''
    )

    $script:results.Add([PSCustomObject]@{ Section = $Section; Name = $Name; Status = $Status; Detail = $Detail })

    switch ($Status) {
        'PASS' { $color = 'Green'; $glyph = '[ OK ]' }
        'FAIL' { $color = 'Red'; $glyph = '[FAIL]' }
        'WARN' { $color = 'Yellow'; $glyph = '[WARN]' }
        'SKIP' { $color = 'DarkGray'; $glyph = '[SKIP]' }
    }
    $line = '{0}  {1}' -f $glyph, $Name
    if (-not [string]::IsNullOrEmpty($Detail)) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Write-Section {
    param ([System.String] $Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SPSWeather - Readiness Check' -ForegroundColor Cyan
Write-Host "  Computer : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# 1. Module
Write-Section -Title 'Module'
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSWeather.Common\SPSWeather.Common.psd1'
if (Test-Path -Path $modulePath) {
    try {
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $version = (Get-Module -Name SPSWeather.Common).Version
        Add-CheckResult -Section 'Module' -Name 'SPSWeather.Common import' -Status 'PASS' -Detail "v$version"
    }
    catch {
        Add-CheckResult -Section 'Module' -Name 'SPSWeather.Common import' -Status 'FAIL' -Detail $_.Exception.Message
    }
}
else {
    Add-CheckResult -Section 'Module' -Name 'SPSWeather.Common import' -Status 'FAIL' -Detail "Module not found at $modulePath"
}

# 2. Configuration
Write-Section -Title 'Configuration'
$cfg = $null
if (-not (Test-Path -Path $ConfigFile)) {
    Add-CheckResult -Section 'Config' -Name 'Configuration file' -Status 'FAIL' -Detail "Not found: $ConfigFile"
}
else {
    try {
        $cfg = Import-PowerShellDataFile -Path $ConfigFile -ErrorAction Stop
        Add-CheckResult -Section 'Config' -Name 'Configuration file' -Status 'PASS' -Detail $ConfigFile
    }
    catch {
        Add-CheckResult -Section 'Config' -Name 'Configuration file' -Status 'FAIL' -Detail "Parse error: $($_.Exception.Message)"
    }
}

if ($null -ne $cfg) {
    # SMTPEnabled / SMTPPreview must be booleans ($true / $false, or their string forms, like
    # the entry script accepts). The SMTP relay settings are only required when emails are
    # sent: an environment with SMTPEnabled = $false (e.g. a lab without relay) must pass.
    $smtpKeysRequired = $true
    foreach ($flag in @('SMTPEnabled', 'SMTPPreview')) {
        if ($cfg.Contains($flag)) {
            $flagValue = $cfg[$flag]
            $flagParsed = $false
            if ($flagValue -is [bool]) { $flagParsed = $flagValue; $flagValid = $true }
            else { $flagValid = ($flagValue -is [string]) -and [bool]::TryParse($flagValue.Trim(), [ref]$flagParsed) }
            if ($flagValid) {
                Add-CheckResult -Section 'Config' -Name "Key '$flag'" -Status 'PASS' -Detail "$flagParsed"
                if ($flag -eq 'SMTPEnabled' -and -not $flagParsed) { $smtpKeysRequired = $false }
            }
            else {
                Add-CheckResult -Section 'Config' -Name "Key '$flag'" -Status 'FAIL' -Detail "Must be `$true or `$false (got '$flagValue')"
            }
        }
    }

    # EmailMode (optional): 'PerFarm' (default) or 'Consolidated'. An unknown value is a WARN, never
    # a FAIL: the run falls back to one email per farm.
    if ($cfg.Contains('EmailMode')) {
        if (Get-Command -Name Resolve-SPSSmtpSetting -ErrorAction SilentlyContinue) {
            $modeCheck = Resolve-SPSSmtpSetting -Config $cfg
            $modeMessages = @($modeCheck.Messages | Where-Object -FilterScript { $_ -like 'EmailMode*' })
            if ($modeMessages.Count -gt 0) {
                Add-CheckResult -Section 'Config' -Name "Key 'EmailMode'" -Status 'WARN' -Detail ($modeMessages -join ' ')
            }
            else {
                Add-CheckResult -Section 'Config' -Name "Key 'EmailMode'" -Status 'PASS' -Detail $modeCheck.Mode
            }
        }
        else {
            Add-CheckResult -Section 'Config' -Name "Key 'EmailMode'" -Status 'SKIP' -Detail 'SPSWeather.Common is not loaded'
        }
    }

    # Language (optional): display language of the dashboard and the email. A language that is not
    # available is a WARN, never a FAIL: the run falls back to English.
    if ($cfg.Contains('Language')) {
        if (Get-Command -Name Resolve-SPSWeatherLanguage -ErrorAction SilentlyContinue) {
            $languageCheck = Resolve-SPSWeatherLanguage -Language $cfg['Language']
            if ($languageCheck.Messages.Count -gt 0) {
                Add-CheckResult -Section 'Config' -Name "Key 'Language'" -Status 'WARN' -Detail ($languageCheck.Messages -join ' ')
            }
            elseif ($languageCheck.Requested -ieq 'auto') {
                Add-CheckResult -Section 'Config' -Name "Key 'Language'" -Status 'PASS' -Detail "auto -> $($languageCheck.Culture) for this session (the account that runs the task may differ)"
            }
            else {
                Add-CheckResult -Section 'Config' -Name "Key 'Language'" -Status 'PASS' -Detail $languageCheck.Culture
            }
        }
        else {
            Add-CheckResult -Section 'Config' -Name "Key 'Language'" -Status 'SKIP' -Detail 'SPSWeather.Common is not loaded'
        }
    }

    # Dashboard.Cockpit (optional): the multi-farm page. An invalid value is a WARN, never a FAIL: the run does not produce
    # the page (Event ID 2001). When it is on, the folder that receives it must exist or be creatable and accept a file.
    if ($cfg.Contains('Dashboard') -and ($cfg['Dashboard'] -is [System.Collections.IDictionary]) -and $cfg['Dashboard'].Contains('Cockpit')) {
        if (Get-Command -Name Resolve-SPSCockpitSetting -ErrorAction SilentlyContinue) {
            $cockpitCheck = Resolve-SPSCockpitSetting -Config $cfg -Application "$($cfg['ApplicationName'])" -Environment "$($cfg['ConfigurationName'])" -ResultsFolder (Join-Path -Path $PSScriptRoot -ChildPath 'Results')
            if ($cockpitCheck.Messages.Count -gt 0) {
                Add-CheckResult -Section 'Config' -Name "Key 'Dashboard.Cockpit'" -Status 'WARN' -Detail ($cockpitCheck.Messages -join ' ')
            }
            elseif (-not $cockpitCheck.Enabled) {
                Add-CheckResult -Section 'Config' -Name "Key 'Dashboard.Cockpit'" -Status 'PASS' -Detail 'False: no cockpit page'
            }
            else {
                Add-CheckResult -Section 'Config' -Name "Key 'Dashboard.Cockpit'" -Status 'PASS' -Detail "True: $($cockpitCheck.Path)"
                # Read-only: a folder that does not exist is judged by its nearest existing parent, nothing is created.
                # The folder is made absolute the way the exporter does, so the check and the probe use the path the run will write to.
                $probe = $cockpitCheck.Folder
                $resolveError = $null
                if (-not [string]::IsNullOrWhiteSpace($probe)) {
                    try { $probe = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($probe) }
                    catch { $resolveError = $_.Exception.Message }
                }
                $targetFolder = $probe
                $blockedBy = $null
                while (-not $resolveError -and $probe -and -not (Test-Path -LiteralPath $probe -PathType Container)) {
                    # A part of the path that exists but is not a folder can never hold the page
                    if (Test-Path -LiteralPath $probe -PathType Leaf) { $blockedBy = $probe; break }
                    $probe = Split-Path -Path $probe -Parent
                }
                if ($null -ne $resolveError) {
                    Add-CheckResult -Section 'Config' -Name 'Cockpit page folder' -Status 'WARN' -Detail "Cannot resolve $($cockpitCheck.Folder): $resolveError"
                }
                elseif ($null -ne $blockedBy) {
                    Add-CheckResult -Section 'Config' -Name 'Cockpit page folder' -Status 'WARN' -Detail "$blockedBy is a file, not a folder: the run will not be able to write the page to $targetFolder"
                }
                elseif ([string]::IsNullOrWhiteSpace($probe)) {
                    Add-CheckResult -Section 'Config' -Name 'Cockpit page folder' -Status 'WARN' -Detail "No existing folder found for $($cockpitCheck.Folder): the run will not be able to write the page"
                }
                else {
                    $writeError = $null
                    $removeError = $null
                    $testFile = Join-Path -Path $probe -ChildPath ('.spsweather-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
                    try { [System.IO.File]::WriteAllText($testFile, 'x') }
                    catch { $writeError = $_.Exception.Message }
                    if ($null -eq $writeError) {
                        # The run replaces the page of the day before: an account that can create a file but not delete one cannot do it
                        try {
                            [System.IO.File]::Delete($testFile)
                            if ([System.IO.File]::Exists($testFile)) { throw 'the file is still there' }
                        }
                        catch { $removeError = $_.Exception.Message }
                    }
                    if ($null -ne $writeError) {
                        Add-CheckResult -Section 'Config' -Name 'Cockpit page folder' -Status 'WARN' -Detail "Not writable by this account ($probe): $writeError"
                    }
                    elseif ($null -ne $removeError) {
                        Add-CheckResult -Section 'Config' -Name 'Cockpit page folder' -Status 'WARN' -Detail "A file can be created in $probe but not removed ($removeError): the run could not replace the page it wrote before. The test file $testFile was left behind, remove it by hand."
                    }
                    else {
                        $note = if ($probe -ne $targetFolder) { " ($targetFolder will be created by the run)" } else { '' }
                        Add-CheckResult -Section 'Config' -Name 'Cockpit page folder' -Status 'PASS' -Detail "Writable: $probe$note"
                    }
                }
                if ([string]::IsNullOrWhiteSpace($cockpitCheck.Url)) {
                    Add-CheckResult -Section 'Config' -Name 'Cockpit page link' -Status 'PASS' -Detail 'Dashboard.Url is empty: the consolidated email has no cockpit button'
                }
                else {
                    Add-CheckResult -Section 'Config' -Name 'Cockpit page link' -Status 'PASS' -Detail $cockpitCheck.Url
                }
            }
        }
        else {
            Add-CheckResult -Section 'Config' -Name "Key 'Dashboard.Cockpit'" -Status 'SKIP' -Detail 'SPSWeather.Common is not loaded'
        }
    }

    foreach ($key in @('ConfigurationName', 'ApplicationName', 'Domain', 'SMTPToAddress', 'SMTPFromAddress', 'SMTPServer', 'CredentialKey', 'Farms')) {
        # The SMTP settings use the runtime's emptiness rule (Resolve-SPSSmtpSetting): '', blanks
        # and an empty array count as missing, otherwise the pre-flight is green and no mail is sent.
        $isPresent = $cfg.Contains($key) -and $null -ne $cfg[$key]
        if ($isPresent -and $key -like 'SMTP*') { $isPresent = -not [string]::IsNullOrWhiteSpace((@($cfg[$key]) -join '')) }
        if ($isPresent) {
            Add-CheckResult -Section 'Config' -Name "Key '$key'" -Status 'PASS'
        }
        elseif (-not $smtpKeysRequired -and $key -like 'SMTP*') {
            Add-CheckResult -Section 'Config' -Name "Key '$key'" -Status 'SKIP' -Detail 'Not required: SMTPEnabled = $false'
        }
        else {
            Add-CheckResult -Section 'Config' -Name "Key '$key'" -Status 'FAIL' -Detail 'Missing or empty'
        }
    }

    if ($cfg.Contains('Farms') -and $cfg.Farms) {
        $badFarms = @($cfg.Farms | Where-Object { [string]::IsNullOrEmpty($_.Name) -or [string]::IsNullOrEmpty($_.Server) })
        if ($badFarms.Count -eq 0) {
            Add-CheckResult -Section 'Config' -Name 'Farms entries' -Status 'PASS' -Detail "$(@($cfg.Farms).Count) farm(s)"
        }
        else {
            Add-CheckResult -Section 'Config' -Name 'Farms entries' -Status 'FAIL' -Detail 'A farm is missing Name or Server'
        }
    }
}

# 3. Secrets (DPAPI)
Write-Section -Title 'Secrets'
if ($null -ne $cfg -and $cfg.Contains('CredentialKey') -and $cfg.CredentialKey) {
    $configFolder = Split-Path -Path $ConfigFile -Parent
    if ([string]::IsNullOrEmpty($configFolder)) { $configFolder = '.' }
    $secretsPath = Join-Path -Path $configFolder -ChildPath 'secrets.psd1'
    if (-not (Test-Path -Path $secretsPath)) {
        Add-CheckResult -Section 'Secrets' -Name 'secrets.psd1' -Status 'FAIL' -Detail "Not found at $secretsPath. Run SPSWeather.ps1 -Action Install as the service account."
    }
    else {
        # Get-SPSSecret is exported by the module; call it directly.
        if ($null -eq (Get-Module -Name SPSWeather.Common)) {
            Add-CheckResult -Section 'Secrets' -Name 'Get-SPSSecret' -Status 'SKIP' -Detail 'Module not loaded; cannot validate the secret'
        }
        else {
            try {
                $cred = Get-SPSSecret -CredentialKey $cfg.CredentialKey -ConfigPath $configFolder -ErrorAction Stop
                if ($null -ne $cred -and $cred.GetNetworkCredential().Password.Length -gt 0) {
                    Add-CheckResult -Section 'Secrets' -Name "Credential '$($cfg.CredentialKey)'" -Status 'PASS' -Detail "DPAPI decrypt OK (user: $($cred.UserName))"
                }
                else {
                    Add-CheckResult -Section 'Secrets' -Name "Credential '$($cfg.CredentialKey)'" -Status 'FAIL' -Detail 'Not found in secrets.psd1'
                }
            }
            catch {
                Add-CheckResult -Section 'Secrets' -Name "Credential '$($cfg.CredentialKey)'" -Status 'FAIL' -Detail "Decrypt failed (wrong account/machine?): $($_.Exception.Message)"
            }
        }
    }
}
else {
    Add-CheckResult -Section 'Secrets' -Name 'CredentialKey' -Status 'SKIP' -Detail 'No CredentialKey in config'
}

# 4. Scheduled task: the deprecated -EnableSMTP switch is removed in 4.0.0. Information only, never a failure, and nothing is
# changed: the task is only read.
Write-Section -Title 'Scheduled task'
if ($null -ne $cfg -and (Get-Command -Name Get-SPSScheduledTaskSmtpCheck -ErrorAction SilentlyContinue)) {
    $taskSmtp = Resolve-SPSSmtpSetting -Config $cfg
    $taskCheck = Get-SPSScheduledTaskSmtpCheck -Application "$($cfg['ApplicationName'])" -Environment "$($cfg['ConfigurationName'])" -ConfigDefinesEnabled:$taskSmtp.ConfigDefinesEnabled
    Add-CheckResult -Section 'Scheduled task' -Name "Task '$($taskCheck.TaskName)'" -Status $taskCheck.Status -Detail $taskCheck.Detail
}
else {
    Add-CheckResult -Section 'Scheduled task' -Name 'Scheduled task' -Status 'SKIP' -Detail 'No readable configuration or SPSWeather.Common is not loaded'
}

# 5. Privileges
Write-Section -Title 'Privileges'
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if ($isAdmin) {
    Add-CheckResult -Section 'Privileges' -Name 'Administrator rights' -Status 'PASS'
}
else {
    Add-CheckResult -Section 'Privileges' -Name 'Administrator rights' -Status 'FAIL' -Detail 'Run elevated (needed for the Event Log and SharePoint cmdlets)'
}

# 6. Network / CredSSP reachability
Write-Section -Title 'Network'
if ($SkipNetwork) {
    Add-CheckResult -Section 'Network' -Name 'Farm reachability' -Status 'SKIP' -Detail '-SkipNetwork specified'
}
elseif ($null -ne $cfg -and $cfg.Contains('Farms') -and $cfg.Farms) {
    # Start from the per-farm servers declared in the config.
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($farm in $cfg.Farms) {
        if ($farm.Server) { $targets.Add("$($farm.Server).$($cfg.Domain)") }
    }

    # Enrich with every server of the local farm (Get-SPServer), so all the
    # machines that SPSWeather will reach are checked - not just the declared
    # entry point. This needs the SharePoint command surface; load it via the
    # SharePointServer module (Subscription Edition).
    if (-not $SkipSharePoint -and (Get-Command -Name Import-SPSSharePointCommand -ErrorAction SilentlyContinue)) {
        try {
            $null = Import-SPSSharePointCommand
            $farmServers = @(Get-SPServer | Where-Object { $_.Role -ne 'Invalid' } | Select-Object -ExpandProperty Name)
            foreach ($s in $farmServers) {
                $fqdn = if ($s -like "*.*") { $s } else { "$s.$($cfg.Domain)" }
                if ($targets -notcontains $fqdn) { $targets.Add($fqdn) }
            }
            Add-CheckResult -Section 'Network' -Name 'Farm server enumeration' -Status 'PASS' -Detail "$($farmServers.Count) server(s) via Get-SPServer"
        }
        catch {
            Add-CheckResult -Section 'Network' -Name 'Farm server enumeration' -Status 'SKIP' -Detail "Get-SPServer unavailable: $($_.Exception.Message)"
        }
    }
    else {
        Add-CheckResult -Section 'Network' -Name 'Farm server enumeration' -Status 'SKIP' -Detail 'SharePoint not loaded; using declared servers only'
    }

    foreach ($target in ($targets | Sort-Object -Unique)) {
        # Probe WinRM with a short timeout so an unreachable server cannot hang the
        # pre-flight (Test-WSMan has no timeout). An unreachable server is a WARN,
        # not a FAIL: the run's per-farm resilience skips it, so it should not block.
        $cim = $null
        try {
            $opt = New-CimSessionOption -Protocol Wsman
            $cim = New-CimSession -ComputerName $target -OperationTimeoutSec $TimeoutSeconds -SessionOption $opt -ErrorAction Stop
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'PASS' -Detail 'Confirm CredSSP is enabled for the full run'
        }
        catch {
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'WARN' -Detail "Unreachable within ${TimeoutSeconds}s (the run will skip it): $($_.Exception.Message)"
        }
        finally {
            if ($cim) { Remove-CimSession -CimSession $cim -ErrorAction SilentlyContinue }
        }
    }
}
else {
    Add-CheckResult -Section 'Network' -Name 'Farm reachability' -Status 'SKIP' -Detail 'No farms to probe'
}

# Summary
$fail = @($script:results | Where-Object Status -eq 'FAIL').Count
$warn = @($script:results | Where-Object Status -eq 'WARN').Count
$pass = @($script:results | Where-Object Status -eq 'PASS').Count
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host (' Summary : {0} passed, {1} warning(s), {2} failure(s)' -f $pass, $warn, $fail) -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 } else { exit 0 }
