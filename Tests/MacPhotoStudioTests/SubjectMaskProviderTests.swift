import CoreGraphics
import CoreImage
import XCTest
@testable import MacPhotoStudio

final class SubjectMaskProviderTests: XCTestCase {
    func testThreeSubjectMasksShareOneSegmentationRequestPerRender() {
        let counter = InvocationCounter()
        let provider = SubjectMaskProvider { source in
            counter.count += 1
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage()
        let masks = (0..<3).map { _ in Self.subjectMask() }

        _ = PhotoImagePipeline.applyLocalMasks(
            masks,
            to: source,
            subjectMaskProvider: provider,
            subjectMaskCacheKey: Self.key(extent: source.extent)
        )

        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(provider.diagnostics().generatedRequests, 1)
        XCTAssertEqual(provider.diagnostics().cacheHits, 2)
    }

    func testSubjectSegmentationUsesStablePreLocalAdjustmentSourceRegardlessOfMaskOrder() {
        let samples = PixelSamples()
        let provider = SubjectMaskProvider { source in
            samples.redValues.append(Self.redValue(of: source))
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage(red: 0.20)
        let subject = Self.subjectMask()
        let fullFrameBrightening = LocalMask(
            kind: .radialGradient,
            adjustments: LocalMaskAdjustments(exposure: 1),
            radius: 1,
            feather: 0.001
        )

        _ = PhotoImagePipeline.applyLocalMasks(
            [fullFrameBrightening, subject],
            to: source,
            subjectMaskProvider: provider,
            subjectMaskCacheKey: Self.key(extent: source.extent, sourceRevision: "first-order")
        )
        _ = PhotoImagePipeline.applyLocalMasks(
            [subject, fullFrameBrightening],
            to: source,
            subjectMaskProvider: provider,
            subjectMaskCacheKey: Self.key(extent: source.extent, sourceRevision: "second-order")
        )

        XCTAssertEqual(samples.redValues.count, 2)
        XCTAssertEqual(samples.redValues[0], samples.redValues[1], accuracy: 0.01)
        XCTAssertEqual(samples.redValues[0], 0.20, accuracy: 0.03)
    }

    func testIrrelevantPhotoSlidersReuseCachedPreviewSubjectMask() async throws {
        let counter = InvocationCounter()
        let samples = PixelSamples()
        let provider = SubjectMaskProvider { source in
            counter.count += 1
            samples.redValues.append(Self.redValue(of: source))
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioSubjectMaskTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appending(path: "preview-source.png")
        try CIContext(options: [.useSoftwareRenderer: true]).writePNGRepresentation(
            of: source,
            to: sourceURL,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        let renderer = PreviewRenderer(subjectMaskProvider: provider)
        var firstState = PhotoEditState.identity
        firstState.localMasks = [Self.subjectMask()]
        firstState.light.exposure = -0.65
        var secondState = firstState
        secondState.light.exposure = 1.1
        secondState.color.temperature = 0.3
        var redAdjustment = secondState.hsl[.red]
        redAdjustment.saturation = -0.2
        secondState.hsl[.red] = redAdjustment

        _ = try await renderer.render(
            sourceURL: sourceURL,
            state: firstState,
            lut: nil,
            maximumPixelSize: 128
        )
        _ = try await renderer.render(
            sourceURL: sourceURL,
            state: secondState,
            lut: nil,
            maximumPixelSize: 128
        )

        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(provider.diagnostics().cacheHits, 1)
        XCTAssertEqual(samples.redValues.count, 1)
        XCTAssertEqual(
            samples.redValues[0],
            0.42,
            accuracy: 0.01,
            "Vision basis must be the decoded source, not the exposure-adjusted preview"
        )
    }

    func testSourceRevisionAndGeometryInvalidateTheMaskCache() {
        let counter = InvocationCounter()
        let provider = SubjectMaskProvider { source in
            counter.count += 1
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage()
        let originalKey = Self.key(extent: source.extent)

        _ = provider.mask(for: source, key: originalKey)
        _ = provider.mask(for: source, key: originalKey)
        _ = provider.mask(for: source, key: Self.key(extent: source.extent, sourceRevision: "changed-file"))
        _ = provider.mask(for: source, key: Self.key(extent: CGRect(x: 0, y: 0, width: 32, height: 16)))

        XCTAssertEqual(counter.count, 3)
        XCTAssertEqual(provider.diagnostics().cachedEntries, 3)
    }

    func testFailedSubjectGenerationIsCachedAndLeavesPixelsUnchanged() {
        let counter = InvocationCounter()
        let provider = SubjectMaskProvider { _ in
            counter.count += 1
            return nil
        }
        let source = Self.sourceImage(red: 0.34)
        let cacheKey = Self.key(extent: source.extent)
        let output = PhotoImagePipeline.applyLocalMasks(
            [Self.subjectMask()],
            to: source,
            subjectMaskProvider: provider,
            subjectMaskCacheKey: cacheKey
        )

        _ = provider.mask(for: source, key: cacheKey)

        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(Self.redValue(of: output), Self.redValue(of: source), accuracy: 0.01)
    }

    private static func sourceImage(red: CGFloat = 0.42) -> CIImage {
        CIImage(color: CIColor(red: red, green: 0.35, blue: 0.25, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 24, height: 16))
    }

    private static func subjectMask() -> LocalMask {
        LocalMask(kind: .subject, adjustments: LocalMaskAdjustments(exposure: 0.5))
    }

    private static func opaqueMask(for source: CIImage) -> CIImage {
        CIImage(color: .white).cropped(to: source.extent)
    }

    private static func key(extent: CGRect, sourceRevision: String = "v1") -> SubjectMaskCacheKey {
        SubjectMaskCacheKey(
            sourceIdentifier: "subject-mask-fixture",
            sourceRevision: sourceRevision,
            rendition: .preview,
            extent: extent
        )
    }

    private static func redValue(of image: CIImage) -> CGFloat {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent.integral,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ), let data = cgImage.dataProvider?.data else { return 0 }
        return CGFloat(CFDataGetBytePtr(data)![0]) / 255
    }
}

private final class InvocationCounter {
    var count = 0
}

private final class PixelSamples {
    var redValues: [CGFloat] = []
}
