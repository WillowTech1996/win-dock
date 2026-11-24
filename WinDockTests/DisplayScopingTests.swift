import XCTest
@testable import WinDock

final class DisplayScopingTests: XCTestCase {
    private let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let right = CGRect(x: 1920, y: -41, width: 1920, height: 1080)
    private var displays: [CGRect] { [left, right] }

    private func window(_ id: CGWindowID, _ bounds: CGRect) -> WindowInfo {
        WindowInfo(title: "w\(id)", windowID: id, bounds: bounds, isMinimized: false, isOnScreen: true)
    }

    private func app(pinned: Bool, windows: [WindowInfo]) -> DockApp {
        DockApp(bundleIdentifier: "com.test.app", name: "Test", icon: nil, url: nil, isPinned: pinned,
                runningApplication: nil, windows: windows)
    }

    func testWindowBelongsToDisplayHoldingItsCenter() {
        let w = window(1, CGRect(x: 2000, y: 0, width: 800, height: 600))

        XCTAssertTrue(w.isOn(right, among: displays))
        XCTAssertFalse(w.isOn(left, among: displays))
    }

    func testWindowStraddlingDisplaysGoesToTheOneHoldingItsCenter() {
        let w = window(1, CGRect(x: 1500, y: 0, width: 800, height: 600)) // center x = 1900, on the left

        XCTAssertTrue(w.isOn(left, among: displays))
        XCTAssertFalse(w.isOn(right, among: displays))
    }

    func testWindowOnNoDisplayBelongsToEveryDisplay() {
        let w = window(1, CGRect(x: -9000, y: -9000, width: 800, height: 600))

        XCTAssertTrue(w.isOn(left, among: displays))
        XCTAssertTrue(w.isOn(right, among: displays))
    }

    func testUnpinnedAppIsHiddenWhereItHasNoWindows() {
        let a = app(pinned: false, windows: [window(1, CGRect(x: 100, y: 100, width: 800, height: 600))])

        XCTAssertNotNil(a.scoped(to: left, among: displays))
        XCTAssertNil(a.scoped(to: right, among: displays))
    }

    func testPinnedAppStaysEverywhereButOnlyKeepsLocalWindows() throws {
        let a = app(pinned: true, windows: [window(1, CGRect(x: 100, y: 100, width: 800, height: 600))])

        let onRight = try XCTUnwrap(a.scoped(to: right, among: displays))
        XCTAssertTrue(onRight.windows.isEmpty)
        XCTAssertFalse(onRight.hasWindows)
        XCTAssertEqual(try XCTUnwrap(a.scoped(to: left, among: displays)).windowCount, 1)
    }

    func testAppWithNoWindowsAnywhereIsUnchanged() throws {
        let a = app(pinned: false, windows: [])

        let scoped = try XCTUnwrap(a.scoped(to: right, among: displays))
        XCTAssertNil(scoped.displayBounds)
    }

    func testWindowsAreSplitAcrossDisplays() throws {
        let a = app(pinned: false, windows: [
            window(1, CGRect(x: 100, y: 100, width: 800, height: 600)),
            window(2, CGRect(x: 2000, y: 0, width: 800, height: 600)),
            window(3, CGRect(x: 200, y: 200, width: 800, height: 600)),
        ])

        XCTAssertEqual(try XCTUnwrap(a.scoped(to: left, among: displays)).windows.map(\.windowID), [1, 3])
        XCTAssertEqual(try XCTUnwrap(a.scoped(to: right, among: displays)).windows.map(\.windowID), [2])
    }

    // MARK: - Taskbar window reconciliation

    func testHotPlugKeepsExistingWindowsAndCreatesOnlyTheNewOne() {
        let changes = AppDelegate.displayChanges(existing: [1, 2], wanted: [1, 2, 3])

        XCTAssertEqual(changes.create, [3])
        XCTAssertTrue(changes.close.isEmpty)
    }

    func testUnplugClosesOnlyTheGoneDisplaysWindow() {
        let changes = AppDelegate.displayChanges(existing: [1, 2, 3], wanted: [1, 3])

        XCTAssertTrue(changes.create.isEmpty)
        XCTAssertEqual(changes.close, [2])
    }

    func testNoChangeDoesNothing() {
        let changes = AppDelegate.displayChanges(existing: [1, 2], wanted: [2, 1])

        XCTAssertTrue(changes.create.isEmpty)
        XCTAssertTrue(changes.close.isEmpty)
    }
}
