# Behavioural tests for ConvertTo-SPSWeatherReport (report assembly + alert flag).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Report assembly (ConvertTo-SPSWeatherReport)' {
    It 'adds every non-null section as a property, preserving order' {
        $sections = [ordered]@{
            SectionA = @([pscustomobject]@{ IsInfo = $true })
            SectionB = @([pscustomobject]@{ IsInfo = $true })
            SectionC = @()
        }
        $result = ConvertTo-SPSWeatherReport -Section $sections
        $result.Report.PSObject.Properties.Name | Should -Be @('SectionA', 'SectionB', 'SectionC')
    }

    It 'raises IsAlert when any row has IsInfo = $false' {
        $sections = [ordered]@{
            Healthy = @([pscustomobject]@{ IsInfo = $true })
            Broken  = @([pscustomobject]@{ IsInfo = $true }, [pscustomobject]@{ IsInfo = $false })
        }
        (ConvertTo-SPSWeatherReport -Section $sections).IsAlert | Should -BeTrue
    }

    It 'keeps IsAlert false when every row is informational' {
        $sections = [ordered]@{
            One = @([pscustomobject]@{ IsInfo = $true })
            Two = @([pscustomobject]@{ IsInfo = $true }, [pscustomobject]@{ IsInfo = $true })
        }
        (ConvertTo-SPSWeatherReport -Section $sections).IsAlert | Should -BeFalse
    }

    It 'never raises IsAlert for info-only sections without an IsInfo property' {
        $sections = [ordered]@{
            SYSLastRebootStatus = @([pscustomobject]@{ Server = 'SRV1'; LastReboot = '2026-06-28' })
            SYSDOTNETVersion    = @([pscustomobject]@{ Server = 'SRV1'; Version = '4.8' })
        }
        (ConvertTo-SPSWeatherReport -Section $sections).IsAlert | Should -BeFalse
    }

    It 'keeps empty-collection sections (stable JSON shape)' {
        $sections = [ordered]@{ Empty = @() }
        $result = ConvertTo-SPSWeatherReport -Section $sections
        $result.Report.PSObject.Properties.Name | Should -Contain 'Empty'
    }

    It 'matches a hand-rolled replication of the legacy assembly logic' {
        $sections = [ordered]@{
            SPHealthAnalyzer   = @([pscustomobject]@{ IsInfo = $true })
            SPSContentDBStatus = @([pscustomobject]@{ IsInfo = $false })
            SPWeatherListInfo  = @([pscustomobject]@{ PSVersion = '5.1' })
            SYSDiskUsageStatus = @()
        }

        # Replicate the original per-section behavior.
        $legacy = [PSCustomObject]@{}
        $legacyAlert = 'INFO'
        foreach ($name in $sections.Keys) {
            $data = $sections[$name]
            if ($null -ne $data) {
                if ($data.IsInfo -contains $false) { $legacyAlert = 'ALERT' }
                $legacy | Add-Member -MemberType NoteProperty -Name $name -Value $data
            }
        }

        $result = ConvertTo-SPSWeatherReport -Section $sections
        $result.Report.PSObject.Properties.Name | Should -Be ($legacy.PSObject.Properties.Name)
        (& { if ($result.IsAlert) { 'ALERT' } else { 'INFO' } }) | Should -Be $legacyAlert
    }
}
