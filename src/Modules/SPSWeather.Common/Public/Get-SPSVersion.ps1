function Get-SPSVersion {
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

    Write-Verbose "Getting SharePoint Version of Farm '$Server'"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
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
        # Return SharePoint version
        return $spsVersion.DisplayVersion
    }
    return $result
}
