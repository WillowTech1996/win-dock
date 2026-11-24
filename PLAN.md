# WinDock fork: plan

Fork of [barnuri/win-dock](https://github.com/barnuri/win-dock) (MIT, ~11k lines of Swift, 1 maintainer, very few users). Written 2026-11-24 after reviewing upstream at commit `3ba605f`.

## Why fork

I want a Windows-style taskbar on every screen of my Mac. The Dock can only live on one display, and the closed-source option (uBar) costs money. Upstream already has the hard part: per-screen taskbar windows, AX-based window tracking, previews, auto-hide, fullscreen detection. What it lacks is a build I can trust.

## Findings from the upstream review

1. **Release builds are broken.** The published `WinDock.zip` fails `codesign --verify --deep --strict` ("a sealed resource is missing or invalid"), even when extracted with `ditto`. It is signed with a personal Apple Development cert (not Developer ID), is not notarized, and is a debug-flavored build (`get-task-allow` = true). Likely cause: `release.py` builds the zip with `shutil.make_archive`, which doesn't preserve what a signed bundle needs. Not verified yet.
2. **Homebrew tap is broken.** The formula points at v1.0.41 but the latest release asset is v1.0.36, so `brew install` returns a 404.
3. **Over-broad permissions.** Entitlements include Contacts access and Apple Events targets for Finder, System Events, Teams, Slack, Mail and the App Store. Sandbox off. Most of this is not needed for a taskbar.
4. **Multi-monitor exists but is uneven.** One `DockWindow` per screen is created when `showOnAllSpaces` is true (default). `NotificationPositionManager` and `DockWindow` still use `NSScreen.main` in places.
5. **Doc drift.** README says macOS 14, project says 15.0. Upstream `CLAUDE.md` links to docs that don't exist and contains author-specific tool rules.
6. **Private APIs** (`CGS*`, `_AXUIElementGetWindow`) can break on any macOS release. A health check already logs this.

## Phase 0: Fork and baseline (half a day)

- [x] Fork on GitHub; clone into this folder (`gh repo fork barnuri/win-dock --clone` or clone my fork over this directory's two files, keeping `CLAUDE.md` and `PLAN.md`).
- [x] Replace the upstream `CLAUDE.md` with this one; delete `AGENTS.md`, `.github/copilot-instructions.md`, `.specify/`, speckit commands/prompts if unused.
- [ ] (grep audit done 2026-11-24, see notes; full read still open) Read the code I'm going to run. At minimum: `Main.swift`, `AppManager.swift`, `NotificationPositionManager.swift`, `UserProfileManager.swift`, `SystemTrayView.swift`, anything touching AppleScript, network access or file reads. Grep for `NSAppleScript`, `Process(`, `URLSession`, `Contacts`.
- [~] (build done, run on displays still open) Build and run unmodified from Xcode; note what works and what is broken on my displays. Capture baseline notes below.
- [x] Run the existing tests (`⌘U`); record which pass.

## Phase 1: Make it mine and make it safe (1 to 2 days)

- [x] Change bundle ID (e.g. `com.<me>.WinDock`) and DEVELOPMENT_TEAM to mine in all three targets; update `Info.plist`/UserDefaults domain consumers.
- [x] Sign with a stable identity so Accessibility approval survives rebuilds. Personal team is enough for local use. Notarization and distribution need a paid Developer ID account; decide later whether that is worth it for a hobby fork.
- [x] Trim entitlements: remove `personal-information.addressbook` and unused scripting targets; confirm each remaining Apple Events target is actually used in code. Re-test activate/hide/quit.
- [x] Remove or disable features that need extra permissions I don't want (notification repositioning, user profile/contacts) behind a setting, off by default.
- [x] (real cause: build.sh copied icon.png into the signed bundle; fixed by bundling it via Xcode; release.py and tap deleted; package.sh added) Fix packaging: replace `shutil.make_archive` with `ditto -c -k --keepParent` (or build a DMG), then verify with `codesign --verify --deep --strict` and `spctl -a -vv` before any release. Remove the Homebrew tap and upstream repo references from `release.py`, or delete `release.py` and package by hand.
- [x] Fix doc drift: README requirements, deployment target, `Developer.md`.
- [x] Add `logs/` and `build/` to `.gitignore`; make `run.sh` create `logs/`.

## Phase 2: Multi-monitor correctness (2 to 4 days). The main goal

Test setup: laptop plus one external display, both arrangements (external above/left/right), plus unplug/replug while running.

- [ ] Audit every `NSScreen.main` / `screens.first` / `prefix(1)` use and make them per-screen.
- [ ] Rename `showOnAllSpaces` to something accurate (e.g. `showOnAllDisplays`) with a migration for the stored key; verify default behavior.
- [x] Per-screen window lists: option to show only windows that are on this display's taskbar (Windows' "show taskbar buttons on: taskbar where window is open"), default on. Implemented 2026-11-24 (`DockApp.scoped(to:among:)`, setting `taskbarPerDisplayWindows`, default on); unit-tested and confirmed working on two displays. Not yet in settings export/import.
- [ ] Verify `WindowsResizeManager` coordinate conversion for displays with negative origins and different scales.
- [x] Verify display hot-plug, sleep/wake, resolution change, and Spaces switching rebuild or reposition the windows without flicker or duplicates. Done 2026-11-24 and confirmed on two displays: taskbar windows are reconciled by display ID (no full rebuild), re-entrant sync guarded, resize retries after wake when AX is not ready.
- [x] Verify fullscreen detection is per display (fullscreen on one screen should not hide the bar on the other). Done 2026-11-24 and confirmed on two displays. Per-display set of fullscreen display IDs; native fullscreen with the menu bar kept visible is detected via AXFullScreen (bounds alone can't tell it from a zoomed window); window names are not required (they need Screen Recording).
- [ ] Auto-hide and the macOS menu bar/Dock interaction on secondary displays. Hide the system Dock while WinDock runs (there is `MacOSDockManager.swift`); restore on quit and on crash.
- [ ] Unit tests for the screen/geometry logic (pure functions, injectable screen lists).

## Phase 3: Daily-driver polish (ongoing)

From upstream `ROADMAP.md` and `IDEAS.md`, in the order I'd want them:

1. Fix "minimized window doesn't restore when clicking its preview".
2. Taskbar grouping modes (always combine / combine when full / never combine).
3. Keyboard navigation in previews; global hotkeys for the Nth item.
4. Split `SettingsView.swift` (1.5k lines) and `AppManager.swift` (1.1k lines).
5. Lazy preview capture (hover dwell), then ScreenCaptureKit migration for previews (`CGWindowListCreateImage` is deprecated).
6. Snap layouts using `WindowsResizeManager` as the seed (would replace Rectangle).
7. Left-aligned classic mode with Start button in the corner.

Explicitly out of scope for now: widgets board, theme marketplace, Start-menu file search, third-party tray icon hosting.

## Phase 4: Robustness

- [ ] Private-API break plan: keep the public `CGWindowList` fallback useful, and have the health check show a visible warning in Settings, not just a log line.
- [ ] Test on each new macOS point release before updating the OS (or soon after).
- [ ] Crash safety: if the app dies, make sure the system Dock is not left hidden.
- [ ] Energy check in Instruments (idle wakeups when the taskbar is auto-hidden).
- [ ] Decide on distribution: local builds only vs. signed + notarized zip on my own releases.

## Risks and open questions

- **Private API churn** is the permanent cost of this app category. Budget time after each macOS release.
- **Paid developer account?** Without one, no notarization, so only I can run my builds. Fine for a hobby fork; decide before sharing.
- **Overlap with other tools I run:** Rectangle (snapping), DockDoor (hover previews, Option+Tab). WinDock's previews and snapping may conflict with them; decide which to keep once WinDock is stable.
- **Upstream sync:** upstream moves slowly and has one maintainer. Keep the `upstream` remote and cherry-pick fixes; don't expect to merge cleanly after Phase 1 and 2.
- **Is Xcode's current toolchain building upstream cleanly?** Unknown until Phase 0.

## Baseline notes (fill in during Phase 0)

- Build result: Xcode 27.2, Debug, CODE_SIGNING_ALLOWED=NO: BUILD SUCCEEDED (2026-11-24). Signed run not yet tried.
- Tests passing/failing: unit tests 33 passed, 0 failed (unsigned, `-only-testing:WinDockTests`). UI tests not run.
- What works on both displays: taskbar on both screens; with Accessibility granted to the new bundle ID, maximized windows stop above the bar on both external displays (2026-11-24).
- What is broken: fresh installs never started WindowsResizeManager because `enableWindowsResize` was only an @AppStorage default (fixed by registering defaults). Rebuilding under a new bundle ID needs Accessibility re-granted.
