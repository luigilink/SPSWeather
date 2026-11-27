function Get-SPSWeatherTaskArgument {
    <#
        .SYNOPSIS
        Returns the arguments of the scheduled task that runs SPSWeather.ps1.

        .DESCRIPTION
        The single place that builds the arguments written in the Task Scheduler by -Action Install. They use the -File form,
        with the script and the configuration file between double quotation marks, so that a path that holds a space stays one
        argument when the task starts. The task has no working directory: the paths must already be full paths, which is why the
        entry script resolves -ConfigFile before it calls this function.

        .PARAMETER ScriptRoot
        The folder of SPSWeather.ps1.

        .PARAMETER ConfigFile
        The full path of the configuration file.

        .PARAMETER KeepEnableSmtp
        Adds the deprecated -EnableSMTP switch, for a configuration that does not define SMTPEnabled yet.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptRoot,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFile,

        [Parameter()]
        [switch]
        $KeepEnableSmtp
    )

    $scriptFile = $ScriptRoot.TrimEnd('\') + '\SPSWeather.ps1'
    $arguments = '-ExecutionPolicy Bypass -File "{0}" -ConfigFile "{1}"' -f $scriptFile, $ConfigFile
    if ($KeepEnableSmtp) {
        $arguments += ' -EnableSMTP'
    }

    return $arguments
}
