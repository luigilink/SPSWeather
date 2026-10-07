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

    .PARAMETER Action
    Use the Action parameter to manage the scheduled task. Accepted values:
    Install (add the SPSWeather task, InstallAccount required), Uninstall (remove
    the task and stored secret), or Default (run the health check). Defaults to Default.
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.psd1'

    .PARAMETER InstallAccount
    Need parameter InstallAccount when you use -Action Install
    PS D:\> E:\SCRIPT\SPSWeather.ps1 -Action Install -InstallAccount (Get-Credential) -ConfigFile 'contoso-PROD.psd1'

    .EXAMPLE
    SPSWeather.ps1 -ConfigFile 'contoso-PROD.psd1' -EnableSmtp
    SPSWeather.ps1 -ConfigFile 'contoso-PROD.psd1' -Action Install -InstallAccount (Get-Credential)
    SPSWeather.ps1 -ConfigFile 'contoso-PROD.psd1' -Action Uninstall

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
    [ValidateSet('Install', 'Uninstall', 'Default', IgnoreCase = $true)]
    [System.String]
    $Action = 'Default',

    [Parameter(Position = 4)]
    [System.Management.Automation.PSCredential]
    $InstallAccount
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
$DateStarted = Get-date
$psVersion = ($host).Version.ToString()

# The Logs folder must exist before Start-Transcript (it is not created by the
# Results/Config init below, which runs later).
if (-Not (Test-Path -Path $pathLogsFolder)) {
    $null = New-Item -ItemType Directory -Path $pathLogsFolder -Force
}

Start-Transcript -Path $pathLogFile -IncludeInvocationHeader
Write-Output '-------------------------------------'
Write-Output "| Automated Script - SPSWeather v$spsWeatherVersion"
Write-Output "| Started on : $DateStarted by $currentUser"
Write-Output "| PowerShell Version: $psVersion"
Write-Output '-------------------------------------'

# Check UserName and Password if Install action is used
if ($Action -eq 'Install') {
    if ($null -eq $InstallAccount) {
        Write-Warning -Message ('SPSWeather: -Action Install is set. Please set also InstallAccount ' + `
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

    if ($Action -eq 'Uninstall') {
        # Remove SPSWeather script from scheduled Task
        Remove-SPSSheduledTask -TaskName $spWeatherTaskName

        # Remove the stored secret from secrets.psd1 (if present)
        Set-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder -Remove

        Add-SPSWeatherEvent -Message "SPSWeather scheduled task '$spWeatherTaskName' removed on $env:COMPUTERNAME." -EntryType 'Information' -EventID 1002
        Write-Output "SPSWeather uninstalled: task '$spWeatherTaskName' and secret '$($envCfg.CredentialKey)' removed."
    }
    elseif ($Action -eq 'Install') {
        # Persist the service credential as a DPAPI-encrypted SecureString in
        # secrets.psd1. Run -Action Install AS the service account so the value can be
        # decrypted at run time by the scheduled task.
        Set-SPSSecret -CredentialKey $envCfg.CredentialKey -Credential $InstallAccount -ConfigPath $pathConfigFolder

        # Add SPSWeather script in a new scheduled Task
        Add-SPSSheduledTask -ExecuteAsCredential $InstallAccount -TaskName $spWeatherTaskName -ActionArguments "-Execution Bypass $($scriptRootPath)\SPSWeather.ps1 -ConfigFile $($ConfigFile) -EnableSMTP"

        # Configure the CredSSP client role so this host (which may not be a SharePoint
        # server) can reach the farms. The server side stays owned by DSC on the farms.
        $credSspTargets = @($envCfg.Farms | ForEach-Object { "$($_.Server).$($envCfg.Domain)" } | Where-Object { $_ -and $_ -ne '.' })
        if ($credSspTargets.Count -gt 0) {
            [void](Set-SPSCredSSPClient -DelegateComputer $credSspTargets)
            Write-Output "CredSSP client configured for: $($credSspTargets -join ', ')"
        }

        Add-SPSWeatherEvent -Message "SPSWeather scheduled task '$spWeatherTaskName' installed/updated for $Application/$Environment on $env:COMPUTERNAME." -EntryType 'Information' -EventID 1003
        Write-Output "SPSWeather installed: task '$spWeatherTaskName' created/updated and secret '$($envCfg.CredentialKey)' stored."
    }
    else {
        # Initialize Security
        $scriptFQDN = $envCfg.Domain
        $credential = Get-SPSSecret -CredentialKey $envCfg.CredentialKey -ConfigPath $pathConfigFolder
        if ($null -ne $credential) {
            New-Variable -Name 'ADM' -Value $credential -Force
        }
        else {
            Throw "Credential '$($envCfg.CredentialKey)' was not found in Config\secrets.psd1. Run SPSWeather.ps1 -Action Install as the service account, or populate secrets.psd1 manually. See the wiki for details."
        }
        $spFarms = $envCfg.Farms
        # Optional SQL thresholds (config overrides, with safe defaults)
        $sqlDiskThreshold = if ($null -ne $envCfg.SQLDiskFreeThresholdPercent) { [int]$envCfg.SQLDiskFreeThresholdPercent } else { 15 }
        $sqlBackupMaxAge = if ($null -ne $envCfg.SQLBackupMaxAgeDays) { [int]$envCfg.SQLBackupMaxAgeDays } else { 3 }
        $jsonHistoryRetentionDays = if ($null -ne $envCfg.JsonHistoryRetentionDays) { [int]$envCfg.JsonHistoryRetentionDays } else { 30 }
        $logRetentionDays = if ($null -ne $envCfg.LogRetentionDays) { [int]$envCfg.LogRetentionDays } else { 180 }
        $pathHistoryFolder = Join-Path -Path $pathResultsFolder -ChildPath 'history'
        # Track only the farms actually reached: an unreachable farm (skipped below)
        # must not be published/emailed as healthy.
        $probedFarms = New-Object System.Collections.ArrayList
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
            [void]$probedFarms.Add("$($spFarm.Name)")

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
        # --- Per-farm reporting (Opt.1: one dashboard + one short email per farm) ---
        # The aggregate $reportSections span every farm; slice them per farm, then render
        # a hosted dashboard and send a short alert email for each one. Only farms that
        # were actually reached ($probedFarms) are rendered - an unreachable farm has
        # empty sections and must not be published/emailed as healthy.
        $dashboardCfg = $envCfg.Dashboard
        $dashOutputPath = if ($null -ne $dashboardCfg -and -not [string]::IsNullOrWhiteSpace($dashboardCfg.OutputPath)) { $dashboardCfg.OutputPath } else { $pathResultsFolder }
        $dashBaseUrl = if ($null -ne $dashboardCfg) { "$($dashboardCfg.Url)".TrimEnd('/') } else { '' }
        if (-not (Test-Path -Path $dashOutputPath)) { $null = New-Item -ItemType Directory -Path $dashOutputPath -Force }

        # The chart shows 30 bars: up to 29 past runs plus the current one (appended by
        # the renderer). This is a run count, independent of the day-based history retention.
        $historyBars = 29

        foreach ($farmName in @($probedFarms)) {
            # Property access is case-insensitive, so $_.Farm matches both 'Farm' and 'farm'.
            $farmSections = [ordered]@{}
            foreach ($entry in $reportSections.GetEnumerator()) {
                $farmSections[$entry.Key] = @($entry.Value | Where-Object { $_ -and ("$($_.Farm)" -eq $farmName) })
            }
            $farmResult = ConvertTo-SPSWeatherReport -Section $farmSections

            $farmJson = [PSCustomObject]@{}
            foreach ($section in $farmResult.Report.PSObject.Properties) {
                $farmJson | Add-Member -MemberType NoteProperty -Name $section.Name -Value $section.Value
            }

            # Stable per-farm names (no date: the hosted dashboard URL and json snapshot are
            # overwritten each run; the time dimension lives in the history folder).
            $safeFarm = ($farmName -replace '[^A-Za-z0-9_-]', '_')
            $farmStem = "$($Application)-$($Environment)-$($safeFarm)"
            $farmJsonFile = Join-Path -Path $pathResultsFolder -ChildPath ($farmStem + '.json')
            $farmHistFolder = Join-Path -Path $pathHistoryFolder -ChildPath $safeFarm
            $dashFile = Join-Path -Path $dashOutputPath -ChildPath ($farmStem + '-dashboard.html')

            # Per-farm resilience: a failure rendering or mailing one farm must not abort
            # the others. Log it and move on (no silent broad Trap).
            try {
                # History: archive the previous snapshot, build the past-runs series, write the new one.
                [void](Backup-SPSWeatherJsonFile -Path $farmJsonFile -HistoryFolder $farmHistFolder -RetentionDays $jsonHistoryRetentionDays -ErrorAction SilentlyContinue)
                $farmHistory = Get-SPSWeatherHistory -HistoryFolder $farmHistFolder -Max $historyBars -ErrorAction SilentlyContinue
                $farmJson | ConvertTo-Json -Depth 6 | Set-Content -Path $farmJsonFile -Force

                $runDuration = '{0:hh\:mm\:ss}' -f ((Get-Date) - $DateStarted)
                [void](Export-SPSWeatherReport -InputObject $farmJson `
                        -OutputFile $dashFile `
                        -Farm $farmName `
                        -Application $Application `
                        -Environment $Environment `
                        -Version $spsWeatherVersion `
                        -ExecutedBy $currentUser `
                        -Duration $runDuration `
                        -History $farmHistory)
                Write-Output " * Dashboard: $dashFile"

                $dashUrl = if ($dashBaseUrl) { "$dashBaseUrl/$($farmStem)-dashboard.html" } else { '' }
                $mailHTMLBody = ConvertTo-SPSWeatherEmailBody -InputObject $farmJson `
                    -Summary $farmResult.Summary `
                    -Farm $farmName `
                    -Application $Application `
                    -Environment $Environment `
                    -Version $spsWeatherVersion `
                    -ExecutedBy $currentUser `
                    -Duration $runDuration `
                    -DashboardUrl $dashUrl

                # Outcome from the shared severity counts: failures -> ALERT/High,
                # warnings only -> WARN/Normal, otherwise OK.
                $failCount = [int]$farmResult.Summary.Fail
                $warnCount = [int]$farmResult.Summary.Warn
                if ($failCount -gt 0) { $farmAlert = 'ALERT'; $farmPriority = 'High' }
                elseif ($warnCount -gt 0) { $farmAlert = 'WARN'; $farmPriority = 'Normal' }
                else { $farmAlert = 'OK'; $farmPriority = 'Normal' }
                $mailSubject = "[$farmAlert] $Application/$Environment/$farmName - SPSWeather"

                if ($farmResult.IsAlert) {
                    Add-SPSWeatherEvent -Message "SPSWeather outcome $farmAlert for $Application/$Environment farm '$farmName' ($failCount failure(s), $warnCount warning(s)). Dashboard: $dashFile." -EntryType 'Warning' -EventID 2000
                }
                else {
                    Add-SPSWeatherEvent -Message "SPSWeather completed with no alert for $Application/$Environment farm '$farmName'." -EntryType 'Information' -EventID 1001
                }

                if ($EnableSmtp) {
                    $SmtpToAddress = $envCfg.SMTPToAddress
                    $SmtpFromAddress = $envCfg.SMTPFromAddress
                    $SmtpServerAddress = $envCfg.SMTPServer
                    Write-Output '--------------------------------------------------------------'
                    Write-Output "Sending Email for farm '$farmName'"
                    Write-Output " * To: $SmtpToAddress"
                    Write-Output " * From: $SmtpFromAddress"
                    Write-Output " * SmtpServer: $SmtpServerAddress"
                    Send-MailMessage -To $SmtpToAddress `
                        -From $SmtpFromAddress `
                        -Subject $mailSubject `
                        -Body $mailHTMLBody `
                        -BodyAsHtml `
                        -Encoding 'UTF8' `
                        -SmtpServer $SmtpServerAddress `
                        -Priority $farmPriority `
                        -ea stop
                    Write-Output "Email sent successfully to $SmtpToAddress"
                }
            }
            catch {
                Write-Output $_
                Add-SPSWeatherEvent -Message "SPSWeather failed to produce the dashboard/email for $Application/$Environment farm '$farmName'. Exception: $($_.Exception.Message)" -EntryType 'Error' -EventID 3000
            }
        }

        # Clean the folder of log files (once per run).
        Clear-SPSLog -path $pathLogsFolder -Retention $logRetentionDays
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
