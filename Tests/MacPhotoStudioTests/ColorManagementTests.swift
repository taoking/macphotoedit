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

    func testTechnicalLUTStrengthBlendsOnlyOutputEncodedBranches() throws {
        let metadata = TechnicalLUTMetadata(input: .displayP3, output: .rec709)
        let technical = try technicalColorShiftLUT(metadata: metadata)
        let source = try taggedSolidImage(
            red: 0.74,
            green: 0.28,
            blue: 0.62,
            colorSpace: PhotoColorSpace.displayP3.cgColorSpace
        )

        let zero = try TechnicalLUTProcessor.apply(technical, to: source, metadata: metadata, strength: 0)
        let half = try TechnicalLUTProcessor.apply(technical, to: source, metadata: metadata, strength: 0.5)
        let full = try TechnicalLUTProcessor.apply(technical, to: source, metadata: metadata, strength: 1)

        for output in [zero, half, full] {
            let colorSpace = try XCTUnwrap(output.colorSpace)
            XCTAssertTrue(PhotoColorSpace.rec709.matchesEmbeddedProfile(of: colorSpace))
        }

        // Independently construct the three expected output-encoded branches:
        // P3 source → P3 LUT input → untouched Rec.709, full raw cube result
        // tagged Rec.709, then a raw Rec.709-code-value blend.
        let encodedInput = try colorConverted(source, to: PhotoColorSpace.displayP3.cgColorSpace)
        let expectedZero = try colorConverted(encodedInput, to: PhotoColorSpace.rec709.cgColorSpace)
        let expectedFull = try rawMaterialized(
            LUTProcessor.apply(technical, to: encodedInput, strength: 1),
            tagged: PhotoColorSpace.rec709.cgColorSpace
        )
        let expectedHalf = try rawBlended(
            foreground: expectedFull,
            background: expectedZero,
            strength: 0.5,
            tagged: PhotoColorSpace.rec709.cgColorSpace
        )

        assertPixel(zero, matches: expectedZero)
        assertPixel(half, matches: expectedHalf)
        assertPixel(full, matches: expectedFull)
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

    func testHDRCapabilityAuditKeepsDisplayAndProductionClaimsSeparate() {
        XCTAssertTrue(HDRPhotoCapabilities.hasExtendedRangePreviewPath)
        XCTAssertFalse(HDRPhotoCapabilities.supportsExtendedRangePreview(potentialHeadroom: 1.0))
        XCTAssertTrue(HDRPhotoCapabilities.supportsExtendedRangePreview(potentialHeadroom: 1.01))
        XCTAssertFalse(HDRPhotoCapabilities.supportsHDRGainMapExport)
        XCTAssertFalse(HDRPhotoCapabilities.supportsHDRExport)

        XCTAssertTrue(HDRVideoCapabilities.supportsNativePlayback)
        XCTAssertFalse(HDRVideoCapabilities.supportsEditing)
        XCTAssertFalse(HDRVideoCapabilities.supportsExport)
        XCTAssertFalse(HDRVideoCapabilities.supportsProxy)
        XCTAssertEqual(PhotoDynamicRange.hdr.title, "扩展范围预览（非 HDR 导出）")
    }

    private func technicalIdentityLUT(metadata: TechnicalLUTMetadata) throws -> CubeLUT {
        var lut = try CubeLUTParser.parse(data: identityCubeData(dimension: 17))
        lut.kind = .technical
        lut.technicalMetadata = metadata
        return lut
    }

    private func technicalColorShiftLUT(metadata: TechnicalLUTMetadata) throws -> CubeLUT {
        var lut = try technicalIdentityLUT(metadata: metadata)
        lut.title = "P3-to-709-Color-Shift"
        for index in lut.values.indices {
            let value = lut.values[index]
            lut.values[index] = SIMD3<Float>(
                min(1, 0.08 + value.x * 0.68 + value.y * 0.12),
                min(1, 0.04 + value.y * 0.78 + value.z * 0.10),
                min(1, 0.10 + value.z * 0.66 + value.x * 0.16)
            )
        }
        return lut
    }

    private func taggedSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat, colorSpace: CGColorSpace) throws -> CIImage {
        let image = CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        return try colorConverted(image, to: colorSpace)
    }

    private func colorConverted(_ image: CIImage, to colorSpace: CGColorSpace) throws -> CIImage {
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .workingFormat: CIFormat.RGBAh.rawValue
        ])
        let cgImage = try XCTUnwrap(context.createCGImage(
            image,
            from: image.extent.integral,
            format: .RGBAh,
            colorSpace: colorSpace
        ))
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    private func rawMaterialized(_ image: CIImage, tagged colorSpace: CGColorSpace) throws -> CIImage {
        let context = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAh.rawValue
        ])
        let cgImage = try XCTUnwrap(context.createCGImage(
            image,
            from: image.extent.integral,
            format: .RGBAh,
            colorSpace: colorSpace
        ))
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    private func rawBlended(
        foreground: CIImage,
        background: CIImage,
        strength: CGFloat,
        tagged colorSpace: CGColorSpace
    ) throws -> CIImage {
        let mask = CIImage(color: CIColor(red: strength, green: strength, blue: strength, alpha: 1))
            .cropped(to: foreground.extent)
        let blended = foreground.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])
        return try rawMaterialized(blended, tagged: colorSpace)
    }

    private func assertPixel(_ actual: CIImage, matches expected: CIImage, file: StaticString = #filePath, line: UInt = #line) {
        let colorSpace = PhotoColorSpace.rec709.cgColorSpace
        let context = CIContext(options: [.workingColorSpace: colorSpace])
        let actualCG = context.createCGImage(actual, from: actual.extent.integral, format: .RGBA8, colorSpace: colorSpace)
        let expectedCG = context.createCGImage(expected, from: expected.extent.integral, format: .RGBA8, colorSpace: colorSpace)
        let actualData = actualCG?.dataProvider?.data as Data?
        let expectedData = expectedCG?.dataProvider?.data as Data?
        XCTAssertNotNil(actualData, file: file, line: line)
        XCTAssertNotNil(expectedData, file: file, line: line)
        guard let actualData, let expectedData else { return }
        XCTAssertEqual(actualData.count, expectedData.count, file: file, line: line)
        for (actualByte, expectedByte) in zip(actualData, expectedData) {
            XCTAssertLessThanOrEqual(abs(Int(actualByte) - Int(expectedByte)), 2, file: file, line: line)
        }
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
