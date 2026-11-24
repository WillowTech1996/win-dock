import XCTest
@testable import WinDock

final class SettingsMigrationTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "SettingsMigrationTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testOldKeyIsCopiedToTheNewKeyAndRemoved() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showOnAllSpaces")

        AppDelegate.migrateLegacySettings(in: defaults)

        XCTAssertEqual(defaults.object(forKey: "showOnAllDisplays") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "showOnAllSpaces"))
    }

    func testNewKeyWinsWhenBothExist() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showOnAllSpaces")
        defaults.set(true, forKey: "showOnAllDisplays")

        AppDelegate.migrateLegacySettings(in: defaults)

        XCTAssertEqual(defaults.object(forKey: "showOnAllDisplays") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "showOnAllSpaces"))
    }

    func testNothingIsCreatedWhenNeitherKeyExists() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        AppDelegate.migrateLegacySettings(in: defaults)

        XCTAssertNil(defaults.object(forKey: "showOnAllDisplays"))
    }

    func testBackupMadeBeforeTheRenameStillImports() throws {
        let json = #"{"showOnAllSpaces": false}"#.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertFalse(settings.showOnAllDisplays)
    }

    func testBackupWithTheNewNameImportsAndTheDefaultIsTrue() throws {
        let renamed = try JSONDecoder().decode(AppSettings.self, from: #"{"showOnAllDisplays": false}"#.data(using: .utf8)!)
        let empty = try JSONDecoder().decode(AppSettings.self, from: "{}".data(using: .utf8)!)

        XCTAssertFalse(renamed.showOnAllDisplays)
        XCTAssertTrue(empty.showOnAllDisplays)
    }
}
