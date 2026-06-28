function Get-SPWeatherListInfo {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [System.String]
        $Version,

        [Parameter()]
        [System.String]
        $PSVersion,

        [Parameter()]
        [System.String]
        $UserAccount,

        [Parameter()]
        [System.String]
        $DateStarted,

        [Parameter()]
        [System.String]
        $DateEnded,

        [Parameter()]
        [System.String]
        $Environment,

        [Parameter()]
        [System.String]
        $Application
    )

    class SPWeatherScriptInfo {
        [System.String]$Version
        [System.String]$PSVersion
        [System.String]$UserAccount
        [System.String]$DateStarted
        [System.String]$DateEnded
        [System.String]$Environment
        [System.String]$Application
    }

    try {
        #Initialize ArrayList variable
        $tbSPWeatherScriptInfo = New-Object -TypeName System.Collections.ArrayList
        [void]$tbSPWeatherScriptInfo.Add([SPWeatherScriptInfo]@{
                Version     = $Version;
                PSVersion   = $PSVersion;
                UserAccount = $UserAccount;
                DateStarted = $DateStarted;
                DateEnded   = $DateEnded;
                Environment = $Environment;
                Application = $Application;
            })
    }
    catch {
        return $_
    }
    return $tbSPWeatherScriptInfo
}
