import XCTest
@testable import MultiCodex

final class ManagedAccountMigratorTests: XCTestCase {
    func testMigrationIsIdempotent() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-migration-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: tempDir + "/.config/multicodex"
        )

        // Create a legacy account
        try fm.createDirectory(atPath: paths.accountDir("alpha"), withIntermediateDirectories: true)
        try Data("{\"tokens\":{}}".utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("alpha")))

        let first = try ManagedAccountMigrator.migrateIfNeeded(paths: paths)
        XCTAssertEqual(first, 1)

        let second = try ManagedAccountMigrator.migrateIfNeeded(paths: paths)
        XCTAssertEqual(second, 0)
    }
}
