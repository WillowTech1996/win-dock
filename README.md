# Win Dock

A feature-rich macOS SwiftUI application that emulates the Windows 11 style taskbar, bringing a modern Windows experience to your Mac.

![Win Dock Taskbar](screenshots/dock.png)

> Personal fork of [barnuri/win-dock](https://github.com/barnuri/win-dock) (MIT). Local builds only for now; see `PLAN.md` for the roadmap.

## Requirements

-   macOS 15 Sequoia or later
-   Xcode (current release)
-   Your own signing identity (a free Personal Team is enough for local use)

## Quick Start

```bash
git clone https://github.com/WillowTech1996/win-dock.git
cd win-dock
open WinDock.xcodeproj   # set your Team in Signing & Capabilities, then ⌘R
```

Grant **Accessibility** when prompted. See `Developer.md` for signing details.

## Screenshots

### Taskbar with App Icons

![Win Dock Taskbar](screenshots/dock.png)

### Start Menu

![Start Menu](screenshots/start-menu.png)

## Features

### Core Features

-   ✅ Windows 11-style taskbar with centered icons
-   ✅ Click to activate/launch apps
-   ✅ Start Menu with quick actions and power options
-   ✅ System Tray with time, date, battery, and network status
-   ✅ Taskbar positioning (Bottom, Top, Left, Right)
-   ✅ Alt+Tab compatible - appears in app switcher
-   ✅ Pin/unpin favorite applications
-   ✅ Right-click context menus (Show, Hide, Quit, Pin/Unpin)
-   ✅ App hover previews with window count
-   ✅ Running indicator dots
-   ✅ Window count badges
-   ✅ Customizable appearance and behavior

### Customization Options

-   Multiple taskbar positions (Bottom, Top, Left, Right)
-   Auto-hide taskbar functionality
-   Taskbar size options (Small, Medium, Large)
-   Icon centering toggle
-   Transparency and visual effects settings
-   Animation speed adjustment
-   Show/hide labels and system tray
-   Clock format and date format options
-   Search button app selection (Spotlight, Alfred, Raycast)

### Smart App Management

-   Dynamic detection of new apps launching/quitting
-   Persistent pinned applications
-   Proper app state tracking (running, hidden, window count)
-   Smooth animations and hover effects
-   Group multiple windows of the same application

### System Integration

-   Runs as background accessory app
-   Status bar menu for quick access
-   Multi-monitor support (one taskbar per display)
-   All Spaces support
-   Settings import/export for backup and sharing
-   Advanced logging for troubleshooting

## Building

### Xcode

```bash
open WinDock.xcodeproj
```

Set your Team under Signing & Capabilities, then press ⌘R.

### Command line

```bash
./run.sh       # build, run, and tail logs
./build.sh     # Release build into ./build
./package.sh   # Release build + signed zip (build/WinDock.zip), signature verified
```

The zip is signed with your development certificate and is not notarized, so it will run on your own Mac only.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
