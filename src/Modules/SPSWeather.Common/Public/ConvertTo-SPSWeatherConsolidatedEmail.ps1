function ConvertTo-SPSWeatherConsolidatedEmail {
    <#
        .SYNOPSIS
        Builds one Outlook-safe email that summarizes every farm of an environment.

        .DESCRIPTION
        Returns an object with the Subject, the Priority, the worst Alert level and the HTML Body
        of a single email for all the farms: a header with the weather of the worst farm, the totals
        of checks (failures, warnings, OK) across the farms, then one card per farm, worst first.
        A card shows the status of the farm, its health bar, its counts, the areas that need the
        most attention and a button to the dashboard of the farm. A farm that could not be reached
        gets a grey card instead of disappearing from the report.

        The subject keeps the English severity tag of the worst farm ([ALERT], [WARN] or [OK]),
        like the per-farm email, so that existing inbox rules keep working. An unreachable farm
        counts as ALERT. The priority is High when a farm is in alert or unreachable.

        Only the labels are translated; the values of the checks are shown as collected. See the
        SPSWeather wiki (Dashboard page) for the full reference.

        .PARAMETER FarmResult
        One object per farm, in the order of the configuration. Properties: Name, Server,
        Reachable (default $true), Report (the farm report object), Summary (Ok, Warn, Fail as
        returned by ConvertTo-SPSWeatherReport; computed from the report when absent) and
        DashboardUrl (empty = no button). A farm with Reachable = $false has no report.

        .PARAMETER MaxAttentionPerFarm
        Maximum number of areas listed on a farm card, the ones with the most failures first; the
        rest is summarized in a "+ N more" line. Defaults to 3; 0 lists every area.

        .PARAMETER Language
        Display language: a culture name such as 'fr-FR', 'auto' (UI culture of the process) or
        nothing for en-US. An unknown language falls back to en-US.

        .PARAMETER CockpitUrl
        Address of the cockpit page of the environment. When it is not empty, a button to it is shown under the totals;
        empty (the default) leaves the email exactly as it was.

        .EXAMPLE
        $mail = ConvertTo-SPSWeatherConsolidatedEmail -FarmResult $farmResults `
            -Application 'zebes' -Environment 'PROD' -Language 'fr-FR'
        Send-MailMessage -Subject $mail.Subject -Body $mail.Body -BodyAsHtml -Priority $mail.Priority ...
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]]
        $FarmResult,

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
        [ValidateRange(0, [int]::MaxValue)]
        [System.Int32]
        $MaxAttentionPerFarm = 3,

        [Parameter()]
        [System.String]
        $Language = 'en-US',

        [Parameter()]
        [System.String]
        $CockpitUrl = ''
    )

    function _enc([object]$v) {
        if ($null -eq $v) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$v)
    }

    # Display strings of the language (a missing key or a bad format falls back to English)
    $text = Get-SPSWeatherResource -Language $Language
    $english = Get-SPSWeatherResource -Language 'en-US'
    $ci = try { [System.Globalization.CultureInfo]::GetCultureInfo([string]$text.Culture) } catch { [System.Globalization.CultureInfo]::InvariantCulture }
    function _t([string]$key) {
        $s = $text[$key]
        if ($null -eq $s) { return $key }
        if ($args.Count -gt 0) {
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
        # Any argument after the base name is a further placeholder of the text.
        return (_t $key $n @args)
    }
    function _has($o, [string]$name) { return ($null -ne $o) -and ($o.PSObject.Properties.Name -contains $name) }
    function _text($o, [string]$name) { if (_has $o $name) { return "$($o.$name)" } else { return '' } }

    $areaMap = Get-SPSWeatherEmailAreaMap
    $areaIndex = @{}
    for ($i = 0; $i -lt $areaMap.Order.Count; $i++) { $areaIndex[$areaMap.Order[$i]] = $i }

    # The look of each status: accent, tint, dark text, border.
    $look = @{
        ALERT = @{ Accent = '#e24a4a'; Tint = '#fdeaea'; Dark = '#b93b3b'; Border = '#f1d6d6'; Key = 'FarmStatusAlert' }
        WARN  = @{ Accent = '#e8923a'; Tint = '#fdf1e4'; Dark = '#8a6530'; Border = '#f3e0c8'; Key = 'FarmStatusWarn' }
        OK    = @{ Accent = '#2fae66'; Tint = '#e6f7ee'; Dark = '#2c6b48'; Border = '#cfe9da'; Key = 'FarmStatusOk' }
        DOWN  = @{ Accent = '#8a94a3'; Tint = '#eef0f3'; Dark = '#59616e'; Border = '#d9dde3'; Key = 'FarmStatusDown' }
    }
    $rank = @{ DOWN = 0; ALERT = 1; WARN = 2; OK = 3 }

    # One entry per farm: status, counts and the areas that need attention.
    $farms = New-Object -TypeName System.Collections.ArrayList
    $position = 0
    foreach ($item in $FarmResult) {
        $reachable = if (_has $item 'Reachable') { [bool]$item.Reachable } else { $true }
        $fail = 0; $warn = 0; $ok = 0
        $areas = @{}
        if ($reachable -and (_has $item 'Report') -and $null -ne $item.Report) {
            $computedOk = 0
            foreach ($prop in $item.Report.PSObject.Properties) {
                foreach ($row in @($prop.Value | Where-Object { $null -ne $_ })) {
                    $sev = Get-SPSWeatherRowSeverity -Row $row
                    if ($sev -eq 'ok') {
                        # Only real checks count toward OK, like the per-farm email and the dashboard.
                        $n = $row.PSObject.Properties.Name
                        if (($n -contains 'IsInfo') -or ($n -contains 'severity')) { $computedOk++ }
                        continue
                    }
                    if ($sev -eq 'fail') { $fail++ } else { $warn++ }
                    if (-not $areaMap.Map.ContainsKey($prop.Name)) { continue }
                    $areaId = $areaMap.Map[$prop.Name][1]
                    if (-not $areas.ContainsKey($areaId)) { $areas[$areaId] = [PSCustomObject]@{ Id = $areaId; Fail = 0; Warn = 0 } }
                    if ($sev -eq 'fail') { $areas[$areaId].Fail++ } else { $areas[$areaId].Warn++ }
                }
            }
            $ok = $computedOk
            if ((_has $item 'Summary') -and ($null -ne $item.Summary)) {
                $fail = [int]$item.Summary.Fail; $warn = [int]$item.Summary.Warn; $ok = [int]$item.Summary.Ok
            }
        }
        $status = if (-not $reachable) { 'DOWN' } elseif ($fail -gt 0) { 'ALERT' } elseif ($warn -gt 0) { 'WARN' } else { 'OK' }
        [void]$farms.Add([PSCustomObject]@{
                Name     = _text $item 'Name'
                Server   = _text $item 'Server'
                Url      = _text $item 'DashboardUrl'
                Status   = $status
                Fail     = $fail
                Warn     = $warn
                Ok       = $ok
                Areas    = @($areas.Values)
                Position = $position
            })
        $position++
    }

    $nFarms = $farms.Count
    $nQueried = @($farms | Where-Object { $_.Status -ne 'DOWN' }).Count
    $nDown = $nFarms - $nQueried
    $nAlert = @($farms | Where-Object { $_.Status -eq 'ALERT' }).Count
    $nWarn = @($farms | Where-Object { $_.Status -eq 'WARN' }).Count
    $nOkFarms = @($farms | Where-Object { $_.Status -eq 'OK' }).Count
    $nAttention = $nFarms - $nOkFarms
    $totalFail = [int](($farms | Measure-Object -Property Fail -Sum).Sum)
    $totalWarn = [int](($farms | Measure-Object -Property Warn -Sum).Sum)
    $totalOk = [int](($farms | Measure-Object -Property Ok -Sum).Sum)
    # The weather is the one of the worst farm, not of the sum of the failures of all of them.
    $worstFarmFail = [int](($farms | Measure-Object -Property Fail -Maximum).Maximum)

    # Worst first: unreachable, alert, warning, healthy; then the most failures; then the configuration order.
    $ordered = @($farms | Sort-Object -Property @{ Expression = { $rank[$_.Status] } }, @{ Expression = { $_.Fail }; Descending = $true }, @{ Expression = { $_.Warn }; Descending = $true }, @{ Expression = { $_.Position } })

    $worst = if (($nAlert + $nDown) -gt 0) { 'ALERT' } elseif ($nWarn -gt 0) { 'WARN' } else { 'OK' }
    $priority = if ($worst -eq 'ALERT') { 'High' } else { 'Normal' }
    # The subject stays in English on purpose: inbox rules filter on the severity tag.
    $mix = New-Object -TypeName System.Collections.ArrayList
    if ($nAlert -gt 0) { [void]$mix.Add("$nAlert ALERT") }
    if ($nDown -gt 0) { [void]$mix.Add("$nDown UNREACHABLE") }
    if ($nWarn -gt 0) { [void]$mix.Add("$nWarn WARN") }
    if ($nOkFarms -gt 0) { [void]$mix.Add("$nOkFarms OK") }
    $farmWord = if ($nFarms -eq 1) { 'farm' } else { 'farms' }
    $subject = "[$worst] $Application/$Environment - $nFarms $farmWord ($($mix -join ', ')) - SPSWeather"

    if ($worstFarmFail -gt 5) { $wx = '&#9928;&#65039;'; $wxLabel = _enc (_t 'WeatherStormy') }
    elseif (($worstFarmFail -gt 0) -or ($nDown -gt 0)) { $wx = '&#9925;'; $wxLabel = _enc (_t 'WeatherCloudy') }
    elseif ($totalWarn -gt 0) { $wx = '&#127780;&#65039;'; $wxLabel = _enc (_t 'WeatherFair') }
    else { $wx = '&#9728;&#65039;'; $wxLabel = _enc (_t 'WeatherSunny') }

    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    $envText = _enc ((@($Application, $Environment) | Where-Object { $_ }) -join ' / ')

    # Widths (whole percentages summing to 100, a non-empty part is at least 2) of the health bar.
    function _bar([int]$okN, [int]$warnN, [int]$failN) {
        $parts = @(@{ C = '#2fae66'; V = $okN }, @{ C = '#e8923a'; V = $warnN }, @{ C = '#e24a4a'; V = $failN })
        $total = $okN + $warnN + $failN
        if ($total -le 0) { return '' }
        $raw = @($parts | ForEach-Object { if ($_.V -gt 0) { [math]::Max($_.V / $total * 100, 2) } else { 0 } })
        $sum = ($raw | Measure-Object -Sum).Sum
        $w = @($raw | ForEach-Object { [int][math]::Round($_ / $sum * 100) })
        $big = 0
        for ($j = 1; $j -lt 3; $j++) { if ($w[$j] -gt $w[$big]) { $big = $j } }
        $w[$big] += 100 - (($w | Measure-Object -Sum).Sum)
        $cells = for ($i = 0; $i -lt 3; $i++) {
            if ($w[$i] -gt 0) { "<td width=`"$($w[$i])%`" height=`"8`" style=`"background:$($parts[$i].C);font-size:1px;line-height:1px;mso-line-height-rule:exactly;height:8px;`">&nbsp;</td>" }
        }
        return "<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`"><tr>$($cells -join '')</tr></table>"
    }

    $cardsHtml = New-Object -TypeName System.Text.StringBuilder
    foreach ($f in $ordered) {
        $lk = $look[$f.Status]
        $pill = "<span style=`"display:inline-block;padding:3px 10px;background:$($lk.Tint);color:$($lk.Dark);border:1px solid $($lk.Accent);font-size:11px;font-weight:700;letter-spacing:.05em;border-radius:12px;`">$(_enc (_t $lk.Key))</span>"
        $serverHtml = if ($f.Server) { "<div style=`"font-size:11px;color:#6b7280;margin-top:2px;`">$(_enc $f.Server)</div>" } else { '' }
        [void]$cardsHtml.Append("<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`" style=`"margin-bottom:14px;border:1px solid $($lk.Border);border-left:5px solid $($lk.Accent);border-radius:10px;overflow:hidden;`">")
        [void]$cardsHtml.Append("<tr><td style=`"padding:14px 16px 6px;`"><table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`"><tr><td><div style=`"font-size:17px;font-weight:700;color:#1b2733;`">$(_enc $f.Name)</div>$serverHtml</td><td align=`"right`" valign=`"top`">$pill</td></tr></table></td></tr>")

        if ($f.Status -eq 'DOWN') {
            [void]$cardsHtml.Append("<tr><td style=`"padding:8px 16px 14px;font-size:13px;color:#1b2733;`"><b>$(_enc (_t 'UnreachableTitle'))</b><div style=`"color:#6b7280;font-size:12px;margin-top:3px;`">$(_enc (_t 'UnreachableText'))</div></td></tr></table>")
            continue
        }

        $checks = $f.Ok + $f.Warn + $f.Fail
        if ($checks -gt 0) {
            $pct = [int][math]::Round($f.Ok / $checks * 100)
            # Rounding must not hide a failure or a warning next to a red or orange status.
            if ((($f.Fail + $f.Warn) -gt 0) -and ($pct -gt 99)) { $pct = 99 }
            [void]$cardsHtml.Append("<tr><td style=`"padding:8px 16px 0;`">$(_bar $f.Ok $f.Warn $f.Fail)<table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`"><tr><td style=`"padding-top:6px;font-size:13px;font-weight:700;color:$($lk.Dark);`">$(_enc (_t 'FarmHealth' (_t 'Percent' $pct)))</td><td align=`"right`" style=`"padding-top:6px;font-size:12px;color:#6b7280;`">$(_enc (_t 'CountsSummary' $f.Ok $f.Warn $f.Fail))</td></tr></table></td></tr>")
        }

        if ($f.Status -eq 'OK') {
            [void]$cardsHtml.Append("<tr><td style=`"padding:10px 16px 2px;font-size:13px;color:#2c6b48;`">&#10003; $(_enc (_t 'AllClearText'))</td></tr>")
        }
        elseif ($f.Areas.Count -gt 0) {
            $sortedAreas = @($f.Areas | Sort-Object -Property @{ Expression = { $_.Fail }; Descending = $true }, @{ Expression = { $_.Warn }; Descending = $true }, @{ Expression = { $areaIndex[$_.Id] } })
            $shown = $sortedAreas
            $hidden = @()
            if ($MaxAttentionPerFarm -gt 0 -and $sortedAreas.Count -gt $MaxAttentionPerFarm) {
                $shown = @($sortedAreas[0..($MaxAttentionPerFarm - 1)])
                $hidden = @($sortedAreas[$MaxAttentionPerFarm..($sortedAreas.Count - 1)])
            }
            $rowsHtml = New-Object -TypeName System.Text.StringBuilder
            foreach ($a in $shown) {
                $parts = @()
                if ($a.Fail -gt 0) { $parts += _count $a.Fail 'Failure' }
                if ($a.Warn -gt 0) { $parts += _count $a.Warn 'Warning' }
                $dot = if ($a.Fail -gt 0) { $look.ALERT.Accent } else { $look.WARN.Accent }
                [void]$rowsHtml.Append("<tr><td width=`"14`" valign=`"top`" style=`"padding:2px 0;font-size:13px;color:$dot;`">&#9679;</td><td style=`"padding:2px 0;font-size:13px;color:#1b2733;`">$(_enc (_t "Area_$($a.Id)"))</td><td align=`"right`" style=`"padding:2px 0;font-size:12px;color:#6b7280;`">$(_enc ($parts -join ', '))</td></tr>")
            }
            if ($hidden.Count -gt 0) {
                $hf = [int](($hidden | Measure-Object -Property Fail -Sum).Sum)
                $hw = [int](($hidden | Measure-Object -Property Warn -Sum).Sum)
                $parts = @()
                if ($hf -gt 0) { $parts += _count $hf 'Failure' }
                if ($hw -gt 0) { $parts += _count $hw 'Warning' }
                [void]$rowsHtml.Append("<tr><td></td><td colspan=`"2`" style=`"padding:2px 0;font-size:12px;color:#6b7280;font-style:italic;`">$(_enc (_t 'MoreItems' ($hf + $hw) ($parts -join ', ')))</td></tr>")
            }
            [void]$cardsHtml.Append("<tr><td style=`"padding:10px 16px 2px;`"><div style=`"font-size:11px;color:#6b7280;text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px;`">$(_enc (_t 'FarmAttentionTitle'))</div><table role=`"presentation`" width=`"100%`" cellpadding=`"0`" cellspacing=`"0`">$($rowsHtml.ToString())</table></td></tr>")
        }

        if ($f.Url) {
            [void]$cardsHtml.Append("<tr><td style=`"padding:10px 16px 14px;`"><table role=`"presentation`" cellpadding=`"0`" cellspacing=`"0`"><tr><td style=`"border:1px solid #2b5797;border-radius:8px;`"><a href=`"$(_enc $f.Url)`" style=`"display:inline-block;padding:8px 16px;color:#2b5797;font-size:12px;font-weight:700;text-decoration:none;`">$(_enc (_t 'OpenDashboard')) &rarr;</a></td></tr></table></td></tr></table>")
        }
        else {
            [void]$cardsHtml.Append('<tr><td style="padding-bottom:12px;"></td></tr></table>')
        }
    }

    $ofTotal = "<b>$(_enc (_count $nAttention 'FarmsOfTotal' $nFarms))</b>"
    $intro = if ($nAttention -gt 1) { _th 'IntroFarmsMany' $ofTotal "<b>$envText</b>" }
    elseif ($nAttention -eq 1) { _th 'IntroFarmsOne' $ofTotal "<b>$envText</b>" }
    else { _th 'IntroClear' "<b>$envText</b>" }

    $cockpitHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($CockpitUrl)) {
        $cockpitHtml = "<tr><td style=`"padding:4px 26px 8px;`"><table role=`"presentation`" cellpadding=`"0`" cellspacing=`"0`"><tr><td style=`"border:1px solid #2b5797;border-radius:8px;`"><a href=`"$(_enc $CockpitUrl.Trim())`" style=`"display:inline-block;padding:8px 16px;color:#2b5797;font-size:12px;font-weight:700;text-decoration:none;`">$(_enc (_t 'OpenCockpit')) &rarr;</a></td></tr></table></td></tr>"
    }

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
      <td style="color:#ffffff;"><div style="font-size:19px;font-weight:700;">SPSWeather &mdash; $envText</div><div style="font-size:12px;color:#cdd8ea;margin-top:3px;">$(_enc (_count $nFarms 'FarmCount')) &middot; $generated</div></td>
      <td align="right" style="color:#ffffff;"><div style="font-size:11px;color:#cdd8ea;text-transform:uppercase;letter-spacing:.06em;">$(_enc (_t 'WeatherLabel'))</div><div style="font-size:18px;font-weight:800;">$wxLabel</div></td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:16px 26px 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td width="33%" align="center" style="padding:10px;background:#fdeaea;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#e24a4a;line-height:1;">$totalFail</div><div style="font-size:11px;color:#8a4a4a;text-transform:uppercase;letter-spacing:.05em;">$(_enc (_t 'KpiFailures'))</div></td>
      <td width="8"></td>
      <td width="33%" align="center" style="padding:10px;background:#fdf1e4;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#e8923a;line-height:1;">$totalWarn</div><div style="font-size:11px;color:#8a6530;text-transform:uppercase;letter-spacing:.05em;">$(_enc (_t 'KpiWarnings'))</div></td>
      <td width="8"></td>
      <td width="33%" align="center" style="padding:10px;background:#e6f7ee;border-radius:10px;"><div style="font-size:26px;font-weight:800;color:#2fae66;line-height:1;">$totalOk</div><div style="font-size:11px;color:#2c6b48;text-transform:uppercase;letter-spacing:.05em;">$(_enc (_t 'KpiChecksOk'))</div></td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:14px 26px 8px;font-size:14px;color:#1b2733;">$intro</td></tr>$cockpitHtml
  <tr><td style="padding:6px 26px 10px;">$($cardsHtml.ToString())</td></tr>
  <tr><td style="background:#f6f8fb;border-top:1px solid #e3e8ef;padding:14px 26px;font-size:11px;color:#9aa4b2;">SPSWeather $(_enc $Version) &middot; $(_enc (_t 'FooterExecutedBy')) $(_enc $ExecutedBy) &middot; $(_enc (_t 'FooterRun')) $(_enc $Duration) &middot; $(_enc (_t 'FooterFarmsQueried' $nQueried $nFarms)).</td></tr>
</table>
</td></tr></table>
</body></html>
"@

    return [PSCustomObject]@{
        Subject  = $subject
        Priority = $priority
        Alert    = $worst
        Body     = $body
    }
}
