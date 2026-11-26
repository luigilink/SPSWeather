# SPSWeather - Release Notes

## [2.4.1] - 2026-11-26

Patch release of the **2.x line** for SharePoint Server **2016 and 2019** (still compatible with **Subscription Edition**). It fixes
one defect that has been in every release since 2.0.0 (2.0.0 to 2.4.0, and 3.0.0 to 3.4.1): the **Failed timer jobs check never
reported a failure**. The same fix is in 3.5.0 (#126), brought here for 2016 and 2019 (#132).

### What was wrong

The collectors handed their parameters to the remote script block as the caller wrote them. A parameter that was left out and kept
its default reached the block empty. The entry script calls the Failed timer jobs collector without the look-back (24 hours) and the
failure threshold (5 %), so the look-back window was zero hours: no timer-job run was ever inside it and the check returned no row,
whatever the timer jobs did. The dashboard and the email showed the check as healthy.

### What changes

- **The Failed timer jobs check reports again.** A timer job that failed more often than 5 % of its runs over the last 24 hours now
  appears in the dashboard and in the alerts of the email. **A farm that has failing timer jobs will show a new warning at its first
  run with 2.4.1**: it is the check doing what its documentation says, not a new problem.
- Twelve other collectors (the SharePoint 2016/2019 AppFabric check among them) now hand the block the farm label they resolved. The
  entry script already wrote it in a run, so their results do not change; only a call by hand without `-Farm` now carries `SPS` instead
  of an empty label.
- Nothing else changes: same checks, same dashboards, same emails, same configuration, no new key.

### What has been tested

- The whole test suite passes on PowerShell 7 and on Windows PowerShell 5.1 (continuous integration), and the code analysis is clean.
- A test calls the Failed timer jobs collector the way the entry script does and checks the rows it returns; a second test reads every
  collector and checks that each default value it relies on reaches the remote block. Both fail on 2.4.0 and pass on 2.4.1.
- As for 2.4.0, **this release was not run on a real SharePoint 2016 or 2019 farm**: the lab has none. The 2016/2019 code path is the
  one of 2.3.7, and its only change here is the hand-over of the farm label. A report of what worked and what did not is very welcome
  (https://github.com/luigilink/SPSWeather/issues).

### How to update

Replace the `Modules` folder with the one of this archive and keep `Config\` and `Results\`. No change to the configuration is needed.
If you come from 2.3.7, read the [release notes of 2.4.0](https://github.com/luigilink/SPSWeather/releases/tag/v2.4.0) first: the
dashboards and the emails changed there.

### About the versions

The 3.x line (`main`) is for Subscription Edition only and gets the new features. This 2.x line is maintained for 2016 and 2019 and
gets the fixes that are asked for.

A full list of changes can be found in the [change log](CHANGELOG.md).
