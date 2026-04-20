import XCTest
@testable import MultiCodex

final class AppPreferencesStoreTests: XCTestCase {
    func testCustomCodexPathDefaultsToEmptyWhenUnset() {
        let defaults = makeEphemeralDefaults()

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.customCodexPath, "")
    }

    func testSelectedSettingsAccountDefaultsToNilWhenUnset() {
        let defaults = makeEphemeralDefaults()

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertNil(store.selectedSettingsAccountName)
    }

    func testSettingCustomCodexPathPersistsCanonicalKey() {
        let defaults = makeEphemeralDefaults()

        var store = AppPreferencesStore(defaults: defaults)
        store.customCodexPath = "/usr/local/bin/codex"

        XCTAssertEqual(defaults.string(forKey: AppPreferencesStore.Keys.customCodexPath), "/usr/local/bin/codex")
    }

    func testDefaultsForDisplaySettings() {
        let defaults = makeEphemeralDefaults()
        var store = AppPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.resetDisplayMode, .relative)
        XCTAssertEqual(store.menuDensity, .compact)
        XCTAssertEqual(store.usageBarStyle, .depleting)
        XCTAssertEqual(store.accountSwitchingStrategy, .manual)
        XCTAssertFalse(store.autoSwitchNotificationsEnabled)

        store.resetDisplayMode = .absolute
        store.menuDensity = .comfortable
        store.usageBarStyle = .filling
        store.accountSwitchingStrategy = .expiryAware
        store.autoSwitchNotificationsEnabled = true

        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.resetDisplayMode, .absolute)
        XCTAssertEqual(persisted.menuDensity, .comfortable)
        XCTAssertEqual(persisted.usageBarStyle, .filling)
        XCTAssertEqual(persisted.accountSwitchingStrategy, .expiryAware)
        XCTAssertTrue(persisted.autoSwitchNotificationsEnabled)
    }

    func testDefaultsForAccountSorting() {
        let defaults = makeEphemeralDefaults()
        let store = AppPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.accountSortCriterion, .used)
        XCTAssertEqual(store.accountSortWindow, .fiveHour)
        XCTAssertEqual(store.accountSortDirection, .descending)
    }

    func testAccountSortingPreferencesRoundTrip() {
        let defaults = makeEphemeralDefaults()
        var store = AppPreferencesStore(defaults: defaults)

        store.accountSortCriterion = .remaining
        store.accountSortWindow = .weekly
        store.accountSortDirection = .ascending

        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.accountSortCriterion, .remaining)
        XCTAssertEqual(persisted.accountSortWindow, .weekly)
        XCTAssertEqual(persisted.accountSortDirection, .ascending)
    }

    func testInvalidAccountSortingRawValuesFallbackToDefaults() {
        let defaults = makeEphemeralDefaults()
        defaults.set("bogus", forKey: AppPreferencesStore.Keys.accountSortCriterion)
        defaults.set("bogus", forKey: AppPreferencesStore.Keys.accountSortWindow)
        defaults.set("bogus", forKey: AppPreferencesStore.Keys.accountSortDirection)

        let store = AppPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.accountSortCriterion, .used)
        XCTAssertEqual(store.accountSortWindow, .fiveHour)
        XCTAssertEqual(store.accountSortDirection, .descending)
    }

}
