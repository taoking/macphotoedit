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

    func testConcurrentRequestsForTheSameKeyShareOneGeneration() {
        let counter = LockedInvocationCounter()
        let generationStarted = expectation(description: "first generation started")
        let completed = expectation(description: "both callers completed")
        completed.expectedFulfillmentCount = 2
        let releaseGeneration = DispatchSemaphore(value: 0)
        let provider = SubjectMaskProvider { source in
            counter.increment()
            generationStarted.fulfill()
            releaseGeneration.wait()
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage()
        let key = Self.key(extent: source.extent)

        DispatchQueue.global(qos: .userInitiated).async {
            _ = provider.mask(for: source, key: key)
            completed.fulfill()
        }
        wait(for: [generationStarted], timeout: 1)

        DispatchQueue.global(qos: .userInitiated).async {
            _ = provider.mask(for: source, key: key)
            completed.fulfill()
        }
        waitUntil("second caller registered as an in-flight cache hit") {
            provider.diagnostics().cacheHits == 1
        }
        releaseGeneration.signal()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(provider.diagnostics().generatedRequests, 1)
        XCTAssertEqual(provider.diagnostics().cachedEntries, 1)
    }

    func testConcurrentRequestsForDifferentKeysDoNotHoldTheGlobalLockDuringGeneration() {
        let counter = LockedInvocationCounter()
        let firstGenerationStarted = expectation(description: "first generation started")
        let secondGenerationStarted = expectation(description: "second generation started")
        let completed = expectation(description: "both different-key callers completed")
        completed.expectedFulfillmentCount = 2
        let releaseGeneration = DispatchSemaphore(value: 0)
        let provider = SubjectMaskProvider { source in
            let invocation = counter.increment()
            if invocation == 1 {
                firstGenerationStarted.fulfill()
            } else {
                secondGenerationStarted.fulfill()
            }
            releaseGeneration.wait()
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage()
        let firstKey = Self.key(extent: source.extent, sourceRevision: "first")
        let secondKey = Self.key(extent: source.extent, sourceRevision: "second")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = provider.mask(for: source, key: firstKey)
            completed.fulfill()
        }
        wait(for: [firstGenerationStarted], timeout: 1)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = provider.mask(for: source, key: secondKey)
            completed.fulfill()
        }

        let result = XCTWaiter().wait(for: [secondGenerationStarted], timeout: 1)
        // Release both workers even if the assertion below fails, so a failed
        // concurrency regression cannot leave an XCTest worker blocked.
        releaseGeneration.signal()
        releaseGeneration.signal()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(result, .completed, "different source keys must not serialize Vision work")
        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(provider.diagnostics().generatedRequests, 2)
    }

    func testLRUEvictionRetainsRecentlyUsedSubjectMask() {
        let counter = InvocationCounter()
        let provider = SubjectMaskProvider(capacity: 2) { source in
            counter.count += 1
            return Self.opaqueMask(for: source)
        }
        let source = Self.sourceImage()
        let first = Self.key(extent: source.extent, sourceRevision: "first")
        let second = Self.key(extent: source.extent, sourceRevision: "second")
        let third = Self.key(extent: source.extent, sourceRevision: "third")

        _ = provider.mask(for: source, key: first)
        _ = provider.mask(for: source, key: second)
        _ = provider.mask(for: source, key: first) // Touch first; second becomes LRU.
        _ = provider.mask(for: source, key: third)
        _ = provider.mask(for: source, key: second)

        XCTAssertEqual(counter.count, 4)
        XCTAssertEqual(provider.diagnostics().cachedEntries, 2)
    }

    func testSourceURLCacheKeyIncludesFileResourceIdentifierWhenAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioSubjectMaskKeyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.jpg")
        try Data("subject-cache-key".utf8).write(to: sourceURL)
        let values = try sourceURL.resourceValues(forKeys: [.fileResourceIdentifierKey])
        guard let fileResourceIdentifier = values.fileResourceIdentifier else {
            throw XCTSkip("Temporary volume does not expose a file resource identifier")
        }

        let key = SubjectMaskCacheKey(
            sourceURL: sourceURL,
            rendition: .preview,
            extent: CGRect(x: 0, y: 0, width: 24, height: 16)
        )

        XCTAssertTrue(key.sourceRevision.contains(String(describing: fileResourceIdentifier)))
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1,
        condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTFail("Timed out waiting for \(description)")
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

private final class LockedInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class PixelSamples {
    var redValues: [CGFloat] = []
}
