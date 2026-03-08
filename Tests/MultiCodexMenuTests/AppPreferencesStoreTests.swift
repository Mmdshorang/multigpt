import XCTest
@testable import MultiCodexMenu

final class AppPreferencesStoreTests: XCTestCase {
    func testCustomCodexPathDefaultsToEmptyWhenUnset() {
        let defaults = ephemeralDefaults()

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.customCodexPath, "")
    }

    func testSelectedSettingsAccountDefaultsToNilWhenUnset() {
        let defaults = ephemeralDefaults()

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertNil(store.selectedSettingsAccountName)
    }

    func testSettingCustomCodexPathPersistsCanonicalKey() {
        let defaults = ephemeralDefaults()

        var store = AppPreferencesStore(defaults: defaults)
        store.customCodexPath = "/usr/local/bin/codex"

        XCTAssertEqual(defaults.string(forKey: AppPreferencesStore.Keys.customCodexPath), "/usr/local/bin/codex")
    }

    func testDefaultsForDisplayAndSandboxSettings() {
        let defaults = ephemeralDefaults()
        var store = AppPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.resetDisplayMode, .relative)
        XCTAssertEqual(store.menuDensity, .compact)
        XCTAssertEqual(store.usageBarStyle, .depleting)
        XCTAssertFalse(store.temporaryAuthSandboxEnabled)
        XCTAssertNil(store.temporaryAuthSandboxHome)

        store.resetDisplayMode = .absolute
        store.menuDensity = .comfortable
        store.usageBarStyle = .filling
        store.temporaryAuthSandboxEnabled = true
        store.temporaryAuthSandboxHome = "/tmp/multicodex-test-home"

        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.resetDisplayMode, .absolute)
        XCTAssertEqual(persisted.menuDensity, .comfortable)
        XCTAssertEqual(persisted.usageBarStyle, .filling)
        XCTAssertTrue(persisted.temporaryAuthSandboxEnabled)
        XCTAssertEqual(persisted.temporaryAuthSandboxHome, "/tmp/multicodex-test-home")
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "MultiCodexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
