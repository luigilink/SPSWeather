function Get-SPSSearchEntTopology {
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
        class SearchTopologyStatus {
            [System.String]$Farm
            [System.String]$SearchService
            [System.String]$ComponentHost
            [System.String]$ComponentName
            [System.String]$State
            [System.Boolean]$IsInfo
        }
        $spSearchEntSvc = Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue
        if ($null -ne $spSearchEntSvc) {
            $tbSearchTopologyStatus = New-Object -TypeName System.Collections.ArrayList
            try {
                $getSchStatus = Get-SPEnterpriseSearchStatus -SearchApplication $spSearchEntSvc -Detailed -ErrorAction Stop
                foreach ($compoSch in $getSchStatus) {
                    $isMailInfo = $True
                    if ($compoSch.State -ne 'Active') {
                        $isMailInfo = $false
                    }
                    if ($null -eq $compoSch.Details['Host']) {
                        $spComponentServer = 'NotApplicable'
                    }
                    else {
                        $spComponentServer = $($compoSch.Details['Host']).ToUpper()
                    }
                    [void]$tbSearchTopologyStatus.Add([SearchTopologyStatus]@{
                        Farm             = $params.Farm;
                        SearchService    = $spSearchEntSvc.Name;
                        ComponentHost    = $spComponentServer;
                        ComponentName    = $compoSch.Name;
                        State            = $compoSch.State;
                        IsInfo           = $isMailInfo;
                    })
                }
            }
            catch {
                [void]$tbSearchTopologyStatus.Add([SearchTopologyStatus]@{
                    Farm             = $params.Farm;
                    SearchService    = $spSearchEntSvc.Name;
                    ComponentHost    = 'Unreachable';
                    ComponentName    = 'Search unavailable';
                    State            = $_.Exception.Message;
                    IsInfo           = $false;
                })
            }
            return $tbSearchTopologyStatus
        }
    }
    return $result
}
