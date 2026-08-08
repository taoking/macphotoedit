@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import XCTest
@testable import MacPhotoStudio

final class VideoGeometryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioVideoGeometryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDisplaySizeAppliesPreferredTransformIncludingTranslation() {
        let portraitTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1_080, ty: 0)
        XCTAssertEqual(
            VideoGeometry.displaySize(
                naturalSize: CGSize(width: 1_920, height: 1_080),
                preferredTransform: portraitTransform
            ),
            CGSize(width: 1_080, height: 1_920)
        )
    }

    func testMetadataExtractorStoresRotatedDisplayDimensions() async throws {
        let url = temporaryDirectory.appending(path: "portrait.mov")
        try await makePortraitVideo(at: url)

        let metadata = try await MediaMetadataExtractor().extractVideo(from: url)

        XCTAssertEqual(metadata.width, 48)
        XCTAssertEqual(metadata.height, 64)
    }

    private func makePortraitVideo(at url: URL) async throws {
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
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0)
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
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(5))
        }
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
                &buffer
            ),
            kCVReturnSuccess
        )
        XCTAssertTrue(adaptor.append(try XCTUnwrap(buffer), withPresentationTime: .zero))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? StudioError.exportFailed(message: "无法创建旋转视频测试文件。")
        }
    }
}
