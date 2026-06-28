function Get-SPSUpgradeStatus {
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
        class UpgradeStatusInfo {
            [System.String]$farm
            [System.String]$server
            [System.String]$SPBuildVersion
            [System.String]$SPRegVersion
            [System.String]$UpgradeStatus
            [System.Boolean]$IsInfo
        }

        try {
            #Initialize ArrayList variable
            $tbUpgradeListItems = New-Object -TypeName System.Collections.ArrayList
            $spfarm = Get-SPFarm
            $spServers = (Get-SPServer | Where-Object -FilterScript { $_.Role -ne 'Invalid' })
            $productVersions = [Microsoft.SharePoint.Administration.SPProductVersions]::GetProductVersions($spfarm)
            $buildVersion = $spfarm.BuildVersion -Join '.'

            foreach ($spServer in $spServers) {
                $isMailInfo = $true
                # location in registry to get info about installed software
                $regLoc = Get-ChildItem HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
                # Get SharePoint Products and language packs
                $programs = $regLoc |  Where-Object -FilterScript {
                    $_.PsPath -like '*\Office*'
                } | ForEach-Object -Process { Get-ItemProperty $_.PsPath }
                # output the info about Products and Language Packs
                $spsVersion = $programs | Where-Object -FilterScript {
                    $_.DisplayName -like '*SharePoint Server*'
                }
                $serverProductInfo = $productVersions.GetServerProductInfo($spServer.Id)
                if ($serverProductInfo.InstallStatus -ne 'NoActionRequired') {
                    $isMailInfo = $false
                }
                [void]$tbUpgradeListItems.Add([UpgradeStatusInfo]@{
                        farm           = $params.Farm
                        server         = $spServer.Address;
                        SPBuildVersion = $buildVersion;
                        SPRegVersion   = $spsVersion.DisplayVersion;
                        UpgradeStatus  = $serverProductInfo.InstallStatus
                        IsInfo         = $isMailInfo;
                    })
            }
            return $tbUpgradeListItems
        }
        catch {
            return $_
        }
    }
    return $result
}
