# Tests for Get-SPSWeatherTaskArgument: the arguments of the scheduled task are built in one place, with the two paths between
# double quotes and in the -File form, so that a path that holds a space stays one argument. On Windows the arguments are
# also run for real with Windows PowerShell 5.1, which is what the Task Scheduler starts.

# $IsWindows does not exist in Windows PowerShell 5.1: the platform is read when the tests are discovered
$onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    # Splits a command line the way Windows does: a quoted part is one argument and its quotation marks are dropped
    function Split-CommandLine {
        param([string]$Line)
        @([regex]::Matches($Line, '"[^"]*"|\S+') | ForEach-Object -Process { $_.Value.Trim('"') })
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Get-SPSWeatherTaskArgument' {
    It 'builds the -File form with the script and the configuration file between double quotes' {
        Get-SPSWeatherTaskArgument -ScriptRoot 'D:\SCRIPT\SPSWeather' -ConfigFile 'D:\SCRIPT\SPSWeather\Config\contoso-PROD.psd1' |
            Should -BeExactly '-ExecutionPolicy Bypass -File "D:\SCRIPT\SPSWeather\SPSWeather.ps1" -ConfigFile "D:\SCRIPT\SPSWeather\Config\contoso-PROD.psd1"'
    }

    It 'keeps a path that holds a space in one argument (<Name>)' -ForEach @(
        @{ Name = 'script folder'; Root = 'D:\My Scripts\SPSWeather'; Config = 'D:\SCRIPT\Config\c.psd1'; ScriptFile = 'D:\My Scripts\SPSWeather\SPSWeather.ps1'; ConfigValue = 'D:\SCRIPT\Config\c.psd1' }
        @{ Name = 'configuration file'; Root = 'D:\SCRIPT\SPSWeather'; Config = 'D:\SCRIPT\My Config\contoso PROD.psd1'; ScriptFile = 'D:\SCRIPT\SPSWeather\SPSWeather.ps1'; ConfigValue = 'D:\SCRIPT\My Config\contoso PROD.psd1' }
        @{ Name = 'both, on a share'; Root = '\\srv\My Share\SPS Weather'; Config = '\\srv\My Share\SPS Weather\Config\c d.psd1'; ScriptFile = '\\srv\My Share\SPS Weather\SPSWeather.ps1'; ConfigValue = '\\srv\My Share\SPS Weather\Config\c d.psd1' }
    ) {
        $tokens = @(Split-CommandLine -Line (Get-SPSWeatherTaskArgument -ScriptRoot $Root -ConfigFile $Config))
        $tokens.Count | Should -Be 6
        $tokens[2] | Should -Be '-File'
        $tokens[3] | Should -Be $ScriptFile
        $tokens[4] | Should -Be '-ConfigFile'
        $tokens[5] | Should -Be $ConfigValue
    }

    It 'does not double the backslash when the script is at the root of a drive' {
        Get-SPSWeatherTaskArgument -ScriptRoot 'D:\' -ConfigFile 'D:\c.psd1' | Should -Match '-File "D:\\SPSWeather\.ps1"'
    }

    It 'adds the deprecated -EnableSMTP switch as its own last argument only when it is asked for' {
        $with = @(Split-CommandLine -Line (Get-SPSWeatherTaskArgument -ScriptRoot 'D:\S' -ConfigFile 'D:\S\c.psd1' -KeepEnableSmtp))
        $with.Count | Should -Be 7
        $with[6] | Should -BeExactly '-EnableSMTP'
        $without = @(Split-CommandLine -Line (Get-SPSWeatherTaskArgument -ScriptRoot 'D:\S' -ConfigFile 'D:\S\c.psd1'))
        $without.Count | Should -Be 6
        $without | Should -Not -Contain '-EnableSMTP'
    }

    It 'asks for both paths' {
        { Get-SPSWeatherTaskArgument -ScriptRoot '' -ConfigFile 'D:\c.psd1' } | Should -Throw
        { Get-SPSWeatherTaskArgument -ScriptRoot 'D:\S' -ConfigFile '' } | Should -Throw
    }

    It 'gives arguments that the check of the task reads like those of a task registered by 3.5.0' {
        $arguments = Get-SPSWeatherTaskArgument -ScriptRoot 'D:\S' -ConfigFile 'D:\S\c.psd1' -KeepEnableSmtp
        InModuleScope SPSWeather.Common -Parameters @{ Arguments = $arguments } {
            param($Arguments)
            Mock Read-SPSScheduledTask { [PSCustomObject]@{ Supported = $true; Found = $true; Readable = $true; Arguments = $Arguments; Error = '' } }
            (Get-SPSScheduledTaskSmtpCheck -Application 'contoso' -Environment 'PROD').State | Should -Be 'HasSwitch'
        }
    }

    It 'starts the script with the right arguments in Windows PowerShell 5.1, in a folder with spaces' -Skip:(-not $onWindows) {
        $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('SPS Weather task ' + [guid]::NewGuid().ToString('N'))
        New-Item -Path (Join-Path -Path $root -ChildPath 'My Config') -ItemType Directory -Force | Out-Null
        try {
            Set-Content -Path (Join-Path -Path $root -ChildPath 'SPSWeather.ps1') -Encoding UTF8 -Value @(
                'param([string]$ConfigFile, [switch]$EnableSMTP)'
                'Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath ''received.txt'') -Value @($ConfigFile, [string]$EnableSMTP.IsPresent)'
            )
            $config = Join-Path -Path $root -ChildPath 'My Config\contoso PROD.psd1'
            Set-Content -Path $config -Value '@{}'
            $arguments = Get-SPSWeatherTaskArgument -ScriptRoot $root -ConfigFile $config -KeepEnableSmtp
            $exe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $process = Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            $process.ExitCode | Should -Be 0
            $received = @(Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'received.txt'))
            $received[0] | Should -Be $config
            $received[1] | Should -Be 'True'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
