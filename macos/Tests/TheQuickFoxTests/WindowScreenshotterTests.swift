#if canImport(XCTest)
import XCTest
@testable import TheQuickFox

final class WindowScreenshotterTests: XCTestCase {

    func testCaptureLatency() throws {
        // Skip in CI or environments lacking Screen Recording permission.
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Skipping screenshot test in CI environment")
        }

        do {
            let screenshot = try WindowScreenshotter.captureFrontmost()
            XCTAssertLessThan(screenshot.latencyMs, 200, "Capture latency exceeds 200 ms")
        } catch {
            throw XCTSkip("Skipping screenshot test (likely missing Screen Recording permission): \(error)")
        }
    }
}
#endif
