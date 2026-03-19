# Change log for SPSWeather

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- scripts/Modules/sps.util.psm1
  - Update Get-SPSFailedTimerJob to evaluate timer job failures over a configurable lookback window instead of deduplicating failed entries only
  - Add failure ratio metrics per timer job: failed runs, total runs, failure percentage, threshold percentage, and IsInfo flag
  - Mark timer jobs below the default 5% failure threshold as informational to reduce false positives
- scripts/Modules/html.util.psm1
  - Extend the SharePoint Failed Timer Jobs report with failed runs, total runs, and failure rate columns
  - Render below-threshold timer job failures as warnings instead of hard failures

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
