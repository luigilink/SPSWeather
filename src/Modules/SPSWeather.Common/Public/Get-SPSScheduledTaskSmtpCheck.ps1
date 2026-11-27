function Get-SPSScheduledTaskSmtpCheck {
    <#
        .SYNOPSIS
        Tells whether the scheduled task of an environment still runs the script with the deprecated -EnableSMTP switch.

        .DESCRIPTION
        4.0.0 removes the -EnableSmtp switch of SPSWeather.ps1. A task registered by an older version may still carry it:
        PowerShell would then refuse to start the script and the morning run would not happen, with an error that only shows
        in the Task Scheduler. This reads the task (read-only, see Read-SPSScheduledTask) and looks for the switch as a token
        of the action arguments: case does not matter, quotes are respected, and -EnableSMTP:$false counts. An abbreviation of
        the parameter name is not looked for, as the script writes the task itself.

        Returns Status, for the readiness check: WARN when the switch is there (with what to do), PASS when it is not, and SKIP,
        which is only information and never a failure, when the task does not exist on this host, when the host is not Windows,
        or when the task cannot be read. State says which case it is (HasSwitch, Clean, NotFound, Unreadable, NotSupported).
        It never throws.

        .PARAMETER Application
        The ApplicationName of the configuration.

        .PARAMETER Environment
        The ConfigurationName of the configuration.

        .PARAMETER ConfigDefinesEnabled
        The configuration defines SMTPEnabled (the ConfigDefinesEnabled of Resolve-SPSSmtpSetting). It decides what the warning
        asks for: running -Action Install again, or adding SMTPEnabled first.

        .EXAMPLE
        $smtp = Resolve-SPSSmtpSetting -Config $cfg
        Get-SPSScheduledTaskSmtpCheck -Application 'contoso' -Environment 'PROD' -ConfigDefinesEnabled:$smtp.ConfigDefinesEnabled
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Application,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Environment,

        [Parameter()]
        [switch]
        $ConfigDefinesEnabled
    )

    $taskName = Get-SPSWeatherTaskName -Application $Application -Environment $Environment
    $outcome = {
        param([string]$State, [string]$Status, [string]$Detail)
        [PSCustomObject]@{ TaskName = $taskName; State = $State; Status = $Status; Detail = $Detail }
    }

    try { $task = Read-SPSScheduledTask -TaskName $taskName }
    catch { $task = [PSCustomObject]@{ Supported = $true; Found = $true; Readable = $false; Arguments = ''; Error = $_.Exception.Message } }

    if ($null -eq $task) {
        return & $outcome 'Unreadable' 'SKIP' "The scheduled task '$taskName' cannot be read."
    }
    if (-not $task.Supported) {
        return & $outcome 'NotSupported' 'SKIP' 'The scheduled task is only read on Windows.'
    }
    if (-not $task.Readable) {
        return & $outcome 'Unreadable' 'SKIP' "The scheduled task '$taskName' cannot be read ($($task.Error)). Run this check as an administrator."
    }
    if (-not $task.Found) {
        return & $outcome 'NotFound' 'SKIP' "No scheduled task named '$taskName' on this host (not installed here, or installed on another server)."
    }

    # A token is a run of characters that are not blanks, or a quoted part with double quotes or with apostrophes (the task that -Action Install
    # registers is read by PowerShell as a command, which honours both): a quoted path that holds the text is not the switch. An apostrophe that is
    # never closed, as in a folder named O'Brien, is an ordinary character.
    $hasSwitch = $false
    foreach ($match in [regex]::Matches([string]$task.Arguments, '(?:"[^"]*"|''[^'']*''|\S)+')) {
        if (($match.Value -replace '["'']', '') -match '^-EnableSMTP(:.*)?$') { $hasSwitch = $true; break }
    }
    if (-not $hasSwitch) {
        return & $outcome 'Clean' 'PASS' "The scheduled task '$taskName' does not use the deprecated -EnableSMTP switch."
    }

    $detail = "The scheduled task '$taskName' still runs the script with the deprecated -EnableSMTP switch. 4.0.0 removes it and the script will then no longer start, so the morning run would not happen. "
    if ($ConfigDefinesEnabled) {
        $detail += 'SMTPEnabled is defined in the configuration, so the switch does nothing today: run SPSWeather.ps1 -Action Install again to register the task without it.'
    }
    else {
        $detail += 'SMTPEnabled is not defined in the configuration, so the switch still decides whether the email is sent: add SMTPEnabled = $true (or $false) to the configuration file, then run SPSWeather.ps1 -Action Install again to register the task without it.'
    }
    return & $outcome 'HasSwitch' 'WARN' $detail
}
