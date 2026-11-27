<#
    .SYNOPSIS
    READ-ONLY probe for the design of the IIS drift check (#138), with the real-farm reads of the limit checks (#137).

    .DESCRIPTION
    Collects, without changing anything, what the two checks need to know:
      - SharePoint: the servers with their role and their service instances, the web applications with their zones, the IIS settings
        that SharePoint expects (site name, path, bindings, secure bindings) and the alternate access mappings. The names of the
        properties are listed too, because the exact shape of SPIisSettings and of the bindings has to be confirmed.
      - IIS, on each server of the farm: the sites with their bindings and their application pool, the application pools with
        their identity (never a password), whether the IIS configuration history and audit log exist and what they hold.
      - The facts that the limit checks of SPSWeather 3.6.0 read: the content databases (site count, Remote BLOB Storage), the managed
        paths, and the used size of the data of three content databases (FILEPROPERTY SpaceUsed, integrated security).
    No Set-*, New-*, Remove-*, Enable-* or write on the farm, IIS or SQL Server; the only file written is the JSON report, in
    -OutputFolder. A section that fails is recorded with its error and the others go on.

    Two ways to run it (Windows PowerShell 5.1):
      - On a farm server, in a SharePoint Management Shell, as a farm administrator:   .\Probe-SPSIisDrift.ps1
      - From another machine that is set up for CredSSP like SPSWeather (the pull server):
        .\Probe-SPSIisDrift.ps1 -Server 'entrypoint.contoso.com'   (it asks for the service account)

    .PARAMETER Server
    FQDN of a farm server. When given, the SharePoint facts are read there and every server is reached with CredSSP and -Credential.
    When omitted, the script runs on a farm server and the other servers are reached with the current identity.

    .PARAMETER Credential
    The account for the remote sessions. Asked when -Server is given and this is not.

    .PARAMETER OutputFolder
    Where the JSON report is written (default: the folder 'output' next to the script).

    .PARAMETER SkipLimitFacts
    Does not read the facts of the limit checks.
#>
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $Server,

    [Parameter()]
    [System.Management.Automation.PSCredential]
    $Credential,

    [Parameter()]
    [System.String]
    $OutputFolder = $(if ($PSScriptRoot) { Join-Path -Path $PSScriptRoot -ChildPath 'output' } else { Join-Path -Path (Get-Location).Path -ChildPath 'output' }),

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $SkipLimitFacts
)

$ErrorActionPreference = 'Stop'
$startedAt = Get-Date

function Write-Section {
    param([System.String]$Title)
    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Test-LocalComputer {
    param([System.String]$Computer)
    if ([string]::IsNullOrWhiteSpace($Computer)) { return $true }
    $short = ($Computer -split '\.')[0]
    return (($short -ieq $env:COMPUTERNAME) -or ($Computer -ieq 'localhost'))
}

# The block runs here for the local computer without a credential, else in a session (CredSSP when a credential is given:
# the SharePoint cmdlets reach SQL Server with the identity of the session, which is a second hop).
function Invoke-Probe {
    param([System.String]$Computer, [System.Management.Automation.ScriptBlock]$Block, [System.Object[]]$ArgumentList = @())
    if ((Test-LocalComputer -Computer $Computer) -and (-not $script:Credential)) {
        return (& $Block @ArgumentList)
    }
    $splat = @{ ComputerName = $Computer; ScriptBlock = $Block; ArgumentList = $ArgumentList; ErrorAction = 'Stop' }
    if ($script:Credential) { $splat['Credential'] = $script:Credential; $splat['Authentication'] = 'Credssp' }
    return (Invoke-Command @splat)
}

# Both blocks return a JSON text, so that nothing depends on how a remote session hands objects back.
$spBlock = {
    param([System.Boolean]$IncludeLimitFacts)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Command -Name Get-SPFarm -ErrorAction SilentlyContinue)) {
        Import-Module -Name SharePointServer -DisableNameChecking -WarningAction SilentlyContinue
    }

    function Get-Safe {
        param([System.Management.Automation.ScriptBlock]$Block)
        try {
            $result = & $Block
            if ($result -is [System.Array]) { return , $result }
            return $result
        }
        catch { return ('ERROR: ' + $_.Exception.Message) }
    }

    # The scalar properties of an object, without any property that could hold a secret
    function Get-Scalar {
        param($Object)
        $result = [ordered]@{}
        if ($null -eq $Object) { return $result }
        foreach ($property in $Object.PSObject.Properties) {
            if ($property.Name -match '(?i)password|secret|credential|token|connectionstring') { continue }
            $value = $null
            try { $value = $property.Value } catch { continue }
            if ($null -eq $value) { $result[$property.Name] = $null }
            elseif ($value -is [System.Boolean] -or $value -is [System.Int32] -or $value -is [System.Int64] -or $value -is [System.Double] -or $value -is [System.Decimal]) { $result[$property.Name] = $value }
            elseif ($value -is [System.String] -or $value -is [System.Guid] -or $value -is [System.Enum] -or $value -is [System.DateTime]) { $result[$property.Name] = "$value" }
        }
        return $result
    }

    function Get-PropertyName {
        param($Object)
        if ($null -eq $Object) { return , @() }
        return , @($Object | Get-Member -MemberType Properties | ForEach-Object { $_.Name })
    }

    $out = [ordered]@{}
    $out['collectedOn'] = $env:COMPUTERNAME
    $out['psVersion'] = $PSVersionTable.PSVersion.ToString()
    $farm = Get-SPFarm
    $out['farm'] = [ordered]@{ name = "$($farm.Name)"; buildVersion = "$($farm.BuildVersion)" }

    $servers = New-Object -TypeName System.Collections.ArrayList
    foreach ($spServer in @(Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' })) {
        $row = [ordered]@{ name = "$($spServer.Name)"; address = "$($spServer.Address)"; role = "$($spServer.Role)"; status = "$($spServer.Status)" }
        $row['compliantWithMinRole'] = Get-Safe -Block { "$($spServer.CompliantWithMinRole)" }
        $row['propertyNames'] = Get-Safe -Block { Get-PropertyName -Object $spServer }
        $row['serviceInstances'] = Get-Safe -Block {
, @(Get-SPServiceInstance -Server $spServer | ForEach-Object -Process {
                    [ordered]@{ typeName = "$($_.TypeName)"; clrType = $_.GetType().Name; status = "$($_.Status)" }
                })
        }
        [void]$servers.Add($row)
    }
    $out['servers'] = @($servers)

    $webApplications = New-Object -TypeName System.Collections.ArrayList
    foreach ($webApp in @(Get-SPWebApplication -IncludeCentralAdministration)) {
        $row = [ordered]@{ displayName = "$($webApp.DisplayName)"; url = "$($webApp.Url)"; id = "$($webApp.Id)"; isAdministrationWebApplication = [bool]$webApp.IsAdministrationWebApplication }
        $row['applicationPool'] = Get-Safe -Block { [ordered]@{ name = "$($webApp.ApplicationPool.Name)"; identity = "$($webApp.ApplicationPool.Username)" } }
        $row['alternateUrls'] = Get-Safe -Block { , @($webApp.AlternateUrls | ForEach-Object -Process { Get-Scalar -Object $_ }) }
        $row['zones'] = Get-Safe -Block {
            $zones = New-Object -TypeName System.Collections.ArrayList
            foreach ($zone in @($webApp.IisSettings.Keys)) {
                $iis = $webApp.IisSettings[$zone]
                $zoneRow = [ordered]@{ zone = "$zone"; clrType = $iis.GetType().FullName; propertyNames = (Get-PropertyName -Object $iis); scalars = (Get-Scalar -Object $iis) }
                $zoneRow['serverBindings'] = Get-Safe -Block { , @($iis.ServerBindings | ForEach-Object -Process { Get-Scalar -Object $_ }) }
                $zoneRow['serverBindingPropertyNames'] = Get-Safe -Block { Get-PropertyName -Object (@($iis.ServerBindings)[0]) }
                $zoneRow['secureBindings'] = Get-Safe -Block { , @($iis.SecureBindings | ForEach-Object -Process { Get-Scalar -Object $_ }) }
                $zoneRow['secureBindingPropertyNames'] = Get-Safe -Block { Get-PropertyName -Object (@($iis.SecureBindings)[0]) }
                [void]$zones.Add($zoneRow)
            }
            return , @($zones)
        }
        [void]$webApplications.Add($row)
    }
    $out['webApplications'] = @($webApplications)

    if ($IncludeLimitFacts) {
        $limits = [ordered]@{}
        $databases = @(Get-SPContentDatabase)
        $limits['contentDatabaseCount'] = $databases.Count
        $limits['contentDatabases'] = @($databases | ForEach-Object -Process {
                $database = $_
                [ordered]@{
                    name              = "$($database.Name)"
                    serverAddress     = Get-Safe -Block { "$($database.Server.Address)" }
                    serverText        = "$($database.Server)"
                    currentSiteCount  = Get-Safe -Block { [int]$database.CurrentSiteCount }
                    warningSiteCount  = Get-Safe -Block { [int]$database.WarningSiteCount }
                    maximumSiteCount  = Get-Safe -Block { [int]$database.MaximumSiteCount }
                    diskSizeRequiredGB = Get-Safe -Block { [math]::Round([double]$database.DiskSizeRequired / 1GB, 2) }
                    rbsEnabled        = Get-Safe -Block { [bool]$database.RemoteBlobStorageSettings.Enabled() }
                }
            })
        $limits['webApplicationCount'] = @(Get-SPWebApplication).Count
        $limits['managedPaths'] = @(Get-SPWebApplication | ForEach-Object -Process {
                $webApp = $_
                [ordered]@{ webApplication = "$($webApp.DisplayName)"; count = Get-Safe -Block { @(Get-SPManagedPath -WebApplication $webApp).Count } }
            })
        $limits['hostNamedManagedPathCount'] = Get-Safe -Block { @(Get-SPManagedPath -HostHeader).Count }

        # The query of the check, for the first three content databases: used size of the data files, with the identity of the session
        $samples = New-Object -TypeName System.Collections.ArrayList
        foreach ($database in @($databases | Select-Object -First 3)) {
            $sample = [ordered]@{ name = "$($database.Name)"; usedDataMB = $null; error = '' }
            $connection = $null
            try {
                $builder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
                $builder['Data Source'] = if ($database.Server.Address) { "$($database.Server.Address)" } else { "$($database.Server)" }
                $builder['Initial Catalog'] = "$($database.Name)"
                $builder['Integrated Security'] = $true
                $builder['Application Name'] = 'SPSWeather probe (read-only)'
                $builder['Connect Timeout'] = 15
                $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection -ArgumentList $builder.ConnectionString
                $connection.Open()
                $command = $connection.CreateCommand()
                $command.CommandText = "SELECT CAST(ISNULL(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)), 0) * 8 / 1024.0 AS decimal(18,2)) FROM sys.database_files WHERE type = 0"
                $command.CommandTimeout = 30
                $sample['usedDataMB'] = [System.Decimal]$command.ExecuteScalar()
            }
            catch { $sample['error'] = $_.Exception.Message }
            finally { if ($null -ne $connection) { $connection.Close(); $connection.Dispose() } }
            [void]$samples.Add($sample)
        }
        $limits['usedSizeSamples'] = @($samples)
        $out['limitFacts'] = $limits
    }

    return ($out | ConvertTo-Json -Depth 12 -Compress)
}

$iisBlock = {
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Command -Name Get-Website -ErrorAction SilentlyContinue)) {
        Import-Module -Name WebAdministration -DisableNameChecking
    }

    function Get-Safe {
        param([System.Management.Automation.ScriptBlock]$Block)
        try {
            $result = & $Block
            if ($result -is [System.Array]) { return , $result }
            return $result
        }
        catch { return ('ERROR: ' + $_.Exception.Message) }
    }

    $out = [ordered]@{ computer = "$env:COMPUTERNAME"; collectedAt = (Get-Date).ToString('s') }
    $out['sites'] = Get-Safe -Block {
        , @(Get-Website | ForEach-Object -Process {
                $site = $_
                [ordered]@{
                    name            = "$($site.Name)"
                    id              = $site.Id
                    state           = "$($site.State)"
                    applicationPool = "$($site.applicationPool)"
                    physicalPath    = "$($site.physicalPath)"
                    bindings        = @($site.Bindings.Collection | ForEach-Object -Process {
                            [ordered]@{ protocol = "$($_.protocol)"; bindingInformation = "$($_.bindingInformation)"; sslFlags = "$($_.sslFlags)"; certificateHash = "$($_.certificateHash)"; certificateStoreName = "$($_.certificateStoreName)" }
                        })
                }
            })
    }
    # The identity of a pool is read, never its password
    $out['applicationPools'] = Get-Safe -Block {
        , @(Get-ChildItem -Path 'IIS:\AppPools' | ForEach-Object -Process {
                $pool = $_
                [ordered]@{ name = "$($pool.Name)"; state = "$($pool.State)"; managedRuntimeVersion = "$($pool.managedRuntimeVersion)"; identityType = "$($pool.processModel.identityType)"; userName = "$($pool.processModel.userName)" }
            })
    }
    $out['configHistory'] = Get-Safe -Block {
        $history = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub\history'
        if (-not (Test-Path -Path $history)) { return 'absent' }
        return , @(Get-ChildItem -Path $history -Directory | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object -Process {
                [ordered]@{ name = "$($_.Name)"; lastWriteTime = $_.LastWriteTime.ToString('s') }
            })
    }
    $out['configAuditLog'] = Get-Safe -Block {
        $log = Get-WinEvent -ListLog 'Microsoft-IIS-Configuration/Operational'
        $events = @()
        try {
            $events = @(Get-WinEvent -LogName 'Microsoft-IIS-Configuration/Operational' -MaxEvents 5 | ForEach-Object -Process {
                    $text = "$($_.Message)"
                    [ordered]@{ id = $_.Id; timeCreated = $_.TimeCreated.ToString('s'); message = $text.Substring(0, [math]::Min(200, $text.Length)) }
                })
        }
        catch { $events = @() }
        return [ordered]@{ isEnabled = [bool]$log.IsEnabled; recordCount = $log.RecordCount; latestEvents = $events }
    }
    return ($out | ConvertTo-Json -Depth 10 -Compress)
}

# --- Run ---------------------------------------------------------------------------------------------------------------------------
if ($Server -and (-not $Credential)) {
    $Credential = Get-Credential -Message 'Account used for the remote sessions (CredSSP)'
}
$mode = if ($Server) { 'remote (CredSSP)' } else { 'local (current identity)' }
Write-Host "SPSWeather probe, read-only. Mode: $mode. Nothing is changed on the farm, in IIS or in SQL Server." -ForegroundColor Yellow

Write-Section 'SharePoint: servers, web applications, bindings that SharePoint expects, limit facts'
$spJson = Invoke-Probe -Computer $Server -Block $spBlock -ArgumentList @(-not $SkipLimitFacts.IsPresent)
$sharePoint = $spJson | ConvertFrom-Json
Write-Host "Farm '$($sharePoint.farm.name)', build $($sharePoint.farm.buildVersion): $(@($sharePoint.servers).Count) server(s), $(@($sharePoint.webApplications).Count) web application(s) with Central Administration."

$suffix = ''
if ($Server -and $Server -match '\.') { $suffix = $Server.Substring($Server.IndexOf('.') + 1) }
else {
    try { $own = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName; if ($own -match '\.') { $suffix = $own.Substring($own.IndexOf('.') + 1) } } catch { $suffix = '' }
}

Write-Section 'IIS: sites, bindings, application pools, history and audit, on each server'
$iisResults = New-Object -TypeName System.Collections.ArrayList
foreach ($spServer in @($sharePoint.servers)) {
    $name = "$($spServer.name)"
    $computer = if (($name -notmatch '\.') -and $suffix) { "$name.$suffix" } else { $name }
    try {
        $iis = (Invoke-Probe -Computer $computer -Block $iisBlock) | ConvertFrom-Json
        [void]$iisResults.Add($iis)
        $siteCount = if ($iis.sites -is [System.String]) { 'error' } else { @($iis.sites).Count }
        Write-Host ("{0,-24} sites: {1}" -f $name, $siteCount)
    }
    catch {
        [void]$iisResults.Add([PSCustomObject]@{ computer = $name; error = $_.Exception.Message })
        Write-Host ("{0,-24} ERROR: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
    }
}

$report = [ordered]@{
    probe      = [ordered]@{ name = 'Probe-SPSIisDrift'; version = 1; readOnly = $true; mode = $mode; startedAt = $startedAt.ToString('s'); psVersion = $PSVersionTable.PSVersion.ToString(); host = $env:COMPUTERNAME }
    sharePoint = $sharePoint
    iis        = @($iisResults)
}
if (-not (Test-Path -Path $OutputFolder)) { [void](New-Item -Path $OutputFolder -ItemType Directory -Force) }
$farmLabel = ("$($sharePoint.farm.name)" -replace '[^A-Za-z0-9_-]', '_')
$file = Join-Path -Path $OutputFolder -ChildPath ("Probe-SPSIisDrift-$farmLabel-" + (Get-Date -Format 'yyyyMMdd-HHmm') + '.json')
[System.IO.File]::WriteAllText($file, ($report | ConvertTo-Json -Depth 20), (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))

Write-Section 'Summary'
foreach ($webApp in @($sharePoint.webApplications)) {
    foreach ($zone in @($webApp.zones)) {
        if ($zone -is [System.String]) { continue }
        $bindings = @(@($zone.serverBindings) + @($zone.secureBindings) | Where-Object -FilterScript { $_ -and ($_ -isnot [System.String]) } | ForEach-Object -Process { ($_.PSObject.Properties | Where-Object -FilterScript { $_.Name -match 'HostHeader|Port|Address' } | ForEach-Object -Process { "$($_.Name)=$($_.Value)" }) -join ' ' })
        Write-Host ("{0} [{1}] site '{2}' | {3}" -f $webApp.displayName, $zone.zone, $zone.scalars.ServerComment, ($bindings -join ' ; '))
    }
}
foreach ($spServer in @($sharePoint.servers)) {
    $hosts = @(@($spServer.serviceInstances) | Where-Object -FilterScript { $_ -isnot [System.String] -and "$($_.typeName)" -match 'Web Application|Central Administration' } | ForEach-Object -Process { "$($_.typeName)=$($_.status)" })
    Write-Host ("{0,-24} role={1} minRoleCompliant={2} | {3}" -f $spServer.name, $spServer.role, $spServer.compliantWithMinRole, ($hosts -join ' ; '))
}
Write-Host ''
Write-Host "Report written to: $file" -ForegroundColor Green
