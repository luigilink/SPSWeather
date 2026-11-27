# Keeps the wiki and the README in step with the parameters of SPSWeather.ps1: a command that a page shows must be one that the script accepts.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'), [ref]$tokens, [ref]$errs)
    $script:entryParameters = @($ast.ParamBlock.Parameters | ForEach-Object -Process { $_.Name.VariablePath.UserPath })
    $script:actionValues = @($ast.ParamBlock.Parameters | Where-Object -FilterScript { $_.Name.VariablePath.UserPath -eq 'Action' } |
            ForEach-Object -Process { $_.Attributes | Where-Object -FilterScript { $_.TypeName.Name -eq 'ValidateSet' } } |
            ForEach-Object -Process { $_.PositionalArguments | ForEach-Object -Process { $_.Value } })
    $script:pages = @(Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'wiki') -Filter '*.md') + @(Get-Item -Path (Join-Path -Path $repoRoot -ChildPath 'README.md'))
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
        $text = [System.IO.File]::ReadAllText($Path)
        $unknown = New-Object -TypeName System.Collections.ArrayList
        foreach ($line in ($text -split "`n")) {
            if ($line -notmatch '(?<![\w-])SPSWeather\.ps1\s') { continue }
            if ($line -match 'Test-SPSWeather|New-SPSDashboard') { continue }
            foreach ($match in [regex]::Matches($line, '\s-([A-Za-z]+)\b')) {
                $name = $match.Groups[1].Value
                $known = $entryParameters + @('NoProfile', 'ExecutionPolicy', 'File', 'Execution', 'Command', 'WhatIf', 'Verbose')
                if ($known -notcontains $name -and $name -notmatch '^(EnableSMTP)$') { [void]$unknown.Add($name) }
            }
        }
        @($unknown) | Should -BeNullOrEmpty
    }
}
