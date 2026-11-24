import XCTest
@testable import WinDock

final class SystemDockTests: XCTestCase {
    typealias Saved = MacOSDockManager.SavedSettings

    func testRestoreWritesTheUsersOwnValues() {
        let commands = MacOSDockManager.restoreCommands(Saved(autohide: true, autohideDelay: 0.5))

        XCTAssertEqual(commands.first, "defaults write com.apple.dock autohide -bool true")
        XCTAssertTrue(commands.contains("defaults write com.apple.dock autohide-delay -float 0.5"))
        XCTAssertEqual(commands.last, "killall Dock")
    }

    func testRestoreDeletesKeysTheUserNeverSet() {
        let commands = MacOSDockManager.restoreCommands(Saved(autohide: nil, autohideDelay: nil))

        XCTAssertTrue(commands[0].hasPrefix("defaults delete com.apple.dock autohide "))
        XCTAssertTrue(commands[1].hasPrefix("defaults delete com.apple.dock autohide-delay "))
    }

    func testDockHiddenByTheOldButtonIsTreatedAsDefaults() {
        let original = MacOSDockManager.originalSettings(autohide: true, autohideDelay: 1000)

        XCTAssertEqual(original, Saved(autohide: nil, autohideDelay: nil))
    }

    func testUsersOwnAutohideIsKept() {
        let original = MacOSDockManager.originalSettings(autohide: true, autohideDelay: 0.2)

        XCTAssertEqual(original, Saved(autohide: true, autohideDelay: 0.2))
    }

    func testHideCommandsTurnOnAutohideWithAHugeDelay() {
        let commands = MacOSDockManager.hideCommands(edge: "left")

        XCTAssertTrue(commands.contains("defaults write com.apple.dock autohide -bool true"))
        XCTAssertTrue(commands.contains("defaults write com.apple.dock autohide-delay -float 1000.0"))
    }

    func testWatchdogWaitsForThePidAndRestoresOnlyWhileTheMarkerExists() {
        let script = MacOSDockManager.watchdogScript(pid: 4242, domain: "Some.Domain", saved: Saved(autohide: nil, autohideDelay: nil))

        XCTAssertTrue(script.contains("kill -0 4242"))
        XCTAssertTrue(script.contains("defaults read Some.Domain \(MacOSDockManager.savedKey)"))
        XCTAssertTrue(script.contains("pgrep -x WinDock"))
        XCTAssertTrue(script.contains("killall Dock"))
        XCTAssertTrue(script.hasSuffix("defaults delete Some.Domain \(MacOSDockManager.savedKey)"))
    }

    func testWatchdogScriptCannotBeKilledByRunShsPkill() {
        // run.sh does `pkill -f "WinDock.app"`; the watcher must outlive that.
        let script = MacOSDockManager.watchdogScript(pid: 1, domain: "WillowTech.WinDock", saved: Saved(autohide: true, autohideDelay: 0))

        XCTAssertNil(script.range(of: "WinDock.app", options: .regularExpression))
    }

    // MARK: - Dock edge

    func testDockMovesAwayFromTheTaskbarsEdge() {
        XCTAssertEqual(MacOSDockManager.dockEdge(avoiding: .bottom), "left")
        XCTAssertEqual(MacOSDockManager.dockEdge(avoiding: .top), "left")
        XCTAssertEqual(MacOSDockManager.dockEdge(avoiding: .right), "left")
        XCTAssertEqual(MacOSDockManager.dockEdge(avoiding: .left), "right")
    }

    func testHideCommandsMoveTheDockToTheChosenEdge() {
        let commands = MacOSDockManager.hideCommands(edge: "right")

        XCTAssertTrue(commands.contains("defaults write com.apple.dock orientation -string right"))
        XCTAssertEqual(commands.last, "killall Dock")
    }

    func testRestorePutsTheUsersOrientationBack() {
        let commands = MacOSDockManager.restoreCommands(Saved(autohide: nil, autohideDelay: nil, orientation: "bottom", changedOrientation: true))

        XCTAssertTrue(commands.contains("defaults write com.apple.dock orientation -string bottom"))
        XCTAssertEqual(commands.last, "killall Dock")
    }

    func testRestoreDeletesOrientationTheUserNeverSet() {
        let commands = MacOSDockManager.restoreCommands(Saved(autohide: nil, autohideDelay: nil, orientation: nil, changedOrientation: true))

        XCTAssertTrue(commands.contains { $0.hasPrefix("defaults delete com.apple.dock orientation ") })
    }

    func testMarkerFromBeforeOrientationSupportLeavesOrientationAlone() throws {
        // A marker saved by the previous version has no orientation fields at all.
        let old = #"{"autohide":true,"autohideDelay":0.5}"#.data(using: .utf8)!
        let saved = try JSONDecoder().decode(Saved.self, from: old)

        XCTAssertNotEqual(saved.changedOrientation, true)
        XCTAssertFalse(MacOSDockManager.restoreCommands(saved).contains { $0.contains("orientation") })
    }
}
