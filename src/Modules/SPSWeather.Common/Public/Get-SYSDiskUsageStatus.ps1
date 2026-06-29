function Get-SYSDiskUsageStatus {
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
        $Servers,

        [Parameter()]
        [System.UInt32]
        $WarningPercentage
    )

    $result = Invoke-SPSCommand -Credential $InstallAccount `
                                -Arguments $PSBoundParameters `
                                -Server $Server `
                                -ScriptBlock {
        $params = $args[0]
        class SYSDiskUsageStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$DriveLetter
            [System.String]$Size
            [System.String]$FreeSpace
            [System.String]$Status
            [System.Boolean]$IsInfo
        }
        $tbSYSDiskUsageStatus = New-Object -TypeName System.Collections.ArrayList
        foreach ($spServer in $params.Servers) {
            try {
                [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
                $getDrives = Invoke-Command -ComputerName $remoteServer { Get-Volume | Where-Object -FilterScript { $_.DriveType -eq 'Fixed' -and $null -ne $_.DriveLetter } }
                foreach ($getDrive in $getDrives) {
                    $driveSize = [math]::Round($($getDrive.Size) / 1073741824, 2)
                    $driveFree = [math]::Round($($getDrive.SizeRemaining) / 1073741824, 2)
                    $perFreeSpace = ($getDrive.SizeRemaining / $getDrive.Size) * 100
                    if ($perFreeSpace -gt $params.WarningPercentage) {
                        $freeSpaceStatus = 'OK'
                        $isMailInfo      = $true
                    }
                    else {
                        $freeSpaceStatus = "Less than $($params.WarningPercentage) %"
                        $isMailInfo      = $false
                    }
                    [void]$tbSYSDiskUsageStatus.Add([SYSDiskUsageStatus]@{
                            Farm        = $params.Farm;
                            Server      = $spServer;
                            DriveLetter = $getDrive.DriveLetter;
                            Size        = $driveSize;
                            FreeSpace   = $driveFree;
                            Status      = $freeSpaceStatus;
                            IsInfo      = $isMailInfo
                        })
                }
            }
            catch {
                [void]$tbSYSDiskUsageStatus.Add([SYSDiskUsageStatus]@{
                        Farm        = $params.Farm;
                        Server      = $spServer;
                        DriveLetter = '';
                        Size        = '';
                        FreeSpace   = '';
                        Status      = 'Unreachable';
                        IsInfo      = $false
                    })
            }
        }
        return $tbSYSDiskUsageStatus
    }
    return $result
}
