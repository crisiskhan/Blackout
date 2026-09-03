import XCTest
import VisionCoreML
@testable import VisionCapture

final class VisionCaptureTests: XCTestCase {
    func testAddFrame() {
        var g = GuidedCapture()
        g.addFrame([1, 0, 0])
        g.addFrame([0, 1, 0])
        XCTAssertEqual(g.frames.count, 2)
        XCTAssertEqual(g.mergedFeatures()[0], 0.5, accuracy: 0.01)
    }
}
