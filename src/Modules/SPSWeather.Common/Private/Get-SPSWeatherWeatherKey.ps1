function Get-SPSWeatherWeatherKey {
    <#
        .SYNOPSIS
        Gives the weather of a farm for a number of warnings and failures.

        .DESCRIPTION
        The rule of the per-farm dashboard: no failure and no warning is 'sunny', no failure is 'fair', up to
        -StormyAbove failures is 'cloudy', more is 'stormy'. Returns the key, never a label: the labels belong to
        the resource files and are chosen by the display language.

        .PARAMETER Warn
        Number of warnings.

        .PARAMETER Fail
        Number of failures.

        .PARAMETER StormyAbove
        More failures than this is stormy. Default: 5.

        .EXAMPLE
        Get-SPSWeatherWeatherKey -Warn 0 -Fail 33
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Warn,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Fail,

        [Parameter()]
        [System.Int32]
        $StormyAbove = 5
    )

    if ($Fail -eq 0 -and $Warn -eq 0) { return 'sunny' }
    if ($Fail -eq 0) { return 'fair' }
    if ($Fail -le $StormyAbove) { return 'cloudy' }
    return 'stormy'
}
