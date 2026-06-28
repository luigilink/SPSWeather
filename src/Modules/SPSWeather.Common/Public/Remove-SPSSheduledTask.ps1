function Remove-SPSSheduledTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TaskName, # Name of the scheduled task to be removed

        [Parameter()]
        [System.String]
        $TaskPath = 'SharePoint' # Path of the task folder
    )

    # Connect to the local TaskScheduler Service
    $TaskSvc = New-Object -ComObject ('Schedule.service')
    $TaskSvc.Connect($env:COMPUTERNAME)
    
    # Check if the folder exists
    try {
        $TaskFolder = $TaskSvc.GetFolder($TaskPath) # Attempt to get the task folder
    }
    catch {
        Write-Output "Task folder '$TaskPath' does not exist."
    }

    # Retrieve the scheduled task
    $getScheduledTask = $TaskFolder.GetTasks(0) | Where-Object -FilterScript {
        $_.Name -eq $TaskName
    }
    
    if ($null -eq $getScheduledTask) {
        Write-Warning -Message 'Scheduled Task already removed - skipping.' # Task not found
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "Removing $($TaskName) script in Task Scheduler Service ..."
        if ($PSCmdlet.ShouldProcess($TaskName, 'Remove scheduled task')) {
            try {
                $TaskFolder.DeleteTask($TaskName, $null) # Remove the task
                Write-Output "Successfully removed $($TaskName) script from Task Scheduler Service"
            }
            catch {
                Write-Error -Message $_ # Handle any errors during task removal
            }
        }
    }
}
