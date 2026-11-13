# Contract tests for Add-SPSWeatherEvent (Windows event-log writer).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Add-SPSWeatherEvent' {
    It 'requires a mandatory -Message' {
        $param = (Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common).Parameters['Message']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'restricts -EntryType with a ValidateSet' {
        $cmd = Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common
        $validate = $cmd.Parameters['EntryType'].Attributes.Where{ $_.TypeId.Name -eq 'ValidateSetAttribute' }
        $validate | Should -Not -BeNullOrEmpty
        $validate[0].ValidValues | Should -Contain 'Information'
        $validate[0].ValidValues | Should -Contain 'Warning'
        $validate[0].ValidValues | Should -Contain 'Error'
    }

    It 'defaults -Source to SPSWeather and exposes -EventID' {
        $cmd = Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common
        $cmd.Parameters['Source'].Attributes.Where{ $_ -is [System.Management.Automation.ParameterAttribute] } |
            Should -Not -BeNullOrEmpty
        $cmd.Parameters.Keys | Should -Contain 'EventID'
    }

    It 'self-heals a misrouted source instead of returning silently' {
        $src = (Get-Command -Name Add-SPSWeatherEvent -Module SPSWeather.Common).Definition
        $src | Should -Match 'DeleteEventSource'
        $src | Should -Not -Match '\[ERROR\] Specified source'
    }
}
