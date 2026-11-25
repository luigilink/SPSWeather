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
        A culture is only returned when its resource file really loads and is usable: it must parse
        as a data file, its Culture key must be its folder name, and every placeholder ({0}, {1}...)
        of a key must exist in the English text of that key (a placeholder that the code does not
        fill would make the formatting fail). A defective file is reported and English is used, so
        a translation that was edited by hand can never stop a run or silence an alert.
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
        [System.Object]
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

    # The value comes straight from a configuration file: a list (Language = @('fr-FR')) or a number
    # must not make the resolution throw, so it is turned into text first.
    $languageText = if ($Language -is [System.Array]) { ($Language | Select-Object -First 1) -as [string] } else { $Language -as [string] }
    $requested = if ([string]::IsNullOrWhiteSpace($languageText)) { $default } else { $languageText.Trim() }
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

    # A culture is only usable if its file loads and matches the reference.
    if ($culture -and $culture -ne $default) {
        $problem = $null
        try {
            $reference = Import-PowerShellDataFile -Path (Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath $default) -ChildPath $resourceFile) -ErrorAction Stop
            $overlay = Import-PowerShellDataFile -Path (Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath $culture) -ChildPath $resourceFile) -ErrorAction Stop
            if ($null -eq $overlay) {
                $problem = 'the file is empty'
            }
            elseif ([string]$overlay['Culture'] -ne [string]$culture) {
                $problem = "its Culture key is '$($overlay['Culture'])' instead of '$culture'"
            }
            else {
                foreach ($key in $overlay.Keys) {
                    if (-not $reference.ContainsKey($key)) { continue }
                    $allowed = @([regex]::Matches([string]$reference[$key], '\{(\d+)\}') | ForEach-Object -Process { $_.Groups[1].Value })
                    $used = @([regex]::Matches([string]$overlay[$key], '\{(\d+)\}') | ForEach-Object -Process { $_.Groups[1].Value })
                    $unknown = @($used | Where-Object -FilterScript { $allowed -notcontains $_ } | Sort-Object -Unique)
                    if ($unknown.Count -gt 0) {
                        $problem = "key '$key' uses {$($unknown -join '}, {')} which the English text does not provide"
                        break
                    }
                    # A stray brace would also make String.Format throw.
                    if (([string]$overlay[$key] -replace '\{\d+\}', '') -match '[{}]') {
                        $problem = "key '$key' contains a brace that is not a {n} placeholder"
                        break
                    }
                }
            }
        }
        catch {
            $problem = "the file cannot be read ($($_.Exception.Message))"
        }
        if ($problem) {
            [void]$messages.Add("Language '$culture' cannot be used: $problem; using $default.")
            $culture = $default
            $isFallback = $true
        }
    }

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
