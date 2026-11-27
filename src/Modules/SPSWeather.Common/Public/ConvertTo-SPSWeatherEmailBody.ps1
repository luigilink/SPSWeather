function ConvertTo-SPSWeatherEmailBody {
    <#
        .SYNOPSIS
        Builds the short, Outlook-safe alert email body for one farm.

        .DESCRIPTION
        Returns an HTML string listing only the items that need attention (classified
        through the shared severity model), grouped by functional area, with a KPI strip
        and a CTA button to the farm dashboard. See the SPSWeather wiki (Dashboard page)
        for the full reference.

        Each area lists at most -MaxItemsPerArea items, failures first; the remainder is
        summarized in a "+ N more" row. Counters (KPI strip, intro, area header) always
        count every item.

        .PARAMETER MaxItemsPerArea
        Maximum number of items listed per area. Defaults to 10; 0 lists everything.

        .PARAMETER Language
        Display language of the email: a culture name such as 'fr-FR', 'auto' (UI culture of the
        process) or nothing for en-US. An unknown language falls back to en-US. Only the labels are
        translated; the values of the checks are shown as collected.

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
        $DashboardUrl = '',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [System.Int32]
        $MaxItemsPerArea = 10,

        [Parameter()]
        [System.String]
        $Language = 'en-US'
    )

    function _enc([object]$v) {
        if ($null -eq $v) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$v)
    }
    function _sev($row) { Get-SPSWeatherRowSeverity -Row $row }

    # Display strings of the language (a missing key falls back to English): _t formats, _th formats HTML, _count picks the plural
    $text = Get-SPSWeatherResource -Language $Language
    $english = Get-SPSWeatherResource -Language 'en-US'
    $ci = try { [System.Globalization.CultureInfo]::GetCultureInfo([string]$text.Culture) } catch { [System.Globalization.CultureInfo]::InvariantCulture }
    function _t([string]$key) {
        $s = $text[$key]
        if ($null -eq $s) { return $key }
        if ($args.Count -gt 0) {
            # A label must never stop the report: if the text cannot be formatted with these arguments,
            # fall back to the English text rather than throwing.
            try { return [string]::Format($ci, $s, [object[]]$args) }
            catch { return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $english[$key], [object[]]$args) }
        }
        return $s
    }
    function _th([string]$key) {
        $s = $text[$key]
        if ($null -eq $s) { $s = $key }
        try { return [string]::Format($ci, (_enc $s), [object[]]$args) }
        catch { return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, (_enc $english[$key]), [object[]]$args) }
    }
    function _count([int]$n, [string]$base) {
        $key = if ($n -gt 1) { "${base}Many" } else { "${base}One" }
        return (_t $key $n)
    }
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
    function _toDec([object]$v) {
        if ($null -eq $v) { return $null }
        $s = [string]$v
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        # Row values are stringified with the invariant culture, so parse them the same way.
        $d = [decimal]0
        if ([decimal]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
        return $null
    }
    function _pct([decimal]$p) {
        return (_t 'FreePercent' ([double]$p).ToString('0.##', $ci))
    }

    # section -> (icon, area id) and the order of the areas: shared with the consolidated email
    $areaMap = Get-SPSWeatherEmailAreaMap
    $areaOf = $areaMap.Map
    # section -> (label fields, detail fields) to compose a one-line alert
    $lineOf = @{
        SPUpgradeStatus         = @{ Label = @('server', 'Server'); Detail = @('UpgradeStatus', 'SPBuildVersion') }
        SPAPIHttpStatus         = @{ Label = @('Title'); Detail = @('Url', 'HTTPCode') }
        SPSSitesHttpStatus      = @{ Label = @('Url'); Detail = @('HTTPCode', 'Status') }
        SPSearchLastCrawlStatus = @{ Label = @('ContentSource'); Detail = @('CrawlState') }
        SPSearchCrawlLogs       = @{ Label = @('ContentSource'); Detail = @('Message', 'ErrorID') }
        SPTimerServiceStatus    = @{ Label = @('Server'); Detail = @('Status') }
        SPFailedTimerJobs       = @{ Label = @('Server', 'JobDefinitionTitle'); Detail = @('Status') }
        SPSolutionDeployment    = @{ Label = @('SolutionName'); Detail = @('LastOperationResult', 'DeploymentState') }
        SPHealthAnalyzer        = @{ Label = @('title'); Detail = @('category', 'severity') }
        AppFabricStatus         = @{ Label = @('Server'); Detail = @('CacheStatus', 'SPInstanceStatus') }
        USPAudienceStatus       = @{ Label = @('Server'); Detail = @('Status') }
        IISApplicationPoolStatus = @{ Label = @('Server', 'ApplicationPool'); Detail = @('Status') }
        IISWorkerProcessStatus  = @{ Label = @('Server'); Detail = @('ApplicationPool') }
        IISWebSiteCertStatus    = @{ Label = @('Server', 'WebSiteName'); Detail = @('Status', 'ExpirationDate') }
        SYSDiskUsageStatus      = @{ Label = @('Server', 'DriveLetter'); Detail = @('FreePercent', 'Status') }
        SYSEventViewerAppErrors = @{ Label = @('Server', 'Name'); Detail = @('Count') }
        SPSContentDBStatus      = @{ Label = @('DatabaseName', 'Name'); Detail = @('Upgrade', 'Status') }
        SQLInstanceStatus       = @{ Label = @('SqlServer'); Detail = @('Recommendation') }
        SQLDatabaseStatus       = @{ Label = @('Name'); Detail = @('Recommendation', 'State') }
        SQLDiskStatus           = @{ Label = @('SqlServer', 'Volume'); Detail = @('FreePercent') }
        SQLAvailabilityStatus   = @{ Label = @('Name', 'SqlServer'); Detail = @('Detail') }
        SQLAliasStatus          = @{ Label = @('Name'); Detail = @('Note') }
        SPSLimitStatus          = @{ Label = @('Limit', 'Object'); Detail = @('Recommendation') }
    }
    $areaOrder = $areaMap.Order

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
            if ($sk -eq 'SYSDiskUsageStatus') {
                $statusText = _first $row @('Status')
                $percent = _toDec (_first $row @('FreePercent'))
                if ($null -eq $percent) {
                    $free = _toDec (_first $row @('FreeSpace'))
                    $size = _toDec (_first $row @('Size'))
                    if (($null -ne $free) -and ($null -ne $size) -and ($size -gt 0)) {
                        $percent = [math]::Round(($free / $size) * 100, 2)
                    }
                }
                if ($null -ne $percent) {
                    $pctText = _pct $percent
                    $detail = if ($statusText) { "$pctText · $statusText" } else { $pctText }
                }
                elseif ($statusText) {
                    $detail = $statusText
                }
            }
            if ($sk -eq 'SQLDiskStatus') {
                $percent = _toDec (_first $row @('FreePercent'))
                if ($null -ne $percent) { $detail = _pct $percent }
            }
            [void]$groups[$area].Items.Add([PSCustomObject]@{ Sev = $sev; Label = $label; Detail = $detail })
        }
    }

    if ($null -ne $Summary) { $kOk = [int]$Summary.Ok }
    else { $kOk = $totalOk }
    $attention = ($groups.Keys | ForEach-Object { $groups[$_].Items.Count } | Measure-Object -Sum).Sum
    if (-not $attention) { $attention = 0 }

    if ($totalFail -gt 5) { $wx = '&#9928;&#65039;'; $wxLabel = _enc (_t 'WeatherStormy') }
    elseif ($totalFail -gt 0) { $wx = '&#9925;'; $wxLabel = _enc (_t 'WeatherCloudy') }
    elseif ($totalWarn -gt 0) { $wx = '&#127780;&#65039;'; $wxLabel = _enc (_t 'WeatherFair') }
    else { $wx = '&#9728;&#65039;'; $wxLabel = _enc (_t 'WeatherSunny') }

    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
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
        [void]$groupsHtml.Append("<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`" style=`"margin-bottom:12px;border:1px solid $bd;border-radius:10px;overflow:hidden;`"><tr><td style=`"background:$hb;padding:8px 14px;font-size:12px;font-weight:700;color:$hc;`">$($g.Icon) $(_enc (_t "Area_$area")) &nbsp;&middot;&nbsp; $(_enc (_count $n 'ItemCount'))</td></tr>")
        # Worst first (failures, then warnings; order otherwise preserved), then cap the list.
        $rows = @(@($g.Items | Where-Object { $_.Sev -eq 'fail' }) + @($g.Items | Where-Object { $_.Sev -ne 'fail' }))
        $hidden = @()
        if ($MaxItemsPerArea -gt 0 -and $rows.Count -gt $MaxItemsPerArea) {
            $hidden = @($rows[$MaxItemsPerArea..($rows.Count - 1)])
            $rows = @($rows[0..($MaxItemsPerArea - 1)])
        }
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $it = $rows[$i]
            $bb = if (($i -lt $rows.Count - 1) -or $hidden.Count -gt 0) { 'border-bottom:1px dashed #eee;' } else { '' }
            $det = if ($it.Detail) { " <span style=`"color:#6b7280;font-size:12px;`">&mdash; $(_enc $it.Detail)</span>" } else { '' }
            [void]$groupsHtml.Append("<tr><td style=`"padding:10px 14px;font-size:13px;color:#1b2733;$bb`"><b>$(_enc $it.Label)</b>$det</td></tr>")
        }
        if ($hidden.Count -gt 0) {
            $hf = @($hidden | Where-Object { $_.Sev -eq 'fail' }).Count
            $hw = $hidden.Count - $hf
            $parts = @()
            if ($hf -gt 0) { $parts += _count $hf 'Failure' }
            if ($hw -gt 0) { $parts += _count $hw 'Warning' }
            [void]$groupsHtml.Append("<tr><td style=`"padding:10px 14px;font-size:12px;color:#6b7280;font-style:italic;`">$(_enc (_t 'MoreItems' $hidden.Count ($parts -join ', '))) &mdash; $(_enc (_t 'MoreSeeDashboard'))</td></tr>")
        }
        [void]$groupsHtml.Append('</table>')
    }
    if ($attention -eq 0) {
        [void]$groupsHtml.Append("<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`" style=`"border:1px solid #cfe9d9;border-radius:10px;`"><tr><td style=`"padding:14px;font-size:13px;color:#2c6b48;background:#e6f7ee;border-radius:10px;`"><b>$(_enc (_t 'AllClearTitle'))</b> $(_enc (_t 'AllClearText'))</td></tr></table>")
    }

    $ctaHtml = ''
    if ($DashboardUrl) {
        $encUrl = _enc $DashboardUrl
        $ctaHtml = @"
  <tr><td align="center" style="padding:20px 26px 24px;">
    <table role="presentation" cellpadding="0" cellspacing="0"><tr><td align="center" style="background:#2b5797;border-radius:10px;">
      <a href="$encUrl" style="display:inline-block;padding:13px 30px;color:#ffffff;font-size:14px;font-weight:700;text-decoration:none;">$(_enc (_t 'OpenDashboard')) &rarr;</a>
    </td></tr></table>
    <div style="margin-top:10px;font-size:11px;color:#9aa4b2;">$encUrl</div>
  </td></tr>
"@
    }

    $intro = if ($attention -gt 0) { _th 'IntroAttention' "<b>$(_enc (_count $attention 'ItemCount'))</b>" "<b>$envText</b>" } else { _th 'IntroClear' "<b>$envText</b>" }
    $farmText = if ($Farm) { "$(_enc (_t 'FarmLabel')) $(_enc $Farm) &middot; " } else { '' }

    $body = @"
<!DOCTYPE html>
<html lang="$(_enc (_t 'HtmlLang'))" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
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
      <td align="right" style="color:#ffffff;"><div style="font-size:11px;color:#cdd8ea;text-transform:uppercase;letter-spacing:.06em;">$(_enc (_t 'WeatherLabel'))</div><div style="font-size:18px;font-weight:800;">$wxLabel</div></td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:16px 26px 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td width="33%" align="center" style="padding:10px;background:#fdeaea;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#e24a4a;line-height:1;">$totalFail</div><div style="font-size:11px;color:#8a4a4a;text-transform:uppercase;letter-spacing:.05em;">$(_enc (_t 'KpiFailures'))</div></td>
      <td width="8"></td>
      <td width="33%" align="center" style="padding:10px;background:#fdf1e4;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#e8923a;line-height:1;">$totalWarn</div><div style="font-size:11px;color:#8a6530;text-transform:uppercase;letter-spacing:.05em;">$(_enc (_t 'KpiWarnings'))</div></td>
      <td width="8"></td>
      <td width="33%" align="center" style="padding:10px;background:#e6f7ee;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#2fae66;line-height:1;">$kOk</div><div style="font-size:11px;color:#2c6b48;text-transform:uppercase;letter-spacing:.05em;">$(_enc (_t 'KpiChecksOk'))</div></td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:14px 26px 2px;font-size:14px;color:#1b2733;">$intro</td></tr>
  <tr><td style="padding:10px 26px 4px;">$($groupsHtml.ToString())</td></tr>
$ctaHtml
  <tr><td style="background:#f6f8fb;border-top:1px solid #e3e8ef;padding:14px 26px;font-size:11px;color:#9aa4b2;">SPSWeather $(_enc $Version) &middot; $(_enc (_t 'FooterExecutedBy')) $(_enc $ExecutedBy) &middot; $(_enc (_t 'FooterRun')) $(_enc $Duration) &middot; $(_enc (_t 'CountsSummary' $kOk $totalWarn $totalFail)).</td></tr>
</table>
</td></tr></table>
</body></html>
"@
    return $body
}
