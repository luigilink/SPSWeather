function Get-SPSContentDBStatus {
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
        class SPDatabaseStatusInfo {
            [System.String]$farm
            [System.String]$SQLInstance
            [System.String]$DatabaseName
            [System.String]$Type
            [System.String]$Upgrade
            [System.String]$DiskSize
            [System.Boolean]$IsInfo
        }
        try {
            $spDatabases = Get-SPDatabase

            if ($null -ne $spDatabases) {
                #Initialize ArrayList variable
                $tbSPDatabases = New-Object -TypeName System.Collections.ArrayList
                foreach ($spDatabase in $spDatabases) {
                    $upgradeStatus = 'No Action Required'
                    $isMailInfo = $true
                    if ($null -ne $spDatabase.Server.Address) {
                        $sqlInstance = $spDatabase.Server.Address
                    }
                    else {
                        $sqlInstance = $spDatabase.Server
                    }
                    if ($spDatabase.NeedsUpgrade) {
                        $upgradeStatus = 'Upgrade Required'
                        $isMailInfo = $false
                    }
                    if ($spDatabase.Type.Contains('.')) {
                        $spDatabaseType = ([regex]::Matches($spDatabase.Type, '(?<=\.)[^.]*$')).value
                    }
                    else {
                        $spDatabaseType = $spDatabase.Type
                    }
                    [void]$tbSPDatabases.Add([SPDatabaseStatusInfo]@{
                            farm         = $params.Farm;
                            SQLInstance  = $sqlInstance;
                            DatabaseName = $spDatabase.Name;
                            Type         = $spDatabaseType;
                            Upgrade      = $upgradeStatus;
                            DiskSize     = ([math]::Round($spDatabase.DiskSizeRequired / 1GB, 2)).ToString();
                            IsInfo       = $isMailInfo;
                        })
                }
                return $tbSPDatabases
            }
        }
        catch {
            return $_
        }
    }
    return $result
}
