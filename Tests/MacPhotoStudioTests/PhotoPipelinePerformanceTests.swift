import CoreImage
import XCTest
@testable import MacPhotoStudio

final class PhotoPipelinePerformanceTests: XCTestCase {
    private let source = CIImage(color: CIColor(red: 0.42, green: 0.28, blue: 0.73, alpha: 1))
        .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))

    override func tearDown() {
        PhotoImagePipeline.resetCubeCachesForTesting()
        super.tearDown()
    }

    func testColorCubeCachesByOnlyTheParametersThatAffectItsPixels() {
        PhotoImagePipeline.resetCubeCachesForTesting()
        var state = PhotoEditState.identity
        state.light.whites = 0.25

        _ = PhotoImagePipeline.applyCreativeAdjustments(state, to: source)
        let first = PhotoImagePipeline.cubeCacheDiagnostics().color
        XCTAssertEqual(first.generationCount, 1)
        XCTAssertEqual(first.entryCount, 1)
        XCTAssertEqual(first.dataByteCount, 33 * 33 * 33 * 4 * MemoryLayout<Float>.stride)

        // Exposure changes a different Core Image filter and must not rebuild
        // the HSL/white/black cube.
        state.light.exposure = 0.5
        _ = PhotoImagePipeline.applyCreativeAdjustments(state, to: source)
        XCTAssertEqual(PhotoImagePipeline.cubeCacheDiagnostics().color.generationCount, 1)

        state.hsl[.blue] = HSLAdjustment(hue: 0.1, saturation: -0.2, luminance: 0.05)
        _ = PhotoImagePipeline.applyCreativeAdjustments(state, to: source)
        XCTAssertEqual(PhotoImagePipeline.cubeCacheDiagnostics().color.generationCount, 2)
    }

    func testToneCurveCubeCachesAndItsStorageStaysBounded() {
        PhotoImagePipeline.resetCubeCachesForTesting()
        var state = PhotoEditState.identity
        state.curves[.master] = [
            CurvePoint(x: 0, y: 0.04),
            CurvePoint(x: 0.5, y: 0.62),
            CurvePoint(x: 1, y: 1)
        ]

        _ = PhotoImagePipeline.applyCreativeAdjustments(state, to: source)
        let first = PhotoImagePipeline.cubeCacheDiagnostics().toneCurve
        XCTAssertEqual(first.generationCount, 1)
        XCTAssertEqual(first.entryCount, 1)
        XCTAssertEqual(first.dataByteCount, 33 * 33 * 33 * 4 * MemoryLayout<Float>.stride)

        state.color.temperature = 0.2
        _ = PhotoImagePipeline.applyCreativeAdjustments(state, to: source)
        XCTAssertEqual(PhotoImagePipeline.cubeCacheDiagnostics().toneCurve.generationCount, 1)

        for index in 0..<10 {
            state.curves[.red] = [
                CurvePoint(x: 0, y: 0),
                CurvePoint(x: 0.5, y: Double(index) / 20),
                CurvePoint(x: 1, y: 1)
            ]
            _ = PhotoImagePipeline.applyCreativeAdjustments(state, to: source)
        }
        let afterDrag = PhotoImagePipeline.cubeCacheDiagnostics().toneCurve
        XCTAssertEqual(afterDrag.generationCount, 11)
        XCTAssertLessThanOrEqual(afterDrag.entryCount, 8)
    }
}
