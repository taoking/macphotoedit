import CoreImage
import XCTest
@testable import MacPhotoStudio

final class SmartMaskTests: XCTestCase {
    func testForegroundSubjectMaskCapabilityMatchesDeploymentTarget() {
        XCTAssertTrue(VisionSubjectMaskCapabilities.supportsForegroundSubjectMask)
    }

    func testInvalidSourceFailsClosedWithoutProducingAMask() {
        let empty = CIImage(color: .black).cropped(to: .zero)
        XCTAssertNil(VisionSubjectMaskRenderer.image(for: empty))
    }

    func testForegroundMaskResultIfVisionFindsOneIsAlignedToSource() {
        let source = CIImage(color: CIColor(red: 0.15, green: 0.35, blue: 0.55, alpha: 1))
            .cropped(to: CGRect(x: 20, y: 30, width: 64, height: 48))

        if let mask = VisionSubjectMaskRenderer.image(for: source) {
            XCTAssertEqual(mask.extent, source.extent)
        }
    }
}
