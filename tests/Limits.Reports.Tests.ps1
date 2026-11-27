# Tests of the limit rows (SPSLimitStatus) in what a run produces: the severity model, the dashboard, the short alert email,
# the identity that follows an item from one run to the next, the cockpit dataset and the texts in both languages.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSWeather.Common/SPSWeather.Common.psd1') -Force

    function script:New-LimitRow {
        param([string]$Limit = 'ContentDatabaseSize', [string]$Object = 'WSS_Content_A', [bool]$IsInfo = $true, [string]$Recommendation = '', [double]$Value = 160)
        [PSCustomObject]@{ Farm = 'CONTENT'; Limit = $Limit; Object = $Object; Value = $Value; Unit = 'GB'; Warning = 150; Failure = 200; Status = $(if ($IsInfo) { 'Warning' } else { 'Failure' }); Recommendation = $Recommendation; Note = ''; IsInfo = $IsInfo }
    }
    function script:Get-DashboardHtml {
        param($Report, [string]$Language = 'en-US')
        $file = Join-Path -Path $TestDrive -ChildPath ('dash-' + [guid]::NewGuid().ToString('N') + '.html')
        [void](Export-SPSWeatherReport -InputObject $Report -OutputFile $file -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Version '3.6.0' -ExecutedBy 'DOM\jc' -Duration '00:01:00' -History @() -Language $Language)
        [System.IO.File]::ReadAllText($file)
    }
    function script:New-ReportWith {
        param($Rows)
        $report = [PSCustomObject]@{}
        $report | Add-Member -MemberType NoteProperty -Name SPAPIHttpStatus -Value @([PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'https://sp'; HTTPCode = 200; Status = 'OK'; IsInfo = $true })
        if ($null -ne $Rows) { $report | Add-Member -MemberType NoteProperty -Name SPSLimitStatus -Value @($Rows) }
        $report
    }
}

AfterAll {
    Remove-Module -Name SPSWeather.Common -Force -ErrorAction SilentlyContinue
}

Describe 'A limit row in the severity model' {
    It 'is a failure when IsInfo is false, a warning when it is true with a recommendation, and nothing otherwise' {
        InModuleScope SPSWeather.Common {
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $false; Recommendation = 'x' }) | Should -Be 'fail'
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true; Recommendation = 'x' }) | Should -Be 'warn'
            Get-SPSWeatherRowSeverity -Row ([PSCustomObject]@{ IsInfo = $true; Recommendation = '' }) | Should -Be 'ok'
        }
    }

    It 'counts in the summary of the report like any other check, and a farm with no row is the report of before' {
        $sections = [ordered]@{
            SPAPIHttpStatus = @([PSCustomObject]@{ Farm = 'CONTENT'; Title = 'Root'; Url = 'u'; Status = 'OK'; IsInfo = $true })
            SPSLimitStatus  = @((New-LimitRow -IsInfo $true -Recommendation 'plan a second database'), (New-LimitRow -Object 'B' -IsInfo $false -Recommendation 'split now'))
        }
        $with = ConvertTo-SPSWeatherReport -Section $sections
        $with.Summary.Warn | Should -Be 1
        $with.Summary.Fail | Should -Be 1
        $with.Summary.Ok | Should -Be 1
        $with.IsAlert | Should -BeTrue
        $sections.SPSLimitStatus = @()
        $none = ConvertTo-SPSWeatherReport -Section $sections
        $none.Summary.Warn | Should -Be 0
        $none.Summary.Fail | Should -Be 0
        $none.Summary.Ok | Should -Be 1
        $none.IsAlert | Should -BeFalse
    }
}

Describe 'Dashboard with limit rows' {
    It 'shows the area and the section with their names, and the rows, when a limit is reached' {
        $html = Get-DashboardHtml -Report (New-ReportWith -Rows @(New-LimitRow -IsInfo $false -Recommendation 'Move sites to another content database'))
        $html | Should -Match 'Capacity &amp; limits'
        $html | Should -Match 'Supported limits'
        $html | Should -Match 'WSS_Content_A'
        $html | Should -Match 'Move sites to another content database'
    }

    It 'gives the area a link to a section that exists on the page' {
        $html = Get-DashboardHtml -Report (New-ReportWith -Rows @(New-LimitRow -IsInfo $false -Recommendation 'x'))
        $links = @([regex]::Matches($html, '<div class="foot"><a href="#(d-[A-Za-z0-9_-]+)">') | ForEach-Object { $_.Groups[1].Value })
        $sections = @([regex]::Matches($html, '<details class="sec" id="(d-[A-Za-z0-9_-]+)"') | ForEach-Object { $_.Groups[1].Value })
        $links | Should -Contain 'd-SPSLimitStatus'
        $sections | Should -Contain 'd-SPSLimitStatus'
    }

    It 'speaks French when asked, and keeps the values untouched' {
        $html = Get-DashboardHtml -Report (New-ReportWith -Rows @(New-LimitRow -IsInfo $false -Recommendation 'x')) -Language 'fr-FR'
        $html | Should -Match 'Capacit(é|&#233;) et limites'
        $html | Should -Match 'Limites support(é|&#233;)es'
        $html | Should -Match 'WSS_Content_A'
        $html | Should -Not -Match 'Supported limits'
    }

    It 'adds nothing for a farm below every threshold: no area card, no section' {
        $quiet = Get-DashboardHtml -Report (New-ReportWith -Rows @())
        $absent = Get-DashboardHtml -Report (New-ReportWith -Rows $null)
        $quiet | Should -Not -Match 'Capacity &amp; limits'
        $quiet | Should -Not -Match 'Supported limits'
        $absent | Should -Not -Match 'Capacity &amp; limits'
        $quiet.Length | Should -Be $absent.Length
    }

    It 'counts a failing limit in the donut and a warning as a warning, never as healthy' {
        $warn = Get-DashboardHtml -Report (New-ReportWith -Rows @(New-LimitRow -IsInfo $true -Recommendation 'plan'))
        $fail = Get-DashboardHtml -Report (New-ReportWith -Rows @(New-LimitRow -IsInfo $false -Recommendation 'act'))
        $healthy = Get-DashboardHtml -Report (New-ReportWith -Rows @())
        $warn | Should -Not -Be $healthy
        $fail | Should -Not -Be $warn
    }
}

Describe 'Short alert email with limit rows' {
    It 'lists the limit among the alerts, with its object and its recommendation, under the area of the limits' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-ReportWith -Rows @(New-LimitRow -IsInfo $false -Recommendation 'Move sites to another content database')) -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD'
        $html | Should -Match 'Capacity &amp; limits'
        $html | Should -Match 'ContentDatabaseSize'
        $html | Should -Match 'WSS_Content_A'
        $html | Should -Match 'Move sites to another content database'
    }

    It 'says nothing about the limits when there is no row' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-ReportWith -Rows @()) -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD'
        $html | Should -Not -Match 'Capacity &amp; limits'
        $html | Should -Not -Match 'ContentDatabaseSize'
    }

    It 'translates the area name in French' {
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-ReportWith -Rows @(New-LimitRow -IsInfo $true -Recommendation 'plan')) -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Language 'fr-FR'
        $html | Should -Match 'Capacit(é|&eacute;|&#233;|&#xE9;) et limites'
    }

    It 'puts the failures of the limits before the warnings of the same area, so that a cap never hides a failure' {
        $rows = @((New-LimitRow -Object 'W1' -IsInfo $true -Recommendation 'plan'), (New-LimitRow -Object 'F1' -IsInfo $false -Recommendation 'act'))
        $html = ConvertTo-SPSWeatherEmailBody -InputObject (New-ReportWith -Rows $rows) -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD'
        $html.IndexOf('F1') | Should -BeLessThan $html.IndexOf('W1')
    }
}

Describe 'Identity of a limit row from one run to the next' {
    BeforeAll {
        function script:Get-Identity {
            param($Row)
            InModuleScope SPSWeather.Common -Parameters @{ R = $Row } { param($R) Get-SPSWeatherItemIdentity -Section 'SPSLimitStatus' -Row $R }
        }
    }

    It 'is the limit and the object, whatever the value, so that a growing database stays the same item' {
        $a = Get-Identity -Row (New-LimitRow -Value 160)
        $b = Get-Identity -Row (New-LimitRow -Value 190 -IsInfo $false -Recommendation 'act')
        $a.Id | Should -Be $b.Id
        $a.Id | Should -Be 'SPSLimitStatus|contentdatabasesize|wss_content_a'
        $a.Name | Should -Be 'ContentDatabaseSize / WSS_Content_A'
    }

    It 'tells two objects of the same limit apart, and two limits of the same object' {
        (Get-Identity -Row (New-LimitRow -Object 'A')).Id | Should -Not -Be (Get-Identity -Row (New-LimitRow -Object 'B')).Id
        (Get-Identity -Row (New-LimitRow -Limit 'SiteCountPerDatabase')).Id | Should -Not -Be (Get-Identity -Row (New-LimitRow -Limit 'ContentDatabaseSize')).Id
    }
}

Describe 'Cockpit dataset with limit rows' {
    BeforeAll {
        function script:Get-LimitData {
            param($Snapshot)
            $res = Join-Path -Path $TestDrive -ChildPath ('res-' + [guid]::NewGuid().ToString('N'))
            New-Item -Path $res -ItemType Directory -Force | Out-Null
            $now = [datetime]'2026-11-26T09:00:00'
            $file = Join-Path -Path $res -ChildPath 'zebes-PROD-CONTENT.json'
            [System.IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Snapshot -Depth 6))
            (Get-Item -LiteralPath $file).LastWriteTime = $now.AddHours(-1)
            InModuleScope SPSWeather.Common -Parameters @{ R = $res; N = $now } {
                param($R, $N)
                Get-SPSWeatherCockpitData -ResultsFolder $R -Application 'zebes' -Environment 'PROD' -FarmName @('CONTENT') -RetentionDays 30 -Now $N -MaxItemsPerFarm 300 -MaxSnapshotsPerFarm 400 -WarningAction SilentlyContinue
            }
        }
    }

    It 'lists a limit that is reached as an item to watch, with its name, its section and its severity' {
        $data = Get-LimitData -Snapshot (New-ReportWith -Rows @((New-LimitRow -IsInfo $false -Recommendation 'Move sites to another content database'), (New-LimitRow -Object 'B' -IsInfo $true -Recommendation 'plan')))
        $items = @(@($data.farms)[0].attention | Where-Object { $_.section -eq 'SPSLimitStatus' })
        $items.Count | Should -Be 2
        ($items | Where-Object { $_.name -eq 'ContentDatabaseSize / WSS_Content_A' }).severity | Should -Be 'fail'
        ($items | Where-Object { $_.name -eq 'ContentDatabaseSize / B' }).severity | Should -Be 'warn'
        ($items | Where-Object { $_.name -eq 'ContentDatabaseSize / WSS_Content_A' }).cause | Should -Match 'Move sites'
    }

    It 'lists nothing when the farm is below every threshold' {
        $data = Get-LimitData -Snapshot (New-ReportWith -Rows @())
        @(@($data.farms)[0].attention | Where-Object { $_.section -eq 'SPSLimitStatus' }).Count | Should -Be 0
    }
}

Describe 'Texts of the limits' {
    It 'exist in both languages, and the French ones are not the English ones' {
        InModuleScope SPSWeather.Common {
            foreach ($key in 'Area_Limits', 'Section_SPSLimitStatus') {
                $en = (Get-SPSWeatherResource -Language 'en-US')[$key]
                $fr = (Get-SPSWeatherResource -Language 'fr-FR')[$key]
                $en | Should -Not -BeNullOrEmpty
                $fr | Should -Not -BeNullOrEmpty
                $fr | Should -Not -Be $en
            }
        }
    }
}
