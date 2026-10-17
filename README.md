# RightCmd

A native Swift app switcher for macOS 26. Hold the **right ⌘** key and type the first letters of an app's name:

- `right⌘ + S` → the first app whose name starts with **S** (e.g. Safari)
- `right⌘ + S E` → an app whose name starts with **SE** (e.g. Sequel Ace)
- `right⌘ + V S C` → Visual Studio Code (initials also work)

Release right ⌘ and you're there. No Dock icon, no windows — just a menu bar item.

It is inspired by [takeiteasy/rcmd](https://github.com/takeiteasy/rcmd) (an Objective‑C tool) and, like that project, has no connection to the commercial *rcmd* app.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 / Swift 6.x toolchain to build
- Accessibility permission (requested on first launch)

## Build and install

```sh
make test       # run the unit tests
make app        # build/RightCmd.app, ad-hoc signed
make install    # copies it to /Applications
```

The bundle identifier is `com.rightcmd.app` (in `Packaging/Info.plist` and `project.yml`); change it to your own reverse‑DNS name before signing with a real identity.

For a signature that survives rebuilds (and for notarization), sign with a real identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
```

Or open the package in Xcode (`open Package.swift`) for day‑to‑day development, or generate a full Xcode project with `make xcodeproj` (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)).

`swift run RightCmd` also works for quick experiments; launch‑at‑login is only available from the `.app` bundle.

### First launch

macOS will ask for **Accessibility** permission. RightCmd needs it to observe keystrokes system‑wide and to bring other apps to the front. Grant it in *System Settings › Privacy & Security › Accessibility*; the app notices within a couple of seconds and starts without a relaunch. The menu bar item reports the current state.

## Usage

| Keys (while holding right ⌘) | Effect |
| --- | --- |
| letters / digits | Narrow the match |
| ⌫ | Remove the last letter |
| ↓ / → | Select the next matching app |
| ↑ / ← | Select the previous matching app |
| ⎋ | Cancel (in "as you type" mode, returns to the app you came from) |
| ↩ | Confirm and stop listening (right ⌘ can stay held) |

**Switch modes** (menu bar › Switch, or Settings):

- **As You Type** (default) — the front app changes with every letter, exactly like the reference tool.
- **When Right ⌘ Is Released** — nothing moves until you let go, so `S`‑`E` never briefly shows Safari.

**Switch as soon as only one app matches** (on by default) ends the search the moment the typed letters are unambiguous: `right⌘ + X` jumps to Xcode on the first keystroke and ignores anything else you type until you let go. This is what makes the on‑release mode feel instant. Turn it off in Settings if you prefer to see the match before it happens.

**Menu bar icon** (on by default) tints the icon while right ⌘ is held: blue while listening, green once the letters match an app, red when they match nothing. The colour lingers for half a second after you let go so a quick switch still shows its result. All three colours are configurable in Settings; it's a quick confirmation that works even with the overlay turned off.

**Matching** is case‑ and accent‑insensitive and ranks results deterministically so the same keys always land on the same app:

1. name starts with the letters (`sa` → Safari)
2. a later word starts with them (`ch` → Google **Ch**rome)
3. initials (`vsc` → **V**isual **S**tudio **C**ode)

Within a tier results are alphabetical. Type more letters, or use the arrow keys, to disambiguate.

**Settings** (menu bar › Settings…) let you change the mode, overlay position, icon tint and colours, matching strategies, exclude apps by name or bundle id with wildcards (`com.apple.*`), opt Finder back in, prefer a *different* app when the best match is already in front, and enable launch at login.

### Things to know

- The overlay appears on the display under the mouse pointer, so it follows you across monitors.
- If the right ⌘ *release* is ever missed (the tap was disabled at that instant, a modal dialog was up, a remapper misbehaved), RightCmd notices within half a second by checking the live modifier state, or immediately on the next key press, and lets go. It can't leave your keyboard swallowed.
- Revoking or re‑granting Accessibility, sleeping, or locking the screen is handled without a relaunch.

- Right ⌘ becomes a dedicated switcher key: `right⌘ + C` no longer copies. Left ⌘ is untouched.
- Space and Tab are intentionally ignored while right ⌘ is held (⌘Space and ⌘Tab are system hotkeys). Word‑prefix matching means you never need a space anyway.
- When a password field has focus, macOS enables *secure input* and no app can read keystrokes. The overlay tells you when this is the case.
- Keyboard layouts are respected: letters are resolved through the active input source, not a fixed US table.

## Architecture

```
Sources/RightCmdCore      Pure Swift, Foundation only, fully unit tested
  AppMatcher             prefix / word / initials ranking
  SwitchSession          the hold‑and‑type state machine → [SessionAction]
  KeyInput               key classification, right‑⌘ detection from CGEventFlags
  Settings               Codable settings + UserDefaults store
  ExclusionList          wildcard patterns

Sources/RightCmd          Thin AppKit shell (no business logic)
  EventTap               CGEventTap wrapper (keyDown/keyUp/flagsChanged), swallows keys while active
  KeyboardLayoutTranslator  UCKeyTranslate against the current input source
  RunningApps            NSWorkspace‑based app discovery, secure‑input check
  AppActivator           AX frontmost + NSRunningApplication activation
  SwitchCoordinator      tap → SwitchSession → overlay / activation
  OverlayPanel           non‑activating NSPanel hosting a SwiftUI view
  StatusMenuController, SettingsWindow, LaunchAtLogin, AppDelegate
```

Two naming notes for anyone extending the AppKit layer: `RightCmdCore.Settings` is written out in files that import SwiftUI (which has its own `Settings` scene), and the colour type is `SRGBColor` because ApplicationServices still exports QuickDraw's `RGBColor`.

The split is deliberate: everything that decides *what should happen* lives in `RightCmdCore` and is exercised by `swift test` without a display, permissions, or a running window server. The AppKit layer only translates system events in and carries actions out.

Compared with the reference implementation, this version:

- enumerates apps with `NSWorkspace` (not `CGWindowListCopyWindowInfo`), so no Screen Recording permission is needed and apps without visible windows still work;
- taps only keyboard events instead of every event, and re‑enables the tap if macOS disables it;
- reacts on key‑down (ignoring auto‑repeat) rather than key‑up, so switching feels immediate;
- uses prefix matching, as specified, rather than Levenshtein fuzzy matching, and makes the ranking deterministic;
- resolves characters through the active keyboard layout;
- never runs as root, and activates apps through the Accessibility API, which is what works on macOS 14+.

## Testing

```sh
swift test
```

The suite covers the matcher (tiers, ordering, case/diacritic folding, option toggles), the full session state machine in both switch modes (typing, backspace, Escape restore, Return, cycling, no‑match, secure input, interruption, candidate snapshotting), key classification, right‑⌘ detection from modifier flags, wildcard exclusions, and settings persistence including forward‑compatible decoding.

The AppKit layer is intentionally thin and is verified manually: hold right ⌘ and type, check the overlay follows, revoke and re‑grant Accessibility in System Settings, and confirm the menu bar status updates.

Logs: `log stream --predicate 'subsystem == "com.rightcmd.app"' --level debug`

## Troubleshooting

**Nothing happens when I hold right ⌘.** Check the menu bar item — it says whether Accessibility is granted and the event tap is running. If you rebuilt an ad‑hoc‑signed app, macOS silently dropped the permission because the signature changed: remove RightCmd from the Accessibility list and add it again, or sign with a stable identity.

**Letters don't register but the overlay appears.** Secure input is on (a password field is focused somewhere, or an app like a password manager left it enabled). The overlay shows a lock icon in this state.

**Right ⌘ isn't detected with Karabiner‑Elements or another remapper.** RightCmd identifies the key by its key code (0x36) and, when present, the right‑⌘ device flag. Make sure the remapper emits a genuine right command key rather than a generic ⌘.

**The app I want is excluded.** Only apps with a Dock presence (regular activation policy) are offered, the same set as ⌘‑Tab. Finder is left out by default because it is always running and would otherwise claim `F`; switch on *Include Finder* in Settings › Excluded apps if you want it. Check your own exclusion patterns there as well.

## License

MIT — see `LICENSE`.
