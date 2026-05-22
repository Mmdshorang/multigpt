import Foundation
@testable import MultiCodex
import XCTest

final class CodexCommandRunnerTests: XCTestCase {
    func testRunAsyncTerminatesProcessOnTaskCancellation() async throws {
        let runtime = CodexRuntimeDescriptor(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            prefixArguments: [],
            display: "/bin/sleep"
        )

        let task = Task {
            try await CodexCommandRunner.runAsync(
                runtime: runtime,
                arguments: ["5"],
                environment: ProcessInfo.processInfo.environment
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to throw.")
        } catch is CancellationError {
        }
    }
}
