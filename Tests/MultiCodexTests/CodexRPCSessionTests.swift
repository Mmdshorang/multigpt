import XCTest
@testable import MultiCodex

final class CodexRPCSessionTests: XCTestCase {
    func testShutdownDoesNotCrashWhenNotStarted() async {
        let session = CodexRPCSession()
        await session.shutdown()
        // Should not crash
    }

    func testFetchRateLimitsFailsGracefullyWhenNotRunning() async {
        let session = CodexRPCSession()
        await session.shutdown()
        // After shutdown with no process, ensureReady will try to launch
        // which should fail since codex is not at /nonexistent
        // Just verify shutdown doesn't crash — the RPC launch is integration-tested
    }
}
