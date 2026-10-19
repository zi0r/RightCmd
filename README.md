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

For a signature that survives rebuilds, sign with a real identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
```

### Distributing (Developer ID + notarization)

The app can't go in the Mac App Store (it needs a global event tap and private window‑server calls, neither of which survives the sandbox), so the route is Developer ID signing plus notarization, which Gatekeeper treats as fully trusted. One‑time setup: create a *Developer ID Application* certificate in your Apple Developer account and install it in your keychain, then store notarization credentials:

```sh
xcrun notarytool store-credentials RightCmd \
    --apple-id you@example.com --team-id TEAMID --password <app-specific password>
```

Then each release:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=RightCmd make dist
```

That builds a universal binary, signs it with the hardened runtime and a secure timestamp, submits it, waits for Apple's verdict, staples the ticket, runs a Gatekeeper assessment, and leaves `build/RightCmd-<version>.zip` ready to publish. No entitlements are needed: the hardened runtime's restrictions (library validation, no JIT, no unsigned memory) don't touch anything this app does, and Accessibility is granted by the user at runtime, not by entitlement.

`Packaging/AppIcon.icns` is the app icon; replace `Packaging/AppIcon-1024.png` and run `make icon` to regenerate it.

### Homebrew

There are two ways to ship through Homebrew, and which one fits depends on whether you have a Developer ID:

| | Cask (prebuilt `.app`) | Formula (built from source) |
| --- | --- | --- |
| Needs an Apple Developer account | Yes, for notarization — without it users must install with `--no-quarantine` | No |
| Gatekeeper | Clean when notarized | Clean: the binary is built locally, so it is never quarantined |
| Accessibility grant across upgrades | Persists (tied to Team ID + bundle id) | Must be re‑granted after each upgrade: the ad‑hoc signature's hash changes with every build |
| User needs Xcode 26 | No | Yes |
| Install | `brew install --cask you/tap/rightcmd` | `brew install you/tap/rightcmd` |

Both can live in the same tap under the same name; Homebrew picks by the `--cask` flag. The formula is the right choice if you won't be paying for a Developer ID; the cask is better for everyone else.

**Formula:** `Packaging/homebrew/rightcmd-formula.rb` builds the tagged source with `swift build`, assembles and ad‑hoc signs `RightCmd.app` inside the Homebrew prefix, and installs a `rightcmd` command that launches it. Its caveats tell users where the app is, how to copy it to /Applications, and about the Accessibility re‑grant. Releasing: push the `<version>` tag, then `make formula REPO=you/RightCmd TAP=you/tap` — that downloads GitHub's source tarball for the tag to compute the checksum, writes the formula, copies it into the local tap as `Formula/rightcmd.rb`, and runs `brew audit --strict --formula` and `brew style`. `brew install --build-from-source you/tap/rightcmd` then exercises it end to end before you push the tap.

**Cask:** `Packaging/homebrew/rightcmd.rb` installs the prebuilt, notarized `.app`. Releasing goes:

1. `make dist` → `build/RightCmd-<version>.zip`. (`make app` produces the same zip from an ad‑hoc build, enough to exercise the cask, but Gatekeeper will refuse an unsigned download on other Macs unless they install with `--no-quarantine`; use `make dist` for anything you publish.)
2. Create a GitHub release tagged `<version>` (e.g. `1.0.3`; set `TAG_PREFIX=v` on the `make` commands below if you prefer `v1.0.3`) and attach that zip, unrenamed.
3. `make cask REPO=you/RightCmd TAP=you/tap` — rewrites the cask with the version from `Info.plist` and the zip's SHA‑256, copies it into a local tap (created with `brew tap-new` if needed), and runs `brew audit --cask --strict` and `brew style` on it. Homebrew only audits and installs casks that live in a tap, not loose files, which is why the local tap exists.
4. Commit and push the tap directory (`$(brew --repository)/Library/Taps/you/homebrew-tap`) to a GitHub repo named `homebrew-tap`.

Users then install with `brew install --cask you/tap/rightcmd`, and `brew upgrade` follows your releases; the cask's `livecheck` block lets `brew livecheck` notice new tags. Homebrew's main repositories have a notability threshold (roughly 30+ stars or forks and a release history), so a personal tap is the right starting point for either file; note that `homebrew/core` would not accept the formula regardless, since core formulae don't install GUI apps — that restriction doesn't apply to your own tap.

Continuous integration: `.github/workflows/ci.yml` builds, tests and assembles an ad‑hoc bundle on a macOS 26 runner for every push and pull request. Signing and notarization stay local on purpose — they need your certificate and credentials.

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
| ← / → | *(with "Let ← and → reach the system" on)* passed through untouched, e.g. for ⌘← / ⌘→ Space shortcuts; ↑ / ↓ still cycle |
| Space | *(with "Let Space reach the system" on)* passed through untouched, for ⌘Space launchers |
| ⇧ / ⌥ / ⌃ + key | *(with "Pass through keys pressed with Shift, Option or Control" on)* passed through untouched, e.g. ⌘⇧P for a private window |
| ⎋ | Cancel (in "as you type" mode, returns to the app you came from) |
| ↩ | Confirm and stop listening (right ⌘ can stay held) |

**The key.** Right ⌘ is the default; Settings › General lets you use right ⌥ or right ⌃ instead. Whichever you choose becomes dedicated to switching while held (its left‑hand twin is untouched), and every pass‑through rule, the modifier‑delivery option and the menu bar tint follow it. Everything in this README that says right ⌘ applies to the key you picked.

**Switch modes** (menu bar › Switch, or Settings):

- **As You Type** (default) — the front app changes with every letter, exactly like the reference tool.
- **When Right ⌘ Is Released** — nothing moves until you let go, so `S`‑`E` never briefly shows Safari.

**Switch as soon as only one app matches** (on by default) ends the search the moment the typed letters are unambiguous: `right⌘ + X` jumps to Xcode on the first keystroke and ignores anything else you type until you let go. This is what makes the on‑release mode feel instant. Turn it off in Settings if you prefer to see the match before it happens.

**Move the pointer to the window you switch to** (off by default) places the pointer at the center of the target app's front window as soon as the switch is final: on a unique‑match commit, on Return, or otherwise on release — handy on large or multi‑monitor setups. It happens once per hold (not per letter in as‑you‑type mode), is skipped when the pointer is already inside that window or the window is minimised, and never after Escape.

**Switch Spaces instantly** (off by default) removes the slide animation when the app you switch to lives on another Space. RightCmd asks the window server which Space the app's front window is on; if it isn't the current one, it posts a synthetic trackpad swipe with near‑zero travel and a huge fling velocity — the technique from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) — so the Dock commits the Space change before any animation can run, then activates the app once the change is reported. It follows the system's own rule: no Space change if the app already has a window on the current Space. If the window is on a different display's Space, the pointer is moved to that display first, because the Dock applies swipes to the display under the pointer. This uses private `CGS`/SkyLight calls resolved at runtime; on a macOS that lacks them the toggle is disabled and activation works as before. Mission Control must not be open for the swipe to register; if it fails, the app still activates with the normal animation after 0.4s. In as‑you‑type mode, an activation that arrives while a jump is still landing is queued and planned once the Space change is reported, so fast typing across Spaces can't overshoot.

**Menu bar icon** (on by default) tints the icon while right ⌘ is held: blue while listening, green once the letters match an app, red when they match nothing, and orange whenever keys are being passed through rather than interpreted — a pass‑through key is down, or a modifier combination the pass‑through settings cover (such as `right⌘ ⇧`) is held — returning to the session colour when that ends. The colour lingers for half a second after you let go so a quick switch still shows its result. All four colours are configurable in Settings; it's a quick confirmation that works even with the overlay turned off.

**Matching** is case‑ and accent‑insensitive and ranks results deterministically so the same keys always land on the same app:

1. name starts with the letters (`sa` → Safari)
2. a later word starts with them (`ch` → Google **Ch**rome)
3. initials (`vsc` → **V**isual **S**tudio **C**ode)

Within a tier results are alphabetical. Type more letters, or use the arrow keys, to disambiguate.

**Other names and aliases.** Every app is matched under all the names macOS has for it — the localized name you see, the bundle's file name, and its `CFBundleName`/`CFBundleDisplayName` when they differ — so a localised or renamed app answers to both. For names only you use, add an **alias** (Settings › Matching › Aliases): pick the running app (stored by bundle id) and type comma‑separated names. Microsoft's "Windows App" can keep answering to "Microsoft Remote Desktop" or "rdp" that way. Aliases match at the same tiers as the real name, never cause a non‑matching app to appear, and the overlay notes which alias a match came through (`as “Microsoft Remote Desktop”`). Exclusion and priority patterns also match the alternate names.

**Priority apps** (Settings › Priorities) let you put your own apps first. Anything on the list that matches what you typed outranks every other match, in list order — so with Slack at the top, `S` goes to Slack even though Safari sorts first alphabetically, and with Chrome listed, `C` prefers Chrome over an app whose *name* starts with "C". Priority never adds an app that doesn't match. Add apps from the running-app menu (stored by bundle id, so renames and localisation don't matter) or type a name/bundle‑id pattern; reorder with the arrows. Prioritised matches show a small pin in the overlay.

**Deprioritized apps** are the mirror image: anything on that list still matches and is still switchable, but ranks after every other match (list order among themselves), so a helper app that shares a first letter with something you use constantly never wins a tie — type one more letter, or let it be the only match, and it's reachable as ever. An app on both lists counts as a priority app. Deprioritised matches show a small down‑arrow in the overlay.

**Settings** (menu bar › Settings…) are organised in five tabs: *General* (activator key, switch mode, commit on unique match, prefer another app, move the pointer, ←/→, Space and modified‑key pass‑through, modifier delivery, instant Space switching, launch at login, permission status), *Matching* (word‑prefix and initials matching, aliases), *Priorities* (the priority and deprioritized lists), *Appearance* (overlay, menu bar icon tint and colours), and *Exclusions* (Finder opt‑in, wildcard patterns such as `com.apple.*`).

### Things to know

- The overlay appears on the display under the mouse pointer, so it follows you across monitors.
- If the right ⌘ *release* is ever missed (the tap was disabled at that instant, a modal dialog was up, a remapper misbehaved), RightCmd notices within half a second by checking the live modifier state, or immediately on the next key press, and lets go. It can't leave your keyboard swallowed.
- Revoking or re‑granting Accessibility, sleeping, or locking the screen is handled without a relaunch.

- Right ⌘ becomes a dedicated switcher key: `right⌘ + C` no longer copies. Left ⌘ is untouched. Three opt‑in exceptions: *Let ← and → reach the system* passes those two keys through (down, up and auto‑repeat) so shortcuts such as Mission Control's "move left/right a Space" bound to ⌘← / ⌘→ keep working while right ⌘ is held; *Let Space reach the system* does the same for Space (⌘Space launchers); and *Pass through keys pressed with Shift, Option or Control* passes any key that has a second modifier down (or both ⌘ keys), so ⌘⇧P and friends reach the front app. In both cases the switcher session simply continues. Note that with the second one on, Shift is no longer ignored while typing app names — type with right ⌘ alone.
- By design the right ⌘ *modifier* event itself is swallowed too, so apps see passed‑through keys with the ⌘ flag but never see ⌘ go down. That satisfies key‑equivalent matching (Firefox's ⌘⇧P works), but an app that reacts to the modifier being held — ⌘‑hover link underlining in terminals, temporary tool modes, menu alternates — needs the modifier delivered. *Let apps see right ⌘ itself* does that; leave it off unless something misbehaves, since a bare ⌘ press also fires "double‑tap ⌘" launchers. Press and release are always delivered as a pair, even if the setting changes mid‑hold.
- Space and Tab are intentionally ignored while right ⌘ is held (⌘Space and ⌘Tab are system hotkeys). Word‑prefix matching means you never need a space anyway. *Let Space reach the system* hands Space on instead, for ⌘Space launchers.
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

Sources/SpaceSwitchKit    C: Space lookup via SkyLight (dlsym) + instant swipe posting,
                          adapted from InstantSpaceSwitcher (MIT)

Sources/RightCmd          Thin AppKit shell (no business logic)
  EventTap               CGEventTap wrapper (keyDown/keyUp/flagsChanged), swallows keys while active
  KeyboardLayoutTranslator  UCKeyTranslate against the current input source
  RunningApps            NSWorkspace‑based app discovery, secure‑input check
  AppActivator           AX frontmost + NSRunningApplication activation
  SpaceSwitcher          decides whether a Space jump is needed, performs it, activates after
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

About 150 XCTest cases cover the matcher (tiers, ordering, case/diacritic folding, option toggles, priority lists), the full session state machine in both switch modes (typing, backspace, Escape restore, Return, cycling, no‑match, unique‑match commit, pointer‑move timing, secure input, interruption, candidate snapshotting), key classification and pass‑through rules, right‑⌘ detection from modifier flags, wildcard exclusions, the Space‑switch planner, colour parsing, and settings persistence including forward‑compatible decoding.

The AppKit layer is intentionally thin and is verified manually: hold right ⌘ and type, check the overlay follows, revoke and re‑grant Accessibility in System Settings, confirm the menu bar status updates, and (with instant Space switching on) switch to an app two Spaces away, to a full‑screen app, and to one with windows on both the current and another Space.

Logs: `log stream --predicate 'subsystem == "com.rightcmd.app"' --level debug`

## Troubleshooting

**Nothing happens when I hold right ⌘.** Check the menu bar item — it says whether Accessibility is granted and the event tap is running. If you rebuilt an ad‑hoc‑signed app, macOS silently dropped the permission because the signature changed: remove RightCmd from the Accessibility list and add it again, or sign with a stable identity.

**Letters don't register but the overlay appears.** Secure input is on (a password field is focused somewhere, or an app like a password manager left it enabled). The overlay shows a lock icon in this state.

**Right ⌘ isn't detected with Karabiner‑Elements or another remapper.** RightCmd identifies the key by its key code (0x36) and, when present, the right‑⌘ device flag. Make sure the remapper emits a genuine right command key rather than a generic ⌘.

**The app I want is excluded.** Only apps with a Dock presence (regular activation policy) are offered, the same set as ⌘‑Tab. Finder is left out by default because it is always running and would otherwise claim `F`; switch on *Include Finder* in Settings › Excluded apps if you want it. Check your own exclusion patterns there as well.

## License

MIT — see `LICENSE`. `Sources/SpaceSwitchKit` includes code adapted from and vendored verbatim from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher), © jurplel, MIT; its license is reproduced in `Sources/SpaceSwitchKit/LICENSE-InstantSpaceSwitcher`.
