import CoreGraphics
import Darwin
import SwiftUI
import AppKit
import Combine
#if canImport(IOKit)
import IOKit
#endif
#if canImport(IOKit.ps)
import IOKit.ps
#endif

class DockWindow: NSPanel {
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    private static var sharedAppManager: AppManager = AppManager()
    private var appManager: AppManager { DockWindow.sharedAppManager }
    private var windowObserver: NSObjectProtocol?
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("searchAppChoice") private var searchAppChoice = SearchAppChoice.spotlight
    
    private var hideTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var dockView: NSHostingView<DockView>?
    private var cancellables = Set<AnyCancellable>()
    private let fullscreenManager = FullscreenDetectionManager.shared
    private let visibilityManager = DockVisibilityManager.shared
    private(set) var targetDisplayID: CGDirectDisplayID?

    private var targetScreen: NSScreen? {
        // A window made for a specific display must never wander onto another one. If its display is gone
        // it has no screen, and the sync closes it.
        guard let targetDisplayID else { return screen ?? NSScreen.main }
        return NSScreen.screens.first { $0.displayID == targetDisplayID }
    }
    
    convenience init(screen: NSScreen? = nil) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        targetDisplayID = screen?.displayID
        if !isPreview {
            setup()
        }
    }
    
    private func setup() {
        if isPreview { return }
        level = .floating // Use normal level to appear in Alt+Tab
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .participatesInCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        
        // Completely disable resizing - make window non-resizable
        styleMask.remove(.resizable)
        
        // Enhanced accessibility and app switcher support
        self.setAccessibilityTitle("WinDock Taskbar")
        self.setAccessibilityRole(.application)
        self.setAccessibilitySubrole(.standardWindow)
        
        // Set a proper window title for app switcher
        self.title = "WinDock Taskbar"

        // Start hidden if our display is already fullscreen; the flag must match so a later update isn't skipped.
        isHiddenForFullscreen = fullscreenManager.isFullscreen(on: targetDisplayID)
        alphaValue = visibilityManager.isVisible && !isHiddenForFullscreen ? 1.0 : 0.0
        if isHiddenForFullscreen { beginFullscreenPeek() }
        
        updatePosition()
        appManager.startMonitoring()
        
        // Register the dock window with the visibility manager
        visibilityManager.addDockWindow(self)
        
        // Start fullscreen detection for auto-hide functionality
        fullscreenManager.startMonitoring()
        
        // Subscribe to fullscreen state changes
        fullscreenManager.$fullscreenDisplayIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displayIDs in
                self?.handleFullscreenStateChange(displayIDs)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        windowObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // DockView reacts to setting changes via @AppStorage — no need to rebuild it.
            self.updatePosition()
            self.handleAutoHideSettingChange()
        }

        setupDockView()
        setupTrackingArea()
    }
    
    /// True while a fullscreen window on this window's own display has hidden the taskbar.
    private(set) var isHiddenForFullscreen = false
    /// True while the taskbar is shown over a fullscreen app because the pointer pushed against its screen edge.
    private(set) var isRevealedInFullscreen = false
    private var edgeMonitor: Any?
    private var revealWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?

    /// A thin strip along the taskbar's screen edge that reveals it during fullscreen. AppKit coordinates.
    static func edgeTrigger(for position: DockPosition, screenFrame: NSRect, barFrame: NSRect) -> NSRect {
        let thickness: CGFloat = 4
        switch position {
        case .bottom: return NSRect(x: barFrame.minX, y: screenFrame.minY, width: barFrame.width, height: thickness)
        case .top: return NSRect(x: barFrame.minX, y: screenFrame.maxY - thickness, width: barFrame.width, height: thickness)
        case .left: return NSRect(x: screenFrame.minX, y: barFrame.minY, width: thickness, height: barFrame.height)
        case .right: return NSRect(x: screenFrame.maxX - thickness, y: barFrame.minY, width: thickness, height: barFrame.height)
        }
    }

    /// While a fullscreen app owns this display the taskbar is invisible, so it must not swallow clicks, and the
    /// pointer is watched (only now) for a push against the taskbar's edge. Both the system Dock and the Windows
    /// taskbar do this, and without it there is no mouse route out of a fullscreen app.
    private func beginFullscreenPeek() {
        ignoresMouseEvents = true
        guard edgeMonitor == nil else { return }
        edgeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.pointerMovedDuringFullscreen()
        }
    }

    private func endFullscreenPeek() {
        if let edgeMonitor { NSEvent.removeMonitor(edgeMonitor) }
        edgeMonitor = nil
        revealWorkItem?.cancel(); revealWorkItem = nil
        hideWorkItem?.cancel(); hideWorkItem = nil
        isRevealedInFullscreen = false
        ignoresMouseEvents = false
    }

    private func pointerMovedDuringFullscreen() {
        guard isHiddenForFullscreen, let screen = targetScreen, let position = AppDelegate.shared?.dockPosition else { return }
        let pointer = NSEvent.mouseLocation

        if isRevealedInFullscreen {
            if frame.insetBy(dx: -4, dy: -4).contains(pointer) {
                hideWorkItem?.cancel(); hideWorkItem = nil
            } else if hideWorkItem == nil {
                let item = DispatchWorkItem { [weak self] in self?.setRevealedInFullscreen(false) }
                hideWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
            }
            return
        }

        if Self.edgeTrigger(for: position, screenFrame: screen.frame, barFrame: frame).contains(pointer) {
            if revealWorkItem == nil {
                let item = DispatchWorkItem { [weak self] in self?.setRevealedInFullscreen(true) }
                revealWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)  // dwell, so grazing the edge does nothing
            }
        } else {
            revealWorkItem?.cancel(); revealWorkItem = nil
        }
    }

    private func setRevealedInFullscreen(_ revealed: Bool) {
        revealWorkItem = nil; hideWorkItem = nil
        guard isHiddenForFullscreen, isRevealedInFullscreen != revealed else { return }
        isRevealedInFullscreen = revealed
        ignoresMouseEvents = !revealed
        if revealed { orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = revealed ? 1.0 : 0.0
        }
        AppLogger.shared.info("Taskbar \(revealed ? "revealed" : "hidden again") over fullscreen on display \(targetDisplayID.map(String.init) ?? "unknown")")
    }

    private func handleFullscreenStateChange(_ fullscreenDisplayIDs: Set<CGDirectDisplayID>) {
        let shouldHide = targetDisplayID.map { fullscreenDisplayIDs.contains($0) } ?? false
        guard shouldHide != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = shouldHide

        if shouldHide {
            // Windows-like behavior: the taskbar on a display steps aside for a fullscreen window on that display only.
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().alphaValue = 0.0
            }
            beginFullscreenPeek()
            AppLogger.shared.info("Taskbar hidden for fullscreen window on display \(targetDisplayID.map(String.init) ?? "unknown")")
        } else {
            endFullscreenPeek()
        }
        if !shouldHide, visibilityManager.isVisible && !visibilityManager.isManuallyHidden {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().alphaValue = 1.0
            }
            AppLogger.shared.info("Taskbar shown after fullscreen on display \(targetDisplayID.map(String.init) ?? "unknown")")
        }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func setupDockView() {
        let dockView = DockView(appManager: appManager, displayID: targetDisplayID)
        let hostingView = NSHostingView(rootView: dockView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView = hostingView
        self.dockView = hostingView
    }
    
    private func handleAutoHideSettingChange() {
        // If auto-hide is off, ensure the dock is fully visible
        if !autoHide && visibilityManager.isVisible && !isHiddenForFullscreen && alphaValue < 1.0 {
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().alphaValue = 1.0
            }
        }
    }
    
    private func setupTrackingArea() {
        if let existingTrackingArea = trackingArea {
            contentView?.removeTrackingArea(existingTrackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            contentView?.addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hideTimer?.invalidate()
        if autoHide && !isHiddenForFullscreen {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().alphaValue = 1.0
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if autoHide && !isHiddenForFullscreen {
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self?.animator().alphaValue = 0.0
                }
            }
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        _ = contentView?.convert(locationInWindow, from: nil) ?? .zero
        let menu = NSMenu()
        // Position submenu
        let positionMenu = NSMenu()
        guard let appDelegate = AppDelegate.shared else { return }
        for position in DockPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(changePosition(_:)),
                keyEquivalent: ""
            )
            item.representedObject = position.rawValue
            item.target = self
            item.state = position.rawValue == appDelegate.dockPosition.rawValue ? .on : .off
            positionMenu.addItem(item)
        }
        let positionItem = NSMenuItem(title: "Taskbar Position", action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(
            title: "Quit Win Dock",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: locationInWindow, in: self.contentView)
    }
    
    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let position = DockPosition(rawValue: raw),
              let appDelegate = AppDelegate.shared else { return }
        appDelegate.updateDockPosition(position)
    }
    
    @objc private func openSettings() {
        AppLogger.shared.info("Opening settings from DockWindow context menu")
        SettingsHelper.shared.requestOpenSettings()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func screenDidChange() {
        updatePosition()
    }
    
    func updatePosition() {
        guard let appDelegate = AppDelegate.shared, let screen = targetScreen else {
            AppLogger.shared.warning("DockWindow.updatePosition skipped: delegate or screen unavailable (display \(targetDisplayID.map(String.init) ?? "unknown"))")
            return
        }
        let newFrame = dockFrame(for: appDelegate.dockPosition, screen: screen)
        // Called on every UserDefaults change: do nothing visible unless the frame really moved.
        let frameChanged = frame != newFrame
        if frameChanged {
            AppLogger.shared.info("Taskbar for display \(targetDisplayID.map(String.init) ?? "unknown") moved from \(frame) to \(newFrame)")
            setFrame(newFrame, display: true, animate: false)
        }
        
        // Update size constraints based on dock position
        let dockHeight = getDockHeight()
        if appDelegate.dockPosition == .left || appDelegate.dockPosition == .right {
            // Vertical dock (disable resize)
            let size = NSSize(width: dockHeight, height: screen.frame.height)
            minSize = size
            maxSize = size
        } else {
            // Horizontal dock (disable resize)
            let size = NSSize(width: screen.frame.width, height: dockHeight)
            minSize = size
            maxSize = size
        }
        
        if frameChanged { setupTrackingArea() }
    }
    
    func cleanup() {
        // appManager and fullscreenManager are shared across all dock windows and live for the app's
        // lifetime — do not stop them here, or closing one window (e.g. a disconnected monitor, or the
        // old windows being replaced on a screen change) freezes the others.
        cancellables.removeAll()
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
    
    deinit {
        if !isPreview {
            NotificationCenter.default.removeObserver(self)
            if let observer = windowObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            cleanup()
        }
        // Unregister the dock window from the visibility manager
        visibilityManager.removeDockWindow(self)
    }
}


// Fixed lock screen function
func lockScreen() {
    let script = """
    tell application "System Events"
        keystroke "q" using {command down, control down}
    end tell
    """
    
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("Lock screen error: \(error)")
            // Fallback to screen saver
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "ScreenSaverEngine"]
            task.launch()
        } else {
            AppLogger.shared.info("Lock screen triggered successfully")
        }
    }
}
