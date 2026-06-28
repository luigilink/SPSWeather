function Get-SPSFailedTimerJob {
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
        [ValidateRange(0, 100)]
        [System.Double]
        $FailureThresholdPercent = 5,

        [Parameter()]
        [ValidateRange(1, 168)]
        [System.Int32]
        $LookbackHours = 24
    )
    $result = Invoke-SPSCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -Server $Server `
        -ScriptBlock {
        $params = $args[0]
        class FailedTimerJob {
            [System.String]$Farm
            [System.String]$server
            [System.String]$JobDefinitionTitle
            [System.Int32]$FailedExecutions
            [System.Int32]$TotalExecutions
            [System.Double]$FailurePercentage
            [System.Double]$ThresholdPercentage
            [System.String]$Status
            [System.Boolean]$IsInfo
        }
        try {
            $startTime = (Get-Date).AddHours(-1 * $params.LookbackHours)
            $farm = Get-SPFarm
            $timerService = $farm.TimerService
            $jobHistoryEntries = $timerService.JobHistoryEntries | Where-Object -FilterScript {
                ($_.StartTime -gt $startTime) -and -not [System.String]::IsNullOrWhiteSpace($_.JobDefinitionTitle)
            }

            if ($null -ne $jobHistoryEntries) {
                #Initialize ArrayList variable
                $tbfailedJobs = New-Object -TypeName System.Collections.ArrayList
                $jobHistoryGroups = $jobHistoryEntries | Group-Object -Property ServerName, JobDefinitionTitle
                foreach ($jobHistoryGroup in $jobHistoryGroups) {
                    $jobRuns = @($jobHistoryGroup.Group)
                    $failedExecutions = @($jobRuns | Where-Object -FilterScript { $_.Status -eq 'Failed' }).Count
                    if ($failedExecutions -eq 0) {
                        continue
                    }

                    $totalExecutions = $jobRuns.Count
                    if ($totalExecutions -eq 0) {
                        continue
                    }

                    $failurePercentage = [math]::Round(($failedExecutions / $totalExecutions) * 100, 2)
                    $isInfo = $failurePercentage -lt $params.FailureThresholdPercent
                    if ($isInfo) {
                        $jobStatus = "Below $($params.FailureThresholdPercent)% threshold"
                    }
                    else {
                        $jobStatus = "Failure rate above $($params.FailureThresholdPercent)% threshold"
                    }

                    $firstRun = $jobRuns | Select-Object -First 1
                    [void]$tbfailedJobs.Add([FailedTimerJob]@{
                            farm               = $params.Farm;
                            server             = $firstRun.ServerName;
                            JobDefinitionTitle = $firstRun.JobDefinitionTitle;
                            FailedExecutions   = $failedExecutions;
                            TotalExecutions    = $totalExecutions;
                            FailurePercentage  = $failurePercentage;
                            ThresholdPercentage = $params.FailureThresholdPercent;
                            Status             = $jobStatus;
                            IsInfo             = $isInfo
                        })
                }

                return $tbfailedJobs | Sort-Object -Property `
                    @{ Expression = 'IsInfo'; Descending = $false }, `
                    @{ Expression = 'FailurePercentage'; Descending = $true }, `
                    @{ Expression = 'FailedExecutions'; Descending = $true }, `
                    @{ Expression = 'JobDefinitionTitle'; Descending = $false }
            }
        }
        catch {
            return $_
        }
    }
    return $result
}
