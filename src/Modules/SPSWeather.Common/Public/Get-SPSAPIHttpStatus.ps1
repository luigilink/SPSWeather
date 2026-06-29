function Get-SPSAPIHttpStatus {
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
        class APIHttpStatus {
            [System.String]$Farm
            [System.String]$Title
            [System.String]$Url
            [System.String]$HTTPCode
            [System.String]$Status
            [System.Boolean]$IsInfo
        }
        $collectionWebsURL = New-Object -TypeName System.Collections.ArrayList
        $spWebApplications = Get-SPWebApplication -ErrorAction SilentlyContinue

        if ($null -ne $spWebApplications) {
            #Initialize ArrayList variable
            $tbSPAPIHttpStatus = New-Object -TypeName System.Collections.ArrayList
            foreach ($spWebApplication in $spWebApplications) {
                $getRootSPSite = Get-SPSite ($spWebApplication.url)
                if ($getRootSPSite) {
                    $rootSPSiteUrl = $getRootSPSite.Url
                    $collectionWebsURL = @{
                        RootSite    = @{
                            Url   = "$($rootSPSiteUrl)"
                            Title = 'Root SPSite'
                        }
                        UserProfile = @{
                            Url   = "$($rootSPSiteUrl)/_api/sp.userprofiles.peoplemanager/GetMyProperties"
                            Title = 'User Profile REST'
                        }
                        Search      = @{
                            Url   = "$($rootSPSiteUrl)/_api/search/query?querytext='*'&RowLimit=1"
                            Title = 'Search REST'
                        }
                    }
                    $useragent = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
                    $authentUrl = ("$($rootSPSiteUrl)" + '/_windows/default.aspx?ReturnUrl=/_layouts/15/Authenticate.aspx?Source=%2f')
                    Write-Verbose -Message "Getting webSession by opening $($authentUrl) with Invoke-WebRequest"
                    try {
                        [void](Invoke-WebRequest -Uri $authentUrl `
                                -SessionVariable webSession `
                                -TimeoutSec 90 `
                                -UserAgent $useragent `
                                -UseDefaultCredentials `
                                -UseBasicParsing)
                    }
                    catch {
                        Write-Warning -Message $_.Exception.Message
                    }

                    foreach ($collectionKey in $collectionWebsURL.keys) {
                        $exceptionResponse = $null
                        $httpCODE = $null
                        $webUrlStatus = 'Failed'
                        $webUrlPSO = $collectionWebsURL[$collectionKey]
                        $attempt = 1
                        while ($attempt -le 5 -and $httpCODE -ne '200') {
                            try {
                                $webUrlResponse = Invoke-WebRequest -Uri $webUrlPSO.Url `
                                    -WebSession $webSession `
                                    -TimeoutSec 90 `
                                    -UserAgent $useragent `
                                    -UseBasicParsing `
                                    -ErrorAction SilentlyContinue
                            }
                            catch [Net.WebException] {
                                $exceptionResponse = $_.Exception.Message
                            }
                            if ($exceptionResponse) {
                                $httpCODE = $exceptionResponse
                            }
                            else {
                                if ($webUrlResponse.StatusCode -eq 200) {
                                    $webUrlStatus = 'OK'
                                    $httpCODE = '200'
                                    $isMailInfo = $true
                                }
                                else {
                                    $httpCODE = $webUrlResponse.StatusCode
                                    $isMailInfo = $false
                                }
                            }
                            $attempt++
                        }
                        [void]$tbSPAPIHttpStatus.Add([APIHttpStatus]@{
                                Farm     = $params.farm
                                Title    = $webUrlPSO.Title;
                                Url      = $webUrlPSO.Url;
                                HTTPCode = $httpCODE;
                                Status   = $webUrlStatus
                                IsInfo   = $isMailInfo;
                            })
                    }
                }
            }
            return $tbSPAPIHttpStatus
        }
    }
    return $result
}
