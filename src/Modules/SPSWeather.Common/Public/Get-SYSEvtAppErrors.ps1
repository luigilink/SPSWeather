function Get-SYSEvtAppErrors {
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
        $Farm = 'SPS',

        [Parameter()]
        [System.String[]]
        $Servers
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -Server $Server `
                                -ScriptBlock {
        $params = $args[0]
        class SYSEventViewerAppError {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$ID
            [System.String]$Severity
            [System.String]$Name
            [System.String]$Count
        }
        $tbSYSEventViewerAppErrors = New-Object -TypeName System.Collections.ArrayList
        foreach ($pSserver in $params.Servers) {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($pSserver).HostName
            try {
                $appErrors = Invoke-Command -ComputerName $remoteServer -ErrorAction Stop -ScriptBlock {
                    Get-WinEvent -FilterHashTable @{LogName = 'Application'; Level = 2; StartTime = ((Get-Date) - (New-TimeSpan -Days 1)) } `
                                 -ErrorAction SilentlyContinue
                }
                if ($null -eq $appErrors) {
                    [void]$tbSYSEventViewerAppErrors.Add([SYSEventViewerAppError]@{
                        Farm     = $params.Farm
                        Server   = $pSserver;
                        ID       = 'Non Applicable';
                        Severity = 'Non Applicable';
                        Name     = 'No error found the last 24h';
                        Count    = '0';
                    })
                }
                else {
                    $grpAppErrors = $appErrors | Group-Object Id | Select-Object -Property Count, Name
                    foreach ($grpAppError in $grpAppErrors) {
                        $currentAppError = $appErrors | Where-Object -FilterScript { $_.ID -eq $grpAppError.Name } | Get-Unique
                        [void]$tbSYSEventViewerAppErrors.Add([SYSEventViewerAppError]@{
                            Farm     = $params.Farm
                            Server   = $pSserver;
                            ID       = $currentAppError.Id;
                            Severity = $currentAppError.LevelDisplayName;
                            Name     = $currentAppError.ProviderName;
                            Count    = $grpAppError.Count;
                        })
                    }
                }
            }
            catch {
                [void]$tbSYSEventViewerAppErrors.Add([SYSEventViewerAppError]@{
                    Farm     = $params.Farm
                    Server   = $pSserver;
                    ID       = 'Non Applicable';
                    Severity = 'Warning';
                    Name     = 'Unreachable';
                    Count    = '0';
                })
            }
        }
        return $tbSYSEventViewerAppErrors
    }
    return $result
}
