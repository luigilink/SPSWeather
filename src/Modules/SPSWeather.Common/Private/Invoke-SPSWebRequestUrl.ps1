function Invoke-SPSWebRequestUrl {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Server,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $InstallAccount,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $URL,

        [Parameter()]
        [System.String]
        $Name
    )

    Write-Verbose -Message "Invoking WebRequest from '$Server' with User '$UserName'"
    Write-Verbose -Message "Testing $Name access on $url"
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        try {
            $responseObject = Invoke-WebRequest -Uri $params.URL `
                -UseDefaultCredentials `
                -Method Get `
                -UseBasicParsing `
                -Verbose
        }
        catch [Net.WebException] {
            Write-Output $_.Exception.Message
        }

        if ($responseObject.StatusCode -ne 200) {
            throw "$($params.Name) access failed. $($params.URL) is not responding properly."
        }
        else {
            Write-Verbose -Message "HTTP 200 - $($params.URL) is accessible"
        }
    }
    return $result
}
