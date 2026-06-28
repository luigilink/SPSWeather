# Change log for SPSWeather

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-06-28

This is a major modernization release. The flat helper modules become a real
`SPSWeather.Common` PowerShell module, the embedded CredentialManager dependency
is replaced by a DPAPI `secrets.psd1`, the configuration moves to a `.psd1` data
file, and the tool gains Windows Event Log instrumentation. See the migration
notes in `RELEASE-NOTES.md`.

### Added

- `src/Modules/SPSWeather.Common/` — a proper module with a manifest, a loader
  that dot-sources `Private/` then `Public/`, and a Public/Private split (one file
  per function). `ModuleVersion` is the single source of truth for the version (#3, #4).
- `.gitattributes`, `.editorconfig` and `PSScriptAnalyzerSettings.psd1` to enforce
  the UTF-8 BOM + CRLF (PowerShell) / LF (yml, md, json) encoding policy and lint
  rules (#2).
- Cross-platform Pester structural test suite and a `pester.yml` CI workflow
  running Pester and PSScriptAnalyzer on pull requests (#5).
- DPAPI credential store: `Get-SPSSecret` / `Set-SPSSecret`, `Config/secrets.psd1`
  (gitignored) and `Config/secrets.example.psd1` (#9).
- `Add-SPSWeatherEvent` and a dedicated `SPSWeather` Windows Event Log; the entry
  script emits start (1000), completion (1001), ALERT (2000) and email-failure
  (3000) events (#10).
- `wiki/_Sidebar.md` and `wiki/Release-Process.md`; the whole wiki was rewritten
  for the 2.0.0 layout (#11).
- `Get-SPSFailedTimerJob` now evaluates failures over a configurable lookback
  window with failure-ratio metrics (failed runs, total runs, failure percentage,
  threshold percentage, IsInfo), and the report gained the matching columns.

### Changed

- Move the script tree from `scripts/` to `src/` (#3).
- `SPSWeather.ps1` imports the `SPSWeather.Common` manifest instead of the
  `util.psm1` chain and derives its displayed version from `ModuleVersion` (#4).
- Migrate the environment configuration from JSON to a `.psd1` data file read with
  `Import-PowerShellDataFile`; the `StoredCredential` field becomes `CredentialKey` (#8).
- `Join-HtmlBodyFromPSo` builds a self-contained HTML document with email-optimized
  CSS (no reliance on caller-scope variables) (#7).
- `release.yml` packages the contents of `src/` so the ZIP extracts straight to
  `SPSWeather.ps1`, `Config/` and `Modules/` (#6).
- `Remove-SPSSheduledTask` now declares `SupportsShouldProcess` (#3).
- Below-threshold timer-job failures are rendered as warnings instead of hard
  failures.

### Removed

- The embedded third-party CredentialManager dependency (signed DLLs + UTF-16
  manifest) and all Windows Credential Manager usage, replaced by the DPAPI
  `secrets.psd1` store (#9).
- The legacy flat `scripts/Modules/*.util.psm1` helper modules (#3).

### Fixed

- Restore the report's HTML `<head>`/CSS wrapper that previously lived in the
  `html.util.psm1` module scope and was otherwise lost in the module split (#7).

## [1.0.3] - 2023-10-16

### Added

- scripts/SPSWeather.ps1 - Add Installation process:

  - New parameters: Install, Uninstall and InstallAccount
  - New functions: Add-SPSSheduledTask and Remove-SPSSheduledTask

- Wiki Documentation in repository - Add :
  - wiki/Configuration.md
  - wiki/Getting-Started.md
  - wiki/Home.md
  - wiki/Usage.md
  - .github/workflows/wiki.yml

### Changed

- scripts/SPSWeather.ps1 - Remove ExclusionRules parameter
- scripts/Config/CONTOSO-PROD.json - Add ExclusionRules parameter

## [1.0.2] - 2023-10-10

### Added

- README.md
  - Add code_of_conduct.md badge
- Add CODE_OF_CONDUCT.md file
- Add Issue Templates files:
  - 1_bug_report.yml
  - 2_feature_request.yml
  - 3_documentation_request.yml
  - 4_improvement_request.yml
  - config.yml

### Changed

- release.yml
  - Zip scripts folder and mane it with Tag version
- PULL_REQUEST_TEMPLATE.md => Remove examples and unit test tasks

## [1.0.1] - 2023-10-09

### Changed

- README.md
  - Add Requirement and Changelog sections

### Added

- Add RELEASE-NOTES.md file
- Add CHANGELOG.md file
- Add CONTRIBUTING.md file
- Add release.yml file
- Add scripts folder with first version of SPSWeather
