# SPSWeather - Release Notes

## [3.4.1] - 2026-11-26

Patch release: one dashboard bug fix, plus a new issue template and test changes that do not change the shipped scripts.

### Fixed

- **Dashboard: the `View detail →` link of an area card now opens the matching section.** It jumped to
  the section but left it collapsed, so nothing was shown (every card, since 3.1.0). A fragment link only
  reveals a `<details>` that contains its target, never the `<details>` that is the target, and the page
  had no script to open it. A small script now opens the targeted section when a card link is clicked
  (also a second time, after the user closed it) and when the page is opened with a `#d-<Section>`
  fragment, for example a link pasted in a mail or a chat. `Expand all` and `Collapse all` are unchanged.
  This changes the generated dashboard pages only: the emails, the JSON snapshots and the history are the
  same.

### Added

- Issue template **Translation Request**: ask for a new language for the dashboard and the alert email, or
  offer to help translate one. The wiki page *Localization* explains how to ask for a language and what a
  reviewer looks at.

### Changed

- Tests only: the language tests no longer assume which languages are shipped, and new tests prove that a
  language added later is picked up as soon as its folder exists. No change to the shipped module.

### Upgrade notes

- **No change is required.** No configuration key was added or changed. Replace the `Modules` folder and the
  scripts with the new ones (keep `Config\` and `Results\`); the dashboard pages are
  regenerated at the next run, so the fix shows after one run (an already generated page keeps the old
  behaviour until then).
