# SPSWeather - Release Notes

## [2.0.0] - 2026-06-28

A major modernization release. The flat helper modules become a real
`SPSWeather.Common` PowerShell module, credentials move to a DPAPI-encrypted
`secrets.psd1` (no third-party module), the configuration becomes a `.psd1`
data file, the HTML report is rebuilt for email, and the tool gains a dedicated
Windows Event Log.

### Added

- `SPSWeather.Common` module (manifest + loader + Public/Private split); the
  manifest `ModuleVersion` is the single source of truth for the version.
- Encoding/lint configuration (`.gitattributes`, `.editorconfig`,
  `PSScriptAnalyzerSettings.psd1`) and a Pester + PSScriptAnalyzer CI workflow.
- DPAPI credential store (`Get-SPSSecret` / `Set-SPSSecret`, `secrets.psd1`).
- `Add-SPSWeatherEvent` and a dedicated `SPSWeather` Windows Event Log
  (start 1000, completion 1001, ALERT 2000, email failure 3000).
- Rewritten wiki with a sidebar and a Release Process page.

### Changed

- Script tree moved from `scripts/` to `src/`; the release ZIP now extracts
  straight to `SPSWeather.ps1`, `Config/` and `Modules/`.
- Configuration migrated from JSON to a `.psd1` data file
  (`Import-PowerShellDataFile`); the `StoredCredential` field becomes
  `CredentialKey`.
- The HTML report is self-contained and optimized for email delivery.

### Removed

- The embedded CredentialManager dependency (DLLs + UTF-16 manifest) and all
  Windows Credential Manager usage.

### Upgrade / breaking changes

- **Configuration**: convert your `*.json` config to `*.psd1`
  (see `Config/CONTOSO-PROD.example.psd1`) and rename `StoredCredential` to
  `CredentialKey`. Call the script with `-ConfigFile 'Config\contoso-PROD.psd1'`.
- **Credentials**: re-run `-Install` **as the service account** to populate
  `Config\secrets.psd1`, or generate the entry manually with
  `Read-Host -AsSecureString | ConvertFrom-SecureString`. The DPAPI value is
  bound to the account and machine that created it.
- **Layout**: the entry point is now `src/SPSWeather.ps1` in the source tree; the
  release ZIP keeps `SPSWeather.ps1` at its root.

A full list of changes can be found in the [change log](CHANGELOG.md).
