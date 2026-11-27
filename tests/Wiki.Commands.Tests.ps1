# Keeps the wiki and the README in step with the parameters of SPSWeather.ps1: a command that a page shows must be one that the script accepts.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'), [ref]$tokens, [ref]$errs)
    $script:entryParameters = @($ast.ParamBlock.Parameters | ForEach-Object -Process { $_.Name.VariablePath.UserPath })
    $script:actionValues = @($ast.ParamBlock.Parameters | Where-Object -FilterScript { $_.Name.VariablePath.UserPath -eq 'Action' } |
            ForEach-Object -Process { $_.Attributes | Where-Object -FilterScript { $_.TypeName.Name -eq 'ValidateSet' } } |
            ForEach-Object -Process { $_.PositionalArguments | ForEach-Object -Process { $_.Value } })

    # The text of a page with every command on one line: a backtick at the end of a line continues the command on the next one
    function script:Join-Continuation {
        param([string]$Text)
        ($Text -replace "`r`n", "`n") -replace '`[ \t]*\n[ \t]*', ' '
    }

    # The commands of a page that start SPSWeather.ps1 (bare, or quoted as in & '.\SPSWeather.ps1' ...)
    function script:Get-ScriptCommand {
        param([string]$Text)
        foreach ($line in ((Join-Continuation -Text $Text) -split "`n")) {
            if ($line -notmatch '(?<![\w-])SPSWeather\.ps1[''"]?(?=\s|$)') { continue }
            if ($line -match 'Test-SPSWeather|New-SPSDashboard') { continue }
            $line
        }
    }

    # The parameter names of those commands that the script does not have
    function script:Get-UnknownParameter {
        param([string]$Text, [string[]]$Known = $script:entryParameters)
        $accepted = $Known + @('NoProfile', 'ExecutionPolicy', 'File', 'Execution', 'Command', 'WhatIf', 'Verbose')
        foreach ($line in (Get-ScriptCommand -Text $Text)) {
            foreach ($match in [regex]::Matches($line, '\s-([A-Za-z]+)\b')) {
                if ($accepted -notcontains $match.Groups[1].Value) { $match.Groups[1].Value }
            }
        }
    }
}

Describe 'The check of the commands of a page' {
    It 'finds a parameter that the script does not have in <Name>' -ForEach @(
        @{ Name = 'a bare call'; Text = ".\SPSWeather.ps1 -ConfigFile 'c.psd1' -Actoin Install" }
        @{ Name = 'a call quoted with an ampersand'; Text = "& '.\SPSWeather.ps1' -Actoin Install" }
        @{ Name = 'a double-quoted call'; Text = '& ".\SPSWeather.ps1" -Actoin Install' }
        @{ Name = 'a typo on a line that continues the command'; Text = ".\SPSWeather.ps1 -ConfigFile 'c.psd1' ``" + "`n" + "    -Actoin Install" }
        @{ Name = 'a continuation with Windows line endings'; Text = ".\SPSWeather.ps1 -ConfigFile 'c.psd1' ``" + "`r`n" + "    -Actoin Install" }
    ) {
        @(Get-UnknownParameter -Text $Text) | Should -Be @('Actoin')
    }

    It 'accepts the real parameters, whatever their case, on one line or several' {
        @(Get-UnknownParameter -Text ".\SPSWeather.ps1 -ConfigFile 'c.psd1' -action Install -InstallAccount (Get-Credential)").Count | Should -Be 0
        @(Get-UnknownParameter -Text (".\SPSWeather.ps1 -ConfigFile 'c.psd1' ``" + "`n" + "    -Action Install ``" + "`n" + "    -InstallAccount (Get-Credential)")).Count | Should -Be 0
        @(Get-UnknownParameter -Text "powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\SCRIPT\SPSWeather\SPSWeather.ps1 -ConfigFile c.psd1").Count | Should -Be 0
    }

    It 'follows the script: a switch that the script no longer has is found, in any case' {
        $without = @($entryParameters | Where-Object -FilterScript { $_ -ne 'EnableSmtp' })
        @(Get-UnknownParameter -Text ".\SPSWeather.ps1 -ConfigFile 'c.psd1' -EnableSmtp" -Known $without) | Should -Be @('EnableSmtp')
        @(Get-UnknownParameter -Text ".\SPSWeather.ps1 -ConfigFile 'c.psd1' -EnableSMTP" -Known $without) | Should -Be @('EnableSMTP')
        @(Get-UnknownParameter -Text ".\SPSWeather.ps1 -ConfigFile 'c.psd1' -EnableSMTP").Count | Should -Be 0 -Because 'the switch is still in the script today'
    }

    It 'does not look at a line that does not start the script' {
        @(Get-UnknownParameter -Text 'Run -Actoin or -Foo here, and Test-SPSWeatherReadiness.ps1 -Bar').Count | Should -Be 0
    }
}

Describe 'Commands shown in the wiki and the README' {
    It 'finds the parameters of the entry script, and the values of -Action' {
        $entryParameters | Should -Contain 'ConfigFile'
        $entryParameters | Should -Contain 'Action'
        $entryParameters | Should -Contain 'InstallAccount'
        @($actionValues | Sort-Object) | Should -Be @('Default', 'Install', 'Uninstall')
    }

    It 'does not show -Install or -Uninstall as a switch of the script (<Name>)' -ForEach @(
        Get-ChildItem -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'wiki') -Filter '*.md' | ForEach-Object -Process { @{ Name = $_.Name; Path = $_.FullName } }
        @{ Name = 'README.md'; Path = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'README.md') }
    ) {
        $entryParameters | Should -Not -Contain 'Install'
        $entryParameters | Should -Not -Contain 'Uninstall'
        $text = [System.IO.File]::ReadAllText($Path)
        [regex]::Matches($text, '(?<![\w-])-(Install|Uninstall)\b(?!\w)') | ForEach-Object -Process { $_.Value } | Should -BeNullOrEmpty
    }

    It 'only uses parameters of the script in the commands that start SPSWeather.ps1 (<Name>)' -ForEach @(
        Get-ChildItem -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'wiki') -Filter '*.md' | ForEach-Object -Process { @{ Name = $_.Name; Path = $_.FullName } }
        @{ Name = 'README.md'; Path = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'README.md') }
    ) {
        @(Get-UnknownParameter -Text ([System.IO.File]::ReadAllText($Path))) | Should -BeNullOrEmpty
    }
}
