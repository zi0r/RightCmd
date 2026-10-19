# Changelog

## Unreleased

### Added
- A fourth icon colour, **Passing keys through** (orange by default), shown while a
  pass‑through key is down or a pass‑through modifier combination is held; the icon
  returns to the session colour when that ends. Saved colour sets from earlier versions
  pick up the default for it.

### Fixed
- The key‑up of a passed‑through key is now handed on even if the qualifying modifier was
  released first (e.g. letting go of ⇧ before P in ⌘⇧P), so the receiver never sees an
  unbalanced key press.

## 1.0.2 — 2026-10-17

### Added
- **Deprioritized apps**: the mirror of the priority list. Apps on it still match and are
  still switchable, but rank after every other match (list order among themselves); an app
  on both lists counts as prioritised. Marked with a down‑arrow in the overlay. The two
  lists share one editor in Settings › Matching.
- **Let Space reach the system**: passes ⌘Space through for Spotlight/Raycast/Alfred‑style
  launchers, alongside the existing ←/→ pass‑through.

- App icon, and a `make dist` target that notarizes and staples a Developer ID build.
- Homebrew cask template with `make cask` to pin version and checksum per release; CI
  workflow that builds and tests on macOS 26.

### Changed
- `RankedMatch` reports a `MatchPlacement` (prioritised / normal / deprioritised);
  `priorityRank` remains as a derived property.

## 1.0.1 — 2026-10-16

The first version that has been built and used on macOS 26; everything below was added or
fixed against real use after the initial 1.0.0 drop.

### Added
- **Switch as soon as only one app matches** (on by default): the hold ends the moment the
  typed letters are unambiguous, in both switch modes.
- **Menu bar icon state** with configurable colours: blue while listening, green on a match,
  red on no match, lingering briefly after release. Colours are rendered into the icon
  bitmap because macOS 26 ignores `contentTintColor` for menu bar items.
- **Priority apps**: an ordered list that outranks every other match, with an
  add‑running‑app menu and a pin marker in the overlay.
- **Include Finder** toggle (off by default); Finder is otherwise excluded as a built‑in
  rule kept separate from user patterns.
- **Move the pointer to the window you switch to**, fired as soon as the switch is final.
- **Switch Spaces instantly** when the target window is on another Space, using the
  InstantSpaceSwitcher synthetic‑swipe technique; private symbols resolved at runtime,
  activation held until the Space change is reported, in‑flight requests queued and
  re‑planned.
- **Pass‑through settings**: ←/→ to the system, keys pressed with ⇧/⌥/⌃ to the front app,
  and delivery of the right ⌘ modifier itself for apps that react to it.
- Tabbed settings window (General / Matching / Appearance / Exclusions), sized per pane.

### Fixed
- A missed right‑⌘ release could leave every keystroke swallowed; now self‑heals from the
  flags on any later event and from a HID‑state watchdog.
- Revoking and re‑granting Accessibility, sleep and screen lock no longer need a relaunch.
- Overlay appears on the display under the pointer and no longer grows with long names.
- Settings window collapsed to its title bar (grouped forms have no intrinsic height).
- Several Tahoe/SDK naming clashes (`Settings`, `RGBColor`, `UniCharCount`).

## 1.0.0

Initial Swift port of the reference Objective‑C tool.
