# Dropshot v0.1 — Plan

Goal: screenshots that are instantly on the clipboard, sorted off the Desktop,
and previewed in a draggable island that grows out of the notch.

## Architecture

```
Packages/DropshotCore   pure logic, no AppKit UI — unit tested with `swift test`
  PathPlanner             dated folders + rename patterns + collision handling
  CaptureClassifier       image / recording / temp-file rules
  StabilityTracker        "file is fully written" state machine
  EventDeduplicator       collapses FSEvents + Spotlight double reports
  NotchGeometry           notch rect, expanded island, pill, fullscreen math
  ScreenCaptureDefaults   apply / restore com.apple.screencapture keys

Dropshot (app target, AppKit lifecycle, LSUIElement)
  App/        AppDelegate, StatusItemController, AppSettings
  Capture/    FolderWatcher (FSEvents), MetadataWatcher (NSMetadataQuery),
              CapturePipeline (actor), ClipboardWriter, Thumbnailer
  Notch/      NotchPanel, NotchPreviewController, NotchViewModel, SwiftUI views,
              DragSourceView, HoverTracker
  Settings/   SettingsWindowController + SwiftUI tabs
  Onboarding/ 3-screen SwiftUI flow
  System/     SystemDefaultsService (CFPreferences), FullscreenDetector, Updater
```

Flow: macOS writes a capture into the root folder → FSEvents (primary) or
Spotlight (backup) reports it → pipeline dedupes, waits until the size is
stable, moves it to `root/YYYY/MM/DD/` → main actor writes the clipboard and
shows the notch preview.

## Milestones

1. Scaffold — XcodeGen, Makefile, menu bar icon, settings stub.
2. Pipeline — detect → sort → clipboard, with unit tests.
3. Notch preview — panel, spring animation, drag-out, hover, stacking.
4. Non-notch pill, multi-display, fullscreen (compact) handling.
5. Settings, onboarding, restore defaults, launch at login.
6. Release — icon, release.sh, Sparkle keys + appcast, DMG.

Each milestone: build, run, verify, commit. Decisions go in DECISIONS.md,
verification results in TESTING.md.
