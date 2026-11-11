# Testing

Last run: 2026-11-11, macOS 27.2.1, Apple M3 Pro, Xcode 27.2.

## Summary

| Area | How | Result |
|---|---|---|
| Unit tests | `make test` | 71 pass |
| Pipeline end to end | `scripts/smoke-test.sh` (Debug and Release) | 25 of 25 pass |
| Clipboard latency | smoke test, from file written to clipboard ready | 112–125 ms (limit 1000 ms) |
| Idle CPU, Release | `top`, 12 samples of 5 s | 0.0% in every sample (limit 1%) |
| Idle memory, Release | `footprint` | 14 MB after launch, 26–28 MB after three previews (limit 60 MB) |
| macOS settings apply/restore | `--defaults-test` on a test domain | exact round trip |
| Panel placement and timing | window list probe | correct frame, level and hide time |
| Island, Settings, onboarding appearance | offscreen renders | reviewed |
| **Everything in "Manual checklist"** | needs a person at an unlocked Mac | **not run** |

The Mac was at the lock screen for the original build. Since then two things have been seen
on the live display (screen captures of the real desktop): the island growing out of the
notch with thumbnail, dimensions and "Copied ✓" after a capture landed in the folder, and
the clipboard history panel listing three copied texts newest-first. Everything else in
"Manual checklist" is still not run.

### Bug found in the first live run

Screenshots kept going to the Desktop after onboarding although
`com.apple.screencapture location` was set correctly. Cause: `screencaptureui`, the agent
that saves the capture, had the old location cached and Dropshot restarted only
SystemUIServer. Fixed by restarting both. Not yet re-confirmed with a real ⌘⇧3 press.

## Automated

### Unit tests (`make test`)

`Packages/DropshotCore/Tests`: dated path generation, rename patterns and collision
suffixes; capture classification; file stability; duplicate-event filtering; PNG/JPEG
completeness; notch, pill, compact and fullscreen geometry; screen selection; settings
apply/restore (including "user changed it afterwards" and "key did not exist before").

### Smoke test (`scripts/smoke-test.sh [path/to/Dropshot.app]`)

Launches the app against a temporary root folder and a test preferences domain, then uses
`screencapture -x` to produce real captures. It overwrites the clipboard while it runs.

1. One screenshot: moved into `YYYY/MM/DD`, clipboard has PNG, TIFF and the file URL, URL
   points at the sorted file, ready in under 1 s.
2. Burst of five: all sorted, each processed exactly once.
3. Dot-files, non-images and unrelated images in the folder are left alone.
4. A file written slowly is sorted only once complete, and whole.
5. A screen recording is sorted; clipboard has the file URL and no image data.
6. Folder deleted while running: recreated, captures still processed.
7. Folder renamed while running: recreated, captures still processed, no crash.
8. A capture taken while the app was not running is sorted on next launch.

### Idle CPU and memory (Release build)

```bash
open -n build/release/Dropshot.app --args -rootFolderPath /tmp/ds-measure -onboardingCompleted YES -screencaptureDomain app.dropshot.smoketest
```

```bash
footprint $(pgrep -x Dropshot) | grep phys_footprint
```

```bash
top -l 13 -s 5 -pid $(pgrep -x Dropshot) -stats cpu,mem
```

Measured: physical footprint 14 MB idle after launch; 26–28 MB idle after three captures
had been previewed (panel and thumbnails created). CPU 0.0% across 60 s idle; 1.23 s of CPU
time in total over the first 2 min 52 s including launch and three captures. One 10-second
stretch right after the third preview read 1.9% before settling to 0.0%.

`footprint` is the figure Activity Monitor shows as "Memory". Resident size (`ps -o rss`)
was higher, 71–85 MB, because it also counts framework pages shared with other apps.

### macOS settings round trip (Debug build, test domain)

```bash
defaults write app.dropshot.defaultstest location /tmp/previous
```

```bash
build/Build/Products/Debug/Dropshot.app/Contents/MacOS/Dropshot -screencaptureDomain app.dropshot.defaultstest --defaults-test apply /tmp/new-root
```

```bash
build/Build/Products/Debug/Dropshot.app/Contents/MacOS/Dropshot -screencaptureDomain app.dropshot.defaultstest --defaults-test restore
```

After apply: `location` is the new root and `show-thumbnail` is `0`. A fresh process still
reports both as managed. After restore: `location` is `/tmp/previous` again and
`show-thumbnail` is gone (it did not exist before), and no backup record is left behind.
The hook refuses to run against `com.apple.screencapture`.

### Offscreen renders (Debug build)

```bash
build/Build/Products/Debug/Dropshot.app/Contents/MacOS/Dropshot --render-previews /tmp/ds-previews some.png
```

```bash
build/Build/Products/Debug/Dropshot.app/Contents/MacOS/Dropshot --render-windows /tmp/ds-windows
```

The first writes the island in 11 states (notch, pill, compact, stack, hover, recording,
Reduce Motion); the second writes the three Settings tabs and three onboarding screens.

### Other test switches

Any setting can be overridden for one run: `-rootFolderPath`, `-onboardingCompleted YES`,
`-previewDuration 2`, `-screencaptureDomain <domain>`, and in any build
`-debugIslandStyle pill`, `-debugCompact YES`, `-debugReduceMotion YES`. Debug builds also take
`-debugShowHistory YES` (opens the clipboard panel 4 s after launch).

## Manual checklist

Not run yet. Use a notched MacBook; where noted, also an external display.

### First run

- [ ] First launch shows the three setup screens; the notch animation on screen 1 loops.
- [ ] Screen 2 → "Move Screenshots Here": `defaults read com.apple.screencapture location`
      prints the chosen folder.
- [ ] Screen 3 → "Turn Off Floating Thumbnail": `defaults read com.apple.screencapture show-thumbnail` prints `0`,
      and the corner thumbnail no longer appears.
- [ ] Closing the setup window early: it comes back on next launch, and nothing is watched meanwhile.

### Capture

- [ ] ⌘⇧3: on the clipboard within a second (⌘V into Notes), filed under today's folder,
      nothing on the Desktop.
- [ ] ⌘⇧4 region. ⌘⇧4 then Space (window). ⌘⇧5 capture. Screenshot app.
- [ ] ⌘⇧5 recording: filed and previewed; pasting into Finder pastes the file.
- [ ] Five quick ⌘⇧3 presses: five files, no duplicates, badge counts to 5.
- [ ] With the floating thumbnail left on, the preview still arrives (about 5 s late).

### Notch preview

- [ ] Island grows out of the notch with a spring and matches the notch exactly when idle.
- [ ] Shows thumbnail, pixel dimensions and "Copied ✓". Disappears after about 4 s.
- [ ] Never takes focus: keep typing in another app while it appears.
- [ ] Clicks just beside the island reach the app underneath.
- [ ] Hover keeps it open; leaving restarts the timer; Open, Show in Finder and Move to
      Trash work.
- [ ] Drag the thumbnail into Telegram, Finder, Slack, Figma and a browser upload field.
- [ ] Reduce Motion on (System Settings → Accessibility → Display): fades, no growth.

### Clipboard history

- [ ] ⇧⌘V opens the panel under the notch from any app; pressing it again or Esc closes it.
- [ ] Copy text, an image from a browser, and a file in Finder: all three appear, newest first.
- [ ] ↑ ↓ and Return, digits 1–9, and clicking a row each put that entry on the clipboard.
- [ ] The app you were typing in is still frontmost afterwards.
- [ ] ⌫ removes the selected entry; Clear empties the list.
- [ ] Copy a password from a password manager: it does not appear.
- [ ] "Paste the chosen item directly" on, Accessibility granted: picking pastes into the app.
- [ ] Changing the shortcut in Settings takes effect immediately; Pause disables it.

### Displays

- [ ] External display: black pill at top centre of the screen the shot was taken on.
- [ ] Fullscreen app: smaller preview, on both built-in and external displays.
- [ ] Connect and disconnect a display while a preview is showing and while idle.
- [ ] Close the lid and reopen; sleep and wake; then take a screenshot.

### Settings

- [ ] Launch at login toggles the entry in System Settings → General → Login Items.
- [ ] Pause stops everything; Resume sorts what arrived meanwhile without previews.
- [ ] Hide the menu bar icon; opening the app again from Finder shows Settings.
- [ ] Change folder, subfolder pattern and file names; the example line and the next
      screenshot agree.
- [ ] Preview duration 2 s and 10 s. Play sound.
- [ ] Restore macOS Defaults: `defaults read com.apple.screencapture` matches what it was
      before Dropshot was installed, and screenshots land where they used to.

### Robustness

- [ ] Delete the screenshots folder in Finder, take a screenshot: folder comes back.
- [ ] Rename it, take a screenshot: same.
- [ ] Leave it running for a day; check Activity Monitor for CPU and memory.

## Known limitations

- Most live behaviour is still unverified (see above), including real shortcut presses.
- Clipboard history is not covered by unit tests.
- If you decline "Move screenshots off your Desktop", Dropshot does nothing until you turn
  the setting on; it does not watch the Desktop.
- Fullscreen detection assumes the menu bar window spans the display; untested on real
  fullscreen apps.
- "Check for Updates…" is disabled until the app is built with a feed URL and key.
- The locally built DMG is ad-hoc signed, not notarized, and has no arranged window layout (Finder could
  not be scripted from a locked session; `release.sh` lays it out when it can).
- The app icon is a generated placeholder.
