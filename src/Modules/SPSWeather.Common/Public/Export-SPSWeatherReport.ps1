function Export-SPSWeatherReport {
    <#
        .SYNOPSIS
        Writes the self-contained HTML "cards" dashboard for one farm of an SPSWeather run.

        .DESCRIPTION
        See the SPSWeather wiki (Dashboard page) for the full reference. In short:
        renders one dependency-free HTML page per farm with an overall-health donut,
        a run-history bar chart, one status card per functional area, and collapsible
        detail tables.

        .EXAMPLE
        Export-SPSWeatherReport -InputObject $farmReport -OutputFile $out `
            -Farm 'CONTENT' -Application 'zebes' -Environment 'PROD' -Version '3.1.0'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [PSCustomObject]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [System.String]
        $InputFile,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFile,

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

        # Previous-run summaries for the history bar chart (oldest first). Each item:
        # PSCustomObject with Date (string), Ok, Warn, Fail (int). The current run is appended.
        [Parameter()]
        [PSCustomObject[]]
        $History
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path -Path $InputFile)) { throw "Input JSON file not found: $InputFile" }
        $InputObject = Get-Content -Path $InputFile -Raw | ConvertFrom-Json
    }

    $noiseColumns = @('IsInfo', 'PSComputerName', 'RunspaceId', 'PSShowComputerName')

    function _enc([object]$v) {
        if ($null -eq $v) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$v)
    }

    # Row severity: IsInfo drives ok/fail; severity string drives warn (Health Analyzer).
    function _sev($row) { Get-SPSWeatherRowSeverity -Row $row }

    $areas = @(
        [PSCustomObject]@{ Name = 'Farm & Upgrade'; Icon = '&#127970;'; Sections = @('SPUpgradeStatus') }
        [PSCustomObject]@{ Name = 'Trust Farm (REST)'; Icon = '&#127760;'; Sections = @('SPAPIHttpStatus', 'SPSSitesHttpStatus') }
        [PSCustomObject]@{ Name = 'Search'; Icon = '&#128269;'; Sections = @('SPSearchLastCrawlStatus', 'SPSearchCrawlLogs', 'SPSSearchEntTopology') }
        [PSCustomObject]@{ Name = 'Distributed Cache'; Icon = '&#9889;'; Sections = @('AppFabricStatus') }
        [PSCustomObject]@{ Name = 'Timer Jobs & Solutions'; Icon = '&#9201;'; Sections = @('SPFailedTimerJobs', 'SPSolutionDeployment', 'USPAudienceStatus') }
        [PSCustomObject]@{ Name = 'Health Analyzer'; Icon = '&#129657;'; Sections = @('SPHealthAnalyzer') }
        [PSCustomObject]@{ Name = 'IIS'; Icon = '&#128421;'; Sections = @('IISApplicationPoolStatus', 'IISWorkerProcessStatus', 'IISWebSiteCertStatus') }
        [PSCustomObject]@{ Name = 'System'; Icon = '&#129513;'; Sections = @('SYSDiskUsageStatus', 'SYSLastRebootStatus', 'SYSDOTNETVersion', 'SYSEventViewerAppErrors') }
        [PSCustomObject]@{ Name = 'SQL Server'; Icon = '&#128451;'; Sections = @('SPSContentDBStatus', 'SQLInstanceStatus', 'SQLDatabaseStatus', 'SQLDiskStatus', 'SQLAvailabilityStatus', 'SQLAliasStatus') }
    )

    $sectionLabel = @{
        SPHealthAnalyzer = 'Health Analyzer'; SPUpgradeStatus = 'Upgrade Status'; SPAPIHttpStatus = 'Trust Farm (REST)'
        SPSSitesHttpStatus = 'Site HTTP Status'; SPFailedTimerJobs = 'Failed Timer Jobs'; SPSolutionDeployment = 'Solution Deployment'
        SPSearchLastCrawlStatus = 'Search - Last Crawl'; SPSearchCrawlLogs = 'Search - Crawl Logs'; SPSSearchEntTopology = 'Search - Topology'
        AppFabricStatus = 'Distributed Cache'; USPAudienceStatus = 'User Profile Audiences'; IISApplicationPoolStatus = 'IIS - Application Pools'
        IISWorkerProcessStatus = 'IIS - Worker Processes'; IISWebSiteCertStatus = 'IIS - SSL Certificates'; SYSEventViewerAppErrors = 'System - Event Log Errors'
        SYSDiskUsageStatus = 'System - Disk Usage'; SYSLastRebootStatus = 'System - Last Reboot'; SYSDOTNETVersion = 'System - .NET Framework'
        SPSContentDBStatus = 'Content Databases'; SQLInstanceStatus = 'SQL - Instances'; SQLDatabaseStatus = 'SQL - Databases'
        SQLDiskStatus = 'SQL - Disk Volumes'; SQLAvailabilityStatus = 'SQL - Availability Groups'; SQLAliasStatus = 'SQL - Alias Mapping'
    }

    # Per-section and global counts. Only rows that are actual checks (carrying IsInfo or a
    # severity) count toward OK, so pure info-only rows (reboot time, .NET version) do not
    # inflate the healthy total - keeping the donut/KPI consistent with the email and the
    # report Summary.
    function _isCheck($r) {
        if ($null -eq $r) { return $false }
        $n = $r.PSObject.Properties.Name
        return (($n -contains 'IsInfo') -or ($n -contains 'severity'))
    }
    $gOk = 0; $gWarn = 0; $gFail = 0
    $sectionStats = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $rows = @($prop.Value | Where-Object { $null -ne $_ })
        $o = 0; $w = 0; $f = 0; $info = 0
        foreach ($r in $rows) {
            switch (_sev $r) {
                'warn' { $w++ }
                'fail' { $f++ }
                default { if (_isCheck $r) { $o++ } else { $info++ } }
            }
        }
        $sectionStats[$prop.Name] = [PSCustomObject]@{ Count = $rows.Count; Ok = $o; Warn = $w; Fail = $f; Info = $info }
        $gOk += $o; $gWarn += $w; $gFail += $f
    }
    $gTotal = $gOk + $gWarn + $gFail
    $healthPct = if ($gTotal -gt 0) { [math]::Round(($gOk / $gTotal) * 100) } else { 100 }

    if ($gFail -eq 0 -and $gWarn -eq 0) { $wx = '&#9728;&#65039;'; $wxLabel = 'Sunny' }
    elseif ($gFail -eq 0) { $wx = '&#127780;&#65039;'; $wxLabel = 'Fair' }
    elseif ($gFail -le 5) { $wx = '&#9925;'; $wxLabel = 'Cloudy' }
    else { $wx = '&#9928;&#65039;'; $wxLabel = 'Stormy' }
    $attention = $gWarn + $gFail

    $pOk = if ($gTotal -gt 0) { [math]::Round(($gOk / $gTotal) * 100, 1) } else { 100 }
    $pWarn = if ($gTotal -gt 0) { [math]::Round(($gWarn / $gTotal) * 100, 1) } else { 0 }
    $pFail = if ($gTotal -gt 0) { [math]::Round(($gFail / $gTotal) * 100, 1) } else { 0 }
    $offWarn = (100 - $pOk + 25) % 100
    $offFail = (100 - $pOk - $pWarn + 25) % 100

    # Cards.
    $cardsHtml = New-Object -TypeName System.Text.StringBuilder
    foreach ($area in $areas) {
        $aOk = 0; $aWarn = 0; $aFail = 0; $present = @()
        foreach ($sk in $area.Sections) {
            if ($sectionStats.ContainsKey($sk) -and $sectionStats[$sk].Count -gt 0) {
                $present += $sk
                $aOk += $sectionStats[$sk].Ok; $aWarn += $sectionStats[$sk].Warn; $aFail += $sectionStats[$sk].Fail
            }
        }
        if ($present.Count -eq 0) { continue }
        if ($aFail -gt 0) { $cls = 'fail'; $pill = "$aFail failed" }
        elseif ($aWarn -gt 0) { $cls = 'warn'; $pill = "$aWarn warning" }
        else { $cls = 'ok'; $pill = 'healthy' }
        $aTot = $aOk + $aWarn + $aFail
        $okw = if ($aTot) { [math]::Round($aOk / $aTot * 100) } else { 100 }
        $warw = if ($aTot) { [math]::Round($aWarn / $aTot * 100) } else { 0 }
        $faw = 100 - $okw - $warw
        $anchor = 'd-' + ($present[0] -replace '[^A-Za-z0-9_-]', '')

        [void]$cardsHtml.Append("<div class=`"card`"><div class=`"head`"><div class=`"ci $cls`">$($area.Icon)</div><h4>$(_enc $area.Name)</h4><div class=`"st $cls`">$(_enc $pill)</div></div><div class=`"body`"><div class=`"bar`"><i style=`"width:$okw%;background:#2fae66`"></i><i style=`"width:$warw%;background:#e8923a`"></i><i style=`"width:$faw%;background:#e24a4a`"></i></div>")
        foreach ($sk in $present) {
            $st = $sectionStats[$sk]
            $lbl = if ($sectionLabel.ContainsKey($sk)) { $sectionLabel[$sk] } else { $sk }
            if ($st.Fail -gt 0) { $vcls = 'fail'; $vtxt = "$($st.Fail) alert" }
            elseif ($st.Warn -gt 0) { $vcls = 'warn'; $vtxt = "$($st.Warn) warn" }
            elseif ($st.Ok -gt 0) { $vcls = 'ok'; $vtxt = "$($st.Ok) OK" }
            else { $vcls = 'ok'; $vtxt = "$($st.Count) info" }
            [void]$cardsHtml.Append("<div class=`"rowline`"><span>$(_enc $lbl)</span><span class=`"v $vcls`">$(_enc $vtxt)</span></div>")
        }
        [void]$cardsHtml.Append("</div><div class=`"foot`"><a href=`"#$anchor`">View detail &rarr;</a></div></div>")
    }

    # History chart (append current run, cap 30, one x-label every 5 bars).
    $runs = @()
    if ($null -ne $History) { $runs += @($History) }
    $runs += [PSCustomObject]@{ Date = (Get-Date).ToString('MM-dd'); Ok = $gOk; Warn = $gWarn; Fail = $gFail; Now = $true }
    if ($runs.Count -gt 30) { $runs = $runs[($runs.Count - 30)..($runs.Count - 1)] }
    $barsHtml = New-Object -TypeName System.Text.StringBuilder
    $xHtml = New-Object -TypeName System.Text.StringBuilder
    $lastIdx = $runs.Count - 1
    for ($i = 0; $i -lt $runs.Count; $i++) {
        $h = $runs[$i]
        $o = [int]$h.Ok; $w = [int]$h.Warn; $f = [int]$h.Fail; $t = $o + $w + $f
        $okp = if ($t) { [math]::Round($o / $t * 100) } else { 0 }
        $wp = if ($t) { [math]::Round($w / $t * 100) } else { 0 }
        $fp = 100 - $okp - $wp
        $now = ($i -eq $lastIdx)
        $tip = _enc "$($h.Date)$(if ($now) { ' (now)' }): $o OK / $w warn / $f fail"
        [void]$barsHtml.Append("<div class=`"bcol$(if ($now) { ' now' })`"><div class=`"stack`" title=`"$tip`" style=`"height:88%`"><i class=`"f`" style=`"height:$fp%`"></i><i class=`"w`" style=`"height:$wp%`"></i><i class=`"o`" style=`"height:$okp%`"></i></div></div>")
        $show = $now -or ($i % 5 -eq 0)
        $xt = if ($show) { if ($now) { "<b>$(_enc $h.Date)</b>" } else { _enc $h.Date } } else { '' }
        [void]$xHtml.Append("<span>$xt</span>")
    }
    # trend vs previous run
    if ($runs.Count -ge 2) {
        $prev = $runs[$lastIdx - 1]
        $df = $gFail - [int]$prev.Fail; $dw = $gWarn - [int]$prev.Warn
        $fArrow = if ($df -gt 0) { "<span class=`"trend up`">&#9650;$df</span>" } elseif ($df -lt 0) { "<span class=`"trend down`">&#9660;$([math]::Abs($df))</span>" } else { '' }
        $wArrow = if ($dw -gt 0) { "<span class=`"trend up`">&#9650;$dw</span>" } elseif ($dw -lt 0) { "<span class=`"trend down`">&#9660;$([math]::Abs($dw))</span>" } else { '' }
    }
    else { $fArrow = ''; $wArrow = '' }

    # Collapsible detail.
    $detailHtml = New-Object -TypeName System.Text.StringBuilder
    foreach ($area in $areas) {
        foreach ($sk in $area.Sections) {
            if (-not ($sectionStats.ContainsKey($sk)) -or $sectionStats[$sk].Count -eq 0) { continue }
            $rows = @($InputObject.$sk | Where-Object { $null -ne $_ })
            $cols = @($rows[0].PSObject.Properties.Name | Where-Object { $noiseColumns -notcontains $_ })
            $anchor = 'd-' + ($sk -replace '[^A-Za-z0-9_-]', '')
            $lbl = if ($sectionLabel.ContainsKey($sk)) { $sectionLabel[$sk] } else { $sk }
            $st = $sectionStats[$sk]
            if ($st.Fail -gt 0) { $pc = 'fail'; $pt = "$($st.Fail) failed" } elseif ($st.Warn -gt 0) { $pc = 'warn'; $pt = "$($st.Warn) warning" } else { $pc = 'ok'; $pt = "$($st.Count) OK" }
            [void]$detailHtml.Append("<details class=`"sec`" id=`"$anchor`"><summary><span class=`"sg-ico $pc`">&#9679;</span> $(_enc $lbl) <span class=`"pill $pc`">$(_enc $pt)</span><span class=`"chev`">&#9654;</span></summary><div class=`"tw`"><table><thead><tr>")
            foreach ($c in $cols) { [void]$detailHtml.Append("<th>$(_enc $c)</th>") }
            [void]$detailHtml.Append('</tr></thead><tbody>')
            foreach ($r in $rows) {
                $rc = switch (_sev $r) { 'fail' { ' class="r-fail"' } 'warn' { ' class="r-warn"' } default { '' } }
                [void]$detailHtml.Append("<tr$rc>")
                foreach ($c in $cols) { [void]$detailHtml.Append("<td>$(_enc $r.$c)</td>") }
                [void]$detailHtml.Append('</tr>')
            }
            [void]$detailHtml.Append('</tbody></table></div></details>')
        }
    }

    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $envLine = (@($Application, $Environment) | Where-Object { $_ }) -join ' / '
    if ($Farm) { $envLine = "Farm $Farm &middot; $envLine" }

    $page = @"
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SPSWeather Dashboard - $(_enc $Application)/$(_enc $Environment)/$(_enc $Farm)</title>
<style>
:root{--ink:#1b2733;--muted:#6b7280;--bg:#eef2f7;--card:#fff;--line:#e3e8ef;--brand:#2b5797;--brand2:#1e3d6b;--ok:#2fae66;--ok-bg:#e6f7ee;--warn:#e8923a;--warn-bg:#fdf1e4;--fail:#e24a4a;--fail-bg:#fdeaea;--shadow:0 1px 3px rgba(16,34,54,.08),0 8px 24px rgba(16,34,54,.06)}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 'Segoe UI','Aptos',Arial,sans-serif}
header.top{background:linear-gradient(135deg,var(--brand),var(--brand2));color:#fff;padding:18px 28px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:16px;position:sticky;top:0;z-index:20;box-shadow:0 2px 10px rgba(0,0,0,.15)}
.brand{display:flex;align-items:center;gap:14px}.brand .logo{font-size:30px}.brand h1{margin:0;font-size:18px;font-weight:600}.brand .sub{opacity:.85;font-size:12px;margin-top:2px}
.top-right{display:flex;align-items:center;gap:22px;flex-wrap:wrap}.weather{display:flex;align-items:center;gap:10px}.weather .ico{font-size:34px}.weather .lbl{font-weight:700;font-size:16px}.weather .lbl small{display:block;font-weight:400;opacity:.85;font-size:11px}.meta{font-size:12px;opacity:.85;text-align:right}
.wrap{max-width:1180px;margin:22px auto;padding:0 20px}
.hero{display:grid;grid-template-columns:260px 1fr;gap:20px;margin-bottom:22px}@media(max-width:820px){.hero{grid-template-columns:1fr}}
.donutcard{background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:var(--shadow);padding:18px;text-align:center}.donutcard h3{margin:0 0 10px;font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
.donut{position:relative;width:170px;height:170px;margin:0 auto}.donut .center{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}.donut .center .big{font-size:34px;font-weight:800}.donut .center .small{font-size:11px;color:var(--muted);text-transform:uppercase}
.legend{display:flex;justify-content:center;gap:14px;margin-top:12px;font-size:12px}.legend span{display:inline-flex;align-items:center;gap:5px}.dot{width:10px;height:10px;border-radius:50%;display:inline-block}.dot.ok{background:var(--ok)}.dot.warn{background:var(--warn)}.dot.fail{background:var(--fail)}
.histcard{background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:var(--shadow);padding:16px 18px;display:flex;flex-direction:column}
.histhead{display:flex;align-items:center;gap:14px;margin-bottom:10px;flex-wrap:wrap}.histhead h3{margin:0;font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
.histstats{display:flex;gap:16px;margin-left:auto;flex-wrap:wrap}.hs{display:flex;align-items:baseline;gap:6px}.hs .n{font-size:20px;font-weight:800;line-height:1}.hs .t{font-size:11px;color:var(--muted);text-transform:uppercase}.hs.fail .n{color:var(--fail)}.hs.warn .n{color:var(--warn)}.hs.ok .n{color:var(--ok)}.hs .trend{font-size:11px;font-weight:600}.hs .trend.up{color:var(--fail)}.hs .trend.down{color:var(--ok)}
.chart{position:relative;flex:1;min-height:150px;display:flex;align-items:flex-end;gap:5px;padding:6px 2px 0;border-bottom:1px solid var(--line)}.gl{position:absolute;left:0;right:0;border-top:1px dashed #eef2f7}
.bcol{position:relative;flex:1;min-width:4px;display:flex;flex-direction:column;justify-content:flex-end;height:100%}.bcol .stack{display:flex;flex-direction:column;justify-content:flex-end;border-radius:4px 4px 0 0;overflow:hidden;transition:opacity .12s}.bcol:hover .stack{opacity:.82}.bcol .stack>i{display:block;width:100%}.bcol .stack .f{background:#e24a4a}.bcol .stack .w{background:#e8923a}.bcol .stack .o{background:#2fae66}.bcol.now .stack{outline:2px solid var(--brand)}
.xlabels{display:flex;gap:5px;padding:6px 2px 0}.xlabels span{flex:1;min-width:4px;text-align:center;font-size:9px;color:var(--muted);white-space:nowrap}
.histlegend{display:flex;gap:14px;margin-top:8px;font-size:11px;color:var(--muted)}.histlegend span{display:inline-flex;align-items:center;gap:5px}
.section-title{display:flex;align-items:center;gap:8px;margin:6px 2px 14px;font-size:13px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}@media(max-width:980px){.cards{grid-template-columns:repeat(2,1fr)}}@media(max-width:620px){.cards{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:var(--shadow);overflow:hidden;display:flex;flex-direction:column}.card .head{display:flex;align-items:center;gap:12px;padding:16px 18px 10px}.card .head .ci{width:40px;height:40px;border-radius:11px;display:flex;align-items:center;justify-content:center;font-size:20px}.card .head h4{margin:0;font-size:15px;font-weight:650}.card .head .st{margin-left:auto;font-size:11px;font-weight:700;padding:4px 10px;border-radius:999px;text-transform:uppercase}
.st.ok{background:var(--ok-bg);color:var(--ok)}.st.warn{background:var(--warn-bg);color:var(--warn)}.st.fail{background:var(--fail-bg);color:var(--fail)}.ci.ok{background:var(--ok-bg)}.ci.warn{background:var(--warn-bg)}.ci.fail{background:var(--fail-bg)}
.card .body{padding:4px 18px 10px}.bar{height:6px;border-radius:4px;background:#eef2f7;overflow:hidden;margin:2px 0 8px}.bar>i{display:block;height:100%;float:left}
.rowline{display:flex;align-items:center;justify-content:space-between;padding:7px 0;border-top:1px dashed var(--line);font-size:13px}.rowline:first-child{border-top:none}.rowline .v{font-weight:700}.rowline .v.ok{color:var(--ok)}.rowline .v.warn{color:var(--warn)}.rowline .v.fail{color:var(--fail)}
.card .foot{margin-top:auto;padding:10px 18px;border-top:1px solid var(--line);background:#fafbfd;font-size:12px}.card .foot a{color:var(--brand);text-decoration:none;font-weight:600}.card .foot a:hover{text-decoration:underline}
.details{margin-top:12px}details.sec{background:var(--card);border:1px solid var(--line);border-radius:12px;box-shadow:var(--shadow);margin:0 0 10px;overflow:hidden}details.sec>summary{list-style:none;cursor:pointer;padding:12px 16px;display:flex;align-items:center;gap:10px;font-size:14px;font-weight:600}details.sec>summary::-webkit-details-marker{display:none}details.sec>summary .chev{margin-left:auto;transition:transform .15s;color:var(--muted)}details.sec[open]>summary .chev{transform:rotate(90deg)}details.sec>summary .pill{font-size:11px;font-weight:700;padding:3px 9px;border-radius:999px}
.pill.ok{background:var(--ok-bg);color:var(--ok)}.pill.warn{background:var(--warn-bg);color:var(--warn)}.pill.fail{background:var(--fail-bg);color:var(--fail)}.sg-ico{width:16px;text-align:center;font-size:10px}.sg-ico.ok{color:var(--ok)}.sg-ico.warn{color:var(--warn)}.sg-ico.fail{color:var(--fail)}
.tw{overflow:auto;border-top:1px solid var(--line)}table{width:100%;border-collapse:collapse}th,td{padding:6px 10px;text-align:left;border-bottom:1px solid var(--line);font-size:13px;vertical-align:top}thead th{background:#eef2f7;color:#10222e;font-weight:600}tr.r-fail td{background:#fff5f5}tr.r-warn td{background:#fff9f0}
.detail-head{display:flex;align-items:center;gap:10px;margin:22px 2px 12px}.detail-head .exp{margin-left:auto;font-size:12px}.detail-head .exp button{color:var(--brand);background:none;border:0;padding:0;font:inherit;text-decoration:underline;cursor:pointer}
footer{max-width:1180px;margin:10px auto 36px;padding:0 20px;color:var(--muted);font-size:12px;display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px}
</style></head>
<body>
<header class="top">
  <div class="brand"><div class="logo">$wx</div><div><h1>SPSWeather Dashboard</h1><div class="sub">$envLine &middot; SharePoint Server Subscription Edition</div></div></div>
  <div class="top-right"><div class="weather"><div class="ico">$wx</div><div class="lbl">$wxLabel<small>$attention item(s) need attention</small></div></div><div class="meta">Generated<br><b>$generated</b><br>$(_enc $Duration) &middot; v$(_enc $Version)</div></div>
</header>
<div class="wrap">
  <div class="hero">
    <div class="donutcard"><h3>Overall health</h3>
      <div class="donut"><svg viewBox="0 0 42 42" width="170" height="170">
        <circle cx="21" cy="21" r="15.9155" fill="none" stroke="#eef2f7" stroke-width="6"></circle>
        <circle cx="21" cy="21" r="15.9155" fill="none" stroke="#2fae66" stroke-width="6" stroke-dasharray="$pOk $([math]::Round(100-$pOk,1))" stroke-dashoffset="25"></circle>
        <circle cx="21" cy="21" r="15.9155" fill="none" stroke="#e8923a" stroke-width="6" stroke-dasharray="$pWarn $([math]::Round(100-$pWarn,1))" stroke-dashoffset="$offWarn"></circle>
        <circle cx="21" cy="21" r="15.9155" fill="none" stroke="#e24a4a" stroke-width="6" stroke-dasharray="$pFail $([math]::Round(100-$pFail,1))" stroke-dashoffset="$offFail"></circle>
      </svg><div class="center"><div class="big">$healthPct%</div><div class="small">healthy</div></div></div>
      <div class="legend"><span><i class="dot ok"></i>OK $gOk</span><span><i class="dot warn"></i>Warn $gWarn</span><span><i class="dot fail"></i>Fail $gFail</span></div>
    </div>
    <div class="histcard">
      <div class="histhead"><h3>Run history &mdash; last $($runs.Count) runs</h3>
        <div class="histstats"><div class="hs fail"><span class="n">$gFail</span><span class="t">Fail</span>$fArrow</div><div class="hs warn"><span class="n">$gWarn</span><span class="t">Warn</span>$wArrow</div><div class="hs ok"><span class="n">$gOk</span><span class="t">OK</span></div></div>
      </div>
      <div class="chart"><div class="gl" style="bottom:25%"></div><div class="gl" style="bottom:50%"></div><div class="gl" style="bottom:75%"></div>
        $($barsHtml.ToString())
      </div>
      <div class="xlabels">$($xHtml.ToString())</div>
      <div class="histlegend"><span><i class="dot ok"></i>OK</span><span><i class="dot warn"></i>Warning</span><span><i class="dot fail"></i>Failure</span><span style="margin-left:auto">hover a bar for the run totals</span></div>
    </div>
  </div>
  <div class="section-title">Health by area</div>
  <div class="cards">$($cardsHtml.ToString())</div>
  <div class="detail-head"><div class="section-title" style="margin:0">Detail</div><div class="exp"><button type="button" onclick="document.querySelectorAll('details.sec').forEach(function(d){d.open=true})">Expand all</button> &middot; <button type="button" onclick="document.querySelectorAll('details.sec').forEach(function(d){d.open=false})">Collapse all</button></div></div>
  <div class="details">$($detailHtml.ToString())</div>
</div>
<footer><span>SPSWeather $(_enc $Version) &middot; $envLine</span><span>Executed by $(_enc $ExecutedBy) &middot; $generated</span></footer>
</body></html>
"@

    $dir = Split-Path -Path $OutputFile -Parent
    if ($dir -and -not (Test-Path -Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }
    $page | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    return $OutputFile
}
