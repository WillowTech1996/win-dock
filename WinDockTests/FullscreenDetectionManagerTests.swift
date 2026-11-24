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
}
