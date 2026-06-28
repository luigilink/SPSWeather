function ConvertFrom-SPSSqlAliasValue {
    <#
        .SYNOPSIS
        Parses a single cliconfg alias registry value into its components.

        .DESCRIPTION
        A SQL client alias value has the form "<provider>,<connection-info>":
          - TCP/IP  (DBMSSOCN): "DBMSSOCN,server[\instance][,port]"
          - Named pipes (DBNMPNTW): "DBNMPNTW,\\server\pipe\sql\query"
        This helper splits that into provider, the real server, instance and port
        so callers do not duplicate the (slightly fiddly) parsing. It is kept
        separate from Resolve-SPSSqlAlias so the parsing can be unit-tested without
        a Windows registry.

        .PARAMETER AliasName
        The alias name (the registry value name).

        .PARAMETER RawValue
        The raw registry value data.

        .EXAMPLE
        ConvertFrom-SPSSqlAliasValue -AliasName 'SPSQL' -RawValue 'DBMSSOCN,SQLPROD01\SP,1433'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $AliasName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $RawValue
    )

    $providerCode = ''
    $protocol = 'Unknown'
    $server = ''
    $instance = ''
    $port = ''

    $parts = $RawValue -split ',', 2
    if ($parts.Count -ge 1) { $providerCode = $parts[0].Trim() }
    $remainder = if ($parts.Count -eq 2) { $parts[1].Trim() } else { '' }

    switch ($providerCode.ToUpperInvariant()) {
        'DBMSSOCN' {
            $protocol = 'TCP'
            # remainder = server[\instance][,port]
            $tcpParts = $remainder -split ','
            $target = $tcpParts[0].Trim()
            if ($tcpParts.Count -ge 2) { $port = $tcpParts[1].Trim() }
            if ($target -match '^(?<srv>[^\\]+)\\(?<inst>.+)$') {
                $server = $Matches['srv']
                $instance = $Matches['inst']
            }
            else {
                $server = $target
            }
        }
        'DBNMPNTW' {
            $protocol = 'NamedPipes'
            if ($remainder -match '^\\\\(?<srv>[^\\]+)\\') {
                $server = $Matches['srv']
            }
            if ($remainder -match '\\pipe\\MSSQL\$(?<inst>[^\\]+)\\') {
                $instance = $Matches['inst']
            }
        }
        default {
            # Unknown / other provider: keep the remainder as the server hint.
            $server = $remainder
        }
    }

    return [PSCustomObject]@{
        Alias    = $AliasName
        Provider = $providerCode
        Protocol = $protocol
        Server   = $server
        Instance = $instance
        Port     = $port
        Raw      = $RawValue
    }
}
