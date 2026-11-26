function Get-SPSWeatherRunSetting {
    <#
        .SYNOPSIS
        Resolves the thresholds of a run and the part of them that the run journal records.

        .DESCRIPTION
        The only place that resolves the optional thresholds, so that the values a run uses and the ones its
        journal shows cannot drift apart. Returns Value (the numbers to use), Record (what the journal stores:
        no server, address, credential key, URL or path) and Messages (warnings to display). See the wiki page
        Cockpit-Data.

        .PARAMETER Config
        The environment configuration (hashtable loaded from the .psd1).

        .PARAMETER ConfigFile
        The configuration file given to the entry script; only its file name is kept.

        .EXAMPLE
        $runSetting = Get-SPSWeatherRunSetting -Config $envCfg -ConfigFile $ConfigFile
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Config,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $ConfigFile
    )

    $definitions = @(
        @{ Name = 'SQLDiskFreeThresholdPercent'; Default = 15; ClampNegative = $false }
        @{ Name = 'SQLBackupMaxAgeDays'; Default = 3; ClampNegative = $false }
        @{ Name = 'JsonHistoryRetentionDays'; Default = 30; ClampNegative = $false }
        @{ Name = 'EmailMaxItemsPerArea'; Default = 10; ClampNegative = $true }
        @{ Name = 'LogRetentionDays'; Default = 180; ClampNegative = $false }
    )

    # The values that the entry script tests (a test keeps this list in step)
    $knownExclusions = @(
        'None', 'APIHttpStatus', 'SPSiteHttpStatus', 'EvtViewerStatus', 'IISW3WPStatus', 'HealthStatus', 'WSPStatus',
        'FailedTimerJob', 'TimerServiceStatus', 'SQLInstanceStatus', 'SQLDatabaseStatus', 'SQLDiskStatus',
        'SQLAvailabilityStatus', 'SQLAliasStatus'
    )

    $messages = New-Object -TypeName System.Collections.ArrayList
    $value = [ordered]@{}
    $thresholds = [ordered]@{}

    foreach ($definition in $definitions) {
        $name = $definition.Name
        $raw = $null
        if (($null -ne $Config) -and $Config.Contains($name)) { $raw = $Config[$name] }

        $entry = [ordered]@{ value = $definition.Default; source = 'default' }
        if ($null -ne $raw) {
            $number = $null
            # A blank string casts to 0: treat it as invalid
            if (-not ($raw -is [System.String] -and [string]::IsNullOrWhiteSpace($raw))) {
                try { $number = [int]$raw } catch { $number = $null }
            }
            if ($null -ne $number -and $number -lt 0 -and $definition.ClampNegative) { $number = 0 }

            if ($null -ne $number -and $number -ge 0) {
                $entry = [ordered]@{ value = $number; source = 'config' }
            }
            else {
                $entry['invalid'] = $true
                [void]$messages.Add("$name must be a whole number of 0 or more (got '$raw'); using the default $($definition.Default).")
            }
        }
        $value[$name] = $entry.value
        $thresholds[$name] = $entry
    }

    # Same question as the entry script: $ExclusionRules.Contains('Name')
    $rawExclusions = $null
    if ($null -ne $Config -and $Config.Contains('ExclusionRules')) { $rawExclusions = $Config['ExclusionRules'] }
    $names = New-Object -TypeName System.Collections.ArrayList
    foreach ($known in $knownExclusions) {
        $excluded = $false
        if ($null -ne $rawExclusions) {
            try { $excluded = [bool]$rawExclusions.Contains($known) } catch { $excluded = $false }
        }
        if ($excluded) { [void]$names.Add($known) }
    }

    $leaf = $null
    if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
        $leaf = @($ConfigFile -split '[\\/]' | Where-Object -FilterScript { $_ })[-1]
    }

    return [PSCustomObject]@{
        Value    = [PSCustomObject]$value
        Record   = [PSCustomObject][ordered]@{
            configFile     = $leaf
            thresholds     = [PSCustomObject]$thresholds
            exclusionRules = @($names)
        }
        Messages = @($messages)
    }
}
