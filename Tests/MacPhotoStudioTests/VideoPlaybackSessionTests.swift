@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import XCTest
@testable import MacPhotoStudio

@MainActor
final class VideoPlaybackSessionTests: XCTestCase {
    func testReplacingPlayerItemRebindsEndObserverToNewItem() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioPlaybackSessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "source.mov")
        try await makeVideo(at: sourceURL)
        let session = VideoPlaybackSession(
            sourceURL: sourceURL,
            securityScopedRootURL: rootURL,
            duration: 1,
            frameRate: 30
        )
        defer { session.close() }

        let replacement = AVPlayerItem(url: sourceURL)
        session.replaceCurrentItem(with: replacement, duration: 0)
        for _ in 0..<100 where replacement.status == .unknown {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(replacement.status, .readyToPlay)
        XCTAssertNil(session.playbackError)
        XCTAssertEqual(session.duration, 1, accuracy: 0.05)

        session.play()
        XCTAssertTrue(session.isPlaying)

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: replacement)
        for _ in 0..<20 where session.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(session.isPlaying)
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
            throw writer.error ?? StudioError.exportFailed(message: "无法生成临时播放会话测试视频。")
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
            throw StudioError.exportFailed(message: "无法创建临时播放会话像素帧。")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw StudioError.exportFailed(message: "无法写入临时播放会话像素帧。")
        }
        memset(address, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        return buffer
    }
}
