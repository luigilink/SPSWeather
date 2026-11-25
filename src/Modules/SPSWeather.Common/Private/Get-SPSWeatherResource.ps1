function Get-SPSWeatherResource {
    <#
        .SYNOPSIS
        Loads the display strings of a language as one hashtable.

        .DESCRIPTION
        The reference culture (en-US) is always loaded first and the resolved culture is laid over it,
        so a key that a translation does not define shows the English text instead of an empty label.
        The language goes through Resolve-SPSWeatherLanguage: an unknown language gives the English
        strings. The returned table has a 'Culture' key holding the culture that was used.

        .PARAMETER Language
        A culture name, 'auto', or nothing (en-US). See Resolve-SPSWeatherLanguage.

        .EXAMPLE
        $text = Get-SPSWeatherResource -Language 'fr-FR'
        $text.AllClearTitle
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Language
    )

    $resourceFile = 'SPSWeather.Common.Strings.psd1'
    $culture = (Resolve-SPSWeatherLanguage -Language $Language).Culture

    $table = @{}
    $reference = Import-PowerShellDataFile -Path (Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'en-US') -ChildPath $resourceFile)
    foreach ($key in $reference.Keys) { $table[$key] = $reference[$key] }

    if ($culture -ne 'en-US') {
        $overlay = Import-PowerShellDataFile -Path (Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath $culture) -ChildPath $resourceFile)
        foreach ($key in $overlay.Keys) {
            if ($table.ContainsKey($key) -and -not [string]::IsNullOrEmpty([string]$overlay[$key])) { $table[$key] = $overlay[$key] }
        }
    }

    return $table
}
