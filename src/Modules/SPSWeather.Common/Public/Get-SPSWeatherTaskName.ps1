function Get-SPSWeatherTaskName {
    <#
        .SYNOPSIS
        Returns the name of the scheduled task of an application and an environment.

        .DESCRIPTION
        The single place that builds the name 'SPSWeather-<Application>-<Environment>', used by the entry script
        (-Action Install and Uninstall) and by the readiness check, so the two can never name the task differently.
        The task lives in the 'SharePoint' folder of the Task Scheduler.

        .PARAMETER Application
        The ApplicationName of the configuration.

        .PARAMETER Environment
        The ConfigurationName of the configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Application,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Environment
    )

    return "SPSWeather-$($Application)-$($Environment)"
}
