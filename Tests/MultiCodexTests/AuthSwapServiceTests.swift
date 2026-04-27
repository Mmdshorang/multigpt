import XCTest
@testable import MultiCodex

final class AuthSwapServiceTests: XCTestCase {
    func testAtomicRenameProducesValidResult() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-swap-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let codexDir = (tempDir as NSString).appendingPathComponent(".codex")
        try fm.createDirectory(atPath: codexDir, withIntermediateDirectories: true)

        let targetAuth = Data("{\"tokens\":{\"access_token\":\"new\"}}".utf8)
        let stagedPath = (codexDir as NSString).appendingPathComponent("auth.json.staged-test")
        let authPath = (codexDir as NSString).appendingPathComponent("auth.json")

        try targetAuth.write(to: URL(fileURLWithPath: stagedPath), options: .atomic)

        // Use POSIX rename for atomicity
        let result = stagedPath.withCString { src in
            authPath.withCString { dst in
                rename(src, dst)
            }
        }
        XCTAssertEqual(result, 0)

        let readBack = try Data(contentsOf: URL(fileURLWithPath: authPath))
        XCTAssertEqual(readBack, targetAuth)
    }
}
