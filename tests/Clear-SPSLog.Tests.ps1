# Behavioural tests for Clear-SPSLog (retention-based log pruning).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Clear-SPSLog' {
    It 'deletes files older than the retention window and keeps recent ones' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'logs-prune'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $old = Join-Path -Path $folder -ChildPath 'old.log'
        $new = Join-Path -Path $folder -ChildPath 'new.log'
        Set-Content -Path $old -Value 'x'
        Set-Content -Path $new -Value 'y'
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-200)

        Clear-SPSLog -path $folder -Retention 180 | Out-Null

        Test-Path -Path $old | Should -BeFalse
        Test-Path -Path $new | Should -BeTrue
    }

    It 'does nothing when retention is 0 (pruning disabled)' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'logs-noprune'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $old = Join-Path -Path $folder -ChildPath 'old.log'
        Set-Content -Path $old -Value 'x'
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-500)

        Clear-SPSLog -path $folder -Retention 0 | Out-Null

        Test-Path -Path $old | Should -BeTrue
    }

    It 'only targets files matching the filter' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'logs-filter'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $log = Join-Path -Path $folder -ChildPath 'old.log'
        $txt = Join-Path -Path $folder -ChildPath 'old.txt'
        Set-Content -Path $log -Value 'x'
        Set-Content -Path $txt -Value 'x'
        (Get-Item $log).LastWriteTime = (Get-Date).AddDays(-200)
        (Get-Item $txt).LastWriteTime = (Get-Date).AddDays(-200)

        Clear-SPSLog -path $folder -Retention 180 -Filter '*.log' | Out-Null

        Test-Path -Path $log | Should -BeFalse
        Test-Path -Path $txt | Should -BeTrue
    }

    It 'does not throw when the path does not exist' {
        { Clear-SPSLog -path (Join-Path -Path $TestDrive -ChildPath 'nope') -Retention 30 } | Should -Not -Throw
    }
}
