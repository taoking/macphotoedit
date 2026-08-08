import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import XCTest
@testable import MacPhotoStudio

final class ColorManagementTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioColorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testLegacyPhotoEditStateDecodesWithSafeSDRColorDefaults() throws {
        var legacyState = PhotoEditState.identity
        legacyState.version = 1
        legacyState.light.exposure = 1.25
        var serialized = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyState)) as? [String: Any])
        serialized.removeValue(forKey: "technicalLUT")
        serialized.removeValue(forKey: "colorPipeline")
        let legacyJSON = try JSONSerialization.data(withJSONObject: serialized)
        let state = try JSONDecoder().decode(PhotoEditState.self, from: legacyJSON)
        XCTAssertEqual(state.version, 1)
        XCTAssertEqual(state.light.exposure, 1.25)
        XCTAssertNil(state.technicalLUT)
        XCTAssertEqual(state.colorPipeline, .sdr)
    }

    func testTechnicalLUTRequiresExactInputContractAndCreativeSlotRejectsIt() throws {
        let technical = try technicalIdentityLUT(
            metadata: TechnicalLUTMetadata(input: .rec709, output: .sRGB)
        )
        XCTAssertThrowsError(try ColorPipelinePlan.make(
            source: .sRGB,
            settings: .sdr,
            technicalLUT: technical,
            creativeLUT: nil
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("期望"))
        }
        XCTAssertThrowsError(try ColorPipelinePlan.make(
            source: .rec709,
            settings: .sdr,
            technicalLUT: nil,
            creativeLUT: technical
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("Technical"))
        }
    }

    func testTechnicalLUTRejectsTransferFunctionsWithoutValidatedColorSyncBridge() throws {
        let unsupported = try technicalIdentityLUT(
            metadata: TechnicalLUTMetadata(
                input: PhotoColorDescriptor(colorSpace: .rec2020, transferFunction: .sLog3),
                output: .rec709
            )
        )
        XCTAssertThrowsError(try ColorPipelinePlan.make(
            source: PhotoColorDescriptor(colorSpace: .rec2020, transferFunction: .sLog3),
            settings: .sdr,
            technicalLUT: unsupported,
            creativeLUT: nil
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("ColorSync bridge"))
        }
    }

    func testTechnicalLUTMaterializesItsDeclaredOutputColorSpace() throws {
        let technical = try technicalIdentityLUT(
            metadata: TechnicalLUTMetadata(input: .displayP3, output: .rec709)
        )
        let source = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 12, height: 8))
        let bridged = try TechnicalLUTProcessor.apply(
            technical,
            to: source,
            metadata: try XCTUnwrap(technical.technicalMetadata),
            strength: 1
        )
        let technicalOutputColorSpace = try XCTUnwrap(bridged.colorSpace)
        XCTAssertTrue(PhotoColorSpace.rec709.matchesEmbeddedProfile(of: technicalOutputColorSpace))

        var state = PhotoEditState.identity
        state.technicalLUT = LUTApplication(identifier: technical.id, strength: 1)
        let rendered = try PhotoColorPipeline.apply(
            source: source,
            state: state,
            sourceColor: .displayP3,
            technicalLUT: technical,
            creativeLUT: nil
        )
        XCTAssertEqual(rendered.plan.technicalTransform, technical.technicalMetadata)
    }

    func testPhotoRenderContextsUseExplicitExtendedLinearWorkingSpace() {
        let context = RendererContextFactory.makeContext()
        let workingColorSpace = try? XCTUnwrap(context.workingColorSpace)
        XCTAssertNotNil(workingColorSpace)
        if let workingColorSpace {
            XCTAssertTrue(PhotoColorSpace.extendedLinearSRGB.matchesEmbeddedProfile(of: workingColorSpace))
        }
        XCTAssertEqual(context.workingFormat, .RGBAh)
    }

    func testColorPipelinePlanNamesTheSharedLinearWorkingSpace() throws {
        let plan = try ColorPipelinePlan.make(
            source: .displayP3,
            settings: PhotoColorPipelineSettings(outputColorSpace: .rec2020, dynamicRange: .sdr),
            technicalLUT: nil,
            creativeLUT: nil
        )
        XCTAssertEqual(plan.source, .displayP3)
        XCTAssertEqual(plan.working, .linearWorking)
        XCTAssertEqual(plan.output, PhotoColorDescriptor(colorSpace: .rec2020, transferFunction: .rec709))
    }

    func testTechnicalLUTPersistsItsColorContractWithoutChangingOriginalCube() async throws {
        let sourceURL = temporaryDirectory.appending(path: "SLog3-to-709.cube")
        let sourceData = identityCubeData(dimension: 17)
        try sourceData.write(to: sourceURL)
        let repository = LUTRepository(directoryURL: temporaryDirectory.appending(path: "lut", directoryHint: .isDirectory))
        let metadata = TechnicalLUTMetadata(
            input: PhotoColorDescriptor(colorSpace: .rec2020, transferFunction: .sLog3),
            output: .rec709
        )

        let imported = try await repository.importLUT(from: sourceURL, kind: .technical, technicalMetadata: metadata)
        let restored = try await repository.library().imported.first(where: { $0.id == imported.id })
        XCTAssertEqual(restored?.kind, .technical)
        XCTAssertEqual(restored?.technicalMetadata, metadata)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testHDRPreviewPreservesHDRPipelineAndSDRExportRejectsFalseHDR() async throws {
        var state = PhotoEditState.identity
        state.colorPipeline.outputColorSpace = .displayP3
        state.colorPipeline.dynamicRange = .hdr
        let image = CIImage(color: CIColor(red: 1.4, green: 0.6, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let result = try await PreviewRenderer().render(source: image, state: state, lut: nil)
        XCTAssertEqual(result.colorPipeline?.dynamicRange, .hdr)
        XCTAssertEqual(result.colorPipeline?.output.colorSpace, .displayP3)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result.imageData as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, "public.tiff")

        let destination = temporaryDirectory.appending(path: "not-really-hdr.heic")
        XCTAssertThrowsError(try ImageFileExporter.write(
            image: image,
            context: CIContext(options: [.useSoftwareRenderer: true]),
            sourceURL: nil,
            to: destination,
            options: PhotoExportOptions(format: .heif, dynamicRange: .hdr),
            allowsOverwrite: false
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    private func technicalIdentityLUT(metadata: TechnicalLUTMetadata) throws -> CubeLUT {
        var lut = try CubeLUTParser.parse(data: identityCubeData(dimension: 17))
        lut.kind = .technical
        lut.technicalMetadata = metadata
        return lut
    }

    private func identityCubeData(dimension: Int) -> Data {
        var lines = ["TITLE \"Identity \(dimension)\"", "LUT_3D_SIZE \(dimension)", "DOMAIN_MIN 0 0 0", "DOMAIN_MAX 1 1 1"]
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let divisor = Double(dimension - 1)
                    lines.append("\(Double(red) / divisor) \(Double(green) / divisor) \(Double(blue) / divisor)")
                }
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
