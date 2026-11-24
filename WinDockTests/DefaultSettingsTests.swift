import XCTest
@testable import WinDock

final class DefaultSettingsTests: XCTestCase {

    func testWindowsResizeIsEnabledOnFreshInstall() {
        let suite = "DefaultSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        AppDelegate.registerDefaultSettings(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: "enableWindowsResize"))
    }

    func testUserChoiceOverridesRegisteredDefault() {
        let suite = "DefaultSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: "enableWindowsResize")
        AppDelegate.registerDefaultSettings(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: "enableWindowsResize"))
    }
}
