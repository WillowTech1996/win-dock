import XCTest
@testable import WinDock

final class WindowEnumerationServiceTests: XCTestCase {

    func testTTLIsShortDuringChurn() {
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 0), 1.0)
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 9.9), 1.0)
    }

    func testTTLWidensWhenQuiet() {
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 10.0), 5.0)
        XCTAssertEqual(WindowEnumerationService.cacheTTL(secondsSinceLastInvalidation: 3600), 5.0)
    }

    func testCachedWindowsValidityRespectsTTL() {
        let fresh = WindowEnumerationService.CachedWindows(windows: [], timestamp: Date())
        let stale = WindowEnumerationService.CachedWindows(windows: [], timestamp: Date().addingTimeInterval(-2))

        XCTAssertTrue(fresh.isValid(ttl: 1.0))
        XCTAssertFalse(stale.isValid(ttl: 1.0))
        XCTAssertTrue(stale.isValid(ttl: 5.0))
    }

    // MARK: - Hidden leftover windows

    func testHiddenWindowInAnActiveSpaceIsALeftover() {
        // Claude hides a closed window instead of destroying it: off screen, not minimized, still in Space 1.
        XCTAssertTrue(WindowEnumerationService.isHiddenLeftover(
            isOnScreen: false, isMinimized: false, isAppHidden: false, windowSpaces: [1], activeSpaces: [1, 957]))
    }

    func testWindowInNoSpaceIsALeftover() {
        XCTAssertTrue(WindowEnumerationService.isHiddenLeftover(
            isOnScreen: false, isMinimized: false, isAppHidden: false, windowSpaces: [], activeSpaces: [1, 957]))
    }

    func testVisibleWindowIsNeverALeftover() {
        XCTAssertFalse(WindowEnumerationService.isHiddenLeftover(
            isOnScreen: true, isMinimized: false, isAppHidden: false, windowSpaces: [1], activeSpaces: [1]))
    }

    func testMinimizedWindowIsNeverALeftover() {
        XCTAssertFalse(WindowEnumerationService.isHiddenLeftover(
            isOnScreen: false, isMinimized: true, isAppHidden: false, windowSpaces: [1], activeSpaces: [1]))
    }

    func testWindowOnAnotherSpaceIsKept() {
        // From a fullscreen Space (current 999) the desktop Space's windows are off screen but real.
        XCTAssertFalse(WindowEnumerationService.isHiddenLeftover(
            isOnScreen: false, isMinimized: false, isAppHidden: false, windowSpaces: [1], activeSpaces: [999, 957]))
    }

    func testWindowsOfAnAppHiddenWithCommandHAreKept() {
        XCTAssertFalse(WindowEnumerationService.isHiddenLeftover(
            isOnScreen: false, isMinimized: false, isAppHidden: true, windowSpaces: [1], activeSpaces: [1]))
    }

    func testCurrentSpacesAreReadableOnThisMac() {
        XCTAssertNotNil(WindowEnumerationService.currentSpaceIDs())
    }
}
