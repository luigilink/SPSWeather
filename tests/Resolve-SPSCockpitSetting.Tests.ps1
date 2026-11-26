# Behavioural tests for Resolve-SPSCockpitSetting (public): the one place that reads Dashboard.Cockpit.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    function script:Resolve {
        param($Config)
        Resolve-SPSCockpitSetting -Config $Config -Application 'zebes' -Environment 'PROD' -ResultsFolder 'C:\SPSWeather\Results'
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-SPSCockpitSetting' {
    Context 'the page is opt-in' {
        It 'is off when there is no Dashboard, no Cockpit key, a null configuration, or a Dashboard that is not a table' -ForEach @(
            @{ Name = 'no Dashboard'; Config = @{ ApplicationName = 'a' } }
            @{ Name = 'a Dashboard without the key'; Config = @{ Dashboard = @{ OutputPath = ''; Url = '' } } }
            @{ Name = 'an empty Dashboard'; Config = @{ Dashboard = @{} } }
            @{ Name = 'a null configuration'; Config = $null }
            @{ Name = 'a Dashboard that is a string'; Config = @{ Dashboard = 'text' } }
            @{ Name = 'a Dashboard that is $null'; Config = @{ Dashboard = $null } }
        ) {
            $r = Resolve -Config $Config
            $r.Enabled | Should -BeFalse -Because $Name
            $r.Messages.Count | Should -Be 0 -Because 'nothing is wrong, the key is simply not there'
        }

        It 'is on only for $true or the text true, whatever the case and the blanks' -ForEach @(
            @{ Value = $true; Expected = $true }
            @{ Value = $false; Expected = $false }
            @{ Value = 'true'; Expected = $true }
            @{ Value = 'TRUE'; Expected = $true }
            @{ Value = ' True '; Expected = $true }
            @{ Value = 'false'; Expected = $false }
            @{ Value = 'False'; Expected = $false }
        ) {
            $r = Resolve -Config @{ Dashboard = @{ Cockpit = $Value } }
            $r.Enabled | Should -Be $Expected
            $r.Messages.Count | Should -Be 0
        }
    }

    Context 'a value that is not a boolean' {
        It 'is never cast: <Name> turns the page off and says so' -ForEach @(
            @{ Name = 'maybe'; Value = 'maybe'; Shown = "'maybe'" }
            @{ Name = 'an empty string'; Value = ''; Shown = "''" }
            @{ Name = 'blanks'; Value = '   '; Shown = "'   '" }
            @{ Name = 'yes'; Value = 'yes'; Shown = "'yes'" }
            @{ Name = '1'; Value = 1; Shown = 'a value of type Int32' }
            @{ Name = '0'; Value = 0; Shown = 'a value of type Int32' }
            @{ Name = 'a list'; Value = @($true); Shown = 'a value of type Object' }
            @{ Name = 'a table'; Value = @{ a = 1 }; Shown = 'a value of type Hashtable' }
            @{ Name = '$null'; Value = $null; Shown = '$null' }
        ) {
            $r = Resolve -Config @{ Dashboard = @{ Cockpit = $Value } }
            $r.Enabled | Should -BeFalse
            $r.Messages.Count | Should -Be 1
            $r.Messages[0] | Should -Match 'Dashboard\.Cockpit must be \$true or \$false'
            $r.Messages[0] | Should -Match ([regex]::Escape("got $Shown"))
            $r.Messages[0] | Should -Match 'is not produced'
        }
    }

    Context 'where the page goes and where it is served' {
        It 'goes to Results, named after the application and the environment, when OutputPath is empty or absent' -ForEach @(
            @{ Dashboard = @{ Cockpit = $true } }
            @{ Dashboard = @{ Cockpit = $true; OutputPath = '' } }
            @{ Dashboard = @{ Cockpit = $true; OutputPath = '   ' } }
            @{ Dashboard = @{ Cockpit = $true; OutputPath = $null } }
        ) {
            $r = Resolve -Config @{ Dashboard = $Dashboard }
            $r.FileName | Should -Be 'zebes-PROD-cockpit.html'
            $r.Folder | Should -Be 'C:\SPSWeather\Results'
            $r.Path | Should -Be ('C:\SPSWeather\Results' + [System.IO.Path]::DirectorySeparatorChar + 'zebes-PROD-cockpit.html')
        }

        It 'goes next to the dashboards when OutputPath is set, local folder or share' -ForEach @(
            @{ Folder = '\\pull01\SPSWeather$' }
            @{ Folder = 'D:\Dashboards' }
        ) {
            $r = Resolve -Config @{ Dashboard = @{ Cockpit = $true; OutputPath = $Folder } }
            $r.Folder | Should -Be $Folder
            $r.Path | Should -Be ($Folder + [System.IO.Path]::DirectorySeparatorChar + 'zebes-PROD-cockpit.html')
        }

        It 'builds the address from Url, whatever the slashes and the blanks, and leaves it empty without Url' -ForEach @(
            @{ Url = 'https://pull01/SPSWeather'; Expected = 'https://pull01/SPSWeather/zebes-PROD-cockpit.html' }
            @{ Url = 'https://pull01/SPSWeather/'; Expected = 'https://pull01/SPSWeather/zebes-PROD-cockpit.html' }
            @{ Url = '  https://pull01/SPSWeather//  '; Expected = 'https://pull01/SPSWeather/zebes-PROD-cockpit.html' }
            @{ Url = ''; Expected = '' }
            @{ Url = '   '; Expected = '' }
            @{ Url = $null; Expected = '' }
            @{ Url = 42; Expected = '' }
        ) {
            (Resolve -Config @{ Dashboard = @{ Cockpit = $true; Url = $Url } }).Url | Should -Be $Expected
        }

        It 'does not need the drive of the folder to exist on the machine that resolves it, and does not double a trailing slash' -ForEach @(
            @{ Folder = 'Q:\Nowhere\Dashboards' }
            @{ Folder = 'Q:\Nowhere\Dashboards\' }
            @{ Folder = '\\no-such-server\share$\' }
        ) {
            $r = Resolve -Config @{ Dashboard = @{ Cockpit = $true; OutputPath = $Folder } }
            $r.Path | Should -Be ($Folder.TrimEnd('\') + [System.IO.Path]::DirectorySeparatorChar + 'zebes-PROD-cockpit.html')
            $r.Path | Should -Not -Match '[\\/]{2}zebes'
        }

        It 'gives the same names as the per-farm dashboards, which use the same OutputPath and Url keys' {
            $r = Resolve -Config @{ Dashboard = @{ Cockpit = $true; OutputPath = 'D:\D'; Url = 'https://h/p' } }
            $r.FileName | Should -Be 'zebes-PROD-cockpit.html'
            $r.Url | Should -Be 'https://h/p/zebes-PROD-cockpit.html'
        }

        It 'resolves the paths even when the page is off, so that the readiness check can describe them' {
            $r = Resolve -Config @{ Dashboard = @{ Cockpit = $false; OutputPath = 'D:\D'; Url = 'https://h/p' } }
            $r.Enabled | Should -BeFalse
            $r.Path | Should -Be ('D:\D' + [System.IO.Path]::DirectorySeparatorChar + 'zebes-PROD-cockpit.html')
        }
    }

    Context 'an application or an environment name that is not a file name' {
        It 'keeps the names as the per-farm dashboards do (a farm stem keeps letters, digits, _ and -)' {
            $r = Resolve-SPSCockpitSetting -Config @{ Dashboard = @{ Cockpit = $true } } -Application 'a-b_c' -Environment 'P1' -ResultsFolder 'R'
            $r.FileName | Should -Be 'a-b_c-P1-cockpit.html'
        }
    }

    Context 'the function reads and changes nothing' {
        It 'does not modify the configuration it is given' {
            $config = @{ Dashboard = @{ Cockpit = 'true'; OutputPath = 'D:\D'; Url = 'https://h/p/' } }
            [void](Resolve -Config $config)
            $config.Dashboard.Cockpit | Should -Be 'true'
            $config.Dashboard.Url | Should -Be 'https://h/p/'
        }

        It 'is exported and has no mandatory parameter other than the configuration' {
            $command = Get-Command -Name Resolve-SPSCockpitSetting -Module SPSWeather.Common
            $mandatory = @($command.Parameters.Values | Where-Object -FilterScript { $_.Attributes | Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } } | ForEach-Object -Process { $_.Name })
            $mandatory | Should -Be @('Config')
        }
    }
}
