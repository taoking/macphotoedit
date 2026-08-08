@preconcurrency import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreVideo
import Foundation
import XCTest
@testable import MacPhotoStudio

final class VideoExportAudioTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioVideoExportAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testH264ExportKeepsAudioAndVideoInSyncAfterTrimSpeedFadesAndResize() async throws {
        let sourceURL = temporaryDirectory.appending(path: "source-with-audio.mov")
        try await makeVideoWithAudio(at: sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)

        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceVideoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        let sourceAudioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(sourceVideoTracks.count, 1)
        XCTAssertEqual(sourceAudioTracks.count, 1)

        var state = VideoEditState.identity
        state.trimStart = 0.2
        state.trimEnd = 0.8
        state.speed = 2
        state.transform.flipHorizontal = true
        state.adjustments.exposure = 0.25
        state.audioGain = -6
        state.fadeInDuration = 0.1
        state.fadeOutDuration = 0.1
        state.audioFadeInDuration = 0.1
        state.audioFadeOutDuration = 0.1
        let destinationURL = temporaryDirectory.appending(path: "edited-with-audio.mp4")

        let report = try await VideoExportService().export(
            sourceURL: sourceURL,
            state: state,
            lut: nil,
            destinationURL: destinationURL,
            options: VideoExportOptions(
                format: .h264,
                quality: .high,
                resize: .maximum(32),
                namingRule: .editedName,
                collisionPolicy: .rename
            ),
            allowsOverwrite: false
        )

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)))
        XCTAssertEqual(report.duration, 0.3, accuracy: 0.06)

        let outputAsset = AVURLAsset(url: destinationURL)
        let outputDuration = try await outputAsset.load(.duration)
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let outputAudioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(outputVideoTracks.first)
        let audioTrack = try XCTUnwrap(outputAudioTracks.first)
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let audioTimeRange = try await audioTrack.load(.timeRange)
        let outputSize = try await videoTrack.load(.naturalSize)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)

        XCTAssertEqual(CMTimeGetSeconds(outputDuration), 0.3, accuracy: 0.08)
        XCTAssertEqual(CMTimeGetSeconds(videoTimeRange.duration), 0.3, accuracy: 0.08)
        XCTAssertEqual(CMTimeGetSeconds(audioTimeRange.duration), 0.3, accuracy: 0.08)
        XCTAssertEqual(CMTimeGetSeconds(videoTimeRange.duration), CMTimeGetSeconds(audioTimeRange.duration), accuracy: 0.04)
        XCTAssertEqual(outputSize, CGSize(width: 24, height: 32))
        XCTAssertTrue(formatDescriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 })
    }

    private func makeVideoWithAudio(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 48,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 200_000]
            ]
        )
        videoInput.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0)
        videoInput.expectsMediaDataInRealTime = false
        let videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 48
            ]
        )
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
        )
        audioInput.expectsMediaDataInRealTime = false
        XCTAssertTrue(writer.canAdd(videoInput))
        XCTAssertTrue(writer.canAdd(audioInput))
        writer.add(videoInput)
        writer.add(audioInput)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<30 {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try pixelBuffer(shade: frame.isMultiple(of: 2) ? 0x20 : 0xC0)
            XCTAssertTrue(videoAdaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        for startFrame in stride(from: 0, to: 44_100, by: 1_024) {
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let frameCount = min(1_024, 44_100 - startFrame)
            let buffer = try audioSampleBuffer(startFrame: startFrame, frameCount: frameCount)
            XCTAssertTrue(audioInput.append(buffer))
        }
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? StudioError.exportFailed(message: "无法生成带音轨的临时视频 fixture。")
        }
    }

    private func audioSampleBuffer(startFrame: Int, frameCount: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Int16>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Int16>.size),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw StudioError.exportFailed(message: "无法创建临时音频 format description。")
        }

        var samples = [Int16](repeating: 0, count: frameCount)
        for index in samples.indices {
            let time = Double(startFrame + index) / 44_100
            samples[index] = Int16((sin(2 * Double.pi * 440 * time) * 6_000).rounded())
        }
        let byteCount = samples.count * MemoryLayout<Int16>.size
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else {
            throw StudioError.exportFailed(message: "无法创建临时音频 block buffer。")
        }
        let replaceStatus = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw StudioError.exportFailed(message: "无法写入临时音频样本。")
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 44_100),
            presentationTimeStamp: CMTime(value: Int64(startFrame), timescale: 44_100),
            decodeTimeStamp: .invalid
        )
        var sampleSize = MemoryLayout<Int16>.size
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw StudioError.exportFailed(message: "无法创建临时音频 sample buffer。")
        }
        return sampleBuffer
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
            throw StudioError.exportFailed(message: "无法创建临时视频像素帧。")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw StudioError.exportFailed(message: "无法写入临时视频像素帧。")
        }
        memset(address, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        return buffer
    }
}
