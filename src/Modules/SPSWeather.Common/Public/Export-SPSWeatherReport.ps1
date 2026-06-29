function Export-SPSWeatherReport {
    <#
        .SYNOPSIS
        Writes a standalone, self-contained HTML report for the latest SPSWeather run.

        .DESCRIPTION
        Generates a dependency-free HTML page (no CDN, opens offline) intended for the
        on-disk Results/*.html file. It is richer than the Outlook email body
        (Join-HtmlBodyFromPSo): a fixed top banner with the overall status and OK/Alert
        counters, a quick-jump nav, and one collapsible section per data block with
        sticky table headers.

        Input is the same PSCustomObject built by ConvertTo-SPSWeatherReport (or the
        snapshot JSON), so the email body and the rich report stay in sync.

        .PARAMETER InputObject
        The report PSCustomObject (typically $jsonObject in the entry script).

        .PARAMETER InputFile
        Path to a JSON snapshot to read instead of -InputObject.

        .PARAMETER Summary
        Optional summary object: PSCustomObject with Ok / Alert integer properties.
        Falls back to a recomputed count when omitted.

        .PARAMETER OutputFile
        Destination path of the generated .html file. Required.

        .PARAMETER Title
        Page title and H1. Defaults to 'SPSWeather'.

        .EXAMPLE
        Export-SPSWeatherReport -InputObject $jsonObject `
            -Summary $reportResult.Summary `
            -OutputFile (Join-Path $pathResultsFolder ($spWeatherFileName + '-rich.html')) `
            -Title "SPSWeather $Application/$Environment"
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

        [Parameter()]
        [PSCustomObject]
        $Summary,

        [Parameter()]
        [PSCustomObject]
        $Trend,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFile,

        [Parameter()]
        [System.String]
        $Title = 'SPSWeather'
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path -Path $InputFile)) {
            throw "Input JSON file not found: $InputFile"
        }
        $InputObject = Get-Content -Path $InputFile -Raw | ConvertFrom-Json
    }

    # Recompute summary if not provided, from the IsInfo rows of each section.
    if ($null -eq $Summary) {
        $ok = 0; $alert = 0
        foreach ($prop in $InputObject.PSObject.Properties) {
            foreach ($row in @($prop.Value)) {
                if ($null -ne $row -and ($row.PSObject.Properties.Name -contains 'IsInfo')) {
                    if ($row.IsInfo -eq $false) { $alert++ } else { $ok++ }
                }
            }
        }
        $Summary = [PSCustomObject]@{ Ok = $ok; Alert = $alert }
    }

    $okCount = [int]$Summary.Ok
    $alertCount = [int]$Summary.Alert
    $overall = if ($alertCount -gt 0) { 'ALERT' } else { 'OK' }
    $overallClass = if ($alertCount -gt 0) { 'banner-alert' } else { 'banner-ok' }
    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $trendHtml = ''
    if ($null -ne $Trend -and $Trend.HasPrevious) {
        $arrow = if ($Trend.DeltaAlert -gt 0) { '&uarr;' } elseif ($Trend.DeltaAlert -lt 0) { '&darr;' } else { '=' }
        $trendHtml = "<span class=`"kpi kpi-trend`">Alert $($Trend.Previous.Alert) &rarr; $($Trend.Current.Alert) $arrow</span>"
    }

    # HTML-encode helper (works on Windows PowerShell 5.1 and pwsh 7).
    function _enc([object]$v) {
        if ($null -eq $v) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$v)
    }

    # Build one section per non-empty property. Each section is a <details> with a
    # <table>; headers come from the first row's property names.
    $sectionsHtml = New-Object -TypeName System.Text.StringBuilder
    $navHtml = New-Object -TypeName System.Text.StringBuilder
    foreach ($prop in $InputObject.PSObject.Properties) {
        $rows = @($prop.Value)
        if ($rows.Count -eq 0 -or $null -eq $rows[0]) { continue }
        $sectionId = 'sec-' + ($prop.Name -replace '[^A-Za-z0-9_-]', '')
        $sectionRows = $rows | Where-Object { $null -ne $_ }
        if ($sectionRows.Count -eq 0) { continue }

        $columns = @($sectionRows[0].PSObject.Properties.Name | Where-Object {
                $_ -ne 'IsInfo' -and
                $_ -ne 'PSComputerName' -and
                $_ -ne 'RunspaceId' -and
                $_ -ne 'PSShowComputerName'
            })
        [void]$navHtml.AppendLine("<li><a href=`"#$sectionId`">$(_enc $prop.Name) ($($sectionRows.Count))</a></li>")

        [void]$sectionsHtml.AppendLine("<section id=`"$sectionId`"><h2>$(_enc $prop.Name) <span class=`"badge`">$($sectionRows.Count)</span></h2><div class=`"table-wrap`"><table><thead><tr>")
        foreach ($c in $columns) { [void]$sectionsHtml.Append("<th>$(_enc $c)</th>") }
        [void]$sectionsHtml.AppendLine("</tr></thead><tbody>")
        foreach ($row in $sectionRows) {
            $rowClass = ''
            if (($row.PSObject.Properties.Name -contains 'IsInfo') -and ($row.IsInfo -eq $false)) {
                $rowClass = ' class="row-alert"'
            }
            [void]$sectionsHtml.Append("<tr$rowClass>")
            foreach ($c in $columns) { [void]$sectionsHtml.Append("<td>$(_enc $row.$c)</td>") }
            [void]$sectionsHtml.AppendLine("</tr>")
        }
        [void]$sectionsHtml.AppendLine("</tbody></table></div></section>")
    }

    $encTitle = _enc $Title
    $page = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$encTitle</title>
<style>
:root { --ink:#1b1b1b; --muted:#6b7280; --bg:#f4f6f8; --card:#ffffff; --line:#e5e7eb; --brand:#2b5797; --ok-bg:#bfff80; --ok-ink:#13300a; --alert-bg:#ff6464; --alert-ink:#3a0000; }
* { box-sizing:border-box; }
body { margin:0; padding:0; background:var(--bg); color:var(--ink); font:14px/1.45 'Segoe UI','Aptos',Arial,sans-serif; }
header.banner { position:sticky; top:0; z-index:10; padding:12px 20px; color:#fff; background:var(--brand); display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px; }
header.banner h1 { margin:0; font-size:16px; font-weight:600; }
.kpi { display:inline-block; padding:4px 12px; border-radius:6px; font-weight:700; margin-left:6px; }
.banner-ok { background:var(--ok-bg); color:var(--ok-ink); }
.banner-alert { background:var(--alert-bg); color:var(--alert-ink); }
.kpi-ok { background:var(--ok-bg); color:var(--ok-ink); }
.kpi-alert { background:var(--alert-bg); color:var(--alert-ink); }
.kpi-trend { background:#fff; color:var(--brand); border:1px solid #ffffff55; }
.meta { color:#e5e7eb; font-size:12px; }
.layout { max-width:1200px; margin:16px auto; padding:0 16px; display:grid; grid-template-columns:240px 1fr; gap:16px; }
nav.toc { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px; position:sticky; top:64px; max-height:calc(100vh - 80px); overflow:auto; }
nav.toc h3 { margin:0 0 8px 0; font-size:13px; color:var(--muted); text-transform:uppercase; letter-spacing:0.04em; }
nav.toc ul { list-style:none; padding:0; margin:0; }
nav.toc li a { display:block; padding:4px 6px; border-radius:4px; color:var(--ink); text-decoration:none; font-size:13px; }
nav.toc li a:hover { background:var(--bg); }
main { min-width:0; }
section { background:var(--card); border:1px solid var(--line); border-radius:8px; margin:0 0 16px 0; padding:12px 16px; }
section h2 { margin:0 0 10px 0; font-size:14px; color:var(--brand); display:flex; align-items:center; gap:8px; }
.badge { display:inline-block; background:var(--bg); color:var(--muted); border:1px solid var(--line); border-radius:999px; padding:1px 8px; font-size:11px; font-weight:500; }
.table-wrap { overflow:auto; }
table { width:100%; border-collapse:collapse; }
th, td { padding:6px 10px; text-align:left; border-bottom:1px solid var(--line); font-size:13px; vertical-align:top; }
thead th { position:sticky; top:0; background:#eef2f7; color:#10222e; font-weight:600; }
tr.row-alert td { background:#fff5f5; }
.search { margin:0 0 12px 0; }
.search input { width:100%; padding:8px 10px; border:1px solid var(--line); border-radius:6px; font-size:13px; }
footer { color:var(--muted); font-size:12px; text-align:center; padding:12px 0; }
@media (max-width:900px) { .layout { grid-template-columns:1fr; } nav.toc { position:static; max-height:none; } }
</style>
</head>
<body>
<header class="banner">
  <h1>$encTitle</h1>
  <div>
    <span class="kpi $overallClass">$overall</span>
    <span class="kpi kpi-ok">OK $okCount</span>
    <span class="kpi kpi-alert">Alert $alertCount</span>
    $trendHtml
    <span class="meta">generated $generated</span>
  </div>
</header>
<div class="layout">
  <nav class="toc">
    <h3>Sections</h3>
    <ul>
$($navHtml.ToString())
    </ul>
  </nav>
  <main>
    <div class="search"><input type="search" id="q" placeholder="Filter rows in all sections..."></div>
$($sectionsHtml.ToString())
    <footer>SPSWeather standalone report - $generated</footer>
  </main>
</div>
<script>
(function(){
  var q=document.getElementById('q');
  q.addEventListener('input',function(){
    var t=q.value.toLowerCase();
    document.querySelectorAll('tbody tr').forEach(function(tr){
      tr.style.display = (t==='' || tr.textContent.toLowerCase().indexOf(t)>-1) ? '' : 'none';
    });
  });
})();
</script>
</body>
</html>
"@

    $page | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    return $OutputFile
}
