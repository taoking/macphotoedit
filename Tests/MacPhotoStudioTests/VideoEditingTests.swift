@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import XCTest
@testable import MacPhotoStudio

final class VideoEditingTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioVideoEditingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testVideoEditStateClampsTrimSpeedAndFrameOutputSize() throws {
        var state = VideoEditState.identity
        state.trimStart = -2
        state.trimEnd = 99
        state.speed = 12
        state.audioGain = -100
        state.fadeInDuration = -2
        state.fadeOutDuration = 20
        state.audioFadeInDuration = -1
        state.audioFadeOutDuration = 20
        state.transform.crop = NormalizedCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        state.transform.rotationDegrees = 90

        let trim = try state.resolvedTrim(for: 8)
        XCTAssertEqual(trim.start, 0)
        XCTAssertEqual(trim.end, 8)
        XCTAssertEqual(state.clampedSpeed, 4)
        XCTAssertEqual(state.clampedAudioGain, -60)
        XCTAssertEqual(state.clampedFadeInDuration, 0)
        XCTAssertEqual(state.clampedFadeOutDuration, 20)
        XCTAssertEqual(state.clampedAudioFadeInDuration, 0)
        XCTAssertEqual(state.clampedAudioFadeOutDuration, 20)
        XCTAssertEqual(
            VideoFramePipeline.outputSize(sourceSize: CGSize(width: 1_920, height: 1_080), state: state, maximumPixelSize: nil),
            CGSize(width: 540, height: 960)
        )
        XCTAssertEqual(
            VideoFramePipeline.outputSize(sourceSize: CGSize(width: 1_920, height: 1_080), state: state, maximumPixelSize: 480),
            CGSize(width: 270, height: 480)
        )
        let rotatedSize = VideoGeometry.displaySize(
            naturalSize: CGSize(width: 1_920, height: 1_080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        XCTAssertEqual(rotatedSize.width, 1_080, accuracy: 0.001)
        XCTAssertEqual(rotatedSize.height, 1_920, accuracy: 0.001)
    }

    func testVideoFadeEnvelopeAndFramePipelineRenderToBlackAtClipBoundaries() throws {
        XCTAssertEqual(VideoFadeEnvelope.opacity(at: 0, duration: 4, fadeIn: 1, fadeOut: 1), 0)
        XCTAssertEqual(VideoFadeEnvelope.opacity(at: 0.5, duration: 4, fadeIn: 1, fadeOut: 1), 0.5)
        XCTAssertEqual(VideoFadeEnvelope.opacity(at: 2, duration: 4, fadeIn: 1, fadeOut: 1), 1)
        XCTAssertEqual(VideoFadeEnvelope.opacity(at: 4, duration: 4, fadeIn: 1, fadeOut: 1), 0)
        XCTAssertEqual(VideoFadeEnvelope.opacity(at: 0.5, duration: 1, fadeIn: 1, fadeOut: 1), 0.5)

        var state = VideoEditState.identity
        state.fadeInDuration = 1
        state.fadeOutDuration = 1
        let source = CIImage(color: CIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 4))
        let atStart = VideoFramePipeline.apply(
            source, state: state, lut: nil, renderSize: CGSize(width: 8, height: 4),
            compositionTime: 0, compositionDuration: 4
        )
        let atMiddle = VideoFramePipeline.apply(
            source, state: state, lut: nil, renderSize: CGSize(width: 8, height: 4),
            compositionTime: 2, compositionDuration: 4
        )
        let startPixel = try rgba(of: atStart)
        let middlePixel = try rgba(of: atMiddle)
        XCTAssertLessThan(startPixel.x, 0.02)
        XCTAssertLessThan(startPixel.y, 0.02)
        XCTAssertGreaterThan(middlePixel.x, 0.7)
        XCTAssertGreaterThan(middlePixel.y, 0.35)
    }

    func testVideoFramePipelineAppliesCreativeLUTIntensityAndColorAdjustment() throws {
        let lut = CubeLUT(
            id: UUID(), title: "Green creative look", kind: .creative, dimension: 17,
            domainMinimum: SIMD3<Float>(repeating: 0), domainMaximum: SIMD3<Float>(repeating: 1),
            values: Array(repeating: SIMD3<Float>(0, 1, 0), count: 17 * 17 * 17),
            technicalMetadata: nil, sourceURL: nil, isImported: false, isFavorite: false
        )
        var state = VideoEditState.identity
        state.adjustments.exposure = 0.4
        state.lut = LUTApplication(identifier: lut.id, strength: 0.5)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 4))

        let rendered = VideoFramePipeline.apply(
            source,
            state: state,
            lut: lut,
            renderSize: CGSize(width: 8, height: 4)
        )
        let pixel = try rgba(of: rendered)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 8, height: 4))
        XCTAssertGreaterThan(pixel.y, pixel.x)
        XCTAssertGreaterThan(pixel.y, pixel.z)
        XCTAssertGreaterThan(pixel.y, 0.5)
    }

    func testVideoEditStatePersistsThroughCatalogAndMarksVideoAsEdited() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let root = MediaRootRecord(
            id: UUID(), displayName: "Video Root", bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false), volumeIdentifier: nil,
            availability: .online, createdAt: .now, lastScannedAt: nil, lastScanError: nil
        )
        try await store.saveMediaRoot(root)
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch([
            ScannedMediaAsset(
                rootID: root.id, relativePath: "clip.mov", fileResourceIdentifier: "clip", mediaType: .video,
                fileExtension: "mov", fileSize: 123, createdAt: .now, modifiedAt: .now,
                metadata: .video(VideoMetadata(
                    width: 64, height: 48, duration: 1, frameRate: 30, codec: "H.264", creationDate: .now
                ))
            )
        ], scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)
        let libraryAssets = try await store.libraryAssets(query: .all, limit: 1, offset: 0)
        let asset = try XCTUnwrap(libraryAssets.first)

        var expected = VideoEditState.identity
        expected.trimStart = 0.2
        expected.trimEnd = 0.8
        expected.speed = 2
        expected.adjustments.exposure = 0.75
        expected.lut = LUTApplication(identifier: UUID(), strength: 0.45)
        expected.isMuted = true
        expected.fadeInDuration = 0.2
        expected.fadeOutDuration = 0.3
        expected.audioFadeInDuration = 0.15
        expected.audioFadeOutDuration = 0.25
        try await store.saveVideoEditState(expected, for: asset.id)

        let reopened = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await reopened.bootstrap()
        let schemaVersion = try await reopened.currentSchemaVersion()
        let restoredState = try await reopened.videoEditState(for: asset.id)
        XCTAssertEqual(schemaVersion, 12)
        XCTAssertEqual(restoredState, expected)
        let edited = try await reopened.libraryAssets(query: LibraryQuery(isEdited: true), limit: 10, offset: 0)
        XCTAssertEqual(edited.map(\.id), [asset.id])
    }

    func testH264VideoExportAppliesTrimAndPreservesSourceFile() async throws {
        let sourceURL = temporaryDirectory.appending(path: "source.mov")
        try await makeVideo(at: sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)

        var state = VideoEditState.identity
        state.trimStart = 0.1
        state.trimEnd = 0.5
        state.speed = 2
        state.adjustments.exposure = 0.4
        state.adjustments.saturation = -0.2
        state.transform.crop = NormalizedCrop(x: 0, y: 0, width: 0.75, height: 1)
        let destinationURL = temporaryDirectory.appending(path: "edited.mp4")
        let service = VideoExportService()
        let report = try await service.export(
            sourceURL: sourceURL,
            state: state,
            lut: nil,
            destinationURL: destinationURL,
            options: VideoExportOptions(format: .h264, quality: .high, resize: .original, namingRule: .editedName, collisionPolicy: .rename),
            allowsOverwrite: false
        )

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)))
        XCTAssertNotEqual(destinationURL.standardizedFileURL, sourceURL.standardizedFileURL)
        XCTAssertEqual(report.destinationURL, destinationURL)
        XCTAssertEqual(report.format, .h264)
        XCTAssertEqual(report.duration, 0.2, accuracy: 0.05)

        let outputAsset = AVURLAsset(url: destinationURL)
        let outputDuration = try await outputAsset.load(.duration)
        let outputTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let outputTrack = try XCTUnwrap(outputTracks.first)
        let outputSize = try await outputTrack.load(.naturalSize)
        let formatDescriptions = try await outputTrack.load(.formatDescriptions)
        XCTAssertEqual(CMTimeGetSeconds(outputDuration), 0.2, accuracy: 0.07)
        XCTAssertEqual(outputSize, CGSize(width: 48, height: 48))
        XCTAssertTrue(formatDescriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 })
    }

    func testVideoExportRejectsOriginalAsDestinationBeforeWriting() async throws {
        let sourceURL = temporaryDirectory.appending(path: "protected.mov")
        let service = VideoExportService()
        do {
            _ = try await service.export(
                sourceURL: sourceURL,
                state: .identity,
                lut: nil,
                destinationURL: sourceURL,
                options: VideoExportOptions(),
                allowsOverwrite: true
            )
            XCTFail("Expected export to reject its original source URL")
        } catch let error as StudioError {
            guard case .exportFailed = error else {
                return XCTFail("Unexpected StudioError: \(error)")
            }
        }
    }

    func testHEVCVideoExportWritesHEVCMP4WhenTheSystemPresetIsAvailable() async throws {
        let sourceURL = temporaryDirectory.appending(path: "hevc-source.mov")
        try await makeVideo(at: sourceURL)
        let destinationURL = temporaryDirectory.appending(path: "hevc-edited.mp4")
        let service = VideoExportService()

        do {
            _ = try await service.export(
                sourceURL: sourceURL,
                state: .identity,
                lut: nil,
                destinationURL: destinationURL,
                options: VideoExportOptions(format: .hevc, quality: .high, resize: .original, namingRule: .editedName, collisionPolicy: .rename),
                allowsOverwrite: false
            )
        } catch let error as StudioError {
            guard case .exportFailed(let message) = error,
                  message.contains("不支持") else {
                throw error
            }
            throw XCTSkip("当前 macOS 未提供与此源视频兼容的 HEVC export preset：\(message)")
        }

        let outputAsset = AVURLAsset(url: destinationURL)
        let outputTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let outputTrack = try XCTUnwrap(outputTracks.first)
        let formatDescriptions = try await outputTrack.load(.formatDescriptions)
        XCTAssertTrue(formatDescriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC })
    }

    func testVideoProxyGenerationPersistsDerivedFileAndNeverModifiesSource() async throws {
        let sourceURL = temporaryDirectory.appending(path: "proxy-source.mov")
        try await makeVideo(at: sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)
        let paths = try CatalogPaths.create(in: temporaryDirectory.appending(path: "proxy-catalog", directoryHint: .isDirectory))
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let asset = try await catalogVideoAsset(store: store, sourceURL: sourceURL)
        let service = VideoProxyService(catalogStore: store, directoryURL: paths.videoProxiesDirectory)

        let report = try await service.generate(for: asset, sourceURL: sourceURL)

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.proxyURL.path(percentEncoded: false)))
        XCTAssertEqual(report.proxyURL.deletingLastPathComponent().standardizedFileURL, paths.videoProxiesDirectory.standardizedFileURL)
        let currentProxy = try await service.proxyURL(for: asset)
        XCTAssertEqual(currentProxy, report.proxyURL)
        let reopened = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await reopened.bootstrap()
        let stored = try await reopened.videoProxy(for: asset.id)
        XCTAssertEqual(stored?.sourceFileSize, asset.fileSize)
        XCTAssertEqual(stored?.relativePath, report.proxyURL.lastPathComponent)

        let staleRecord = try XCTUnwrap(stored)
        try await reopened.saveVideoProxy(
            VideoProxyRecord(
                assetID: staleRecord.assetID,
                sourceFileSize: staleRecord.sourceFileSize + 1,
                sourceModifiedAt: staleRecord.sourceModifiedAt,
                relativePath: staleRecord.relativePath,
                width: staleRecord.width,
                height: staleRecord.height,
                createdAt: staleRecord.createdAt,
                updatedAt: .now
            )
        )
        let staleProxy = try await service.proxyURL(for: asset)
        XCTAssertNil(staleProxy)

        try await service.removeProxy(for: asset.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: report.proxyURL.path(percentEncoded: false)))
        let deleted = try await store.videoProxy(for: asset.id)
        XCTAssertNil(deleted)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    private func catalogVideoAsset(store: CatalogStore, sourceURL: URL) async throws -> LibraryAssetRecord {
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path(percentEncoded: false))
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
        let modifiedAt = try XCTUnwrap(attributes[.modificationDate] as? Date)
        let root = MediaRootRecord(
            id: UUID(), displayName: "Proxy Root", bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false), volumeIdentifier: nil,
            availability: .online, createdAt: .now, lastScannedAt: nil, lastScanError: nil
        )
        try await store.saveMediaRoot(root)
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch([
            ScannedMediaAsset(
                rootID: root.id,
                relativePath: sourceURL.lastPathComponent,
                fileResourceIdentifier: "proxy-source",
                mediaType: .video,
                fileExtension: "mov",
                fileSize: fileSize,
                createdAt: modifiedAt,
                modifiedAt: modifiedAt,
                metadata: .video(VideoMetadata(
                    width: 64, height: 48, duration: 0.8, frameRate: 30, codec: "H.264", creationDate: modifiedAt
                ))
            )
        ], scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)
        let assets = try await store.libraryAssets(query: .all, limit: 1, offset: 0)
        return try XCTUnwrap(assets.first)
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 48,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 200_000]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 48
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try pixelBuffer(frame: frame)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? StudioError.exportFailed(message: "无法生成临时 H.264 测试视频。")
        }
    }

    private func pixelBuffer(frame: Int) throws -> CVPixelBuffer {
        var rawBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            48,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &rawBuffer
        )
        guard result == kCVReturnSuccess, let buffer = rawBuffer else {
            throw StudioError.exportFailed(message: "无法创建临时视频像素帧。")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw StudioError.exportFailed(message: "无法写入临时视频像素帧。")
        }
        let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
        memset(address, frame.isMultiple(of: 2) ? 0x20 : 0xC0, bytes)
        return buffer
    }

    private func rgba(of image: CIImage) throws -> SIMD4<Double> {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let bounds = CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1)
        var pixels = Array(repeating: UInt8(0), count: 4)
        context.render(
            image.cropped(to: bounds),
            toBitmap: &pixels,
            rowBytes: 4,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return SIMD4<Double>(
            Double(pixels[0]) / 255,
            Double(pixels[1]) / 255,
            Double(pixels[2]) / 255,
            Double(pixels[3]) / 255
        )
    }
}
