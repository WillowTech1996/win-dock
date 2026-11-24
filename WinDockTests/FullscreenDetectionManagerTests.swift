import XCTest
@testable import WinDock

final class FullscreenDetectionManagerTests: XCTestCase {
    private let primaryDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let secondaryDisplayAbove = CGRect(x: -200, y: -1080, width: 1920, height: 1080)

    func testWindowWithinToleranceMatches() {
        let nearlyFull = primaryDisplay.insetBy(dx: 1, dy: 1)

        XCTAssertEqual(FullscreenDetectionManager.displayIDs(covered: nearlyFull, displays: [(id: 1, bounds: primaryDisplay)]), [1])
    }

    func testNoDisplaysNeverMatches() {
        XCTAssertTrue(FullscreenDetectionManager.displayIDs(covered: primaryDisplay, displays: []).isEmpty)
    }

    // MARK: - Per-display detection

    private var displays: [FullscreenDetectionManager.DisplayInfo] {
        [(id: 1, bounds: primaryDisplay), (id: 2, bounds: secondaryDisplayAbove)]
    }

    func testFullscreenOnSecondaryReportsOnlySecondary() {
        let ids = FullscreenDetectionManager.displayIDs(covered: secondaryDisplayAbove, displays: displays)

        XCTAssertEqual(ids, [2])
    }

    func testFullscreenOnPrimaryReportsOnlyPrimary() {
        let ids = FullscreenDetectionManager.displayIDs(covered: primaryDisplay, displays: displays)

        XCTAssertEqual(ids, [1])
    }

    func testMaximizedWindowReportsNoDisplay() {
        let maximized = CGRect(x: 0, y: 33, width: 1512, height: 949)

        XCTAssertTrue(FullscreenDetectionManager.displayIDs(covered: maximized, displays: displays).isEmpty)
    }

    func testMirroredDisplaysWithIdenticalBoundsAreAllReported() {
        let mirrored: [FullscreenDetectionManager.DisplayInfo] = [(id: 1, bounds: primaryDisplay), (id: 3, bounds: primaryDisplay)]

        XCTAssertEqual(FullscreenDetectionManager.displayIDs(covered: primaryDisplay, displays: mirrored), [1, 3])
    }

    func testIsFullscreenIsFalseForUnknownDisplay() {
        XCTAssertFalse(FullscreenDetectionManager.shared.isFullscreen(on: nil))
    }

    // MARK: - Coverage classification

    func testExactBoundsAreExactCoverage() {
        XCTAssertEqual(FullscreenDetectionManager.coverage(of: primaryDisplay, display: primaryDisplay), .exact)
    }

    func testFullscreenBelowVisibleMenuBarIsDetectedAsCandidate() {
        // Native fullscreen with "always show menu bar in fullscreen": 30pt inset, bottom aligned.
        let window = CGRect(x: 0, y: 30, width: 1512, height: 952)

        XCTAssertEqual(FullscreenDetectionManager.coverage(of: window, display: primaryDisplay), .belowMenuBar)
    }

    func testBelowMenuBarCandidateWorksOnSecondaryDisplayWithNegativeOrigin() {
        let window = CGRect(x: -200, y: -1050, width: 1920, height: 1050)

        XCTAssertEqual(FullscreenDetectionManager.coverage(of: window, display: secondaryDisplayAbove), .belowMenuBar)
    }

    func testWindowAboveTaskbarIsNotACandidate() {
        // A window kept clear of a 56pt taskbar does not reach the bottom edge.
        let window = CGRect(x: 0, y: 33, width: 1512, height: 893)

        XCTAssertEqual(FullscreenDetectionManager.coverage(of: window, display: primaryDisplay), .none)
    }

    func testNarrowWindowIsNotACandidate() {
        let window = CGRect(x: 0, y: 30, width: 1400, height: 952)

        XCTAssertEqual(FullscreenDetectionManager.coverage(of: window, display: primaryDisplay), .none)
    }

    func testLargeTopInsetIsNotACandidate() {
        let window = CGRect(x: 0, y: 300, width: 1512, height: 682)

        XCTAssertEqual(FullscreenDetectionManager.coverage(of: window, display: primaryDisplay), .none)
    }

    // MARK: - Edge reveal during fullscreen

    private let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let barFrame = NSRect(x: 0, y: 0, width: 1920, height: 56)

    func testBottomEdgeTriggerCoversThePointerAtTheScreenEdgeOnly() {
        let trigger = DockWindow.edgeTrigger(for: .bottom, screenFrame: screenFrame, barFrame: barFrame)

        XCTAssertTrue(trigger.contains(NSPoint(x: 900, y: 0)))
        XCTAssertTrue(trigger.contains(NSPoint(x: 900, y: 3)))
        XCTAssertFalse(trigger.contains(NSPoint(x: 900, y: 20)), "pointer over the app's own controls must not reveal the bar")
    }

    func testTopEdgeTriggerIsAtTheTopOfTheScreen() {
        let trigger = DockWindow.edgeTrigger(for: .top, screenFrame: screenFrame, barFrame: NSRect(x: 0, y: 1024, width: 1920, height: 56))

        XCTAssertTrue(trigger.contains(NSPoint(x: 100, y: 1079)))
        XCTAssertFalse(trigger.contains(NSPoint(x: 100, y: 1000)))
    }

    func testSideEdgeTriggersFollowTheBar() {
        let left = DockWindow.edgeTrigger(for: .left, screenFrame: screenFrame, barFrame: NSRect(x: 0, y: 0, width: 56, height: 1080))
        let right = DockWindow.edgeTrigger(for: .right, screenFrame: screenFrame, barFrame: NSRect(x: 1864, y: 0, width: 56, height: 1080))

        XCTAssertTrue(left.contains(NSPoint(x: 1, y: 500)))
        XCTAssertFalse(left.contains(NSPoint(x: 100, y: 500)))
        XCTAssertTrue(right.contains(NSPoint(x: 1918, y: 500)))
        XCTAssertFalse(right.contains(NSPoint(x: 1800, y: 500)))
    }

    func testEdgeTriggerOnASecondaryDisplayUsesThatDisplaysCoordinates() {
        let secondary = NSRect(x: 1920, y: -41, width: 1920, height: 1080)
        let trigger = DockWindow.edgeTrigger(for: .bottom, screenFrame: secondary, barFrame: NSRect(x: 1920, y: -41, width: 1920, height: 56))

        XCTAssertTrue(trigger.contains(NSPoint(x: 2500, y: -40)))
        XCTAssertFalse(trigger.contains(NSPoint(x: 500, y: 0)), "the main display's edge must not trigger this display")
    }
}
