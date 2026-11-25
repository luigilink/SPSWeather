function Resolve-SPSWeatherLanguage {
    <#
        .SYNOPSIS
        Resolves the configured language to a culture that ships display strings.

        .DESCRIPTION
        The dashboard and the alert email are rendered from resource files, one per culture, stored
        in <module>\<culture>\SPSWeather.Common.Strings.psd1. This function maps the value of the
        Language key of the environment configuration to one of the shipped cultures:
          - empty or not defined: en-US (the previous, English only, behavior);
          - 'auto': the UI culture of the current process;
          - an exact culture name (case-insensitive), e.g. 'fr-FR';
          - another culture of a shipped language, e.g. 'fr' or 'fr-BE' resolves to fr-FR;
          - anything else: en-US, with a message naming the available cultures.
        Resolving never fails because of a bad value: the run falls back to English instead.

        Returns Requested, Culture (the resolved culture), IsFallback, Available and Messages
        (the warnings to display).

        .PARAMETER Language
        The configured language: a culture name, 'auto', or nothing.

        .EXAMPLE
        Resolve-SPSWeatherLanguage -Language 'fr-FR'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Language
    )

    $default = 'en-US'
    $resourceFile = 'SPSWeather.Common.Strings.psd1'

    $available = @(Get-ChildItem -Path $script:ModuleRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object -FilterScript { Test-Path -Path (Join-Path -Path $_.FullName -ChildPath $resourceFile) } |
            Select-Object -ExpandProperty Name | Sort-Object)
    if ($available -notcontains $default) {
        throw "The reference resource file '$default\$resourceFile' is missing from '$script:ModuleRoot'."
    }

    $requested = if ([string]::IsNullOrWhiteSpace($Language)) { $default } else { $Language.Trim() }
    $isAuto = ($requested -ieq 'auto')
    $wanted = if ($isAuto) { [System.Globalization.CultureInfo]::CurrentUICulture.Name } else { $requested }

    $culture = $available | Where-Object -FilterScript { $_ -ieq $wanted } | Select-Object -First 1
    if (-not $culture -and $wanted) {
        # Same language, other region: 'fr' or 'fr-BE' -> fr-FR.
        $languageCode = ($wanted -split '[-_]')[0]
        $culture = $available | Where-Object -FilterScript { (($_ -split '-')[0]) -ieq $languageCode } | Select-Object -First 1
    }

    $messages = New-Object -TypeName System.Collections.ArrayList
    $isFallback = $false
    if (-not $culture) {
        $culture = $default
        $isFallback = $true
        # An 'auto' culture without translation is expected (English), not worth a warning.
        if (-not $isAuto) {
            [void]$messages.Add("Language '$requested' is not available (available: $($available -join ', ')); using $default.")
        }
    }

    return [PSCustomObject]@{
        Requested  = $requested
        Culture    = [string]$culture
        IsFallback = $isFallback
        Available  = $available
        Messages   = @($messages)
    }
}
