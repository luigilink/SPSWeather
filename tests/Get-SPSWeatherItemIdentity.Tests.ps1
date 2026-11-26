# Behavioural tests for Get-SPSWeatherItemIdentity (private): how an item is recognised from one run to the next.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force
    function script:Get-Identity {
        param([string]$Section, $Row)
        InModuleScope SPSWeather.Common -Parameters @{ S = $Section; R = $Row } { param($S, $R) Get-SPSWeatherItemIdentity -Section $S -Row $R }
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherItemIdentity' {
    Context 'the identity' {
        It 'names <Section> by <Expected>' -ForEach @(
            @{ Section = 'SQLDatabaseStatus'; Row = [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = 'WSS_Content'; IsInfo = $false }; Expected = 'SQL1 / WSS_Content' }
            @{ Section = 'SQLDiskStatus'; Row = [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Volume = 'E:\'; FreePercent = 4; IsInfo = $false }; Expected = 'SQL1 / E:\' }
            @{ Section = 'IISApplicationPoolStatus'; Row = [PSCustomObject]@{ Farm = 'F'; Server = 'WFE1'; ApplicationPool = 'SharePoint - 80'; Status = 'Stopped'; IsInfo = $false }; Expected = 'WFE1 / SharePoint - 80' }
            @{ Section = 'SYSDiskUsageStatus'; Row = [PSCustomObject]@{ Farm = 'F'; Server = 'APP1'; DriveLetter = 'C'; Status = 'Low'; IsInfo = $false }; Expected = 'APP1 / C' }
            @{ Section = 'SPTimerServiceStatus'; Row = [PSCustomObject]@{ Farm = 'F'; Server = 'APP2'; Status = 'Disabled'; IsInfo = $false }; Expected = 'APP2' }
            @{ Section = 'SPHealthAnalyzer'; Row = [PSCustomObject]@{ farm = 'F'; title = 'Missing server side dependencies.'; severity = '1 - Error'; category = 'Configuration' }; Expected = 'Missing server side dependencies.' }
            @{ Section = 'SPAPIHttpStatus'; Row = [PSCustomObject]@{ Farm = 'F'; Title = 'Search REST'; Url = 'https://sp/_api/search'; HTTPCode = 500; Status = 'Failed'; IsInfo = $false }; Expected = 'Search REST / https://sp/_api/search' }
            @{ Section = 'SPFailedTimerJobs'; Row = [PSCustomObject]@{ farm = 'F'; server = 'APP1'; JobDefinitionTitle = 'Health Analysis'; FailedExecutions = 3; Status = 'Failed'; IsInfo = $false }; Expected = 'APP1 / Health Analysis' }
            @{ Section = 'SYSEventViewerAppErrors'; Row = [PSCustomObject]@{ Farm = 'F'; Server = 'APP1'; ID = 1000; Severity = 'Error'; Name = '.NET Runtime'; Count = 7; IsInfo = $false }; Expected = 'APP1 / 1000 / .NET Runtime' }
            @{ Section = 'SPSContentDBStatus'; Row = [PSCustomObject]@{ farm = 'F'; SQLInstance = 'SQL1'; DatabaseName = 'WSS_Content_1'; DiskSize = '1 GB'; IsInfo = $true }; Expected = 'SQL1 / WSS_Content_1' }
        ) {
            (Get-Identity -Section $Section -Row $Row).Name | Should -Be $Expected
        }

        It 'does not let the role of an availability group replica, which changes with a failover, change its identity' {
            $primary = Get-Identity -Section 'SQLAvailabilityStatus' -Row ([PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Type = 'AvailabilityGroup'; Name = 'AG1 / SQL2 (PRIMARY)'; Detail = 'NOT_HEALTHY'; IsInfo = $false })
            $secondary = Get-Identity -Section 'SQLAvailabilityStatus' -Row ([PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Type = 'AvailabilityGroup'; Name = 'AG1 / SQL2 (SECONDARY)'; Detail = 'NOT_HEALTHY'; IsInfo = $false })
            $primary.Id | Should -Be $secondary.Id
            $primary.Id | Should -Be 'SQLAvailabilityStatus|sql1|availabilitygroup|ag1 / sql2'
            $primary.Name | Should -Be 'SQL1 / AvailabilityGroup / AG1 / SQL2 (PRIMARY)'
        }

        It 'still tells two replicas of a group apart, and two groups apart' {
            $a = Get-Identity -Section 'SQLAvailabilityStatus' -Row ([PSCustomObject]@{ SqlServer = 'SQL1'; Type = 'AvailabilityGroup'; Name = 'AG1 / SQL2 (SECONDARY)' })
            $b = Get-Identity -Section 'SQLAvailabilityStatus' -Row ([PSCustomObject]@{ SqlServer = 'SQL1'; Type = 'AvailabilityGroup'; Name = 'AG1 / SQL3 (SECONDARY)' })
            $c = Get-Identity -Section 'SQLAvailabilityStatus' -Row ([PSCustomObject]@{ SqlServer = 'SQL1'; Type = 'AvailabilityGroup'; Name = 'AG2 / SQL2 (SECONDARY)' })
            $a.Id | Should -Not -Be $b.Id
            $a.Id | Should -Not -Be $c.Id
        }

        It 'leaves the name of a failed SQL Agent job as it is, parentheses included' {
            $job = Get-Identity -Section 'SQLAvailabilityStatus' -Row ([PSCustomObject]@{ SqlServer = 'SQL1'; Type = 'FailedAgentJob'; Name = 'Backup (full)'; Detail = 'failed run on 20261126'; IsInfo = $false })
            $job.Id | Should -Be 'SQLAvailabilityStatus|sql1|failedagentjob|backup (full)'
            $job.Cause | Should -Be 'failed run on #'
        }

        It 'does not change when the state or the figures of a row change' {
            $a = Get-Identity -Section 'SYSDiskUsageStatus' -Row ([PSCustomObject]@{ Farm = 'F'; Server = 'APP1'; DriveLetter = 'C'; Size = 100; FreeSpace = 4; Status = 'Low'; IsInfo = $false })
            $b = Get-Identity -Section 'SYSDiskUsageStatus' -Row ([PSCustomObject]@{ Farm = 'F'; Server = 'APP1'; DriveLetter = 'C'; Size = 100; FreeSpace = 9; Status = 'Critical'; IsInfo = $false })
            $a.Id | Should -Be $b.Id
        }

        It 'is not case sensitive, and tells two items of one section apart' {
            $a = Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'SQL1'; Name = 'DB1' })
            $b = Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'sql1'; Name = 'db1' })
            $c = Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'SQL1'; Name = 'DB2' })
            $a.Id | Should -Be $b.Id
            $a.Id | Should -Not -Be $c.Id
        }

        It 'does not mix two sections that name the same thing' {
            $a = Get-Identity -Section 'SPUpgradeStatus' -Row ([PSCustomObject]@{ server = 'APP1' })
            $b = Get-Identity -Section 'SPTimerServiceStatus' -Row ([PSCustomObject]@{ Server = 'APP1' })
            $a.Id | Should -Not -Be $b.Id
        }

        It 'uses every column except the noise and the state for a section that is not listed' {
            $row = [PSCustomObject]@{ PSComputerName = 'x'; RunspaceId = 'y'; PSShowComputerName = $false; Farm = 'F'; Owner = 'o1'; Kind = 'k1'; Status = 'Bad'; IsInfo = $false }
            $a = Get-Identity -Section 'NewSection' -Row $row
            $a.Name | Should -Be 'o1 / k1'
            $row.Status = 'Worse'
            (Get-Identity -Section 'NewSection' -Row $row).Id | Should -Be $a.Id
        }

        It 'gives the same Id with -IdOnly, and leaves the name, the detail and the cause empty' {
            $row = [PSCustomObject]@{ Farm = 'F'; SqlServer = 'SQL1'; Name = 'DB1'; Recommendation = 'last full backup 4.5 d ago'; IsInfo = $false }
            $full = Get-Identity -Section 'SQLDatabaseStatus' -Row $row
            $light = InModuleScope SPSWeather.Common -Parameters @{ R = $row } { param($R) Get-SPSWeatherItemIdentity -Section 'SQLDatabaseStatus' -Row $R -IdOnly }
            $light.Id | Should -Be $full.Id
            $light.Name | Should -Be ''
            $light.Detail | Should -Be ''
            $light.Cause | Should -Be ''
            $full.Name | Should -Be 'SQL1 / DB1'
        }

        It 'gives an identity to a row that has nothing to name it' {
            $a = Get-Identity -Section 'NewSection' -Row ([PSCustomObject]@{ IsInfo = $false })
            $a.Id | Should -Be 'NewSection|'
            $a.Name | Should -Be ''
        }

        It 'does not throw on a null row' {
            (Get-Identity -Section 'SQLDatabaseStatus' -Row $null).Id | Should -Be 'SQLDatabaseStatus|'
        }
    }

    Context 'the detail and the cause' {
        It 'shows the advisory first, then the state' {
            (Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'S'; Name = 'D'; Recommendation = 'last full backup 4.5 d ago'; State = 'ONLINE' })).Detail | Should -Be 'last full backup 4.5 d ago'
            (Get-Identity -Section 'IISApplicationPoolStatus' -Row ([PSCustomObject]@{ Server = 'S'; ApplicationPool = 'P'; Status = 'Stopped' })).Detail | Should -Be 'Stopped'
            (Get-Identity -Section 'SPUpgradeStatus' -Row ([PSCustomObject]@{ server = 'S'; UpgradeStatus = 'NeedsUpgrade' })).Detail | Should -Be 'NeedsUpgrade'
        }

        It 'shows the severity and the category of a Health Analyzer rule' {
            (Get-Identity -Section 'SPHealthAnalyzer' -Row ([PSCustomObject]@{ title = 'T'; severity = '1 - Error'; category = 'Availability' })).Detail | Should -Be '1 - Error · Availability'
        }

        It 'replaces the numbers of the cause so that the same cause is the same text' {
            $a = Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'S'; Name = 'D1'; Recommendation = 'last full backup 4.5 d ago' })
            $b = Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'S'; Name = 'D2'; Recommendation = 'last full backup 12 d ago' })
            $a.Cause | Should -Be 'last full backup # d ago'
            $b.Cause | Should -Be $a.Cause
            (Get-Identity -Section 'SQLDatabaseStatus' -Row ([PSCustomObject]@{ SqlServer = 'S'; Name = 'D3'; Recommendation = 'no full backup found' })).Cause | Should -Be 'no full backup found'
        }

        It 'keeps the detail on one line, 200 characters at most, and the cause 80' {
            $row = [PSCustomObject]@{ SqlServer = 'S'; Name = 'D'; Recommendation = ("line one`r`nline two`t" * 30) }
            $i = Get-Identity -Section 'SQLDatabaseStatus' -Row $row
            $i.Detail.Length | Should -BeLessOrEqual 200
            $i.Cause.Length | Should -BeLessOrEqual 80
            $i.Detail | Should -Not -Match '[\r\n\t]'
        }

        It 'has an empty detail and cause when there is nothing to say' {
            $i = Get-Identity -Section 'SYSLastRebootStatus' -Row ([PSCustomObject]@{ Server = 'S' })
            $i.Detail | Should -Be ''
            $i.Cause | Should -Be ''
        }
    }
}
