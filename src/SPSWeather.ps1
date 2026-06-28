<#
    .SYNOPSIS
    SPSWeather script for SharePoint Server

    .DESCRIPTION
    SPSWeather is a PowerShell script tool to get farm information and send it by mail

    .PARAMETER ConfigFile
    Need parameter ConfigFile, example:
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -ConfigFile 'contoso-PROD.psd1'

    .PARAMETER EnableSmtp
    Use the switch EnableSmtp parameter if you want to enable Email notifications using SMTP
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -EnableSmtp

    .PARAMETER Install
    Use the switch Install parameter if you want to add the SPSWeather script in taskscheduler
    InstallAccount parameter need to be set
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.psd1'

    .PARAMETER InstallAccount
    Need parameter InstallAccount when you use the switch Install parameter
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.psd1'

    .PARAMETER Uninstall
    Use the switch Uninstall parameter if you want to remove the SPSWeather script from taskscheduler
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Uninstall

    .EXAMPLE
    SPSWeather.ps1 -ConfigFile 'contoso-PROD.psd1' -EnableSmtp
    SPSWeather.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.psd1'
    SPSWeather.ps1 -Uninstall -ConfigFile 'contoso-PROD.psd1'

    .NOTES
    FileName:	SPSWeather.ps1
    Author:		luigilink (Jean-Cyril DROUHIN)
    Date:		Ocotober 15, 2024
    Version:	Defined by the SPSWeather.Common module manifest (ModuleVersion)

    .LINK
    https://spjc.fr/
    https://github.com/luigilink/SPSWeather
#>
param
(
    [Parameter(Position = 1, Mandatory = $true)]
    [System.String]
    $ConfigFile,

    [Parameter(Position = 2)]
    [switch]
    $EnableSmtp,

    [Parameter(Position = 3)]
    [switch]
    $Install,

    [Parameter(Position = 4)]
    [System.Management.Automation.PSCredential]
    $InstallAccount,

    [Parameter(Position = 5)]
    [switch]
    $Uninstall
)

#region Main
# ===================================================================================
#
# SPSWeather Script - MAIN Region
#
# ===================================================================================
Clear-Host
$Host.UI.RawUI.WindowTitle = "SPSWeather script running on $env:COMPUTERNAME"
$script:HelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules'
Import-Module -Name (Join-Path -Path $script:HelperModulePath -ChildPath 'SPSWeather.Common\SPSWeather.Common.psd1') -Force

if (Test-Path $ConfigFile) {
    $envCfg = Import-PowerShellDataFile -Path $ConfigFile
    $Application = $envCfg.ApplicationName
    $Environment = $envCfg.ConfigurationName
    $ExclusionRules = $envCfg.ExclusionRules
}
else {
    Throw "Missing $ConfigFile"
}

# Define variable
$spsWeatherVersion = (Get-Module -Name 'SPSWeather.Common').Version.ToString()
$getDateFormatted = Get-Date -Format yyyy-MM-dd
$spWeatherFileName = "$($Application)-$($Environment)-$($getDateFormatted)"
$spWeatherTaskName = "SPSWeather-$($Application)-$($Environment)"
$currentUser = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
$scriptRootPath = Split-Path -parent $MyInvocation.MyCommand.Definition
$pathLogsFolder = Join-Path -Path $scriptRootPath -ChildPath 'Logs'
$pathResultsFolder = Join-Path -Path $scriptRootPath -ChildPath 'Results'
$pathConfigFolder = Join-Path -Path $scriptRootPath -ChildPath 'Config'

$pathLogFile = Join-Path -Path $pathLogsFolder -ChildPath ($spWeatherFileName + '.log')
$pathHTMLFile = Join-Path -Path $pathResultsFolder -ChildPath ($spWeatherFileName + '.html')
$pathJsonFile = Join-Path -Path $pathResultsFolder -ChildPath ($spWeatherFileName + '.json')
$DateStarted = Get-date
$psVersion = ($host).Version.ToString()
$mailAlert = 'INFO'
$mailPriority = 'Low'

Start-Transcript -Path $pathLogFile -IncludeInvocationHeader
Write-Output '-------------------------------------'
Write-Output "| Automated Script - SPSWeather v$spsWeatherVersion"
Write-Output "| Started on : $DateStarted by $currentUser"
Write-Output "| PowerShell Version: $psVersion"
Write-Output '-------------------------------------'

# Check UserName and Password if Install parameter is used
if ($Install) {
    if ($null -eq $InstallAccount) {
        Write-Warning -Message ('SPSWeather: Install parameter is set. Please set also InstallAccount ' + `
                "parameter. `nSee https://github.com/luigilink/SPSWeather/wiki for details.")
        Break
    }
    else {
        $UserName = $InstallAccount.UserName
        $Password = $InstallAccount.GetNetworkCredential().Password
        $currentDomain = 'LDAP://' + ([ADSI]'').distinguishedName
        Write-Output "Checking Account `"$UserName`" ..."
        $dom = New-Object System.DirectoryServices.DirectoryEntry($currentDomain, $UserName, $Password)
        if ($null -eq $dom.Path) {
            Write-Warning -Message "Password Invalid for user:`"$UserName`""
            Break
        }
    }
}

# Initialize required folders
# Check if the path exists
if (-Not (Test-Path -Path $pathResultsFolder)) {
    # If the path does not exist, create the directory
    New-Item -ItemType Directory -Path $pathResultsFolder
}
if (-Not (Test-Path -Path $pathConfigFolder)) {
    # If the path does not exist, create the directory
    New-Item -ItemType Directory -Path $pathConfigFolder
}

# Initialize jSON Object
New-Variable -Name jsonObject `
    -Description 'jSON object variable' `
    -Option AllScope `
    -Force
$jsonObject = [PSCustomObject]@{}
$tbUpgradeListItems = @()
$tbhealthListItems = @()
$tbSPAPIHttpStatus = @()
$tbSPSSitesHttpStatus = @()
$tbSPSfailedJobs = @()
$tbSPSolutions = @()
$tbSPSSearchEntCrawlStatus = @()
$tbSPSSearchEntCrawlLogs = @()
$tbSPSSearchEntTopology = @()
$tbAppFabricStatus = @()
$tbUSPAudienceStatus = @()
$tbIISApplicationPoolStatus = @()
$tbIISWorkerProcessStatus = @()
$tbIISSiteCertStatus = @()
$tbSYSEventViewerAppErrors = @()
$tbSYSLastRebootStatus = @()
$tbSYSDOTNETVersion = @()
$tbSYSDiskUsageStatus = @()
$tbSPWeatherListInfo = @()
$tbSPSContentDBStatus = @()
$tbSQLInstanceStatus = @()
$tbSQLDatabaseStatus = @()
$tbSQLDiskStatus = @()
$tbSQLAvailabilityStatus = @()
$tbSQLAliasStatus = @()

# Check Permission Level
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Warning -Message 'You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!'
    Break
}
else {
    Write-Output "Setting power management plan to `"High Performance`"..."
    Start-Process -FilePath "$env:SystemRoot\system32\powercfg.exe" `
        -ArgumentList '/s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' `
        -NoNewWindow

    if ($Uninstall) {
        # Remove SPSWeather script from scheduled Task
        Remove-SPSSheduledTask -TaskName $spWeatherTaskName

        # Remove the stored secret from secrets.psd1 (if present)
        Set-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder -Remove
    }
    elseif ($Install) {
        # Persist the service credential as a DPAPI-encrypted SecureString in
        # secrets.psd1. Run -Install AS the service account so the value can be
        # decrypted at run time by the scheduled task.
        Set-SPSSecret -CredentialKey $envCfg.CredentialKey -Credential $InstallAccount -ConfigPath $pathConfigFolder

        # Add SPSWeather script in a new scheduled Task
        Add-SPSSheduledTask -ExecuteAsCredential $InstallAccount -TaskName $spWeatherTaskName -ActionArguments "-Execution Bypass $($scriptRootPath)\SPSWeather.ps1 -ConfigFile $($ConfigFile) -EnableSMTP"
    }
    else {
        # Initialize Security
        $scriptFQDN = $envCfg.Domain
        $credential = Get-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder
        if ($null -ne $credential) {
            New-Variable -Name 'ADM' -Value $credential -Force
        }
        else {
            Throw "Credential '$($envCfg.CredentialKey)' was not found in Config\secrets.psd1. Run SPSWeather.ps1 -Install as the service account, or populate secrets.psd1 manually. See the wiki for details."
        }
        $spFarms = $envCfg.Farms
        # Optional SQL thresholds (config overrides, with safe defaults)
        $sqlDiskThreshold = if ($null -ne $envCfg.SQLDiskFreeThresholdPercent) { [int]$envCfg.SQLDiskFreeThresholdPercent } else { 15 }
        $sqlBackupMaxAge = if ($null -ne $envCfg.SQLBackupMaxAgeDays) { [int]$envCfg.SQLBackupMaxAgeDays } else { 3 }
        Add-SPSWeatherEvent -Message "SPSWeather $spsWeatherVersion started for $Application/$Environment on $env:COMPUTERNAME." -EntryType 'Information' -EventID 1000
        foreach ($spFarm in $spFarms) {
            $spTargetServer = "$($spFarm.Server).$($scriptFQDN)"
            Write-Output '--------------------------------------------------------------'
            Write-Output "Farm: $($spFarm.Name) - Targeted Server: $spTargetServer"
            # Per-farm resilience: probe the target with the first remote call. If the
            # server cannot be reached over CredSSP, log it and move on to the next farm
            # instead of aborting the whole run (or, before 2.0.1, running locally).
            try {
                $spsVersion = Get-SPSVersion -Server $spTargetServer `
                    -InstallAccount $ADM
            }
            catch {
                Write-Warning -Message "Skipping farm '$($spFarm.Name)': '$spTargetServer' is unreachable. $($_.Exception.Message)"
                Add-SPSWeatherEvent -Message "SPSWeather skipped farm '$($spFarm.Name)' ($spTargetServer) which was unreachable: $($_.Exception.Message)" -EntryType 'Error' -EventID 3001
                continue
            }

            Write-Output "SharePoint Version: $spsVersion"

            # Get list of SharePoint Servers
            Write-Output "Getting list of SharePoint Servers of farm $($spFarm.Name)"
            $spServers = Get-SPSServer -Server $spTargetServer `
                -InstallAccount $ADM

            foreach ($spServer in $spServers) { Write-Output "* $($spServer)" }

            # Get Health Analyzer list on Central Admin site
            if (-not($ExclusionRules.Contains('HealthStatus'))) {
                Write-Output 'Getting Health Status from SharePoint Central Administration'
                $tbhealthListItems += Get-SPSHealthStatusFromCA -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)"
            }

            # Get SharePoint Upgrade Status
            Write-Output 'Getting SharePoint Upgrade Status'
            $tbUpgradeListItems += Get-SPSUpgradeStatus -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            # Get SharePoint API Status
            if (-not($ExclusionRules.Contains('APIHttpStatus'))) {
                Write-Output 'Getting SharePoint Trust Farm Status'
                $tbSPAPIHttpStatus += Get-SPSAPIHttpStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)"
            }
            # Get SharePoint All SPSIte HTTP Status
            if (-not($ExclusionRules.Contains('SPSiteHttpStatus'))) {
                Write-Output 'Getting SharePoint SPSite HTTP Status'
                $tbSPSSitesHttpStatus += Get-SPSSiteHttpStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)"
            }
            # Get SharePoint Failed TimerJob Status
            if (-not($ExclusionRules.Contains('FailedTimerJob'))) {
                Write-Output 'Getting SharePoint Failed TimerJob Status'
                $tbSPSfailedJobs += Get-SPSFailedTimerJob -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)"
            }
            # Get SharePoint Solution Deployment Status
            if (-not($ExclusionRules.Contains('WSPStatus'))) {
                Write-Output 'Getting SharePoint Solution Deployment Status'
                $tbSPSolutions += Get-SPSSolutionStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)"
            }

            # Get Search Enterprise Service Information
            Write-Output 'Getting Search Enterprise Service Content Last Crawl'
            $tbSPSSearchEntCrawlStatus += Get-SPSSearchEntCrawlStatus -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            Write-Output 'Getting Search Enterprise Service Content Crawl Logs'
            $tbSPSSearchEntCrawlLogs += Get-SPSSearchEntCrawlLogs -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            Write-Output 'Getting Search Enterprise Service Topology Status'
            $tbSPSSearchEntTopology += Get-SPSSearchEntTopology -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            # Get Distributed Cache Service
            Write-Output 'Getting SharePoint Distributed Cache Status'
            $tbAppFabricStatus += Get-AppFabricStatus -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            # Get User Profile Audience Compilation Status
            Write-Output 'Getting SharePoint User Profile Audience Compilation Status'
            $tbUSPAudienceStatus += Get-USPAudienceStatus -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            # Get Content Database Status
            Write-Output 'Getting SharePoint Content Database Status'
            $tbSPSContentDBStatus += Get-SPSContentDBStatus -Server $spTargetServer `
                -InstallAccount $ADM `
                -Farm "$($spFarm.Name)"

            if ($null -ne $spServers) {
                # Get IIS status for each SPServer
                Write-Output 'Getting Application Pool Status for Each SharePoint Server'
                $tbIISApplicationPoolStatus += Get-SYSIISAppPoolStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)" `
                    -Servers $spServers

                # Get IIS Worker Process (W3WP.exe) Status for each SPServer
                if (-not($ExclusionRules.Contains('IISW3WPStatus'))) {
                    Write-Output 'Getting Worker Process Status for Each SharePoint Server'
                    $tbIISWorkerProcessStatus += Get-SYSIISW3WPEXEStatus -Server $spTargetServer `
                        -InstallAccount $ADM `
                        -Farm "$($spFarm.Name)" `
                        -Servers $spServers
                }

                # Get IIS Certificat for each SPServer
                Write-Output 'Getting WebSite SSL Certificate Status for Each SharePoint Server'
                $tbIISSiteCertStatus += Get-SYSIISSiteCertStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)" `
                    -Servers $spServers `
                    -Expiration 90

                # Get Last Reboot Status
                Write-Output 'Getting Last Reboot Status for Each SharePoint Server'
                $tbSYSLastRebootStatus += Get-SYSLastRebootStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)" `
                    -Servers $spServers

                # Get .net framework version
                Write-Output 'Getting .Net Framework Version for Each SharePoint Server'
                $tbSYSDOTNETVersion += Get-SYSDOTNETVersion -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)" `
                    -Servers $spServers

                # Get Errors from Event Viewer Application
                if (-not($ExclusionRules.Contains('EvtViewerStatus'))) {
                    Write-Output 'Getting Event Viewer Application Errors for Each SharePoint Server'
                    $tbSYSEventViewerAppErrors += Get-SYSEvtAppErrors -Server $spTargetServer `
                        -InstallAccount $ADM `
                        -Farm "$($spFarm.Name)" `
                        -Servers $spServers
                }

                # Get Disk Usage for each SPServer
                Write-Output 'Getting Disk Usage for Each SharePoint Server'
                $tbSYSDiskUsageStatus += Get-SYSDiskUsageStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)" `
                    -Servers $spServers `
                    -WarningPercentage 20
            }

            # Get SQL Server health for the farm (Tier 1+2+3), unless every SQL
            # check is excluded. Get-SPSSqlStatus discovers the SQL servers from
            # Get-SPDatabase and queries them with dependency-free ADO.NET.
            $sqlExclusions = @('SQLInstanceStatus', 'SQLDatabaseStatus', 'SQLDiskStatus', 'SQLAvailabilityStatus', 'SQLAliasStatus')
            if (@($sqlExclusions | Where-Object { -not $ExclusionRules.Contains($_) }).Count -gt 0) {
                Write-Output "Getting SQL Server health for farm $($spFarm.Name)"
                $sqlStatus = Get-SPSSqlStatus -Server $spTargetServer `
                    -InstallAccount $ADM `
                    -Farm "$($spFarm.Name)" `
                    -DiskFreeThresholdPercent $sqlDiskThreshold `
                    -BackupMaxAgeDays $sqlBackupMaxAge `
                    -DeclaredSqlServers $spFarm.SqlServers
                if (-not $ExclusionRules.Contains('SQLInstanceStatus')) { $tbSQLInstanceStatus += $sqlStatus.Instances }
                if (-not $ExclusionRules.Contains('SQLDatabaseStatus')) { $tbSQLDatabaseStatus += $sqlStatus.Databases }
                if (-not $ExclusionRules.Contains('SQLDiskStatus')) { $tbSQLDiskStatus += $sqlStatus.Disks }
                if (-not $ExclusionRules.Contains('SQLAvailabilityStatus')) { $tbSQLAvailabilityStatus += $sqlStatus.Availability }
                if (-not $ExclusionRules.Contains('SQLAliasStatus')) { $tbSQLAliasStatus += $sqlStatus.Aliases }
            }
        }

        $tbSPWeatherListInfo = Get-SPWeatherListInfo -Version $spsWeatherVersion `
            -PSVersion $psVersion `
            -UserAccount $currentUser `
            -DateStarted $DateStarted `
            -DateEnded (Get-Date) `
            -Environment $Environment `
            -Application $Application

        Write-Output 'Assembling the SPSWeather report object:'
        $reportSections = [ordered]@{
            SPHealthAnalyzer         = $tbhealthListItems
            SPUpgradeStatus          = $tbUpgradeListItems
            SPAPIHttpStatus          = $tbSPAPIHttpStatus
            SPSSitesHttpStatus       = $tbSPSSitesHttpStatus
            SPFailedTimerJobs        = $tbSPSfailedJobs
            SPSolutionDeployment     = $tbSPSolutions
            SPSearchLastCrawlStatus  = $tbSPSSearchEntCrawlStatus
            SPSearchCrawlLogs        = $tbSPSSearchEntCrawlLogs
            SPSSearchEntTopology     = $tbSPSSearchEntTopology
            AppFabricStatus          = $tbAppFabricStatus
            USPAudienceStatus        = $tbUSPAudienceStatus
            IISApplicationPoolStatus = $tbIISApplicationPoolStatus
            IISWorkerProcessStatus   = $tbIISWorkerProcessStatus
            IISWebSiteCertStatus     = $tbIISSiteCertStatus
            SYSEventViewerAppErrors  = $tbSYSEventViewerAppErrors
            SYSDiskUsageStatus       = $tbSYSDiskUsageStatus
            SYSLastRebootStatus      = $tbSYSLastRebootStatus
            SYSDOTNETVersion         = $tbSYSDOTNETVersion
            SPWeatherListInfo        = $tbSPWeatherListInfo
            SPSContentDBStatus       = $tbSPSContentDBStatus
            SQLInstanceStatus        = $tbSQLInstanceStatus
            SQLDatabaseStatus        = $tbSQLDatabaseStatus
            SQLDiskStatus            = $tbSQLDiskStatus
            SQLAvailabilityStatus    = $tbSQLAvailabilityStatus
            SQLAliasStatus           = $tbSQLAliasStatus
        }
        $reportResult = ConvertTo-SPSWeatherReport -Section $reportSections
        foreach ($section in $reportResult.Report.PSObject.Properties) {
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name $section.Name `
                -Value $section.Value
        }
        if ($reportResult.IsAlert) { $mailAlert = 'ALERT' }

        Trap { Continue }

        if ($mailAlert -eq 'ALERT') { $mailPriority = 'High' }

        $mailSubject = "[$($mailAlert)]$($Application)_$($Environment) - Meteo SharePoint $($DateEnded)"
        $mailHTMLBody = Join-HtmlBodyFromPSo -PSObjectFromJson $jsonObject
        $mailHTMLBody | Out-File -FilePath $pathHTMLFile -Force
        $jsonObject | ConvertTo-Json | Set-Content -Path $pathJSONFile -Force

        # Record the run outcome in the SPSWeather event log
        if ($mailAlert -eq 'ALERT') {
            Add-SPSWeatherEvent -Message "SPSWeather detected ALERT conditions for $Application/$Environment. See $pathHTMLFile for details." -EntryType 'Warning' -EventID 2000
        }
        else {
            Add-SPSWeatherEvent -Message "SPSWeather completed with no alert for $Application/$Environment." -EntryType 'Information' -EventID 1001
        }

        # Clean the folder of log files
        Clear-SPSLog -path $pathLogsFolder -Retention 180

        # Send Email
        if ($EnableSmtp) {
            $SmtpToAddress = $envCfg.SMTPToAddress
            $SmtpFromAddress = $envCfg.SMTPFromAddress
            $SmtpServerAddress = $envCfg.SMTPServer
            Write-Output '--------------------------------------------------------------'
            Write-Output "Sending Email"
            Write-Output " * To: $SmtpToAddress"
            Write-Output " * From: $SmtpFromAddress"
            Write-Output " * SmtpServer: $SmtpServerAddress"
            try {
                Send-MailMessage -To $SmtpToAddress `
                    -From $SmtpFromAddress `
                    -Subject $mailSubject `
                    -Body $mailHTMLBody `
                    -BodyAsHtml `
                    -Encoding 'UTF8' `
                    -SmtpServer $SmtpServerAddress `
                    -Priority $mailPriority `
                    -ea stop
                Write-Output "Email sent successfully to $SmtpToAddress"
            }
            catch {
                Write-Output $_
                Add-SPSWeatherEvent -Message "SPSWeather failed to send the report email for $Application/$Environment. Exception: $_" -EntryType 'Error' -EventID 3000
            }
        }
    }

    Trap { Continue }

    $DateEnded = Get-date
    Write-Output '-----------------------------------------------'
    Write-Output '| Automated Script - SPSWeather'
    Write-Output "| Started on       - $DateStarted |"
    Write-Output "| Completed on     - $DateEnded |"
    Write-Output '-----------------------------------------------'
    Stop-Transcript
    Remove-Variable * -ErrorAction SilentlyContinue;
    Remove-Module *;
    $error.Clear();
    Exit
}
#endregion
