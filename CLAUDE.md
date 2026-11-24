# CLAUDE.md

Guidance for Claude Code when working in this repository. See `PLAN.md` for the fork roadmap and current priorities.

## What this is

A personal fork of [barnuri/win-dock](https://github.com/barnuri/win-dock) (MIT). WinDock is a macOS SwiftUI/AppKit app that draws a Windows 11-style taskbar: centered app icons, running indicators, window previews on hover, Start button, search button, system tray, per-screen taskbar windows.

It runs as an accessory app (no Dock icon of its own, status-bar menu only) and works by reading other apps' windows through the Accessibility (AX) API.

Fork goals: a taskbar I can trust and run daily on a multi-monitor Mac, built and signed by me, with a smaller permission footprint than upstream. See `PLAN.md`.

## Commands

```bash
open WinDock.xcodeproj            # Xcode; ⌘R run, ⌘U test
./build.sh                        # Release build into ./build (needs `gem install xcpretty`)
./open.sh                         # Open the built app
./run.sh                          # Build + run + tail logs; 'R'+Enter rebuilds, 'Q'+Enter quits
xcodebuild test -scheme WinDock -destination 'platform=macOS'
xcodebuild test -scheme WinDock -destination 'platform=macOS' -only-testing:WinDockTests/AppManagerTests
tail -f ~/Library/Logs/WinDock/app.log
```

`run.sh` symlinks `./logs/app.log`, so `mkdir -p logs` first if it fails. `logs/` and `build/` should stay gitignored.

## Requirements

- macOS 15.0+ deployment target (`MACOSX_DEPLOYMENT_TARGET = 15.0` in the project; the upstream README's "macOS 14" is wrong). Swift 5 language mode.
- Xcode (installed locally; check `xcodebuild -version`).
- Only one package dependency: **SettingsAccess** (SwiftPM).

## Signing matters for day-to-day work

macOS tracks Accessibility approval by code signature. If the signature changes between builds, the permission silently stops working and window detection returns nothing.

- Use a stable signing identity for every local build (Xcode → WinDock target → Signing & Capabilities → Automatically manage signing, your own Team).
- The project currently has upstream's `DEVELOPMENT_TEAM` and bundle ID `barnuri.WinDock`. Changing those to mine is the first task in `PLAN.md`. Do not ship or install a build under the upstream bundle ID.
- If the taskbar shows no windows after a rebuild, re-check Accessibility first (remove the entry, re-add, relaunch).

## Architecture

Event-driven, never polling. The one rule: **never block the main thread** and never call AX APIs on it.

```
NSWorkspace notifications
  → BackgroundTaskCoordinator   (debounce / priority lanes)
  → AppManager.updateDockApps() (@MainActor, state owner)
  → Task.detached → WindowEnumerationService (actor, AX calls, short TTL cache)
  → back on MainActor → DockView (SwiftUI) → AppDockItem
```

Key files in `WinDock/`:

| File | Role |
|---|---|
| `Main.swift` | `AppDelegate`: status-bar menu, permission prompts, builds one `DockWindow` per screen in `setupDockWindowsForAllScreens()`; rebuilds on `didChangeScreenParametersNotification` |
| `AppManager.swift` | Central `@MainActor` state: `dockApps`, pin/unpin, reorder, activate/hide/quit. Also declares the private-API bindings. ~1,100 lines; split is on the roadmap |
| `BackgroundTaskCoordinator.swift` | All dock refreshes go through `scheduleUpdate(reason:)` |
| `WindowEnumerationService.swift` | Actor doing AX window enumeration and filtering (`isValidStandardWindow`, `isSpecialApp`) |
| `DockWindow.swift` / `DockUtilities.swift` | Borderless `NSWindow` per screen, positioning (`dockFrame(for:screen:)`), auto-hide, fullscreen handling |
| `DockView.swift`, `AppDockItem.swift` | SwiftUI taskbar and per-app items (indicators, badges, hover, drag-reorder) |
| `WindowPreviewView.swift`, `WindowsPreviewItem.swift` | Hover previews with window screenshots |
| `WindowsResizeManager.swift` | Keeps other windows out of the taskbar area (maximize respects the bar) |
| `FullscreenDetectionManager.swift` | Hides the bar when a fullscreen app is active |
| `SettingsView.swift`, `SettingsManager.swift`, `SettingsHelper.swift` | Settings UI (~1,500 lines) and `UserDefaults`/`@AppStorage` persistence |
| `StartMenuView.swift`, `SearchButton.swift`, `SystemTrayView.swift`, `UserProfileManager.swift` | Start menu, search launcher (Spotlight/Alfred/Raycast), tray (clock, battery, network) |
| `NotificationPositionManager.swift` | Repositions system notification banners via AX |
| `PrivateAPIHealthCheck.swift` | `dlsym` probe of the private symbols at launch; degrades with a log line |

### Multi-monitor

Each screen gets its own `DockWindow` and the `showOnAllSpaces` setting (default `true`, despite the name it controls all-screens) decides whether all `NSScreen.screens` or only the first get one. `NotificationPositionManager` and parts of `DockWindow` still use `NSScreen.main`; treat those as multi-monitor bugs when found. AppKit uses bottom-left origin, CoreGraphics/AX use top-left; `WindowsResizeManager` converts between them, so be careful with frames on non-primary displays.

### Private APIs (can break on any macOS update)

`CGSGetWindowLevel`, `CGSMainConnectionID`, `CGSHWCaptureWindowList`, `_AXUIElementGetWindow` (bound via `@_silgen_name`), plus a remote-token trick for windows on other Spaces. Keep the public fallback (`CGWindowListCopyWindowInfo`) working and keep `PrivateAPIHealthCheck` in sync when adding any symbol.

### Permissions and entitlements

Needs Accessibility (core) and Automation/Apple Events (activate/hide/quit apps). `WinDock.entitlements` upstream also requests Contacts (`addressbook`) and scripting targets for Finder, System Events, Teams, Slack, Mail, App Store. The sandbox is off. Treat every entitlement and scripting target as something to justify; do not add new ones without a note in `PLAN.md`.

## Conventions and pitfalls

- Route every dock refresh through `coordinator.scheduleUpdate(reason:)`. Don't call `updateDockApps()` directly and don't add timers.
- Heavy work goes in `Task.detached` or the `WindowEnumerationService` actor; hop back to `@MainActor` only for UI state.
- Compute SwiftUI materials synchronously (see `MaterialCache` in `DockView`); no async material work.
- Log with `AppLogger.shared.info/debug/warning/error`, always with enough context to find the app/window involved.
- Window filtering is derived from AltTab (`isValidStandardWindow`): min size 100x50, standard/dialog subroles, special-cased apps. Add app quirks to `isSpecialApp()`.
- Automation error `-1743` means the Automation permission is missing for that target app.
- Respect Reduce Motion / Reduce Transparency and keep VoiceOver labels on new controls.
- Settings use `@AppStorage`; add new keys with defaults and, if they affect windows, observe changes the way `showOnAllSpaces` does.

## Testing

Unit tests live in `WinDockTests/` (app manager, coordinator, enumeration, fullscreen detection, icon cache, preview downsampling, private-API health, logger). Window-enumeration tests need Accessibility granted to the test host. UI tests exist but are only launch smoke tests. Add a unit test with any logic change in `AppManager`, the coordinator, or the enumeration filters.

## Release

`release.py` bumps the version, builds, zips, updates `homebrew-tap/Formula/windock.rb`, and creates a GitHub release. Do not run it as-is in this fork: it targets upstream's repo and tap, and its zip step breaks code signatures (see `PLAN.md`, Phase 1). Distribution for now is local builds only.

## Docs

`README.md`, `ROADMAP.md` (upstream near-term list), `IDEAS.md` (large idea backlog, not commitments), `Developer.md` (signing setup). `AGENTS.md`, `.github/copilot-instructions.md`, `.specify/` and `.claude/commands/speckit.*` are upstream tooling for other agents/workflows and can be removed from the fork if unused.
