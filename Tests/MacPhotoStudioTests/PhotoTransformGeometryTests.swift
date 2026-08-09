import CoreGraphics
import CoreImage
import XCTest
@testable import MacPhotoStudio

final class PhotoTransformGeometryTests: XCTestCase {
    private let sourceExtent = CGRect(x: 0, y: 0, width: 400, height: 300)

    func testSourceDisplaySourceRoundTripForIdentityCropRotationStraightenAndFlips() {
        let transforms: [TransformAdjustments] = [
            .init(),
            transform(crop: NormalizedCrop(x: 0.2, y: 0.15, width: 0.6, height: 0.7)),
            transform(rotation: 90),
            transform(rotation: 180),
            transform(rotation: 270),
            transform(straighten: 8.5),
            transform(horizontal: true),
            transform(vertical: true),
            transform(crop: NormalizedCrop(x: 0.15, y: 0.2, width: 0.7, height: 0.6), rotation: 90),
            transform(crop: NormalizedCrop(x: 0.15, y: 0.2, width: 0.7, height: 0.6), horizontal: true, vertical: true, rotation: -90)
        ]
        let sourcePoint = CGPoint(x: 0.45, y: 0.52)

        for transform in transforms {
            let geometry = PhotoTransformGeometry(sourceExtent: sourceExtent, transform: transform)
            let displayed = geometry.displayedNormalizedPoint(forSourceNormalized: sourcePoint)
            let recovered = geometry.sourceNormalizedPoint(forDisplayedNormalized: displayed)
            XCTAssertEqual(recovered.x, sourcePoint.x, accuracy: 0.000_001, "\(transform)")
            XCTAssertEqual(recovered.y, sourcePoint.y, accuracy: 0.000_001, "\(transform)")
        }
    }

    func testCropAndHorizontalFlipUseTheSameForwardMappingAsTheRenderer() {
        let geometry = PhotoTransformGeometry(
            sourceExtent: sourceExtent,
            transform: transform(crop: NormalizedCrop(x: 0.2, y: 0.25, width: 0.5, height: 0.5), horizontal: true)
        )
        let leftCropEdge = geometry.displayedNormalizedPoint(forSourceNormalized: CGPoint(x: 0.2, y: 0.5))
        let rightCropEdge = geometry.displayedNormalizedPoint(forSourceNormalized: CGPoint(x: 0.7, y: 0.5))
        XCTAssertEqual(leftCropEdge.x, 1, accuracy: 0.000_001)
        XCTAssertEqual(rightCropEdge.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(leftCropEdge.y, 0.5, accuracy: 0.000_001)
    }

    func testVisibleBrushPlacementMapsBackToTheSourcePixelsUsedByThePipeline() throws {
        let transform = transform(
            crop: NormalizedCrop(x: 0.1, y: 0.15, width: 0.7, height: 0.6),
            horizontal: true,
            rotation: 90
        )
        let geometry = PhotoTransformGeometry(sourceExtent: CGRect(x: 0, y: 0, width: 80, height: 60), transform: transform)
        let visibleTarget = geometry.displayedNormalizedPoint(forSourceNormalized: CGPoint(x: 0.42, y: 0.48))
        let storedPoint = geometry.sourceNormalizedPoint(forDisplayedNormalized: visibleTarget)

        var state = PhotoEditState.identity
        state.transform = transform
        state.localMasks = [
            LocalMask(
                kind: .brush,
                adjustments: LocalMaskAdjustments(exposure: 1, contrast: 0, saturation: 0),
                brushStrokes: [BrushStroke(
                    points: [BrushPoint(x: storedPoint.x, y: storedPoint.y)],
                    radius: 0.08,
                    hardness: 1,
                    opacity: 1,
                    erase: false
                )]
            )
        ]
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
        var preTransformState = state
        preTransformState.transform = TransformAdjustments()
        let localMaskStage = PhotoImagePipeline.apply(preTransformState, to: source)
        let sourcePixel = CGPoint(
            x: (storedPoint.x * source.extent.width).rounded(),
            y: (storedPoint.y * source.extent.height).rounded()
        )
        let affected = try pixel(of: localMaskStage, at: sourcePixel)
        let unaffected = try pixel(of: localMaskStage, at: CGPoint(x: 2, y: 2))
        XCTAssertGreaterThan(
            affected.x,
            unaffected.x + 0.08,
            "visible=\(visibleTarget), stored=\(storedPoint)"
        )
        let finalOutput = PhotoImagePipeline.apply(state, to: source)
        XCTAssertEqual(finalOutput.extent.minX, geometry.transformedExtent.minX, accuracy: 0.000_001)
        XCTAssertEqual(finalOutput.extent.minY, geometry.transformedExtent.minY, accuracy: 0.000_001)
        XCTAssertEqual(finalOutput.extent.width, geometry.transformedExtent.width, accuracy: 0.000_001)
        XCTAssertEqual(finalOutput.extent.height, geometry.transformedExtent.height, accuracy: 0.000_001)
    }

    func testRadialAndBrushRadiusVectorsPreserveTheirMetricAtEveryImageEdge() {
        let centers = [
            CGPoint(x: 0.05, y: 0.50), // left
            CGPoint(x: 0.95, y: 0.50), // right
            CGPoint(x: 0.50, y: 0.95), // top
            CGPoint(x: 0.50, y: 0.05), // bottom
            CGPoint(x: 0.05, y: 0.05), // bottom-left
            CGPoint(x: 0.05, y: 0.95), // top-left
            CGPoint(x: 0.95, y: 0.05), // bottom-right
            CGPoint(x: 0.95, y: 0.95)  // top-right
        ]
        let transforms: [TransformAdjustments] = [
            .init(),
            transform(crop: NormalizedCrop(x: 0.2, y: 0.15, width: 0.55, height: 0.65)),
            transform(rotation: 90),
            transform(rotation: 180),
            transform(rotation: 270),
            transform(horizontal: true),
            transform(vertical: true),
            transform(crop: NormalizedCrop(x: 0.2, y: 0.15, width: 0.55, height: 0.65), rotation: 90),
            transform(crop: NormalizedCrop(x: 0.2, y: 0.15, width: 0.55, height: 0.65), horizontal: true),
            transform(crop: NormalizedCrop(x: 0.2, y: 0.15, width: 0.55, height: 0.65), vertical: true, straighten: 7.5)
        ]
        let sourceSmallestDimension = min(sourceExtent.width, sourceExtent.height)
        let radialDistance = max(1, sourceSmallestDimension * 0.30)
        // The selected radius is well above BrushMaskRenderer's 0.5 px floor,
        // so both renderers must expose the same source-space vector metric.
        let brushDistance = max(0.5, sourceSmallestDimension * 0.30)

        for transform in transforms {
            let geometry = PhotoTransformGeometry(sourceExtent: sourceExtent, transform: transform)
            for (kind, distance) in [("radial", radialDistance), ("brush", brushDistance)] {
                let vector = geometry.displayedNormalizedVector(forSourceDistance: distance)
                for center in centers {
                    let endpoint = CGPoint(
                        x: center.x + distance / sourceExtent.width,
                        y: center.y
                    )
                    let displayedCenter = geometry.displayedNormalizedPointUnclamped(forSourceNormalized: center)
                    let displayedEndpoint = geometry.displayedNormalizedPointUnclamped(forSourceNormalized: endpoint)
                    XCTAssertEqual(
                        displayedEndpoint.x - displayedCenter.x,
                        vector.dx,
                        accuracy: 0.000_001,
                        "\(kind), \(transform), \(center)"
                    )
                    XCTAssertEqual(
                        displayedEndpoint.y - displayedCenter.y,
                        vector.dy,
                        accuracy: 0.000_001,
                        "\(kind), \(transform), \(center)"
                    )
                }
            }
        }
    }

    func testRadiusEndpointOutsideTheSourceOrCropIsNotShortenedByPointClamping() {
        let edgeCenter = CGPoint(x: 0.95, y: 0.50)
        let sourceDistance = min(sourceExtent.width, sourceExtent.height) * 0.30
        let endpoint = CGPoint(x: edgeCenter.x + sourceDistance / sourceExtent.width, y: edgeCenter.y)

        for transform in [
            TransformAdjustments(),
            self.transform(crop: NormalizedCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.6)),
            self.transform(rotation: 90),
            self.transform(horizontal: true),
            self.transform(crop: NormalizedCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.6), rotation: 90),
            self.transform(crop: NormalizedCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.6), horizontal: true, straighten: 8)
        ] {
            let geometry = PhotoTransformGeometry(sourceExtent: sourceExtent, transform: transform)
            let expectedVector = geometry.displayedNormalizedVector(forSourceDistance: sourceDistance)
            let unboundedCenter = geometry.displayedNormalizedPointUnclamped(forSourceNormalized: edgeCenter)
            let unboundedEndpoint = geometry.displayedNormalizedPointUnclamped(forSourceNormalized: endpoint)
            let clampedCenter = geometry.displayedNormalizedPoint(forSourceNormalized: edgeCenter)
            let clampedEndpoint = geometry.displayedNormalizedPoint(forSourceNormalized: endpoint)

            XCTAssertEqual(unboundedEndpoint.x - unboundedCenter.x, expectedVector.dx, accuracy: 0.000_001)
            XCTAssertEqual(unboundedEndpoint.y - unboundedCenter.y, expectedVector.dy, accuracy: 0.000_001)
            XCTAssertLessThan(
                hypot(clampedEndpoint.x - clampedCenter.x, clampedEndpoint.y - clampedCenter.y),
                hypot(expectedVector.dx, expectedVector.dy),
                "The old clamped-position calculation would shrink this \(transform) radius."
            )
        }
    }

    func testEdgeRadialDisplayGeometryMatchesAffectedPixelsAfterCrop() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
        let transform = transform(crop: NormalizedCrop(x: 0.3, y: 0.2, width: 0.6, height: 0.6))
        let center = CGPoint(x: 0.95, y: 0.50)
        let sourceDistance = min(source.extent.width, source.extent.height) * 0.30
        let representedVisibleSourcePoint = CGPoint(x: 0.875, y: 0.50)
        let geometry = PhotoTransformGeometry(sourceExtent: source.extent, transform: transform)
        let imageRect = LocalMaskCanvasGeometry.imageRect(
            container: CGSize(width: 480, height: 360),
            imageSize: geometry.transformedExtent.size
        )
        let displayedCenter = LocalMaskCanvasGeometry.unboundedViewPoint(
            x: geometry.displayedNormalizedPointUnclamped(forSourceNormalized: center).x,
            y: geometry.displayedNormalizedPointUnclamped(forSourceNormalized: center).y,
            in: imageRect
        )
        let displayedSample = LocalMaskCanvasGeometry.unboundedViewPoint(
            x: geometry.displayedNormalizedPointUnclamped(forSourceNormalized: representedVisibleSourcePoint).x,
            y: geometry.displayedNormalizedPointUnclamped(forSourceNormalized: representedVisibleSourcePoint).y,
            in: imageRect
        )
        let displayedRadiusVector = LocalMaskCanvasGeometry.viewVector(
            geometry.displayedNormalizedVector(forSourceDistance: sourceDistance),
            in: imageRect
        )

        XCTAssertLessThan(
            hypot(displayedSample.x - displayedCenter.x, displayedSample.y - displayedCenter.y),
            hypot(displayedRadiusVector.dx, displayedRadiusVector.dy),
            "The visible sample must remain inside the unshortened edge radius."
        )

        var state = PhotoEditState.identity
        state.transform = transform
        state.localMasks = [
            LocalMask(
                kind: .radialGradient,
                adjustments: LocalMaskAdjustments(exposure: 1, contrast: 0, saturation: 0),
                centerX: center.x,
                centerY: center.y,
                radius: 0.30,
                feather: 0.10
            )
        ]
        let rendered = PhotoImagePipeline.apply(state, to: source)
        let affected = try pixel(of: rendered, at: CGPoint(x: 70, y: 30))
        let unaffected = try pixel(of: rendered, at: CGPoint(x: 26, y: 30))
        XCTAssertGreaterThan(affected.x, unaffected.x + 0.08)
    }

    private func transform(
        crop: NormalizedCrop = .identity,
        horizontal: Bool = false,
        vertical: Bool = false,
        rotation: Double = 0,
        straighten: Double = 0
    ) -> TransformAdjustments {
        var result = TransformAdjustments()
        result.crop = crop
        result.rotationDegrees = rotation
        result.flipHorizontal = horizontal
        result.flipVertical = vertical
        result.straightenDegrees = straighten
        return result
    }

    private func pixel(of image: CIImage, at point: CGPoint) throws -> SIMD4<Double> {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let bounds = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        var pixels = Array(repeating: UInt8(0), count: 4)
        context.render(
            image.cropped(to: bounds),
            toBitmap: &pixels,
            rowBytes: 4,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return SIMD4(Double(pixels[0]) / 255, Double(pixels[1]) / 255, Double(pixels[2]) / 255, Double(pixels[3]) / 255)
    }

}
