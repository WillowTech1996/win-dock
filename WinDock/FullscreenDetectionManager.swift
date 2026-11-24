import AppKit
import SwiftUI

class FullscreenDetectionManager: ObservableObject {
    static let shared = FullscreenDetectionManager()
    
    /// Displays that currently have a fullscreen window on them (CoreGraphics display IDs).
    @Published private(set) var fullscreenDisplayIDs: Set<CGDirectDisplayID> = []
    private var monitoringTimer: Timer?
    private var isRunning = false
    private var startupTime: Date?
    private var monitoringGeneration = 0
    private static let maxDisplayCount: UInt32 = 32
    private static let boundsTolerance: CGFloat = 2
    
    /// Serial, so a slow check can never finish after (and overwrite) a newer one.
    private let detectionQueue = DispatchQueue(label: "WinDock.fullscreen-detection", qos: .utility)

    /// Main-thread only. A hung app can make a check slow; skip new ones instead of queueing them up.
    private var checkInFlight = false

    private init() {}

    func isFullscreen(on displayID: CGDirectDisplayID?) -> Bool {
        guard let displayID else { return false }
        return fullscreenDisplayIDs.contains(displayID)
    }
    
    func startMonitoring() {
        guard !isRunning else { return }
        
        isRunning = true
        startupTime = Date()
        monitoringGeneration += 1
        let generation = monitoringGeneration
        
        // Add delay to prevent false positives during startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.isRunning, self.monitoringGeneration == generation else { return }
            // Low-frequency safety poll; space/activation notifications below drive prompt updates.
            self.monitoringTimer?.invalidate()
            self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkForFullscreenWindows()
            }

            // Run initial check after delay
            self.checkForFullscreenWindows()
        }

        // Listen for app activation and Space changes for immediate, event-driven updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleCheck),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleCheck),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        AppLogger.shared.info("FullscreenDetectionManager started monitoring")
    }
    
    func stopMonitoring() {
        guard isRunning else { return }
        
        isRunning = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil

        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        AppLogger.shared.info("FullscreenDetectionManager stopped monitoring")
    }
    
    @objc private func scheduleCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkForFullscreenWindows()
        }
    }

    @objc private func activeSpaceDidChange() {
        scheduleCheck()
        // Entering fullscreen animates for about a second; the first check sees the window mid-animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkForFullscreenWindows()
        }
    }

    private func checkForFullscreenWindows() {
        // Skip detection for the first 10 seconds after startup to avoid false positives
        if let startupTime = startupTime, Date().timeIntervalSince(startupTime) < 10.0 {
            return
        }

        guard !checkInFlight else { return }
        checkInFlight = true
        detectionQueue.async { [weak self] in
            let detected = Self.detectFullscreenDisplays(displays: Self.activeDisplays())
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checkInFlight = false
                guard self.fullscreenDisplayIDs != detected else { return }
                self.fullscreenDisplayIDs = detected
                AppLogger.shared.info("Fullscreen displays changed: \(detected.sorted())")
            }
        }
    }

    typealias DisplayInfo = (id: CGDirectDisplayID, bounds: CGRect)

    static func activeDisplays() -> [DisplayInfo] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplayCount))
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(maxDisplayCount, &displayIDs, &displayCount) == .success else {
            return []
        }
        return displayIDs.prefix(Int(displayCount)).map { (id: $0, bounds: CGDisplayBounds($0)) }
    }

    private static func windowMatches(_ window: CGRect, display: CGRect) -> Bool {
        abs(window.width - display.width) <= boundsTolerance &&
            abs(window.height - display.height) <= boundsTolerance &&
            abs(window.origin.x - display.origin.x) <= boundsTolerance &&
            abs(window.origin.y - display.origin.y) <= boundsTolerance
    }

    /// How a window sits relative to a display, in CG global coordinates.
    enum DisplayCoverage: Equatable {
        case none
        /// Matches the display bounds exactly: fullscreen with the menu bar hidden.
        case exact
        /// Full width, reaches the bottom edge, starts below the top by about a menu bar. This is
        /// native fullscreen with the menu bar kept visible, but a zoomed window looks identical,
        /// so it must be confirmed with the window's AXFullScreen attribute.
        case belowMenuBar
    }

    static let maxMenuBarInset: CGFloat = 60

    static func coverage(of window: CGRect, display: CGRect) -> DisplayCoverage {
        if windowMatches(window, display: display) { return .exact }
        let inset = window.minY - display.minY
        guard abs(window.minX - display.minX) <= boundsTolerance,
              abs(window.width - display.width) <= boundsTolerance,
              abs(window.maxY - display.maxY) <= boundsTolerance,
              inset > boundsTolerance, inset <= maxMenuBarInset else { return .none }
        return .belowMenuBar
    }

    /// IDs of the displays whose bounds the window covers (within tolerance). Both are in CG global coordinates.
    static func displayIDs(covered windowBounds: CGRect, displays: [DisplayInfo]) -> Set<CGDirectDisplayID> {
        Set(displays.filter { windowMatches(windowBounds, display: $0.bounds) }.map(\.id))
    }

    /// Asks the app whether the window at `windowBounds` is in native fullscreen. Runs off the main thread.
    private static func isAXFullScreen(pid: pid_t, windowBounds: CGRect) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return false }

        for axWindow in axWindows {
            var posRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                  let posValue = posRef else { continue }
            var origin = CGPoint.zero
            guard AXValueGetValue(posValue as! AXValue, .cgPoint, &origin),
                  abs(origin.x - windowBounds.minX) <= 5, abs(origin.y - windowBounds.minY) <= 5 else { continue }

            var fullScreenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, "AXFullScreen" as CFString, &fullScreenRef) == .success,
               let isFullScreen = fullScreenRef as? Bool {
                return isFullScreen
            }
        }
        return false
    }

    private static func detectFullscreenDisplays(displays: [DisplayInfo]) -> Set<CGDirectDisplayID> {
        var result = Set<CGDirectDisplayID>()
        guard !displays.isEmpty else { return result }

        // Get all on-screen windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return result
        }

        for windowInfo in windowList {
            // Check window layer - skip non-main windows (docks, menus, etc.)
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }

            // Check if window covers the entire screen
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            // Check if the window is on-screen and has full alpha
            guard let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool,
                  isOnScreen,
                  let alpha = windowInfo[kCGWindowAlpha as String] as? CGFloat,
                  alpha > 0.9 else {
                continue
            }

            // Window and display bounds are both in CG global coordinates (top-left origin)
            var covered = displayIDs(covered: bounds, displays: displays)
            var needsAXConfirmation = false
            if covered.isEmpty {
                covered = Set(displays.filter { coverage(of: bounds, display: $0.bounds) == .belowMenuBar }.map(\.id))
                needsAXConfirmation = !covered.isEmpty
            }
            guard !covered.isEmpty,
                  !covered.isSubset(of: result) else {
                continue
            }
            // kCGWindowName is withheld from apps without Screen Recording permission, so it must not
            // gate detection. Layer, alpha, exact display bounds and the owner app check are enough.
            let windowName = (windowInfo[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (windowInfo[kCGWindowOwnerName as String] as? String)
                ?? "unknown"

            // NSRunningApplication lookup is an IPC round-trip, so it runs only for candidates.
            if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               let app = NSRunningApplication(processIdentifier: ownerPID),
               app.bundleIdentifier == Bundle.main.bundleIdentifier || app.activationPolicy != .regular {
                continue
            }

            if needsAXConfirmation {
                guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                      isAXFullScreen(pid: ownerPID, windowBounds: bounds) else { continue }
            }
            AppLogger.shared.info("Detected fullscreen window: \(windowName) on display(s) \(covered.sorted())")
            result.formUnion(covered)
        }

        return result
    }
    
    deinit {
        stopMonitoring()
    }
}
