function Get-SPSWeatherRunSetting {
    <#
        .SYNOPSIS
        Resolves the thresholds and options of a run, and the part of them that the run journal records.

        .DESCRIPTION
        The entry script used to read each optional threshold of the environment configuration with its own
        "if the key is set, else the default" expression, so nothing could say afterwards which value a run
        had really used: a key missing from the configuration silently fell back to its default. This function
        is now the only place that resolves them, so the values that a run uses and the values that its journal
        record shows cannot drift apart.

        Each of SQLDiskFreeThresholdPercent (15), SQLBackupMaxAgeDays (3), JsonHistoryRetentionDays (30),
        EmailMaxItemsPerArea (10) and LogRetentionDays (180) is a whole number of 0 or more. A key that is missing
        (or $null) takes its default. A key that is not a whole number of 0 or more takes its default too, with a
        message to show, instead of an undefined value (EmailMaxItemsPerArea keeps its historical rule: a negative
        number counts as 0, which lists everything).

        Returns Value (the numbers to use), Record (what the run journal stores, see below) and Messages
        (warnings to display).

        Record holds only what is listed here, never "the configuration": the file name of the configuration
        (no folder), for each threshold its value and its source (config or default, plus invalid = true when
        the configuration held a value that could not be used), and the exclusions that the run really applies:
        for each real exclusion value (the fixed list below) it asks the ExclusionRules value of the configuration
        the same question as the entry script, $ExclusionRules.Contains('Name'), so the record and the run always
        agree, whatever the form of the value (a list of names, or a single string). A typo, a server name or a
        path typed there excludes nothing and is not recorded. The names are listed in the order of the fixed list.
        No server name, address, credential key, URL or path is ever part of it.

        .PARAMETER Config
        The environment configuration (hashtable loaded from the .psd1).

        .PARAMETER ConfigFile
        The configuration file given to the entry script; only its file name is kept.

        .EXAMPLE
        $runSetting = Get-SPSWeatherRunSetting -Config $envCfg -ConfigFile $ConfigFile
        $runSetting.Value.SQLBackupMaxAgeDays
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

    # The values that the entry script tests with $ExclusionRules.Contains(...) (and None): a test keeps this list
    # in step with the entry script and with the example configuration.
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
            # A blank string casts to 0, which is a number nobody meant: treat it as an invalid value.
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

    # The entry script tests `$ExclusionRules.Contains('Name')` on the raw value of the configuration: an exact,
    # case-sensitive element of a list, or a case-sensitive substring of a single string. Asking the same question
    # of the same value is what keeps the record equal to what the run did.
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
