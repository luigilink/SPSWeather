function Get-SPSSolutionStatus {
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
        class WSPDeployment {
            [System.String]$Farm
            [System.String]$SolutionName
            [System.String]$DeploymentState
            [System.String]$LastOperationResult
            [System.String]$LastOperationEndTime
            [System.Boolean]$IsInfo
        }
        $spSolutions = (Get-SPFarm).solutions
        if ($null -ne $spSolutions) {
            #Initialize ArrayList variable
            $tbSPSolutions = New-Object -TypeName System.Collections.ArrayList
            foreach ($spSolution in $spSolutions) {
                if (($spSolution.LastOperationResult -ne [Microsoft.SharePoint.Administration.SPSolutionOperationResult]::DeploymentSucceeded) -and `
                    ($spSolution.LastOperationResult -ne [Microsoft.SharePoint.Administration.SPSolutionOperationResult]::RetractionSucceeded) -and `
                    ($spSolution.LastOperationResult -ne [Microsoft.SharePoint.Administration.SPSolutionOperationResult]::NoOperationPerformed)) {
                    $isMailInfo = $false
                }
                else {
                    $isMailInfo = $true
                }
                [void]$tbSPSolutions.Add([WSPDeployment]@{
                        farm                 = $params.Farm;
                        SolutionName         = $spSolution.Name;
                        DeploymentState      = $spSolution.DeploymentState;
                        LastOperationResult  = $spSolution.LastOperationResult;
                        LastOperationEndTime = $spSolution.LastOperationEndTime;
                        IsInfo               = $isMailInfo;
                    })
            }
            return $tbSPSolutions
        }
    }
    return $result
}
