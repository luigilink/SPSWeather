#region Import Modules
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'html.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'search.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'sps.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'sql.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'system.util.psm1') -Force
#endregion

function Invoke-SPSCommand {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter()]
        [Object[]]
        $Arguments,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Server
    )

    $VerbosePreference = 'Continue'
    $baseScript = @"
        if (`$null -eq (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue))
        {
            Add-PSSnapin Microsoft.SharePoint.PowerShell
        }

"@

    $invokeArgs = @{
        ScriptBlock = [ScriptBlock]::Create($baseScript + $ScriptBlock.ToString())
    }
    if ($null -ne $Arguments) {
        $invokeArgs.Add("ArgumentList", $Arguments)
    }
    if ($null -eq $Credential) {
        throw 'You need to specify a Credential'
    }
    else {
        Write-Verbose -Message ("Executing using a provided credential and local PSSession " + `
                "as user $($Credential.UserName)")

        # Running garbage collection to resolve issues related to Azure DSC extention use
        [GC]::Collect()

        $session = New-PSSession -ComputerName $Server `
            -Credential $Credential `
            -Authentication CredSSP `
            -Name "Microsoft.SharePoint.PSSession" `
            -SessionOption (New-PSSessionOption -OperationTimeout 0 `
                -IdleTimeout 60000) `
            -ErrorAction Continue

        if ($session) {
            $invokeArgs.Add("Session", $session)
        }

        try {
            return Invoke-Command @invokeArgs -Verbose
        }
        catch {
            throw $_
        }
        finally {
            if ($session) {
                Remove-PSSession -Session $session
            }
        }
    }
}
function Get-SPSServer {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose "Getting SharePoint Servers of Farm '$Server'"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' }).Name
    }
    return $result
}
function Invoke-SPSWebRequestUrl {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $URL,

        [Parameter()]
        [System.String]
        $Name
    )

    Write-Verbose -Message "Invoking WebRequest from '$Server' with User '$UserName'"
    Write-Verbose -Message "Testing $Name access on $url"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        try {
            $responseObject = Invoke-WebRequest -Uri $params.URL `
                -UseDefaultCredentials `
                -Method Get `
                -UseBasicParsing `
                -Verbose
        }
        catch [Net.WebException] {
            Write-Output $_.Exception.Message
        }

        if ($responseObject.StatusCode -ne 200) {
            throw "$($params.Name) access failed. $($params.URL) is not responding properly."
        }
        else {
            Write-Verbose -Message "HTTP 200 - $($params.URL) is accessible"
        }
    }
    return $result
}

function Clear-SPSLog {
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $path,

        [Parameter()]
        [System.UInt32]
        $Retention = 180
    )

    if (Test-Path $path) {
        # Get the current date
        $Now = Get-Date
        # Define LastWriteTime parameter based on $days
        $LastWrite = $Now.AddDays(-$Retention)
        # Get files based on lastwrite filter and specified folder
        $files = Get-Childitem -Path $path -Filter "$($logFileName)*" | Where-Object -FilterScript {
            $_.LastWriteTime -le "$LastWrite"
        }
        if ($files) {
            Write-Output '--------------------------------------------------------------'
            Write-Output "Cleaning log files in $path ..."
            foreach ($file in $files) {
                if ($null -ne $file) {
                    Write-Output "Deleting file $file ..."
                    Remove-Item $file.FullName | out-null
                }
                else {
                    Write-Output 'No more log files to delete'
                    Write-Output '--------------------------------------------------------------'
                }
            }
        }
        else {
            Write-Output '--------------------------------------------------------------'
            Write-Output "$path - No needs to delete log files"
            Write-Output '--------------------------------------------------------------'
        }
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "$path does not exist"
        Write-Output '--------------------------------------------------------------'
    }
}
function Get-SPWeatherListInfo {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [System.String]
        $Version,

        [Parameter()]
        [System.String]
        $PSVersion,

        [Parameter()]
        [System.String]
        $UserAccount,

        [Parameter()]
        [System.String]
        $DateStarted,

        [Parameter()]
        [System.String]
        $DateEnded,

        [Parameter()]
        [System.String]
        $Environment,

        [Parameter()]
        [System.String]
        $Application
    )

    class SPWeatherScriptInfo {
        [System.String]$Version
        [System.String]$PSVersion
        [System.String]$UserAccount
        [System.String]$DateStarted
        [System.String]$DateEnded
        [System.String]$Environment
        [System.String]$Application
    }

    try {
        #Initialize ArrayList variable
        $tbSPWeatherScriptInfo = New-Object -TypeName System.Collections.ArrayList
        [void]$tbSPWeatherScriptInfo.Add([SPWeatherScriptInfo]@{
                Version     = $Version;
                PSVersion   = $PSVersion;
                UserAccount = $UserAccount;
                DateStarted = $DateStarted;
                DateEnded   = $DateEnded;
                Environment = $Environment;
                Application = $Application;
            })
    }
    catch {
        return $_
    }
    return $tbSPWeatherScriptInfo
}

function Remove-SPSSheduledTask {
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
        try {
            $TaskFolder.DeleteTask($TaskName, $null) # Remove the task
            Write-Output "Successfully removed $($TaskName) script from Task Scheduler Service"
        }
        catch {
            Write-Error -Message $_ # Handle any errors during task removal
        }
    }
}

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

    # Retrieve the scheduled task
    $getScheduledTask = $TaskFolder.GetTasks(0) | Where-Object -FilterScript {
        $_.Name -eq $TaskName
    }
    
    if ($getScheduledTask) {
        Write-Warning -Message 'Scheduled Task already exists - skipping.' # Task already exists
    }
    else {
        Write-Output '--------------------------------------------------------------'
        Write-Output "Adding '$TaskName' script in Task Scheduler Service ..."
        
        # Get credentials for Task Schedule
        $TaskAuthor = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name # Author of the task
        $TaskUser = $UserName # Username for task registration
        $TaskUserPwd = $Password # Password for task registration
        
        # Add a new Task Schedule
        $TaskSchd = $TaskSvc.NewTask(0)
        $TaskSchd.RegistrationInfo.Description = "$($TaskName) Task - Start at 6:00 daily" # Task description
        $TaskSchd.RegistrationInfo.Author = $TaskAuthor # Task author
        $TaskSchd.Principal.RunLevel = 1 # Task run level (1 = Highest)
        
        # Task Schedule - Modify Settings Section
        $TaskSettings = $TaskSchd.Settings
        $TaskSettings.AllowDemandStart = $true
        $TaskSettings.Enabled = $true
        $TaskSettings.Hidden = $false
        $TaskSettings.StartWhenAvailable = $true
        
        # Task Schedule - Trigger Section
        $TaskTriggers = $TaskSchd.Triggers
        
        # Add Trigger Type 2 OnSchedule Daily Start at 6:00 AM
        $TaskTrigger1 = $TaskTriggers.Create(2) # 2 = Daily trigger
        $TaskTrigger1.StartBoundary = $TaskDate + 'T06:00:00' # Start time
        $TaskTrigger1.DaysInterval = 1 # Interval of 1 day
        $TaskTrigger1.Enabled = $true
        
        # Define the task action
        $TaskAction = $TaskSchd.Actions.Create(0) # 0 = Executable action
        $TaskAction.Path = $TaskCmd # Path to the executable
        $TaskAction.Arguments = $ActionArguments # Arguments for the executable
        
        try {
            # Register the task
            $TaskFolder.RegisterTaskDefinition($TaskName, $TaskSchd, 6, $TaskUser, $TaskUserPwd, 1)
            Write-Output "Successfully added '$TaskName' script in Task Scheduler Service"
        }
        catch {
            Write-Error -Message $_ # Handle any errors during task registration
        }
    }
}
