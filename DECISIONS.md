# Decisions

Choices made while building v0.1, with the reason for each.

## Project

- **Logic lives in a local Swift package (`Packages/DropshotCore`).** Path planning, capture
  classification, stability, de-duplication, notch geometry and settings backup/restore have
  no AppKit UI in them, so they are tested with plain `swift test` in about a second.
  `make test` runs exactly that.
- **AppKit lifecycle (`main.swift`), SwiftUI for views.** An agent app with a status item, a
  non-activating panel and on-demand windows is simpler to control from an `NSApplicationDelegate`
  than from the SwiftUI `App` protocol.
- **Dependencies: Sparkle and LaunchAtLogin-Modern only**, as allowed. Nothing else was needed.
- **Bundle identifier `app.dropshot.Dropshot`.** Change it in `project.yml` before shipping
  under your own name.
- **Swift 6 language mode with complete concurrency checking.** The pipeline is an actor; UI
  types are `@MainActor`.

## Capture pipeline

- **Dropshot watches its own root folder only.** macOS is told (with consent) to save into the
  root; Dropshot then sorts into dated subfolders. It never watches or moves anything on the
  Desktop. If you decline step 2 of onboarding, Dropshot does nothing until you turn on
  "Save macOS screenshots to this folder" in Settings, and Settings shows a warning saying so.
- **FSEvents is the primary signal, Spotlight (`NSMetadataQuery`, `kMDItemIsScreenCapture`) the
  backup.** FSEvents is faster; Spotlight catches anything FSEvents coalesces away. Both feed
  one actor, which de-duplicates by device + inode and marks finished files with an
  `app.dropshot.processed` extended attribute so nothing is handled twice, even across launches.
- **What counts as a capture:** a direct child of the root that is an image or `.mov`, is not a
  dot-file, and either carries macOS's `kMDItemIsScreenCapture` attribute or (for files that
  just appeared) has a screenshot-style name. Other files you put in the folder are left alone.
- **"Fully written" means:** size unchanged across consecutive reads (2 reads 100 ms apart for
  images, 4 reads 250 ms apart for recordings), plus a PNG `IEND` / JPEG end-marker check and a
  successful decode. A size check alone accepted a truncated PNG during testing.
- **Clipboard:** PNG bytes are written eagerly; TIFF is promised lazily so a large screenshot
  does not cost a TIFF conversion unless an app asks for it. The file URL is on the same
  pasteboard item. Recordings get the file URL only.
- **Captures found at launch are sorted silently** (no clipboard, no preview): they are not
  "just taken". After wake or a folder hiccup, fresh captures still get the full treatment.
- **Name collisions never overwrite:** `name.png`, `name 2.png`, `name 3.png`.

## Notch preview

- **One `NSPanel`, level just above the menu bar**, non-activating, on all Spaces, joins
  fullscreen Spaces. It is created on the first capture and ordered out when idle, so it only
  exists on screen for the few seconds a preview is showing. Its margins are fully
  transparent, which macOS normally treats as click-through; this is on the manual checklist.
- **The island animates size, not opacity** (spring: response 0.35, damping 0.8). Content is
  laid out once at full size and revealed by the growing shape. With Reduce Motion it
  cross-fades at full size instead.
- **Hover and drag are AppKit** (`NSTrackingArea` with `.activeAlways`, `NSDraggingSource`).
  SwiftUI's `onHover` and `onDrag` do not fire reliably in a panel of an app that is never
  active.
- **Which screen:** the one macOS recorded for the capture (`kMDItemScreenCaptureGlobalRect`),
  else the one under the pointer, else the main screen.
- **Fullscreen detection uses only window bounds from `CGWindowListCopyWindowInfo`**, which
  needs no Screen Recording permission (window titles and contents are not read).
- **Delete moves to the Trash**, never deletes outright.

## System settings

- **Only two macOS preferences are ever written:** `com.apple.screencapture` `location` and
  `show-thumbnail`. Before the first write, the previous value (or its absence) is saved.
  Restore puts that back, deleting the key if it did not exist. If you changed the setting
  yourself after Dropshot did, restore leaves your value alone.
- **`killall SystemUIServer` after each change**, so it applies without logging out.
- **A test domain can stand in for `com.apple.screencapture`** (`-screencaptureDomain`). All
  automated checks use it; the real domain was never touched during development.

## Updates and network

- **Sparkle starts only when the build has both `SUFeedURL` (https) and `SUPublicEDKey`.** The
  default build has neither, so it makes no network connections at all, and "Check for
  Updates…" is disabled with an explanation.
- **Sparkle keys were not generated here.** `generate_keys` stores the private key in your
  login Keychain; that is your signing secret to create. RELEASING.md has the two commands.

## Release

- **Hardened Runtime is on, App Sandbox off**, as specified.
- **Ad-hoc builds carry one entitlement, `com.apple.security.cs.disable-library-validation`.**
  An ad-hoc signature has no Team ID, so without it the Hardened Runtime refuses to load the
  app's own `Sparkle.framework` and the app dies at launch. Developer ID builds are signed
  without any entitlements.
- **`release.sh` launches the signed app for 3 seconds before building the DMG**, to catch
  signing errors that only appear at load time.
- **DMG layout falls back.** `create-dmg` arranges the window by scripting Finder; when that
  is not possible (locked screen, CI) the script retries without layout, then with `hdiutil`.
- **The icon is drawn in code** (`scripts/make-icon.swift`) and is a placeholder.
- **Debug-only command-line hooks** (`--render-previews`, `--render-windows`,
  `--defaults-test`) exist for testing and are compiled out of Release.
