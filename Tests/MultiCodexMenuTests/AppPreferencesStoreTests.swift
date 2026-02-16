import XCTest
@testable import MultiCodexMenu

final class AppPreferencesStoreTests: XCTestCase {
    func testCustomCodexPathFallsBackToLegacyNodeKey() {
        let defaults = ephemeralDefaults()
        defaults.set("/opt/homebrew/bin/codex", forKey: AppPreferencesStore.Keys.legacyCustomNodePath)

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.customCodexPath, "/opt/homebrew/bin/codex")
    }

    func testSelectedSettingsAccountFallsBackToLegacyKey() {
        let defaults = ephemeralDefaults()
        defaults.set("alpha", forKey: AppPreferencesStore.Keys.legacySelectedSettingsAccountKey)

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.selectedSettingsAccountName, "alpha")
    }

    func testSettingCustomCodexPathClearsLegacyKeys() {
        let defaults = ephemeralDefaults()
        defaults.set("legacy", forKey: AppPreferencesStore.Keys.legacyCustomNodePath)
        defaults.set("legacy2", forKey: AppPreferencesStore.Keys.legacyCustomExecutablePath)

        var store = AppPreferencesStore(defaults: defaults)
        store.customCodexPath = "/usr/local/bin/codex"

        XCTAssertEqual(defaults.string(forKey: AppPreferencesStore.Keys.customCodexPath), "/usr/local/bin/codex")
        XCTAssertNil(defaults.string(forKey: AppPreferencesStore.Keys.legacyCustomNodePath))
        XCTAssertNil(defaults.string(forKey: AppPreferencesStore.Keys.legacyCustomExecutablePath))
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "MultiCodexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
