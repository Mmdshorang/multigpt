import Foundation

struct AppPreferencesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var customCodexPath: String {
        get {
            defaults.string(forKey: Keys.customCodexPath)
                ?? defaults.string(forKey: Keys.legacyCustomNodePath)
                ?? defaults.string(forKey: Keys.legacyCustomExecutablePath)
                ?? ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: Keys.customCodexPath)
                defaults.removeObject(forKey: Keys.legacyCustomNodePath)
                defaults.removeObject(forKey: Keys.legacyCustomExecutablePath)
                return
            }
            defaults.set(trimmed, forKey: Keys.customCodexPath)
            defaults.removeObject(forKey: Keys.legacyCustomNodePath)
            defaults.removeObject(forKey: Keys.legacyCustomExecutablePath)
        }
    }

    var resetDisplayMode: ResetDisplayMode {
        get {
            let raw = defaults.string(forKey: Keys.resetDisplayMode) ?? ""
            return ResetDisplayMode(rawValue: raw) ?? .relative
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.resetDisplayMode)
        }
    }

    var selectedSettingsSection: SettingsSection {
        get {
            let raw = defaults.string(forKey: Keys.selectedSettingsSection) ?? ""
            return SettingsSection(rawValue: raw) ?? .dashboard
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedSettingsSection)
        }
    }

    var selectedSettingsAccountName: String? {
        get {
            defaults.string(forKey: Keys.selectedSettingsAccountName)
                ?? defaults.string(forKey: Keys.legacySelectedSettingsAccountKey)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.selectedSettingsAccountName)
                defaults.removeObject(forKey: Keys.legacySelectedSettingsAccountKey)
            } else {
                defaults.removeObject(forKey: Keys.selectedSettingsAccountName)
            }
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var isAdvancedSettingsVisible: Bool {
        get { defaults.bool(forKey: Keys.isAdvancedSettingsVisible) }
        set { defaults.set(newValue, forKey: Keys.isAdvancedSettingsVisible) }
    }

    var menuDensity: MenuDensity {
        get {
            let raw = defaults.string(forKey: Keys.menuDensity) ?? ""
            return MenuDensity(rawValue: raw) ?? .compact
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.menuDensity)
        }
    }

    var usageBarStyle: UsageBarStyle {
        get {
            let raw = defaults.string(forKey: Keys.usageBarStyle) ?? ""
            return UsageBarStyle(rawValue: raw) ?? .depleting
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.usageBarStyle)
        }
    }

    var limitsCacheTTLSeconds: Int {
        get {
            defaults.integer(forKey: Keys.limitsCacheTTLSeconds)
        }
        set {
            defaults.set(newValue, forKey: Keys.limitsCacheTTLSeconds)
        }
    }

    var temporaryAuthSandboxEnabled: Bool {
        get { defaults.bool(forKey: Keys.temporaryAuthSandboxEnabled) }
        set { defaults.set(newValue, forKey: Keys.temporaryAuthSandboxEnabled) }
    }

    var temporaryAuthSandboxHome: String? {
        get { defaults.string(forKey: Keys.temporaryAuthSandboxHome) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.temporaryAuthSandboxHome)
            } else {
                defaults.removeObject(forKey: Keys.temporaryAuthSandboxHome)
            }
        }
    }

    enum Keys {
        static let customCodexPath = "multicodexMenu.customCodexPath"
        static let legacyCustomNodePath = "multicodexMenu.customNodePath"
        static let legacyCustomExecutablePath = "multicodexMenu.customExecutablePath"
        static let resetDisplayMode = "multicodexMenu.resetDisplayMode"
        static let temporaryAuthSandboxEnabled = "multicodexMenu.temporaryAuthSandboxEnabled"
        static let temporaryAuthSandboxHome = "multicodexMenu.temporaryAuthSandboxHome"
        static let selectedSettingsSection = "multicodexMenu.selectedSettingsSection"
        static let selectedSettingsAccountName = "multicodexMenu.selectedSettingsAccountName"
        static let legacySelectedSettingsAccountKey = "multicodexMenu.selectedSettingsProfileName"
        static let hasCompletedOnboarding = "multicodexMenu.hasCompletedOnboarding"
        static let isAdvancedSettingsVisible = "multicodexMenu.isAdvancedSettingsVisible"
        static let menuDensity = "multicodexMenu.menuDensity"
        static let usageBarStyle = "multicodexMenu.usageBarStyle"
        static let limitsCacheTTLSeconds = "multicodexMenu.limitsCacheTTLSeconds"
    }
}
