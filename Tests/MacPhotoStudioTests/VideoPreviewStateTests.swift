@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import XCTest
@testable import MacPhotoStudio

@MainActor
final class VideoPreviewStateTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioVideoPreviewStateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testRestoredPreviewStatePreservesValuesAndClampsOnlyForShorterComposition() {
        let state = VideoPreviewPlaybackState(
            currentTime: 35,
            isPlaying: true,
            playbackRate: 1.5,
            isMuted: true,
            volume: 0.35
        )

        XCTAssertEqual(state.restored(forDuration: 40), state)
        XCTAssertEqual(state.restored(forDuration: 12).currentTime, 12)
        XCTAssertEqual(state.restored(forDuration: 12).isPlaying, true)
        XCTAssertEqual(state.restored(forDuration: 12).playbackRate, 1.5)
        XCTAssertEqual(state.restored(forDuration: 12).isMuted, true)
        XCTAssertEqual(state.restored(forDuration: 12).volume, 0.35)
    }

    func testReplacingPlayerItemRestoresPlayheadAndPlayingState() async throws {
        let sourceURL = temporaryDirectory.appending(path: "preview-source.mov")
        try await makeVideo(at: sourceURL)
        let session = VideoPlaybackSession(
            sourceURL: sourceURL,
            securityScopedRootURL: temporaryDirectory,
            duration: 1,
            frameRate: 30
        )
        defer { session.close() }

        session.seek(to: 0.5)
        session.setPlaybackRate(1.5)
        session.setVolume(0.35)
        session.toggleMute()
        session.play()

        let replacement = AVPlayerItem(url: sourceURL)
        session.replaceCurrentItem(with: replacement, duration: 1)

        for _ in 0..<100 where !session.isPlaying {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(session.isPlaying)
        XCTAssertEqual(session.currentTime, 0.5, accuracy: 0.05)
        XCTAssertEqual(session.playbackRate, 1.5)
        XCTAssertTrue(session.isMuted)
        XCTAssertEqual(session.volume, 0.35, accuracy: 0.001)
        XCTAssertTrue(session.player.isMuted)
        XCTAssertEqual(session.player.volume, 0.35, accuracy: 0.001)
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

        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try pixelBuffer(shade: frame.isMultiple(of: 2) ? 0x20 : 0xC0)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? StudioError.exportFailed(message: "无法生成临时视频预览测试文件。")
        }
    }

    private func pixelBuffer(shade: UInt8) throws -> CVPixelBuffer {
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
            throw StudioError.exportFailed(message: "无法创建临时视频预览像素帧。")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw StudioError.exportFailed(message: "无法写入临时视频预览像素帧。")
        }
        memset(address, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        return buffer
    }
}
