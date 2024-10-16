<#
    .SYNOPSIS
    SPSWeather script for SharePoint Server

    .DESCRIPTION
    SPSWeather is a PowerShell script tool to get farm information and send it by mail

    .PARAMETER ConfigFile
    Need parameter ConfigFile, example:
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -ConfigFile 'contoso-PROD.json'

    .PARAMETER EnableSmtp
    Use the switch EnableSmtp parameter if you want to enable Email notifications using SMTP
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -EnableSmtp

    .PARAMETER Install
    Use the switch Install parameter if you want to add the SPSWeather script in taskscheduler
    InstallAccount parameter need to be set
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'

    .PARAMETER InstallAccount
    Need parameter InstallAccount when you use the switch Install parameter
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'

    .PARAMETER Uninstall
    Use the switch Uninstall parameter if you want to remove the SPSWeather script from taskscheduler
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Uninstall

    .EXAMPLE
    SPSWeather.ps1 -ConfigFile 'contoso-PROD.json' -EnableSmtp
    SPSWeather.ps1 -Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.json'
    SPSWeather.ps1 -Uninstall -ConfigFile 'contoso-PROD.json'

    .NOTES
    FileName:	SPSWeather.ps1
    Author:		luigilink (Jean-Cyril DROUHIN)
    Date:		Ocotober 15, 2024
    Version:	1.0.3

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
Import-Module -Name (Join-Path -Path $script:HelperModulePath -ChildPath 'util.psm1') -Force
Import-Module -Name (Join-Path -Path (Join-Path -Path $script:HelperModulePath -ChildPath 'credentialmanager') -ChildPath 'CredentialManager.psd1') -Force

if (Test-Path $ConfigFile) {
    $jsonEnvCfg = get-content $ConfigFile | ConvertFrom-Json
    $Application = $jsonEnvCfg.ApplicationName
    $Environment = $jsonEnvCfg.ConfigurationName
    $ExclusionRules = $jsonEnvCfg.ExclusionRules
}
else {
    Throw "Missing $ConfigFile"
}

# Define variable
$spsWeatherVersion = '1.0.3'
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
# Initialize Security
$scriptFQDN = $jsonEnvCfg.Domain
$credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
if ($null -ne $credential) {
    New-Variable -Name 'ADM' -Value $credential -Force
}
else {
    Throw "The Target $($jsonEnvCfg.StoredCredential) not present in Credential Manager. Please contact your administrator."
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

        # Remove Credential from Credential Manager
        $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
        if ($null -ne $credential) {
            Remove-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)"
        }
    }
    elseif ($Install) {
        # Add Credential in Credential Manager
        $credential = Get-StoredCredential -Target "$($jsonEnvCfg.StoredCredential)" -ErrorAction SilentlyContinue
        if ($null -eq $credential) {
            New-StoredCredential -Credentials $InstallAccount -Target "$($jsonEnvCfg.StoredCredential)" -Type Generic -Persist LocalMachine
        }

        # Add SPSWeather script in a new scheduled Task
        Add-SPSSheduledTask -TaskName $spWeatherTaskName -ActionArguments "-Execution Bypass $($scriptRootPath)\SPSWeather.ps1 -ConfigFile $($ConfigFile) -EnableSMTP"
    }
    else {
        $spFarms = $jsonEnvCfg.Farms
        foreach ($spFarm in $spFarms) {
            $spTargetServer = "$($spFarm.Server).$($scriptFQDN)"
            Write-Output '--------------------------------------------------------------'
            Write-Output "Farm: $($spFarm.Name) - Targeted Server: $spTargetServer"
            $spsVersion = Get-SPSVersion -Server $spTargetServer `
                -InstallAccount $ADM

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
        }

        $tbSPWeatherListInfo = Get-SPWeatherListInfo -Version $spsWeatherVersion `
            -PSVersion $psVersion `
            -UserAccount $currentUser `
            -DateStarted $DateStarted `
            -DateEnded (Get-Date) `
            -Environment $Environment `
            -Application $Application

        Write-Output 'Adding each list object in PsCustomObject jsonObject:'
        if ($null -ne $tbhealthListItems) {
            if ($tbhealthListItems.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPHealthAnalyzer object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPHealthAnalyzer `
                -Value $tbhealthListItems
        }
        if ($null -ne $tbUpgradeListItems) {
            if ($tbUpgradeListItems.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPUpgradeStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPUpgradeStatus `
                -Value $tbUpgradeListItems
        }
        if ($null -ne $tbSPAPIHttpStatus) {
            if ($tbSPAPIHttpStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPAPIHttpStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPAPIHttpStatus `
                -Value $tbSPAPIHttpStatus
        }
        if ($null -ne $tbSPSSitesHttpStatus) {
            if ($tbSPSSitesHttpStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPSSitesHttpStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPSSitesHttpStatus `
                -Value $tbSPSSitesHttpStatus
        }
        if ($null -ne $tbSPSfailedJobs) {
            if ($tbSPSfailedJobs.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPFailedTimerJobs object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPFailedTimerJobs `
                -Value $tbSPSfailedJobs
        }
        if ($null -ne $tbSPSolutions) {
            if ($tbSPSolutions.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPSolutionDeployment object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPSolutionDeployment `
                -Value $tbSPSolutions
        }
        if ($null -ne $tbSPSSearchEntCrawlStatus) {
            if ($tbSPSSearchEntCrawlStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPSearchLastCrawlStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPSearchLastCrawlStatus `
                -Value $tbSPSSearchEntCrawlStatus
        }
        if ($null -ne $tbSPSSearchEntCrawlLogs) {
            if ($tbSPSSearchEntCrawlLogs.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPSearchCrawlLogs object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPSearchCrawlLogs `
                -Value $tbSPSSearchEntCrawlLogs
        }
        if ($null -ne $tbSPSSearchEntTopology) {
            if ($tbSPSSearchEntTopology.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPSSearchEntTopology object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPSSearchEntTopology `
                -Value $tbSPSSearchEntTopology
        }    
        if ($null -ne $tbAppFabricStatus) {
            if ($tbAppFabricStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding AppFabricStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name AppFabricStatus `
                -Value $tbAppFabricStatus
        }
        if ($null -ne $tbUSPAudienceStatus) {
            if ($tbUSPAudienceStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding USPAudienceStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name USPAudienceStatus `
                -Value $tbUSPAudienceStatus
        }
        if ($null -ne $tbIISApplicationPoolStatus) {
            if ($tbIISApplicationPoolStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding IISApplicationPoolStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name IISApplicationPoolStatus `
                -Value $tbIISApplicationPoolStatus
        }
        if ($null -ne $tbIISWorkerProcessStatus) {
            if ($tbIISWorkerProcessStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding IISWorkerProcessStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name IISWorkerProcessStatus `
                -Value $tbIISWorkerProcessStatus
        }
        if ($null -ne $tbIISSiteCertStatus) {
            if ($tbIISSiteCertStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding IISWebSiteCertStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name IISWebSiteCertStatus `
                -Value $tbIISSiteCertStatus
        }
        if ($null -ne $tbSYSEventViewerAppErrors) {
            if ($tbSYSEventViewerAppErrors.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SYSEventViewerAppErrors object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SYSEventViewerAppErrors `
                -Value $tbSYSEventViewerAppErrors
        }
        if ($null -ne $tbSYSDiskUsageStatus) {
            if ($tbSYSDiskUsageStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SYSDiskUsageStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SYSDiskUsageStatus `
                -Value $tbSYSDiskUsageStatus
        }
        if ($null -ne $tbSYSLastRebootStatus) {
            Write-Output '* Adding SYSLastRebootStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SYSLastRebootStatus `
                -Value $tbSYSLastRebootStatus
        }
        if ($null -ne $tbSYSDOTNETVersion) {
            Write-Output '* Adding SYSDOTNETVersion object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SYSDOTNETVersion `
                -Value $tbSYSDOTNETVersion
        }
        if ($null -ne $tbSPWeatherListInfo) {
            Write-Output '* Adding SPWeatherListInfo object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPWeatherListInfo `
                -Value $tbSPWeatherListInfo
        }
        if ($null -ne $tbSPSContentDBStatus) {
            if ($tbSPSContentDBStatus.IsInfo -contains $false) { $mailAlert = 'ALERT' }
            Write-Output '* Adding SPSContentDBStatus object'
            $jsonObject | Add-Member -MemberType NoteProperty `
                -Name SPSContentDBStatus `
                -Value $tbSPSContentDBStatus
        }

        Trap { Continue }

        if ($mailAlert -eq 'ALERT') { $mailPriority = 'High' }

        $mailSubject = "[$($mailAlert)]$($Application)_$($Environment) - Meteo SharePoint $($DateEnded)"
        $mailHTMLBody = Join-HtmlBodyFromPSo -PSObjectFromJson $jsonObject
        $mailHTMLBody | Out-File -FilePath $pathHTMLFile -Force
        $jsonObject | ConvertTo-Json | Set-Content -Path $pathJSONFile -Force

        # Clean the folder of log files
        Clear-SPSLog -path $pathLogsFolder -Retention 180

        # Send Email
        if ($EnableSmtp) {
            $SmtpToAddress = $jsonEnvCfg.SMTPToAddress
            $SmtpFromAddress = $jsonEnvCfg.SMTPFromAddress
            $SmtpServerAddress = $jsonEnvCfg.SMTPServer
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
