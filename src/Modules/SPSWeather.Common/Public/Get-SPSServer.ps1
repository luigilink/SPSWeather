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
