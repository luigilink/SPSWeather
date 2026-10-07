# Behavioural tests for Backup-SPSWeatherJsonFile (snapshot archiving + retention).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'Backup-SPSWeatherJsonFile' {
    It 'returns $null and does nothing when the source file is missing (first run)' {
        $src = Join-Path -Path $TestDrive -ChildPath 'missing.json'
        $hist = Join-Path -Path $TestDrive -ChildPath 'hist-missing'
        Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist | Should -BeNullOrEmpty
    }

    It 'archives the existing file with a timestamp and leaves the original in place' {
        $src = Join-Path -Path $TestDrive -ChildPath 'zebes-PROD-CONTENT.json'
        $hist = Join-Path -Path $TestDrive -ChildPath 'hist-archive'
        Set-Content -Path $src -Value '{"a":1}'

        $backup = Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist -TimeStamp '20260101-0000'

        $backup | Should -Match 'zebes-PROD-CONTENT-20260101-0000\.json$'
        Test-Path -Path $backup | Should -BeTrue
        Test-Path -Path $src | Should -BeTrue
    }

    It 'prunes history files older than the retention window' {
        $src = Join-Path -Path $TestDrive -ChildPath 'app.json'
        $hist = Join-Path -Path $TestDrive -ChildPath 'hist-retention'
        New-Item -Path $hist -ItemType Directory -Force | Out-Null
        $stale = Join-Path -Path $hist -ChildPath 'app-20200101-0000.json'
        Set-Content -Path $stale -Value '{}'
        (Get-Item $stale).LastWriteTime = (Get-Date).AddDays(-60)
        Set-Content -Path $src -Value '{"b":2}'

        Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist -TimeStamp '20260202-0000' -RetentionDays 30 | Out-Null

        Test-Path -Path $stale | Should -BeFalse
        Test-Path -Path (Join-Path -Path $hist -ChildPath 'app-20260202-0000.json') | Should -BeTrue
    }
}
