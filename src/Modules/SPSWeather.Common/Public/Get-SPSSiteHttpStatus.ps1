function Get-SPSSiteHttpStatus {
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
        class SPSiteHttpStatus {
            [System.String]$Farm
            [System.String]$Url
            [System.String]$HTTPCode
            [System.String]$Status
            [System.Boolean]$IsInfo
        }

        $spWebApplications = Get-SPWebApplication -ErrorAction SilentlyContinue
        #Initialize ArrayList variable
        $tbSPSiteHttpStatus = New-Object -TypeName System.Collections.ArrayList
        if ($null -ne $spWebApplications) {
            foreach ($webApp in $spWebApplications) {
                $getRootSPSite = Get-SPSite ($webApp.url)
                $useragent = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
                $authentUrl = ("$($getRootSPSite.Url)" + '/_windows/default.aspx?ReturnUrl=/_layouts/15/Authenticate.aspx?Source=%2f')
                Write-Output "Getting webSession by opening $($authentUrl) with Invoke-WebRequest"
                try {
                    Invoke-WebRequest -Uri $authentUrl `
                        -SessionVariable webSession `
                        -TimeoutSec 90 `
                        -UserAgent $useragent `
                        -UseDefaultCredentials  `
                        -UseBasicParsing
                }
                catch {
                    Write-Warning -Message $_.Exception.Message
                }
                $sites = $webApp.sites | Where-Object -FilterScript { $_.url -notmatch "$env:COMPUTERNAME" -and $_.url -notmatch 'sitemaster-' }
                if ($sites.Count -ne 0) {
                    foreach ($site in $sites) {
                        $exceptionResponse = $null
                        $httpCODE = $null
                        $webUrlStatus = 'Failed'
                        $attempt = 1
                        while ($attempt -le 5 -and $httpCODE -ne '200') {
                            try {
                                $webUrlResponse = Invoke-WebRequest -Uri $site.RootWeb.Url `
                                    -WebSession $webSession `
                                    -TimeoutSec 90 `
                                    -UserAgent $useragent  `
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
                        [void]$tbSPSiteHttpStatus.Add([SPSiteHttpStatus]@{
                                Farm     = $params.Farm;
                                Url      = $site.RootWeb.Url;
                                HTTPCode = $httpCODE;
                                Status   = $webUrlStatus
                                IsInfo   = $isMailInfo;
                            })
                        $site.Dispose()
                    }
                }
            }
        }
        return $tbSPSiteHttpStatus
    }
    return $result
}
