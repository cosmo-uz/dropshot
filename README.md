# Dropshot

A small macOS menu bar app that fixes the screenshot flow.

Take a screenshot the way you always do (⌘⇧3, ⌘⇧4, ⌘⇧5). Dropshot then:

- **copies it to the clipboard** straight away, as an image and as a file;
- **keeps it off your Desktop**, filed in `~/Pictures/Screenshots/YYYY/MM/DD/`;
- **drops a preview out of the notch** for about 4 seconds, which you can drag into any app;
- **remembers what you copied**: press ⇧⌘V anywhere for a clipboard history, like Windows+V.

No Screen Recording permission, no analytics, no network access. macOS 14 or later, Apple
Silicon and Intel.

> **Status: early (v0.1).** It works on the author's Mac but has had little real-world
> testing. Expect rough edges; see [Known problems](#known-problems). Bug reports and pull
> requests are welcome.

## Install

### Download

Get `Dropshot.dmg` from the [latest release](https://github.com/cosmo-newuu/dropshot/releases/latest),
open it and drag Dropshot to Applications.

The download is **not notarized by Apple** yet, so macOS blocks it the first time. After
dragging it to Applications, run this once:

```bash
xattr -dr com.apple.quarantine /Applications/Dropshot.app
```

Then open Dropshot normally. (Alternatively: try to open it, then go to System Settings →
Privacy & Security and click **Open Anyway**.)

### Build from source

You need Xcode 16 or later and [Homebrew](https://brew.sh).

```bash
brew install xcodegen create-dmg
```

```bash
git clone https://github.com/cosmo-newuu/dropshot.git && cd dropshot
```

```bash
make release
```

This writes `dist/Dropshot.dmg`. To try it without installing, use `make run`.

## First launch

Three setup screens ask before changing anything in macOS:

1. What Dropshot does.
2. **Move screenshots off your Desktop?** Pick a folder; Dropshot tells macOS to save there.
3. **Turn off the macOS floating thumbnail?** While it is on, macOS holds each screenshot
   back for about 5 seconds, which delays the clipboard and the preview.

Both changes can be undone at any time in **Settings → About → Restore macOS Defaults…**,
which puts the system settings back exactly as they were.

## How to use it

### Screenshots

Just take one. The preview appears from the notch (or as a black pill at the top of a
display without a notch).

| Do this | What happens |
|---|---|
| Press ⌘V | Pastes the screenshot. It is already on the clipboard |
| Drag the thumbnail | Drops the file into Telegram, Finder, Slack, Figma, a browser… |
| Click the thumbnail | Opens the screenshot |
| Hover over the preview | Keeps it open and shows Open, Show in Finder, Move to Trash |
| Take several in a row | They stack with a count badge, newest on top |

Screen recordings (⌘⇧5) are filed and previewed the same way; the clipboard gets the file.

### Clipboard history

Press **⇧⌘V** in any app. A panel under the notch lists the last 30 things you copied:
text, images and files.

| Key | Action |
|---|---|
| ↑ ↓ then Return | Choose an entry |
| 1–9 | Choose that entry directly |
| ⌫ | Remove the selected entry |
| Esc | Close |

Choosing an entry puts it on the clipboard; press ⌘V to paste. To have Dropshot paste for
you, turn on **Settings → General → Paste the chosen item directly** and grant the
Accessibility permission when macOS asks.

History is kept in memory only and is forgotten when Dropshot quits. Entries that password
managers mark as secret are not recorded. If ⇧⌘V clashes with "Paste and Match Style" in an
app you use, switch the shortcut to ⌃⌘V or ⌥⌘V in Settings.

### Menu bar

The menu bar icon has Settings…, Open Screenshots Folder, Clipboard History, Pause and
Quit. If you hide the icon, open Dropshot again from Finder or Spotlight to reach Settings.

### Settings

- **General:** launch at login, pause, clipboard history and its shortcut, menu bar icon.
- **Screenshots:** folder, subfolder pattern (`YYYY/MM/DD`, `YYYY-MM` or none), file names
  (macOS style or `2026-11-11_15-41-07`), copy to clipboard, preview duration (2–10 s),
  sound, macOS floating thumbnail.
- **About:** version, updates, Restore macOS Defaults.

## Known problems

- Only lightly tested on a real screen, and only on one Mac (macOS 27, notched MacBook Pro).
  External displays, fullscreen apps, sleep/wake and drag-and-drop into specific apps have
  not been checked by hand. [TESTING.md](TESTING.md) has the full checklist.
- If screenshots still land on the Desktop after setup, log out and back in once, or run
  `killall screencaptureui`. macOS caches the save location.
- If you skip "Move screenshots off your Desktop", Dropshot does nothing until you turn on
  **Save macOS screenshots to this folder** in Settings. It never watches the Desktop.
- Clipboard history has no unit tests yet, and is lost when the app quits (by design).
- "Check for Updates…" is disabled: there is no update feed yet.
- The app icon is a placeholder.

## Development

```bash
make build      # Debug build into build/
make test       # unit tests
make run        # build and launch
make release    # dist/Dropshot.dmg
```

`scripts/smoke-test.sh` runs the screenshot pipeline end to end against a throwaway folder
(it overwrites the clipboard while it runs).

```
Packages/DropshotCore   pure logic, unit tested: paths, detection, geometry, defaults
Dropshot/App            app delegate, settings store, menu bar item
Dropshot/Capture        FSEvents + Spotlight watchers, pipeline, clipboard, thumbnails
Dropshot/Notch          panel, island views, hover, drag-out
Dropshot/History        clipboard history, global shortcut, panel
Dropshot/Settings       Settings window
Dropshot/Onboarding     first-run setup
Dropshot/System         macOS screenshot preferences, Sparkle wrapper
scripts                 release.sh, make-icon.sh, smoke-test.sh
```

Swift 6, SwiftUI + AppKit, XcodeGen. Dependencies: [Sparkle](https://sparkle-project.org)
and [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern).

More detail: [DECISIONS.md](DECISIONS.md) (why things are the way they are) ·
[TESTING.md](TESTING.md) · [RELEASING.md](RELEASING.md) (signing, notarization, updates)

## Contributing

Issues and pull requests are welcome. Please run `make test` before sending a change, and
say which macOS version and Mac you tried it on.

## License

[MIT](LICENSE)
