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

    if (-not $Servers) { $Servers = @($Server) }

    # One direct CredSSP session per server (single hop) so each node is reached
    # without a second hop from the entry server.
    $tbSYSDiskUsageStatus = New-Object -TypeName System.Collections.ArrayList
    foreach ($spServer in $Servers) {
        try {
            [System.String]$remoteServer = [System.Net.Dns]::GetHostByName($spServer).HostName
            $rows = Invoke-SPSCommand -Credential $InstallAccount `
                -Arguments @($Farm, $spServer, $WarningPercentage) `
                -Server $remoteServer `
                -ScriptBlock {
                $cfgFarm = $args[0]; $cfgServer = $args[1]; $cfgWarn = $args[2]
                $disks = New-Object -TypeName System.Collections.ArrayList
                $getDrives = Get-Volume | Where-Object -FilterScript { $_.DriveType -eq 'Fixed' -and $null -ne $_.DriveLetter }
                foreach ($getDrive in $getDrives) {
                    $perFreeSpace = ($getDrive.SizeRemaining / $getDrive.Size) * 100
                    if ($perFreeSpace -gt $cfgWarn) { $freeSpaceStatus = 'OK'; $isMailInfo = $true }
                    else { $freeSpaceStatus = "Less than $cfgWarn %"; $isMailInfo = $false }
                    [void]$disks.Add([PSCustomObject]@{
                            Farm        = $cfgFarm; Server = $cfgServer;
                            DriveLetter = $getDrive.DriveLetter;
                            Size        = [math]::Round($getDrive.Size / 1073741824, 2);
                            FreeSpace   = [math]::Round($getDrive.SizeRemaining / 1073741824, 2);
                            Status      = $freeSpaceStatus; IsInfo = $isMailInfo
                        })
                }
                return $disks
            }
            foreach ($r in $rows) { [void]$tbSYSDiskUsageStatus.Add($r) }
        }
        catch {
            [void]$tbSYSDiskUsageStatus.Add([PSCustomObject]@{
                    Farm        = $Farm; Server = $spServer; DriveLetter = '';
                    Size        = ''; FreeSpace = ''; Status = 'Unreachable'; IsInfo = $false
                })
        }
    }
    return $tbSYSDiskUsageStatus
}
