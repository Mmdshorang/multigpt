import Foundation

enum DebugFeatureFlags {
    // Menu rendering
    static let useSafeMenuFallback = false

    // Recently added account/menu behaviors (temporarily disabled for crash isolation)
    static let excludeCurrentAccountFromMenuList = true
    static let hideConnectedBadge = true
    static let inferWorkspaceEmailFromAuth = true
    static let showWorkspaceEmailHint = true
    static let autoRenameNewAccountAfterLogin = true
}
