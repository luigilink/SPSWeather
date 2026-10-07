function ConvertTo-SPSWeatherEmailBody {
    <#
        .SYNOPSIS
        Builds the short, Outlook-safe alert email body for one farm.

        .DESCRIPTION
        Returns an HTML string listing only the items that need attention (classified
        through the shared severity model), grouped by functional area, with a KPI strip
        and a CTA button to the farm dashboard. See the SPSWeather wiki (Dashboard page)
        for the full reference.

        .EXAMPLE
        ConvertTo-SPSWeatherEmailBody -InputObject $farmReport -Summary $res.Summary `
            -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -DashboardUrl $url
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]
        $InputObject,

        [Parameter()]
        [PSCustomObject]
        $Summary,

        [Parameter()]
        [System.String]
        $Farm = '',

        [Parameter()]
        [System.String]
        $Application = '',

        [Parameter()]
        [System.String]
        $Environment = '',

        [Parameter()]
        [System.String]
        $Version = '',

        [Parameter()]
        [System.String]
        $ExecutedBy = '',

        [Parameter()]
        [System.String]
        $Duration = '',

        [Parameter()]
        [System.String]
        $DashboardUrl = ''
    )

    function _enc([object]$v) {
        if ($null -eq $v) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$v)
    }
    function _sev($row) { Get-SPSWeatherRowSeverity -Row $row }
    # First non-empty property value from a row, among candidate names.
    function _first($row, [string[]]$names) {
        foreach ($n in $names) {
            if ($row.PSObject.Properties.Name -contains $n) {
                $v = "$($row.$n)"
                if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
            }
        }
        return ''
    }

    # section -> area display (icon + title) for grouping alerts
    $areaOf = @{
        SPUpgradeStatus = @('&#127970;', 'Farm & Upgrade'); SPAPIHttpStatus = @('&#127760;', 'Trust Farm (REST)'); SPSSitesHttpStatus = @('&#127760;', 'Trust Farm (REST)')
        SPSearchLastCrawlStatus = @('&#128269;', 'Search'); SPSearchCrawlLogs = @('&#128269;', 'Search'); SPSSearchEntTopology = @('&#128269;', 'Search')
        AppFabricStatus = @('&#9889;', 'Distributed Cache'); SPFailedTimerJobs = @('&#9201;', 'Timer Jobs'); SPSolutionDeployment = @('&#9201;', 'Solutions'); USPAudienceStatus = @('&#9201;', 'User Profiles')
        SPHealthAnalyzer = @('&#129657;', 'Health Analyzer'); IISApplicationPoolStatus = @('&#128421;', 'IIS'); IISWorkerProcessStatus = @('&#128421;', 'IIS'); IISWebSiteCertStatus = @('&#128421;', 'IIS')
        SYSDiskUsageStatus = @('&#129513;', 'System'); SYSLastRebootStatus = @('&#129513;', 'System'); SYSEventViewerAppErrors = @('&#129513;', 'System')
        SPSContentDBStatus = @('&#128451;', 'SQL Server'); SQLInstanceStatus = @('&#128451;', 'SQL Server'); SQLDatabaseStatus = @('&#128451;', 'SQL Server'); SQLDiskStatus = @('&#128451;', 'SQL Server'); SQLAvailabilityStatus = @('&#128451;', 'SQL Server'); SQLAliasStatus = @('&#128451;', 'SQL Server')
    }
    # section -> (label fields, detail fields) to compose a one-line alert
    $lineOf = @{
        SPUpgradeStatus         = @{ Label = @('server', 'Server'); Detail = @('UpgradeStatus', 'SPBuildVersion') }
        SPAPIHttpStatus         = @{ Label = @('Title'); Detail = @('Url', 'HTTPCode') }
        SPSSitesHttpStatus      = @{ Label = @('Url'); Detail = @('HTTPCode', 'Status') }
        SPSearchLastCrawlStatus = @{ Label = @('ContentSource'); Detail = @('CrawlState') }
        SPSearchCrawlLogs       = @{ Label = @('ContentSource'); Detail = @('Message', 'ErrorID') }
        SPFailedTimerJobs       = @{ Label = @('JobDefinitionTitle'); Detail = @('Status') }
        SPSolutionDeployment    = @{ Label = @('SolutionName'); Detail = @('LastOperationResult', 'DeploymentState') }
        SPHealthAnalyzer        = @{ Label = @('title'); Detail = @('category', 'severity') }
        AppFabricStatus         = @{ Label = @('Server'); Detail = @('CacheStatus', 'SPInstanceStatus') }
        USPAudienceStatus       = @{ Label = @('Server'); Detail = @('Status') }
        IISApplicationPoolStatus = @{ Label = @('Server', 'ApplicationPool'); Detail = @('Status') }
        IISWorkerProcessStatus  = @{ Label = @('Server'); Detail = @('ApplicationPool') }
        IISWebSiteCertStatus    = @{ Label = @('Server', 'WebSiteName'); Detail = @('Status', 'ExpirationDate') }
        SYSDiskUsageStatus      = @{ Label = @('Server', 'DriveLetter'); Detail = @('Status') }
        SYSEventViewerAppErrors = @{ Label = @('Server', 'Name'); Detail = @('Count') }
        SPSContentDBStatus      = @{ Label = @('DatabaseName', 'Name'); Detail = @('Upgrade', 'Status') }
        SQLInstanceStatus       = @{ Label = @('SqlServer'); Detail = @('Recommendation') }
        SQLDatabaseStatus       = @{ Label = @('Name'); Detail = @('Recommendation', 'State') }
        SQLDiskStatus           = @{ Label = @('SqlServer', 'Volume'); Detail = @('FreePercent') }
        SQLAvailabilityStatus   = @{ Label = @('Name', 'SqlServer'); Detail = @('Detail') }
        SQLAliasStatus          = @{ Label = @('Name'); Detail = @('Note') }
    }
    $areaOrder = @('Farm & Upgrade', 'Trust Farm (REST)', 'Search', 'Distributed Cache', 'Timer Jobs', 'Solutions', 'User Profiles', 'Health Analyzer', 'IIS', 'System', 'SQL Server')

    # Collect alerts (non-ok rows), grouped by area.
    $groups = [ordered]@{}
    $totalFail = 0; $totalWarn = 0; $totalOk = 0
    foreach ($prop in $InputObject.PSObject.Properties) {
        $sk = $prop.Name
        foreach ($row in @($prop.Value | Where-Object { $null -ne $_ })) {
            $sev = _sev $row
            if ($sev -eq 'ok') {
                # Count only real checks toward OK (exclude pure info-only rows), matching the
                # dashboard donut and the report Summary.
                $n = $row.PSObject.Properties.Name
                if (($n -contains 'IsInfo') -or ($n -contains 'severity')) { $totalOk++ }
                continue
            }
            if ($sev -eq 'fail') { $totalFail++ } else { $totalWarn++ }
            if (-not $areaOf.ContainsKey($sk)) { continue }
            $icon = $areaOf[$sk][0]; $area = $areaOf[$sk][1]
            if (-not $groups.Contains($area)) { $groups[$area] = [PSCustomObject]@{ Icon = $icon; Items = New-Object System.Collections.ArrayList } }
            $cfg = $lineOf[$sk]
            if ($cfg) {
                $label = (@($cfg.Label | ForEach-Object { _first $row @($_) }) | Where-Object { $_ }) -join ' / '
                $detail = (@($cfg.Detail | ForEach-Object { _first $row @($_) }) | Where-Object { $_ }) -join ' · '
            }
            else {
                $label = _first $row @('Name', 'Title', 'Server', 'DatabaseName')
                $detail = _first $row @('Status', 'Recommendation', 'Message')
            }
            if (-not $label) { $label = $sk }
            [void]$groups[$area].Items.Add([PSCustomObject]@{ Sev = $sev; Label = $label; Detail = $detail })
        }
    }

    if ($null -ne $Summary) { $kOk = [int]$Summary.Ok }
    else { $kOk = $totalOk }
    $attention = ($groups.Keys | ForEach-Object { $groups[$_].Items.Count } | Measure-Object -Sum).Sum
    if (-not $attention) { $attention = 0 }

    if ($totalFail -gt 5) { $wx = '&#9928;&#65039;'; $wxLabel = 'Stormy' }
    elseif ($totalFail -gt 0) { $wx = '&#9925;'; $wxLabel = 'Cloudy' }
    elseif ($totalWarn -gt 0) { $wx = '&#127780;&#65039;'; $wxLabel = 'Fair' }
    else { $wx = '&#9728;&#65039;'; $wxLabel = 'Sunny' }

    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $envText = _enc ((@($Application, $Environment) | Where-Object { $_ }) -join ' / ')

    # Build alert groups HTML.
    $groupsHtml = New-Object -TypeName System.Text.StringBuilder
    foreach ($area in $areaOrder) {
        if (-not $groups.Contains($area)) { continue }
        $g = $groups[$area]
        $hasFail = @($g.Items | Where-Object { $_.Sev -eq 'fail' }).Count -gt 0
        $hb = if ($hasFail) { '#fdeaea' } else { '#fdf1e4' }
        $hc = if ($hasFail) { '#b93b3b' } else { '#a86a24' }
        $bd = if ($hasFail) { '#f1d6d6' } else { '#f4e2cf' }
        $n = $g.Items.Count
        [void]$groupsHtml.Append("<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`" style=`"margin-bottom:12px;border:1px solid $bd;border-radius:10px;overflow:hidden;`"><tr><td style=`"background:$hb;padding:8px 14px;font-size:12px;font-weight:700;color:$hc;`">$($g.Icon) $(_enc $area) &nbsp;&middot;&nbsp; $n item$(if ($n -gt 1) { 's' })</td></tr>")
        $rows = @($g.Items)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $it = $rows[$i]
            $bb = if ($i -lt $rows.Count - 1) { 'border-bottom:1px dashed #eee;' } else { '' }
            $det = if ($it.Detail) { " <span style=`"color:#6b7280;font-size:12px;`">&mdash; $(_enc $it.Detail)</span>" } else { '' }
            [void]$groupsHtml.Append("<tr><td style=`"padding:10px 14px;font-size:13px;color:#1b2733;$bb`"><b>$(_enc $it.Label)</b>$det</td></tr>")
        }
        [void]$groupsHtml.Append('</table>')
    }
    if ($attention -eq 0) {
        [void]$groupsHtml.Append("<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`" style=`"border:1px solid #cfe9d9;border-radius:10px;`"><tr><td style=`"padding:14px;font-size:13px;color:#2c6b48;background:#e6f7ee;border-radius:10px;`"><b>All clear.</b> No item needs attention on this farm.</td></tr></table>")
    }

    $ctaHtml = ''
    if ($DashboardUrl) {
        $encUrl = _enc $DashboardUrl
        $ctaHtml = @"
  <tr><td align="center" style="padding:20px 26px 24px;">
    <table role="presentation" cellpadding="0" cellspacing="0"><tr><td align="center" style="background:#2b5797;border-radius:10px;">
      <a href="$encUrl" style="display:inline-block;padding:13px 30px;color:#ffffff;font-size:14px;font-weight:700;text-decoration:none;">Open full dashboard &rarr;</a>
    </td></tr></table>
    <div style="margin-top:10px;font-size:11px;color:#9aa4b2;">$encUrl</div>
  </td></tr>
"@
    }

    $intro = if ($attention -gt 0) { "<b>$attention item$(if ($attention -gt 1) { 's' })</b> need your attention on <b>$envText</b>. Full detail is in the dashboard." } else { "No item needs attention on <b>$envText</b>." }
    $farmText = if ($Farm) { "Farm $(_enc $Farm) &middot; " } else { '' }

    $body = @"
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<title>SPSWeather</title>
<!--[if mso]><xml><o:OfficeDocumentSettings><o:AllowPNG/><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml><![endif]-->
</head>
<body style="margin:0;padding:0;background:#eef2f7;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eef2f7;"><tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:600px;background:#ffffff;border-radius:14px;overflow:hidden;font-family:'Segoe UI',Arial,sans-serif;box-shadow:0 8px 24px rgba(16,34,54,.10);">
  <tr><td style="background:#2b5797;background:linear-gradient(135deg,#2b5797,#1e3d6b);padding:22px 26px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td style="font-size:34px;line-height:1;width:46px;">$wx</td>
      <td style="color:#ffffff;"><div style="font-size:19px;font-weight:700;">SPSWeather &mdash; $envText</div><div style="font-size:12px;color:#cdd8ea;margin-top:3px;">$farmText$generated</div></td>
      <td align="right" style="color:#ffffff;"><div style="font-size:11px;color:#cdd8ea;text-transform:uppercase;letter-spacing:.06em;">Weather</div><div style="font-size:18px;font-weight:800;">$wxLabel</div></td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:16px 26px 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td width="33%" align="center" style="padding:10px;background:#fdeaea;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#e24a4a;line-height:1;">$totalFail</div><div style="font-size:11px;color:#8a4a4a;text-transform:uppercase;letter-spacing:.05em;">Failures</div></td>
      <td width="8"></td>
      <td width="33%" align="center" style="padding:10px;background:#fdf1e4;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#e8923a;line-height:1;">$totalWarn</div><div style="font-size:11px;color:#8a6530;text-transform:uppercase;letter-spacing:.05em;">Warnings</div></td>
      <td width="8"></td>
      <td width="33%" align="center" style="padding:10px;background:#e6f7ee;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#2fae66;line-height:1;">$kOk</div><div style="font-size:11px;color:#2c6b48;text-transform:uppercase;letter-spacing:.05em;">Checks OK</div></td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:14px 26px 2px;font-size:14px;color:#1b2733;">$intro</td></tr>
  <tr><td style="padding:10px 26px 4px;">$($groupsHtml.ToString())</td></tr>
$ctaHtml
  <tr><td style="background:#f6f8fb;border-top:1px solid #e3e8ef;padding:14px 26px;font-size:11px;color:#9aa4b2;">SPSWeather $(_enc $Version) &middot; executed by $(_enc $ExecutedBy) &middot; run $(_enc $Duration) &middot; $kOk OK / $totalWarn warn / $totalFail fail.</td></tr>
</table>
</td></tr></table>
</body></html>
"@
    return $body
}
