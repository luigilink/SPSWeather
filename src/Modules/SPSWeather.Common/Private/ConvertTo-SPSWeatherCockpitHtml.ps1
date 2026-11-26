function ConvertTo-SPSWeatherCockpitHtml {
    <#
        .SYNOPSIS
        Renders the dataset of the multi-farm page as one self-contained HTML document.

        .DESCRIPTION
        Fills the template of the Assets folder with its style sheet, its script, the dataset and the display strings of every
        shipped language. Nothing is loaded from outside the file. The JSON blocks are written so that no value can close the
        script element or open a comment, and the page itself escapes every value it displays. The page and its URL state
        are described in the wiki page Cockpit-Page.

        .PARAMETER Data
        The dataset from Get-SPSWeatherCockpitData.

        .PARAMETER Language
        The language the page opens in (a culture name, 'auto', or nothing for en-US).

        .PARAMETER Version
        The SPSWeather version shown in the page footer. Default: the module version.

        .EXAMPLE
        ConvertTo-SPSWeatherCockpitHtml -Data $data -Language 'fr-FR' -Version '3.5.0'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Data,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Language,

        [Parameter()]
        [System.String]
        $Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "$($MyInvocation.MyCommand.Module.Version)" }

    $assets = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets'
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    function _asset([string]$name) { [System.IO.File]::ReadAllText((Join-Path -Path $assets -ChildPath $name), $utf8) }
    function _json($value) {
        $json = ConvertTo-Json -InputObject $value -Depth 20 -Compress
        # Written as escapes: a value can never end the script element, open a comment or break a line of script
        return $json.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026').Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
    }

    $default = (Resolve-SPSWeatherLanguage -Language $Language).Culture
    $embedded = '^(Cockpit|Section_|Weather|Short|Legend|FarmCount|FarmStatus|FarmHealth|FarmLabel|AllClear|BarTip|CountsSummary|Percent|Generated)'
    $resourceFile = 'SPSWeather.Common.Strings.psd1'
    $cultures = [ordered]@{}
    foreach ($folder in @(Get-ChildItem -Path $script:ModuleRoot -Directory | Where-Object -FilterScript { Test-Path -Path (Join-Path -Path $_.FullName -ChildPath $resourceFile) } | Sort-Object -Property Name)) {
        $table = Get-SPSWeatherResource -Language $folder.Name
        $text = [ordered]@{}
        foreach ($key in @($table.Keys | Where-Object -FilterScript { $_ -match $embedded } | Sort-Object)) { $text[$key] = $table[$key] }
        $cultures[$folder.Name] = [ordered]@{ htmlLang = "$($table.HtmlLang)"; text = $text }
    }
    $page = [ordered]@{ version = $Version; language = $default; fallback = 'en-US'; cultures = $cultures }

    $title = '{0} {1} {2} / {3}' -f 'SPSWeather', [char]0x00B7, $Data.environment.application, $Data.environment.name
    $htmlLang = "$($cultures[$default].htmlLang)"

    $html = _asset 'Cockpit.html'
    $html = $html.Replace('{{HTMLLANG}}', [System.Net.WebUtility]::HtmlEncode($htmlLang))
    $html = $html.Replace('{{TITLE}}', [System.Net.WebUtility]::HtmlEncode($title))
    $html = $html.Replace('{{STYLE}}', (_asset 'Cockpit.css').TrimEnd())
    $html = $html.Replace('{{SCRIPT}}', (_asset 'Cockpit.js').TrimEnd())
    $html = $html.Replace('{{PAGE}}', (_json $page))
    $html = $html.Replace('{{DATA}}', (_json $Data))
    return $html
}
