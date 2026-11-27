function Get-SPSWeatherLimitSetting {
    <#
        .SYNOPSIS
        Resolves the optional Limits block of the configuration: the thresholds of every limit check, the checks that are turned off
        and the exceptions for one object.

        .DESCRIPTION
        The only place that reads the Limits block, so that the values a run uses and the ones its journal shows cannot drift apart.
        A threshold is a Warning (the value from which a warning is raised) and a Failure (the limit above which the check fails);
        either can be $null for none. A value that is not a number of 0 or more (a boolean is never cast), a warning above the failure,
        an unknown check name or setting, an exception without Limit, Object or anything to change, are reported in Messages and the
        default is used (an invalid exception is skipped): a bad value never stops a run.

        Returns Checks (by name: Name, Unit, Warning, Failure, Enabled, WarningSource, FailureSource), Exceptions, Record (what the run
        journal stores: the thresholds with their origin, the checks that are off and the number of exceptions, never an object name)
        and Messages. See the wiki page Limits.

        .PARAMETER Config
        The environment configuration (hashtable loaded from the .psd1).

        .EXAMPLE
        $limitSetting = Get-SPSWeatherLimitSetting -Config $envCfg
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Config
    )

    # Warning is the value from which a warning is raised, Failure the limit above which the check fails
    $definitions = @(
        @{ Name = 'ContentDatabaseSize'; Unit = 'GB'; Warning = 150; Failure = 200; Thresholds = $true }
        @{ Name = 'SiteCountPerDatabase'; Unit = ''; Warning = 5000; Failure = 10000; Thresholds = $true }
        @{ Name = 'ContentDatabasesPerFarm'; Unit = ''; Warning = 375; Failure = 500; Thresholds = $true }
        @{ Name = 'WebApplicationsPerFarm'; Unit = ''; Warning = 15; Failure = 20; Thresholds = $true }
        @{ Name = 'ManagedPaths'; Unit = ''; Warning = 15; Failure = 20; Thresholds = $true }
        @{ Name = 'DistributedCacheSize'; Unit = 'GB'; Warning = $null; Failure = 16; Thresholds = $true }
        @{ Name = 'ApplicationPoolsPerServer'; Unit = ''; Warning = 11; Failure = $null; Thresholds = $true }
        @{ Name = 'SearchTopology'; Unit = ''; Warning = $null; Failure = $null; Thresholds = $false }
    )
    $known = @($definitions | ForEach-Object -Process { $_.Name })
    $settingNames = @('Disabled', 'Exceptions')

    $messages = New-Object -TypeName System.Collections.ArrayList
    $checks = [ordered]@{}
    foreach ($definition in $definitions) {
        $checks[$definition.Name] = [ordered]@{
            Name = $definition.Name; Unit = $definition.Unit; Warning = $definition.Warning; Failure = $definition.Failure
            Enabled = $true; WarningSource = 'default'; FailureSource = 'default'
        }
    }

    # A number of 0 or more. A boolean, a blank and any text that is not a number give $null: they are never cast
    function ConvertTo-LimitNumber {
        param($Raw)
        if ($null -eq $Raw -or $Raw -is [System.Boolean]) { return $null }
        $number = 0.0
        if ($Raw -is [System.String]) {
            if (-not [double]::TryParse($Raw.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $null }
        }
        elseif ($Raw -is [System.ValueType] -and ($Raw -is [System.Int32] -or $Raw -is [System.Int64] -or $Raw -is [System.Double] -or $Raw -is [System.Decimal] -or $Raw -is [System.Single])) {
            $number = [double]$Raw
        }
        else { return $null }
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) { return $null }
        return $number
    }
    function Get-ShownValue {
        param($Raw)
        if ($null -eq $Raw) { return '$null' }
        if ($Raw -is [System.String]) { return "'$Raw'" }
        return "a value of type $($Raw.GetType().Name)"
    }

    $limits = $null
    $present = ($null -ne $Config) -and ($Config -is [System.Collections.IDictionary]) -and $Config.Contains('Limits')
    if ($present) {
        $limits = $Config['Limits']
        if ($limits -isnot [System.Collections.IDictionary]) {
            [void]$messages.Add("Limits must be a table of settings (got $(Get-ShownValue -Raw $limits)); the default limits are used.")
            $limits = $null
        }
    }

    $exceptions = New-Object -TypeName System.Collections.ArrayList
    if ($null -ne $limits) {
        foreach ($key in @($limits.Keys)) {
            if ($known -notcontains "$key" -and $settingNames -notcontains "$key") {
                [void]$messages.Add("Limits.$key is not a known setting and is ignored (the checks are: $($known -join ', '); the other settings are Disabled and Exceptions).")
            }
        }

        foreach ($definition in $definitions) {
            $name = $definition.Name
            if (-not $limits.Contains($name)) { continue }
            $raw = $limits[$name]
            if ($raw -isnot [System.Collections.IDictionary]) {
                [void]$messages.Add("Limits.$name must be a table with Warning and Failure (got $(Get-ShownValue -Raw $raw)); the default is used.")
                continue
            }
            if (-not $definition.Thresholds) {
                [void]$messages.Add("Limits.$name has no threshold to set (its limits are fixed); use Disabled to turn it off.")
                continue
            }
            $warning = $definition.Warning; $failure = $definition.Failure
            $warningSource = 'default'; $failureSource = 'default'
            $valid = $true
            foreach ($setting in @('Warning', 'Failure')) {
                if (-not $raw.Contains($setting)) { continue }
                $value = $raw[$setting]
                # An explicit $null means none: no warning, or no failure
                $number = if ($null -eq $value) { $null } else { ConvertTo-LimitNumber -Raw $value }
                if ($null -ne $value -and $null -eq $number) {
                    [void]$messages.Add("Limits.${name}.${setting} must be a number of 0 or more, or `$null for none (got $(Get-ShownValue -Raw $value)); the default is used.")
                    $valid = $false
                    continue
                }
                if ($setting -eq 'Warning') { $warning = $number; $warningSource = 'config' } else { $failure = $number; $failureSource = 'config' }
            }
            foreach ($setting in @($raw.Keys)) {
                if (@('Warning', 'Failure') -notcontains "$setting") {
                    [void]$messages.Add("Limits.$name.$setting is not a known setting and is ignored (Warning and Failure are).")
                }
            }
            if ($valid -and $null -ne $warning -and $null -ne $failure -and $warning -gt $failure) {
                [void]$messages.Add("Limits.${name}: the warning ($warning) is above the failure ($failure); the defaults are used.")
                $valid = $false
            }
            if (-not $valid) {
                # One bad value: the whole check keeps its defaults, so that it is never half configured
                $warning = $definition.Warning; $failure = $definition.Failure
                $warningSource = 'default'; $failureSource = 'default'
            }
            $checks[$name].Warning = $warning; $checks[$name].Failure = $failure
            $checks[$name].WarningSource = $warningSource; $checks[$name].FailureSource = $failureSource
        }

        if ($limits.Contains('Disabled')) {
            $rawDisabled = $limits['Disabled']
            if ($rawDisabled -is [System.String]) { $rawDisabled = @($rawDisabled) }
            if (($null -eq $rawDisabled) -or ($rawDisabled -is [System.Collections.IDictionary]) -or ($rawDisabled -isnot [System.Collections.IEnumerable])) {
                [void]$messages.Add("Limits.Disabled must be a list of check names (got $(Get-ShownValue -Raw $rawDisabled)); no check is turned off.")
                $rawDisabled = @()
            }
            foreach ($item in @($rawDisabled)) {
                if ($item -is [System.String] -and $known -contains $item.Trim()) { $checks[$item.Trim()].Enabled = $false }
                else { [void]$messages.Add("Limits.Disabled holds $(Get-ShownValue -Raw $item), which is not the name of a check ($($known -join ', ')); it is ignored.") }
            }
        }

        if ($limits.Contains('Exceptions')) {
            $rawExceptions = $limits['Exceptions']
            # A single table is a list of one
            if ($rawExceptions -is [System.Collections.IDictionary]) { $rawExceptions = @($rawExceptions) }
            if (($null -eq $rawExceptions) -or ($rawExceptions -is [System.String]) -or ($rawExceptions -isnot [System.Collections.IEnumerable])) {
                [void]$messages.Add("Limits.Exceptions must be a list of tables (got $(Get-ShownValue -Raw $rawExceptions)); there is no exception.")
                $rawExceptions = @()
            }
            $position = 0
            foreach ($item in @($rawExceptions)) {
                $position++
                $label = "Limits.Exceptions[$position]"
                if ($item -isnot [System.Collections.IDictionary]) {
                    [void]$messages.Add("$label must be a table with Limit, Object and Warning, Failure or Exempt (got $(Get-ShownValue -Raw $item)); it is ignored.")
                    continue
                }
                $limitName = if ($item.Contains('Limit') -and $item['Limit'] -is [System.String]) { $item['Limit'].Trim() } else { '' }
                $objectName = if ($item.Contains('Object') -and $item['Object'] -is [System.String]) { $item['Object'].Trim() } else { '' }
                if ($known -notcontains $limitName) {
                    [void]$messages.Add("$label has no valid Limit (one of: $($known -join ', ')); it is ignored.")
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($objectName)) {
                    [void]$messages.Add("$label has no Object (the name of the database, server or web application); it is ignored.")
                    continue
                }
                $exempt = $false
                if ($item.Contains('Exempt')) {
                    $rawExempt = $item['Exempt']
                    $parsed = $false
                    if ($rawExempt -is [System.Boolean]) { $exempt = $rawExempt }
                    elseif ($rawExempt -is [System.String] -and [bool]::TryParse($rawExempt.Trim(), [ref]$parsed)) { $exempt = $parsed }
                    else {
                        [void]$messages.Add("$label.Exempt must be `$true or `$false (got $(Get-ShownValue -Raw $rawExempt)); it is ignored.")
                        continue
                    }
                }
                $hasWarning = $item.Contains('Warning'); $hasFailure = $item.Contains('Failure')
                $warning = $null; $failure = $null
                $valid = $true
                foreach ($setting in @('Warning', 'Failure')) {
                    if (-not $item.Contains($setting)) { continue }
                    $value = $item[$setting]
                    $number = if ($null -eq $value) { $null } else { ConvertTo-LimitNumber -Raw $value }
                    if ($null -ne $value -and $null -eq $number) {
                        [void]$messages.Add("${label}.${setting} must be a number of 0 or more, or `$null for none (got $(Get-ShownValue -Raw $value)); the exception is ignored.")
                        $valid = $false
                    }
                    if ($setting -eq 'Warning') { $warning = $number } else { $failure = $number }
                }
                if (-not $valid) { continue }
                $definition = $definitions | Where-Object -FilterScript { $_.Name -eq $limitName }
                if (-not $definition.Thresholds -and ($hasWarning -or $hasFailure)) {
                    [void]$messages.Add("$label.Limit '$limitName' has no threshold to set; use Exempt = `$true. The exception is ignored.")
                    continue
                }
                if ($null -ne $warning -and $null -ne $failure -and $warning -gt $failure) {
                    [void]$messages.Add("${label}: the warning ($warning) is above the failure ($failure); the exception is ignored.")
                    continue
                }
                if (-not $exempt -and -not $hasWarning -and -not $hasFailure) {
                    [void]$messages.Add("$label changes nothing: give a Warning, a Failure or Exempt = `$true; it is ignored.")
                    continue
                }
                $reason = if ($item.Contains('Reason') -and $item['Reason'] -is [System.String]) { $item['Reason'].Trim() } else { '' }
                [void]$exceptions.Add([PSCustomObject]@{
                        Limit = $limitName; Object = $objectName; Exempt = $exempt
                        HasWarning = $hasWarning; Warning = $warning; HasFailure = $hasFailure; Failure = $failure; Reason = $reason
                    })
            }
        }
    }

    # The record has the shape of the thresholds of Get-SPSWeatherRunSetting ({ value; source } by name), so that the run journal, the
    # detection of the changes between two runs and the Settings tab of the cockpit take it as it is: one entry for each number,
    # named Limits.<Check>.Warning and Limits.<Check>.Failure ($null is no threshold, and is recorded as such)
    $thresholds = [ordered]@{}
    $disabled = New-Object -TypeName System.Collections.ArrayList
    foreach ($name in $checks.Keys) {
        $check = $checks[$name]
        if (-not $check.Enabled) { [void]$disabled.Add($name) }
        if ($definitions | Where-Object -FilterScript { $_.Name -eq $name -and $_.Thresholds }) {
            $thresholds["Limits.$name.Warning"] = [ordered]@{ value = $check.Warning; source = $check.WarningSource }
            $thresholds["Limits.$name.Failure"] = [ordered]@{ value = $check.Failure; source = $check.FailureSource }
        }
    }

    return [PSCustomObject]@{
        Checks     = $checks
        Exceptions = @($exceptions)
        Record     = [PSCustomObject][ordered]@{
            thresholds = [PSCustomObject]$thresholds
            disabled   = @($disabled | ForEach-Object -Process { "Limits.$_" })
            exceptions = $exceptions.Count
        }
        Messages   = @($messages)
    }
}
