function Join-HtmlTable {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter()]
        [System.String]
        $TitleH1,

        [Parameter()]
        [System.String]
        $TableRole,

        [Parameter()]
        [System.String[]]
        $TableHeaders,

        [Parameter()]
        $TableRows
    )

    $bodyToMerge =
    @"
<h1>$TitleH1</h1>
<table role="$TableRole"><tr>
"@

    foreach ($tableHeader in $TableHeaders) {
        $bodyToMerge += "<td class=`"tdheader`">$tableHeader</td>"
    }
    $bodyToMerge += "</tr>$TableRows</table>"

    return $bodyToMerge
}
