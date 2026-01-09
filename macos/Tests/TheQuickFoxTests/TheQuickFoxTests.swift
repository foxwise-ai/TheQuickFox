#if canImport(XCTest)
import XCTest
@testable import TheQuickFox

final class TheQuickFoxTests: XCTestCase {
    func testDetectorInitialization() {
        let detector = DoubleControlDetector(maxInterval: 0.1) { }
        XCTAssertNotNil(detector)
    }
}
#endif
