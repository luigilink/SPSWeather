# Release Process

This page documents how to ship a new version of SPSWeather. The process is centered on a single source of truth — the `ModuleVersion` field of `SPSWeather.Common.psd1` — and a `v*` git tag that triggers the GitHub release workflow.

## Versioning policy

SPSWeather follows [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html).

| Bump | When |
|---|---|
| MAJOR (X.0.0) | Breaking change in the `.psd1` config/secrets format, the package layout, or a public module function signature. |
| MINOR (X.Y.0) | New backward-compatible feature (new check, new public function, new optional setting). |
| PATCH (X.Y.Z) | Bug fix or documentation-only change. |

## Release checklist

### 1. Bump the version

Edit **one** value in `src/Modules/SPSWeather.Common/SPSWeather.Common.psd1`:

```powershell
ModuleVersion = '2.0.0'   # was '1.0.3'
```

This single change propagates automatically to:

- The script banner (`$spsWeatherVersion` is read from `(Get-Module SPSWeather.Common).Version`)
- The `SPSWeather` Event Log header (`SPSWeather Version: 2.0.0`)
- The `Get-Module SPSWeather.Common` version surfaced to users

### 2. Promote `[Unreleased]` in `CHANGELOG.md`

Move the `[Unreleased]` block to a dated section for the version being released and add a fresh empty `[Unreleased]` heading on top:

```markdown
## [Unreleased]

## [2.0.0] - 2026-MM-DD

### Added
...
```

### 3. Replace `RELEASE-NOTES.md`

`RELEASE-NOTES.md` is used **verbatim** as the body of the GitHub Release. It must contain **only** the section of the version being released (no `[Unreleased]` header).

### 4. Validate locally

```powershell
Import-Module .\src\Modules\SPSWeather.Common\SPSWeather.Common.psd1 -Force
(Get-Module SPSWeather.Common).Version    # should match the bumped version
Invoke-Pester -Path .\tests
Invoke-ScriptAnalyzer -Path .\src\Modules\SPSWeather.Common -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

### 5. Commit on a release branch

```bash
git checkout -b release/2.0.0
git add -A
git commit -m "release: v2.0.0"
git push -u origin release/2.0.0
```

Open a Pull Request, review, merge to `main`.

### 6. Tag from `main`

```bash
git checkout main
git pull
git tag v2.0.0
git push origin v2.0.0
```

The `.github/workflows/release.yml` workflow runs automatically. It:

1. Packages the **contents** of `src/` into `SPSWeather-v2.0.0.zip` (the archive extracts straight to `SPSWeather.ps1`, `Config\` and `Modules\`, with no `src/` wrapper).
2. Publishes a GitHub Release using `RELEASE-NOTES.md` as the body.
3. Attaches the ZIP and `LICENSE` to the release.

### 7. Verify

- **Releases**: <https://github.com/luigilink/SPSWeather/releases> — the new release is listed with the expected body and ZIP.
- **Actions**: <https://github.com/luigilink/SPSWeather/actions> — `release.yml` and `pester.yml` ran green.
- **Wiki**: <https://github.com/luigilink/SPSWeather/wiki> — `wiki.yml` synced any `wiki/` changes pushed in the same release.

## Undoing a release

If you tagged too early:

```bash
git tag -d v2.0.0
git push origin --delete v2.0.0
```

Then delete the auto-created Release on GitHub, fix what needs fixing, commit, and re-tag from the new HEAD.

> ⚠️ **Don't move a published tag** that has been live for more than a few minutes. Prefer publishing a `vX.Y.(Z+1)` patch release instead of rewriting `vX.Y.Z`.

## See also

- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html)
- [Configuration reference](Configuration)
- [Usage](Usage)
