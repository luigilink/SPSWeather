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

    Context 'a history folder shared by several environments' {
        BeforeAll {
            function script:New-Archive {
                param($Folder, [string]$Name, [int]$DaysOld)
                $file = Join-Path -Path $Folder -ChildPath $Name
                Set-Content -Path $file -Value '{}'
                (Get-Item -Path $file).LastWriteTime = (Get-Date).AddDays(-$DaysOld)
                $file
            }
        }

        It 'prunes the old archives of its own file and leaves the old archives of the other environments alone' {
            $hist = Join-Path -Path $TestDrive -ChildPath 'hist-shared'
            New-Item -Path $hist -ItemType Directory -Force | Out-Null
            $ownOld = New-Archive -Folder $hist -Name 'zebes-PROD-CONTENT-20200101-0000.json' -DaysOld 60
            $ownRecent = New-Archive -Folder $hist -Name 'zebes-PROD-CONTENT-20261110-0000.json' -DaysOld 5
            $otherEnvOld = New-Archive -Folder $hist -Name 'zebes-TEST-CONTENT-20200101-0000.json' -DaysOld 60
            $otherAppOld = New-Archive -Folder $hist -Name 'other-PROD-CONTENT-20200101-0000.json' -DaysOld 60
            $src = Join-Path -Path $TestDrive -ChildPath 'zebes-PROD-CONTENT.json'
            Set-Content -Path $src -Value '{"a":1}'

            Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist -TimeStamp '20261126-0900' -RetentionDays 30 | Out-Null

            Test-Path -Path $ownOld | Should -BeFalse
            Test-Path -Path $ownRecent | Should -BeTrue
            Test-Path -Path $otherEnvOld | Should -BeTrue
            Test-Path -Path $otherAppOld | Should -BeTrue
            Test-Path -Path (Join-Path -Path $hist -ChildPath 'zebes-PROD-CONTENT-20261126-0900.json') | Should -BeTrue
        }

        It 'matches its own archives whatever the case of the file name' {
            $hist = Join-Path -Path $TestDrive -ChildPath 'hist-case'
            New-Item -Path $hist -ItemType Directory -Force | Out-Null
            $ownOld = New-Archive -Folder $hist -Name 'ZEBES-prod-content-20200101-0000.json' -DaysOld 60
            $src = Join-Path -Path $TestDrive -ChildPath 'zebes-PROD-CONTENT.json'
            Set-Content -Path $src -Value '{}'
            Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist -TimeStamp '20261126-0900' -RetentionDays 30 | Out-Null
            Test-Path -Path $ownOld | Should -BeFalse
        }

        It 'does not take a file for an archive of this one when only the start of the name looks alike (no dash after the name)' {
            $hist = Join-Path -Path $TestDrive -ChildPath 'hist-alike'
            New-Item -Path $hist -ItemType Directory -Force | Out-Null
            $alike = New-Archive -Folder $hist -Name 'zebes-PROD-CONTENT2-20200101-0000.json' -DaysOld 60
            $src = Join-Path -Path $TestDrive -ChildPath 'zebes-PROD-CONTENT.json'
            Set-Content -Path $src -Value '{}'
            Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist -TimeStamp '20261126-0900' -RetentionDays 30 | Out-Null
            Test-Path -Path $alike | Should -BeTrue
        }

        It 'prunes nothing when the retention is 0, whatever the files' {
            $hist = Join-Path -Path $TestDrive -ChildPath 'hist-zero'
            New-Item -Path $hist -ItemType Directory -Force | Out-Null
            $ownOld = New-Archive -Folder $hist -Name 'zebes-PROD-CONTENT-20200101-0000.json' -DaysOld 400
            $src = Join-Path -Path $TestDrive -ChildPath 'zebes-PROD-CONTENT.json'
            Set-Content -Path $src -Value '{}'
            Backup-SPSWeatherJsonFile -Path $src -HistoryFolder $hist -TimeStamp '20261126-0900' | Out-Null
            Test-Path -Path $ownOld | Should -BeTrue
        }
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
