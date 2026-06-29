function Add-SPSSheduledTask {
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]        
        $ExecuteAsCredential, # Credentials for Task Schedule    

        [Parameter(Mandatory = $true)]
        [System.String]
        $ActionArguments, # Arguments for the task action

        [Parameter(Mandatory = $true)]
        [System.String]
        $TaskName, # Name of the scheduled task to be added

        [Parameter()]
        [System.String]
        $Description = 'SPSWeather daily health-check', # Task description

        [Parameter()]
        [System.String]
        $TaskPath = 'SharePoint' # Path of the task folder
    )

    # Initialize variables
    $TaskDate = Get-Date -Format yyyy-MM-dd # Current date in yyyy-MM-dd format
    $TaskCmd = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' # Path to PowerShell executable
    $UserName = $ExecuteAsCredential.UserName
    $Password = $ExecuteAsCredential.GetNetworkCredential().Password

    # Connect to the local TaskScheduler Service
    $TaskSvc = New-Object -ComObject ('Schedule.service')
    $TaskSvc.Connect($env:COMPUTERNAME)
    
    # Check if the folder exists, if not, create it
    try {
        $TaskFolder = $TaskSvc.GetFolder($TaskPath) # Attempt to get the task folder
    }
    catch {
        Write-Output "Task folder '$TaskPath' does not exist. Creating folder..."
        $RootFolder = $TaskSvc.GetFolder('\') # Get the root folder
        $RootFolder.CreateFolder($TaskPath) # Create the missing task folder
        $TaskFolder = $TaskSvc.GetFolder($TaskPath) # Get the newly created folder
        Write-Output "Successfully created task folder '$TaskPath'"
    }

    # Create or update the task (no skip): adopt the SPSUpdate pattern so an
    # existing task is refreshed rather than silently skipped.
    Write-Output '--------------------------------------------------------------'
    Write-Output "Adding or updating '$TaskName' script in Task Scheduler Service ..."

    # Get credentials for Task Schedule
    $TaskAuthor = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name # Author of the task
    $TaskUser = $UserName # Username for task registration
    $TaskUserPwd = $Password # Password for task registration

    # Add a new Task Schedule
    $TaskSchd = $TaskSvc.NewTask(0)
    $TaskSchd.RegistrationInfo.Description = "$($Description)" # Task description
    $TaskSchd.RegistrationInfo.Author = $TaskAuthor # Task author
    $TaskSchd.Principal.RunLevel = 1 # Task run level (1 = Highest)

    # Task Schedule - Modify Settings Section
    $TaskSettings = $TaskSchd.Settings
    $TaskSettings.AllowDemandStart = $true
    $TaskSettings.Enabled = $true
    $TaskSettings.Hidden = $false
    $TaskSettings.StartWhenAvailable = $true

    # Task Schedule - Trigger Section: daily at 06:00
    $TaskTriggers = $TaskSchd.Triggers
    $TaskTrigger1 = $TaskTriggers.Create(2) # 2 = Daily trigger
    $TaskTrigger1.StartBoundary = $TaskDate + 'T06:00:00' # Start time
    $TaskTrigger1.DaysInterval = 1 # Interval of 1 day
    $TaskTrigger1.Enabled = $true

    # Define the task action
    $TaskAction = $TaskSchd.Actions.Create(0) # 0 = Executable action
    $TaskAction.Path = $TaskCmd # Path to the executable
    $TaskAction.Arguments = $ActionArguments # Arguments for the executable

    try {
        # Register/update the task (6 = create or update, 1 = TASK_LOGON_PASSWORD)
        [void]$TaskFolder.RegisterTaskDefinition($TaskName, $TaskSchd, 6, $TaskUser, $TaskUserPwd, 1)
        Write-Output "Successfully added or updated '$TaskName' script in Task Scheduler Service"
    }
    catch {
        throw @"
An error occurred while adding/updating the scheduled task: $($TaskName)
ActionArguments: $($ActionArguments)
Exception: $($_.Exception.Message)
"@
    }
}
