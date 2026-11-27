function Get-SPSLimitThreshold {
    <#
        .SYNOPSIS
        Gives the thresholds that apply to one object for one limit check, with the exceptions of the configuration applied.

        .DESCRIPTION
        Starts from the thresholds of the check (the defaults, or the ones of the Limits block) and applies the exception that names
        the object, if there is one: Exempt turns the check off for that object, and a Warning or a Failure replaces the threshold (an
        explicit $null means none). The object is matched without regard to case. The first matching exception wins.

        Returns Enabled, Warning and Failure (the number from which a warning is raised, and the number above which the check fails;
        either can be $null) and Reason (the reason given for the exception, empty when there is none).

        .PARAMETER Setting
        The result of Get-SPSWeatherLimitSetting.

        .PARAMETER Limit
        The name of the check.

        .PARAMETER Object
        The name of the object that is checked (a database, a server, a web application).
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        $Setting,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Limit,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Object = ''
    )

    $check = $Setting.Checks[$Limit]
    if ($null -eq $check) { return [PSCustomObject]@{ Enabled = $false; Warning = $null; Failure = $null; Reason = '' } }

    $enabled = [bool]$check.Enabled
    $warning = $check.Warning
    $failure = $check.Failure
    $reason = ''
    foreach ($exception in @($Setting.Exceptions)) {
        if ($exception.Limit -ne $Limit -or [string]::Compare($exception.Object, $Object, $true) -ne 0) { continue }
        $reason = $exception.Reason
        if ($exception.Exempt) { $enabled = $false }
        if ($exception.HasWarning) { $warning = $exception.Warning }
        if ($exception.HasFailure) { $failure = $exception.Failure }
        break
    }
    return [PSCustomObject]@{ Enabled = $enabled; Warning = $warning; Failure = $failure; Reason = $reason }
}
