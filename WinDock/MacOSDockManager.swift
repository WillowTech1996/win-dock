import Foundation
import AppKit

/// Hides the system Dock (auto-hide with a huge delay) and puts the user's own Dock settings back afterwards.
///
/// The original values are saved before the first change and cleared only after they are restored, so the
/// saved copy doubles as a "WinDock hid the Dock" marker that survives a crash. While the Dock is hidden a
/// detached shell watcher restores it if WinDock exits without doing so.
final class MacOSDockManager: ObservableObject {
    static let shared = MacOSDockManager()

    /// A Dock preference as the user had it; nil means the key was not set.
    struct SavedSettings: Codable, Equatable {
        var autohide: Bool?
        var autohideDelay: Double?
        /// The Dock edge the user had, and whether WinDock moved it. Markers saved by earlier versions have
        /// neither, which reads as "not moved".
        var orientation: String?
        var changedOrientation: Bool?
    }

    static let savedKey = "WinDock.savedSystemDock"
    static let preferenceKey = "hideSystemDockWhileRunning"
    /// Posted after WinDock hid or restored the Dock: screens' usable areas change, so taskbars must reposition.
    static let didChangeNotification = Notification.Name("WinDock.systemDockDidChange")
    /// The delay the old manual "Hide Mac Dock" button wrote. Nobody sets this by hand, so it marks a Dock
    /// hidden by an earlier version that saved nothing.
    private static let hiddenDelay = 1000.0

    @Published private(set) var isDockHidden = false
    @Published var lastError: String?
    @Published private(set) var isProcessing = false

    private let queue = DispatchQueue(label: "WinDock.system-dock")
    private var watchdogStarted = false

    private init() {
        queue.async { [weak self] in
            guard let self else { return }
            let hidden = self.isHiddenNow()
            DispatchQueue.main.async { self.isDockHidden = hidden }
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// A fullscreen app reveals the Dock at its edge no matter the auto-hide delay, which would draw it over
    /// WinDock's bar. Moving the Dock to an edge WinDock does not use keeps the two apart.
    static func dockEdge(avoiding position: DockPosition) -> String {
        position == .left ? "right" : "left"
    }

    static func hideCommands(edge: String) -> [String] {
        [
            "defaults write com.apple.dock autohide -bool true",
            "defaults write com.apple.dock autohide-delay -float \(hiddenDelay)",
            "defaults write com.apple.dock orientation -string \(edge)",
            "killall Dock"
        ]
    }

    static func restoreCommands(_ saved: SavedSettings) -> [String] {
        var commands = [
            saved.autohide.map { "defaults write com.apple.dock autohide -bool \($0)" }
                ?? "defaults delete com.apple.dock autohide 2>/dev/null || true",
            saved.autohideDelay.map { "defaults write com.apple.dock autohide-delay -float \($0)" }
                ?? "defaults delete com.apple.dock autohide-delay 2>/dev/null || true"
        ]
        if saved.changedOrientation == true {
            commands.append(saved.orientation.map { "defaults write com.apple.dock orientation -string \($0)" }
                ?? "defaults delete com.apple.dock orientation 2>/dev/null || true")
        }
        commands.append("killall Dock")
        return commands
    }

    /// What to restore, given the Dock's current values when WinDock has not saved anything yet.
    static func originalSettings(autohide: Bool?, autohideDelay: Double?) -> SavedSettings {
        if autohide == true && autohideDelay == hiddenDelay {
            return SavedSettings(autohide: nil, autohideDelay: nil)
        }
        return SavedSettings(autohide: autohide, autohideDelay: autohideDelay)
    }

    /// Runs after WinDock (`pid`) is gone. Waits a few seconds so a quick relaunch (a rebuild) keeps ownership,
    /// and only restores if the saved marker is still there. Must not contain the app bundle's file name:
    /// run.sh kills processes by matching it.
    static func watchdogScript(pid: Int32, domain: String, saved: SavedSettings) -> String {
        """
        while kill -0 \(pid) 2>/dev/null; do sleep 2; done
        sleep 4
        pgrep -x WinDock >/dev/null && exit 0
        defaults read \(domain) \(savedKey) >/dev/null 2>&1 || exit 0
        \(restoreCommands(saved).joined(separator: "; "))
        defaults delete \(domain) \(savedKey)
        """
    }

    // MARK: - Public API

    func hideMacOSDock() {
        perform { self.hide() }
    }

    func showMacOSDock() {
        perform { self.restore() }
    }

    /// Applies the "hide while running" setting: hide if on; if off, undo a hide left over from an earlier run.
    func applyPreference() {
        let wantHidden = UserDefaults.standard.bool(forKey: Self.preferenceKey)
        perform {
            if wantHidden { return self.hide() }
            guard self.savedSettings != nil else { return true }
            return self.restore()
        }
    }

    /// Blocking: called while the app terminates.
    func restoreOnQuit() {
        // Another WinDock (a second instance, or a relaunch) still running owns the hidden Dock.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        guard others.isEmpty else { return }
        queue.sync {
            if self.savedSettings != nil {
                AppLogger.shared.info("Restoring the system Dock on quit")
                _ = self.restore()
            }
        }
    }

    // MARK: - Work (runs on `queue`)

    private var savedSettings: SavedSettings? {
        get { UserDefaults.standard.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode(SavedSettings.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.savedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedKey)
            }
        }
    }

    private func hide() -> Bool {
        // Save first: if anything below dies half way, the marker lets a later run put things back.
        var saved = savedSettings ?? currentSettings()
        if saved.changedOrientation != true {
            saved.orientation = readDockDefault("orientation")
            saved.changedOrientation = true
        }
        savedSettings = saved

        let position = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "bottom") ?? .bottom
        let edge = Self.dockEdge(avoiding: position)
        if !isHiddenNow() || (readDockDefault("orientation") ?? "bottom") != edge {
            guard executeShellCommands(Self.hideCommands(edge: edge)) else { return false }
            AppLogger.shared.info("System Dock hidden on the \(edge) edge; saved original settings: \(saved)")
        }
        startWatchdog(saved)
        return true
    }

    private func restore() -> Bool {
        // With no marker this is a Dock hidden by the old manual button: derive the originals from its values.
        let saved = savedSettings ?? currentSettings()
        guard executeShellCommands(Self.restoreCommands(saved)) else { return false }
        savedSettings = nil
        AppLogger.shared.info("System Dock restored: \(saved)")
        return true
    }

    private func startWatchdog(_ saved: SavedSettings) {
        guard !watchdogStarted else { return }
        watchdogStarted = true
        let script = Self.watchdogScript(pid: ProcessInfo.processInfo.processIdentifier,
                                         domain: Bundle.main.bundleIdentifier ?? "WillowTech.WinDock", saved: saved)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            AppLogger.shared.info("System Dock watchdog started for pid \(ProcessInfo.processInfo.processIdentifier)")
        } catch {
            watchdogStarted = false
            AppLogger.shared.error("Could not start the system Dock watchdog: \(error.localizedDescription)")
        }
    }

    private func perform(_ work: @escaping () -> Bool) {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.lastError = nil
        }
        queue.async {
            _ = work()
            let hidden = self.savedSettings != nil || self.isHiddenNow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isDockHidden = hidden
                self.isProcessing = false
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }

    // MARK: - Reading and running

    private func readDockDefault(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentSettings() -> SavedSettings {
        Self.originalSettings(autohide: readDockDefault("autohide").map { $0 == "1" },
                              autohideDelay: readDockDefault("autohide-delay").flatMap(Double.init))
    }

    private func isHiddenNow() -> Bool {
        readDockDefault("autohide") == "1" && readDockDefault("autohide-delay").flatMap(Double.init) == Self.hiddenDelay
    }

    @discardableResult
    private func executeShellCommands(_ commands: [String]) -> Bool {
        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            let errorPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                report("Failed to run: \(command)\n\(error.localizedDescription)")
                return false
            }
            if process.terminationStatus != 0 {
                let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                report("Command failed: \(command)\n\(message)")
                return false
            }
        }
        return true
    }

    private func report(_ message: String) {
        AppLogger.shared.error(message)
        DispatchQueue.main.async { self.lastError = message }
    }
}
