# Contract tests for the SPSWeather.ps1 entry script parameters.

Describe 'Entry script -Action contract' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $entryPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSWeather.ps1'
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($entryPath, [ref]$tokens, [ref]$errs)
        $script:entryParams = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
    }

    It 'exposes an -Action parameter' {
        $entryParams | Should -Contain 'Action'
    }

    It 'no longer exposes -Install or -Uninstall switches' {
        $entryParams | Should -Not -Contain 'Install'
        $entryParams | Should -Not -Contain 'Uninstall'
    }
}
