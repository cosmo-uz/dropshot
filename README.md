# Dropshot

Take a screenshot the way you always do (⌘⇧3, ⌘⇧4, ⌘⇧5). Dropshot then:

- copies it to the clipboard straight away, as an image **and** as a file;
- files it in `~/Pictures/Screenshots/YYYY/MM/DD/` instead of on your Desktop;
- drops a preview out of the notch for about 4 seconds, which you can drag into any app.

Screen recordings (⌘⇧5) are filed and previewed the same way; the clipboard gets the file.

It also keeps a **clipboard history**: press ⇧⌘V anywhere (like Windows+V) to see the last 30
things you copied — text, images, files — and pick one with the arrow keys, 1–9 or a click.

Dropshot needs no Screen Recording permission. It watches a folder; it never captures the
screen itself. It makes no network connections except Sparkle update checks, and a build
without an update feed (the default) makes none at all. No analytics.

Requires macOS 14 or later. Universal (Apple Silicon and Intel).

## Install

Open `dist/Dropshot.dmg` and drag Dropshot to Applications.

The DMG in this repository is ad-hoc signed and not notarized, so it only opens without
complaint on the Mac that built it. See [RELEASING.md](RELEASING.md) for a notarized build.

On first launch, three setup screens ask before changing anything in macOS:

1. What Dropshot does.
2. Move screenshots off your Desktop? Pick the folder; Dropshot points macOS at it.
3. Turn off the macOS floating thumbnail? While it is on, macOS holds each file back for
   about 5 seconds, which delays the clipboard and the preview.

Both changes can be undone at any time: **Settings → About → Restore macOS Defaults…**

## Use

| | |
|---|---|
| Drag the thumbnail | Drops the file (and image data) into Telegram, Finder, Slack, Figma, a browser… |
| Click the thumbnail | Opens the screenshot |
| Hover | Keeps the preview open and shows Open, Show in Finder, Move to Trash |
| Several shots in a row | Stack up with a count badge, newest on top |

On a display without a notch, the preview is a black pill at the top centre of the screen
the screenshot was taken on. Over a fullscreen app it is smaller.

The menu bar icon has Settings…, Open Screenshots Folder, Clipboard History, Pause and Quit.

Clipboard history lives in memory only and is forgotten when Dropshot quits. Entries that
password managers mark as secret are skipped. By default picking an entry copies it and you
press ⌘V; turn on "Paste the chosen item directly" in Settings (needs the Accessibility
permission) to have it pasted for you. The shortcut can be changed to ⌃⌘V or ⌥⌘V.

## Build

```bash
brew install xcodegen create-dmg
make build      # Debug build into build/
make test       # unit tests (DropshotCore)
make run        # build and launch
make release    # dist/Dropshot.dmg
```

`scripts/smoke-test.sh` runs the whole pipeline end to end against a throwaway folder.

## Layout

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

More: [DECISIONS.md](DECISIONS.md) · [TESTING.md](TESTING.md) · [RELEASING.md](RELEASING.md) · [DEMO.md](DEMO.md)
