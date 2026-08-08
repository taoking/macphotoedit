import CoreGraphics
import XCTest
@testable import MacPhotoStudio

final class LocalMaskCanvasGeometryTests: XCTestCase {
    func testAspectFittedPreviewRectAndCoordinateRoundTripUseBottomLeftMaskOrigin() {
        let rect = LocalMaskCanvasGeometry.imageRect(
            container: CGSize(width: 400, height: 400),
            imageSize: CGSize(width: 1_200, height: 600)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 100, width: 400, height: 200))

        let viewPoint = LocalMaskCanvasGeometry.viewPoint(x: 0.2, y: 0.8, in: rect)
        XCTAssertEqual(viewPoint.x, 80, accuracy: 0.001)
        XCTAssertEqual(viewPoint.y, 140, accuracy: 0.001)
        let normalized = LocalMaskCanvasGeometry.normalizedPoint(viewPoint, in: rect)
        XCTAssertEqual(normalized.x, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(normalized.y, 0.8, accuracy: 0.000_001)
    }

    func testLinearTranslationPreservesGradientDirectionAndClampsAtImageBoundary() {
        let mask = LocalMask(
            kind: .linearGradient,
            startX: 0.2,
            startY: 0.3,
            endX: 0.8,
            endY: 0.7
        )
        let translated = LocalMaskCanvasGeometry.translateLinearMask(
            mask,
            by: CGPoint(x: 0.5, y: -0.6)
        )
        XCTAssertEqual(translated.startX, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(translated.endX, 1, accuracy: 0.000_001)
        XCTAssertEqual(translated.startY, 0, accuracy: 0.000_001)
        XCTAssertEqual(translated.endY, 0.4, accuracy: 0.000_001)
    }

    func testSegmentDistanceAndRadialDistanceUseDisplayedImageBounds() {
        let imageRect = CGRect(x: 10, y: 20, width: 300, height: 180)
        XCTAssertEqual(
            LocalMaskCanvasGeometry.distanceToSegment(
                CGPoint(x: 160, y: 70),
                start: CGPoint(x: 10, y: 20),
                end: CGPoint(x: 310, y: 120)
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LocalMaskCanvasGeometry.normalizedDistance(
                from: CGPoint(x: 160, y: 110),
                to: CGPoint(x: 250, y: 110),
                in: imageRect
            ),
            0.5,
            accuracy: 0.000_001
        )
    }
}
