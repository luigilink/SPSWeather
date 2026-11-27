function Read-SPSScheduledTask {
    <#
        .SYNOPSIS
        Reads the action arguments of a scheduled task, without changing anything.

        .DESCRIPTION
        Connects to the local Task Scheduler and reads the arguments of the program actions of one task. Read-only: it never
        registers, changes or deletes a task and never creates the folder. Returns Supported ($false off Windows), Found,
        Readable (a task that exists but cannot be read, for example without administrator rights, is not a failure) and
        Arguments (the arguments of every program action, joined by a space).

        .PARAMETER TaskName
        Name of the task.

        .PARAMETER TaskPath
        Folder of the task, 'SharePoint' by default, like Add-SPSSheduledTask.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TaskName,

        [Parameter()]
        [System.String]
        $TaskPath = 'SharePoint'
    )

    $result = [PSCustomObject]@{ Supported = $true; Found = $false; Readable = $true; Arguments = ''; Error = '' }
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        $result.Supported = $false
        return $result
    }

    # 0x80070002 and 0x80070003: the file or the path does not exist, which is how the Task Scheduler says that the folder
    # or the task is not there
    $notFound = @(-2147024894, -2147024893)
    $service = $null
    $folder = $null
    $task = $null
    try {
        $service = New-Object -ComObject 'Schedule.service'
        $service.Connect($env:COMPUTERNAME)
        $folder = $service.GetFolder($TaskPath)
        $task = $folder.GetTask($TaskName)
        $arguments = New-Object -TypeName System.Collections.ArrayList
        foreach ($action in $task.Definition.Actions) {
            # 0 = a program to start
            if ($action.Type -eq 0 -and -not [string]::IsNullOrEmpty($action.Arguments)) { [void]$arguments.Add([string]$action.Arguments) }
        }
        $result.Found = $true
        $result.Arguments = ($arguments -join ' ')
    }
    catch {
        $code = $_.Exception.HResult
        if ($null -ne $_.Exception.InnerException) { $code = $_.Exception.InnerException.HResult }
        if ($notFound -notcontains $code) {
            $result.Readable = $false
            $result.Error = $_.Exception.Message
        }
    }
    finally {
        foreach ($com in @($task, $folder, $service)) {
            if ($null -ne $com -and $com -is [System.__ComObject]) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($com) }
        }
    }
    return $result
}
