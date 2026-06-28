function Get-USPAudienceStatus {
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
        class USPAudienceStatus {
            [System.String]$Farm
            [System.String]$Server
            [System.String]$StartTime
            [System.String]$EndTime
            [System.String]$Duration
            [System.String]$Status
        }

        $serviceAppUSP = Get-SPServiceApplication -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            $_.GetType().FullName -eq 'Microsoft.Office.Server.Administration.UserProfileApplication'
        }

        if ($null -ne $serviceAppUSP) {
            $tbUSPAudienceStatus = New-Object -TypeName System.Collections.ArrayList
            $timerJob = Get-SPTimerJob | Where-Object -FilterScript { $_.Name -like '*_AudienceCompilationJob*' }
            if ($null -ne $timerJob) {
                $currentTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById([System.TimeZoneInfo]::Local.Id)
                $lastEntries = $timerJob.HistoryEntries | Where-Object -FilterScript { $_.StartTime -gt (Get-Date).AddDays(-1) }
                foreach ($lastEntry in $lastEntries) {
                    if ($null -ne $lastEntry.StartTime) {
                        $startTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($lastEntry.StartTime, $currentTimeZone)
                    }
                    if ($null -ne $lastEntry.EndTime) {
                        $endTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($lastEntry.EndTime, $currentTimeZone)
                    }
                    if (($null -ne $startTime) -and ($null -ne $endTime)) {
                        $duration = [math]::Round(($endTime - $startTime).TotalSeconds)
                    }
                    $supAudienceStatus = $lastEntry.Status
                    [void]$tbUSPAudienceStatus.Add([USPAudienceStatus]@{
                            Farm      = $params.Farm;
                            Server    = $lastEntry.ServerName;
                            StartTime = $startTime;
                            EndTime   = $endTime;
                            Duration  = $duration;
                            Status    = $supAudienceStatus;
                        })
                }
                return $tbUSPAudienceStatus
            }
        }
    }
    return $result
}
