<#
    .SYNOPSIS
    Pre-flight readiness check for SPSWeather.

    .DESCRIPTION
    Validates, before running SPSWeather.ps1, that the environment is ready:
    the SPSWeather.Common module imports, the environment configuration parses
    and exposes the required keys, the service credential exists in secrets.psd1
    and decrypts under the current account (DPAPI), the session is elevated, and
    each farm server is reachable for CredSSP remoting.

    Read-only: it never changes configuration, credentials or the farm.

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
    $SkipNetwork
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
    foreach ($key in @('ConfigurationName', 'ApplicationName', 'Domain', 'SMTPToAddress', 'SMTPFromAddress', 'SMTPServer', 'CredentialKey', 'Farms')) {
        if ($cfg.Contains($key) -and $null -ne $cfg[$key]) {
            Add-CheckResult -Section 'Config' -Name "Key '$key'" -Status 'PASS'
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
        Add-CheckResult -Section 'Secrets' -Name 'secrets.psd1' -Status 'FAIL' -Detail "Not found at $secretsPath. Run SPSWeather.ps1 -Install as the service account."
    }
    elseif (Get-Command -Name Get-SPSSecret -ErrorAction SilentlyContinue) {
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
    else {
        Add-CheckResult -Section 'Secrets' -Name 'Get-SPSSecret' -Status 'SKIP' -Detail 'Module not loaded; cannot validate the secret'
    }
}
else {
    Add-CheckResult -Section 'Secrets' -Name 'CredentialKey' -Status 'SKIP' -Detail 'No CredentialKey in config'
}

# 4. Privileges
Write-Section -Title 'Privileges'
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if ($isAdmin) {
    Add-CheckResult -Section 'Privileges' -Name 'Administrator rights' -Status 'PASS'
}
else {
    Add-CheckResult -Section 'Privileges' -Name 'Administrator rights' -Status 'FAIL' -Detail 'Run elevated (needed for the Event Log and SharePoint cmdlets)'
}

# 5. Network / CredSSP reachability
Write-Section -Title 'Network'
if ($SkipNetwork) {
    Add-CheckResult -Section 'Network' -Name 'Farm reachability' -Status 'SKIP' -Detail '-SkipNetwork specified'
}
elseif ($null -ne $cfg -and $cfg.Contains('Farms') -and $cfg.Farms) {
    foreach ($farm in $cfg.Farms) {
        $target = "$($farm.Server).$($cfg.Domain)"
        try {
            $null = Test-WSMan -ComputerName $target -ErrorAction Stop
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'PASS' -Detail 'Confirm CredSSP is enabled for the full run'
        }
        catch {
            Add-CheckResult -Section 'Network' -Name "WinRM to $target" -Status 'FAIL' -Detail $_.Exception.Message
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
