#region Import Modules
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'html.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'search.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'sps.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'sql.util.psm1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'system.util.psm1') -Force
#endregion

function Invoke-SPSCommand
{
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
function Get-SPSServer
{
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
        (Get-SPServer | Where-Object -FilterScript {$_.Role -ne 'Invalid'}).Name
    }
    return $result
}
function Invoke-SPSWebRequestUrl
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter(Mandatory=$true)]
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
        [Parameter(Mandatory=$true)]
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
            foreach ($file in $files)
            {
                if ($null -ne $file)
                {
                    Write-Output "Deleting file $file ..."
                    Remove-Item $file.FullName | out-null
                }
                else
                {
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

function Get-USPAudienceStatus {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter()]
        [System.String]
        $Farm = 'SPS'
    )
    $result = Invoke-SPSCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -Server $Server `
                                -ScriptBlock {

        $params = $args[0]
        class USPAudienceStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$StartTime
            [System.String]$EndTime
            [System.String]$Duration
            [System.String]$Status
        }

        $serviceAppUSP = Get-SPServiceApplication -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.GetType().FullName -eq 'Microsoft.Office.Server.Administration.UserProfileApplication'
        }

        if ($null -ne $serviceAppUSP) {
            $tbUSPAudienceStatus = New-Object -TypeName System.Collections.ArrayList
            $timerJob = Get-SPTimerJob | Where-Object -FilterScript { $_.Name -like '*_AudienceCompilationJob*' }
            if ($null -ne $timerJob) {
                $currentTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById([System.TimeZoneInfo]::Local.Id)
                $lastEntries = $timerJob.HistoryEntries | Where-Object -FilterScript { $_.StartTime -gt (Get-Date).AddDays(-1) }
                foreach ($lastEntry in $lastEntries) {
                    if ($null -ne $lastEntry.StartTime) {
                        $startTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($lastEntry.StartTime, $currentTimeZone)
                    }
                    if ($null -ne $lastEntry.EndTime) {
                        $endTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($lastEntry.EndTime, $currentTimeZone)
                    }
                    if (($null -ne $startTime) -and ($null -ne $endTime)) {
                        $duration = [math]::Round(($endTime - $startTime).TotalSeconds)
                    }
                    $supAudienceStatus = $lastEntry.Status
                    [void]$tbUSPAudienceStatus.Add([USPAudienceStatus]@{
                            Farm      = $params.Farm;
                            Server    = $lastEntry.ServerName;
                            StartTime = $startTime;
                            EndTime   = $endTime;
                            Duration  = $duration;
                            Status    = $supAudienceStatus;
                        })
                }
                return $tbUSPAudienceStatus
            }
        }
    }
    return $result
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