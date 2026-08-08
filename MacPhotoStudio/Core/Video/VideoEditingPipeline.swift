@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// AVFoundation objects are created and consumed by the main-actor editor.
/// The wrapper only crosses the service boundary; it is never used concurrently.
final class VideoPreviewPayload: @unchecked Sendable {
    let playerItem: AVPlayerItem
    let duration: Double

    init(playerItem: AVPlayerItem, duration: Double) {
        self.playerItem = playerItem
        self.duration = duration
    }
}

private final class PreparedVideoComposition: @unchecked Sendable {
    let composition: AVMutableComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVAudioMix?
    let duration: Double

    init(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix?,
        duration: Double
    ) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.duration = duration
    }
}

enum VideoFramePipeline {
    static func outputSize(
        sourceSize: CGSize,
        state: VideoEditState,
        maximumPixelSize: Int?
    ) -> CGSize {
        let crop = state.transform.crop.clamped
        var width = max(2, (abs(sourceSize.width) * crop.width).rounded())
        var height = max(2, (abs(sourceSize.height) * crop.height).rounded())
        if state.transform.normalizedRotationDegrees == 90 || state.transform.normalizedRotationDegrees == 270 {
            swap(&width, &height)
        }
        if let maximumPixelSize, maximumPixelSize > 0 {
            let scale = min(1, CGFloat(maximumPixelSize) / max(width, height))
            width = max(2, (width * scale).rounded())
            height = max(2, (height * scale).rounded())
        }
        // H.264 and HEVC export is safest with even dimensions.
        return CGSize(width: even(width), height: even(height))
    }

    static func apply(
        _ source: CIImage,
        state: VideoEditState,
        lut: CubeLUT?,
        renderSize: CGSize,
        compositionTime: Double? = nil,
        compositionDuration: Double? = nil
    ) -> CIImage {
        var image = source
        if state.adjustments.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: state.adjustments.exposure])
        }
        if state.adjustments.contrast != 0 || state.adjustments.saturation != 0 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1 + state.adjustments.contrast,
                kCIInputSaturationKey: max(0, 1 + state.adjustments.saturation)
            ])
        }
        if state.adjustments.temperature != 0 || state.adjustments.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(
                    x: CGFloat(6_500 + state.adjustments.temperature * 2_500),
                    y: CGFloat(state.adjustments.tint * 100)
                ),
                "inputTargetNeutral": CIVector(x: 6_500, y: 0)
            ])
        }
        if let lut, let application = state.lut {
            image = LUTProcessor.apply(lut, to: image, strength: application.clampedStrength)
        }
        image = transformed(image, state: state, renderSize: renderSize)
        if let compositionTime, let compositionDuration {
            let opacity = VideoFadeEnvelope.opacity(
                at: compositionTime,
                duration: compositionDuration,
                fadeIn: state.clampedFadeInDuration,
                fadeOut: state.clampedFadeOutDuration
            )
            if opacity < 1 {
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: opacity, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: opacity, w: 0)
                ])
            }
        }
        return image
    }

    private static func transformed(_ source: CIImage, state: VideoEditState, renderSize: CGSize) -> CIImage {
        let extent = source.extent
        let crop = state.transform.crop.clamped
        let cropRect = CGRect(
            x: extent.minX + extent.width * crop.x,
            y: extent.minY + extent.height * crop.y,
            width: extent.width * crop.width,
            height: extent.height * crop.height
        ).integral
        var image = normalized(source.cropped(to: cropRect))

        switch state.transform.normalizedRotationDegrees {
        case 90:
            image = normalized(image.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)))
        case 180:
            image = normalized(image.transformed(by: CGAffineTransform(rotationAngle: .pi)))
        case 270:
            image = normalized(image.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2)))
        default:
            break
        }
        if state.transform.flipHorizontal {
            image = normalized(image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)))
        }
        if state.transform.flipVertical {
            image = normalized(image.transformed(by: CGAffineTransform(scaleX: 1, y: -1)))
        }
        let transformedExtent = image.extent
        guard transformedExtent.width > 0, transformedExtent.height > 0 else { return source }
        let scale = CGAffineTransform(
            scaleX: renderSize.width / transformedExtent.width,
            y: renderSize.height / transformedExtent.height
        )
        return normalized(image.transformed(by: scale))
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
    }
}

private enum VideoCompositionBuilder {
    static func prepare(
        sourceURL: URL,
        state: VideoEditState,
        lut: CubeLUT?,
        resize: VideoExportResize = .original
    ) async throws -> PreparedVideoComposition {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceDuration = try await sourceAsset.load(.duration)
        let sourceDurationSeconds = sourceDuration.isNumeric ? CMTimeGetSeconds(sourceDuration) : 0
        let trim = try state.resolvedTrim(for: sourceDurationSeconds)
        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw StudioError.exportFailed(message: "源文件不包含可导出的视频轨。")
        }
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw StudioError.exportFailed(message: "无法创建视频编辑轨。")
        }
        let trimRange = CMTimeRange(
            start: CMTime(seconds: trim.start, preferredTimescale: 600),
            duration: CMTime(seconds: trim.duration, preferredTimescale: 600)
        )
        try compositionVideoTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = preferredTransform

        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        for sourceAudioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let sourceAudioRange = try await sourceAudioTrack.load(.timeRange)
            let intersection = CMTimeRangeGetIntersection(trimRange, otherRange: sourceAudioRange)
            guard intersection.isValid, !intersection.isEmpty else { continue }
            let destinationStart = CMTimeSubtract(intersection.start, trimRange.start)
            try compositionAudioTrack.insertTimeRange(intersection, of: sourceAudioTrack, at: destinationStart)
        }

        let scaledDuration = CMTimeMultiplyByFloat64(trimRange.duration, multiplier: 1 / state.clampedSpeed)
        composition.scaleTimeRange(
            CMTimeRange(start: .zero, duration: trimRange.duration),
            toDuration: scaledDuration
        )

        let renderSize = VideoFramePipeline.outputSize(
            sourceSize: VideoGeometry.displaySize(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform
            ),
            state: state,
            maximumPixelSize: resize.maximumPixelSize
        )
        let frameRate = max(1, Int32(nominalFrameRate.rounded()))
        let outputDuration = trim.duration / state.clampedSpeed
        let videoComposition = AVMutableVideoComposition(
            asset: composition,
            applyingCIFiltersWithHandler: { request in
                let rendered = VideoFramePipeline.apply(
                    request.sourceImage,
                    state: state,
                    lut: lut,
                    renderSize: renderSize,
                    compositionTime: CMTimeGetSeconds(request.compositionTime),
                    compositionDuration: outputDuration
                )
                request.finish(with: rendered, context: nil)
            }
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)

        let duration = composition.duration.isNumeric ? CMTimeGetSeconds(composition.duration) : outputDuration
        let audioMix = makeAudioMix(for: composition, state: state, duration: duration)
        return PreparedVideoComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            duration: duration
        )
    }

    private static func makeAudioMix(
        for composition: AVMutableComposition,
        state: VideoEditState,
        duration: Double
    ) -> AVAudioMix? {
        let audioTracks = composition.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return nil }
        let gain: Float = state.isMuted ? 0 : VideoAudioGain.linearVolume(for: state.audioGain)
        let fadeIn = VideoFadeEnvelope.clampedDuration(state.clampedAudioFadeInDuration, within: duration)
        let fadeOut = VideoFadeEnvelope.clampedDuration(state.clampedAudioFadeOutDuration, within: duration)
        let parameters = audioTracks.map { track -> AVMutableAudioMixInputParameters in
            let parameter = AVMutableAudioMixInputParameters(track: track)
            let volume = gain
            if fadeIn > 0, fadeOut > 0, fadeIn + fadeOut > duration {
                // AVAudioMix ramps do not combine multiplicatively. For overlapping
                // fades, use the exact triangular envelope shared by the video fade:
                // min(t / fadeIn, (duration - t) / fadeOut).
                let crossover = duration * fadeIn / (fadeIn + fadeOut)
                let peakVolume = volume * Float(duration / (fadeIn + fadeOut))
                parameter.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: peakVolume,
                    timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: crossover, preferredTimescale: 600))
                )
                parameter.setVolumeRamp(
                    fromStartVolume: peakVolume,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: crossover, preferredTimescale: 600),
                        duration: CMTime(seconds: duration - crossover, preferredTimescale: 600)
                    )
                )
            } else {
                if fadeIn > 0 {
                    parameter.setVolumeRamp(
                        fromStartVolume: 0,
                        toEndVolume: volume,
                        timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: fadeIn, preferredTimescale: 600))
                    )
                } else {
                    parameter.setVolume(volume, at: .zero)
                }
                if fadeOut > 0 {
                    let start = max(0, duration - fadeOut)
                    parameter.setVolumeRamp(
                        fromStartVolume: volume,
                        toEndVolume: 0,
                        timeRange: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: fadeOut, preferredTimescale: 600))
                    )
                }
            }
            return parameter
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

actor VideoExportService {
    func export(
        sourceURL: URL,
        state: VideoEditState,
        lut: CubeLUT?,
        destinationURL: URL,
        options: VideoExportOptions,
        allowsOverwrite: Bool,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> VideoExportReport {
        guard sourceURL.standardizedFileURL.resolvingSymlinksInPath() != destinationURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw StudioError.exportFailed(message: "导出目标不能覆盖原始视频：\(destinationURL.lastPathComponent)")
        }
        let prepared = try await VideoCompositionBuilder.prepare(
            sourceURL: sourceURL,
            state: state,
            lut: lut,
            resize: options.resize
        )
        let preset = try exportPreset(format: options.format, quality: options.quality, asset: prepared.composition)
        guard let session = AVAssetExportSession(asset: prepared.composition, presetName: preset) else {
            throw StudioError.exportFailed(message: "当前 macOS 无法创建视频导出会话。")
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw StudioError.exportFailed(message: "当前导出 preset 不支持 MP4 容器。")
        }
        session.videoComposition = prepared.videoComposition
        session.audioMix = prepared.audioMix

        let directoryURL = destinationURL.deletingLastPathComponent()
        let temporaryURL = directoryURL
            .appending(path: ".mps-video-export-\(UUID().uuidString)")
            .appendingPathExtension(options.format.filenameExtension)
        // AVAssetExportSession does not infer these from the completion target.
        // The temporary file is moved only after AVFoundation finishes successfully.
        session.outputURL = temporaryURL
        session.outputFileType = .mp4
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        await reportProgress?(0)
        try await run(session, reportProgress: reportProgress)
        try Task.checkCancellation()
        await reportProgress?(1)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            guard allowsOverwrite else {
                throw StudioError.exportFailed(message: "目标文件已存在：\(destinationURL.lastPathComponent)")
            }
            do {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } catch {
                throw StudioError.exportFailed(message: "无法替换已明确选择覆盖的文件：\(destinationURL.lastPathComponent)")
            }
        } else {
            do {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                throw StudioError.exportFailed(message: "无法保存视频：\(error.localizedDescription)")
            }
        }
        return VideoExportReport(destinationURL: destinationURL, duration: prepared.duration, format: options.format)
    }

    private func exportPreset(
        format: VideoExportFormat,
        quality: VideoExportQuality,
        asset: AVAsset
    ) throws -> String {
        let candidates: [String] = switch (format, quality) {
        case (.h264, .high): [AVAssetExportPresetHighestQuality]
        case (.h264, .medium): [AVAssetExportPresetMediumQuality, AVAssetExportPresetHighestQuality]
        case (.h264, .low): [AVAssetExportPresetLowQuality, AVAssetExportPresetMediumQuality]
        case (.hevc, .high): [AVAssetExportPresetHEVCHighestQuality]
        case (.hevc, .medium): [AVAssetExportPresetHEVC1920x1080, AVAssetExportPresetHEVCHighestQuality]
        case (.hevc, .low): [AVAssetExportPresetHEVC1920x1080, AVAssetExportPresetHEVCHighestQuality]
        }
        let supported = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard let preset = candidates.first(where: supported.contains) else {
            throw StudioError.exportFailed(message: "当前系统/源视频不支持所选 \(format.title) 导出 preset。")
        }
        return preset
    }

    private func run(
        _ session: AVAssetExportSession,
        reportProgress: (@Sendable (Double) async -> Void)?
    ) async throws {
        let box = ExportSessionBox(session)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                box.session.exportAsynchronously {
                    switch box.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(throwing: box.session.error ?? StudioError.exportFailed(message: "视频导出失败。"))
                    default:
                        continuation.resume(throwing: StudioError.exportFailed(message: "视频导出未完成。"))
                    }
                }
                // Start after exportAsynchronously(). The prior implementation began
                // polling while the session was still `.unknown`, so short exports
                // could skip every intermediate progress update.
                Task { [box, reportProgress] in
                    var lastProgress = -1.0
                    while !Task.isCancelled {
                        let progress = Double(box.session.progress)
                        if progress != lastProgress {
                            lastProgress = progress
                            await reportProgress?(progress)
                        }
                        switch box.session.status {
                        case .completed, .cancelled, .failed:
                            return
                        default:
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                    }
                }
            }
        }, onCancel: {
            box.session.cancelExport()
        })
    }
}

@MainActor
final class VideoEditingService {
    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore
    private let lutRepository: LUTRepository
    private let exportService = VideoExportService()

    init(catalogStore: CatalogStore, mediaRootStore: MediaRootStore, lutRepository: LUTRepository) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
        self.lutRepository = lutRepository
    }

    func editState(for assetID: UUID) async throws -> VideoEditState {
        try await catalogStore.videoEditState(for: assetID) ?? .identity
    }

    func save(_ state: VideoEditState, for assetID: UUID) async throws {
        try await catalogStore.saveVideoEditState(state, for: assetID)
    }

    func lutLibrary() async throws -> LUTLibrary {
        try await lutRepository.library()
    }

    func previewPayload(sourceURL: URL, state: VideoEditState) async throws -> VideoPreviewPayload {
        let lut = try await selectedCreativeLUT(for: state)
        let prepared = try await VideoCompositionBuilder.prepare(sourceURL: sourceURL, state: state, lut: lut)
        let item = AVPlayerItem(asset: prepared.composition)
        item.videoComposition = prepared.videoComposition
        item.audioMix = prepared.audioMix
        return VideoPreviewPayload(playerItem: item, duration: prepared.duration)
    }

    func export(
        asset: LibraryAssetRecord,
        state: VideoEditState,
        destinationURL: URL,
        options: VideoExportOptions,
        allowsOverwrite: Bool,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> VideoExportReport {
        guard asset.mediaType == .video else {
            throw StudioError.exportFailed(message: "只能导出视频媒体。")
        }
        guard asset.videoIsHDR != true else {
            throw StudioError.exportFailed(message: "HDR 视频编辑与导出将在 Phase 10 提供；当前不会以 SDR 管线错误处理 HDR 源文件。")
        }
        guard let root = try await catalogStore.mediaRoot(id: asset.rootID) else {
            throw StudioError.mediaRootNotFound(id: asset.rootID)
        }
        let resolvedRoot = try await mediaRootStore.resolve(root)
        let sourceURL = try sourceURL(for: asset, rootURL: resolvedRoot.directoryURL)
        let lut = try await selectedCreativeLUT(for: state)
        return try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolvedRoot.directoryURL) {
            guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
                throw StudioError.exportFailed(message: "找不到原始视频：\(asset.filename)")
            }
            return try await self.exportService.export(
                sourceURL: sourceURL,
                state: state,
                lut: lut,
                destinationURL: destinationURL,
                options: options,
                allowsOverwrite: allowsOverwrite,
                reportProgress: reportProgress
            )
        }
    }

    private func selectedCreativeLUT(for state: VideoEditState) async throws -> CubeLUT? {
        guard let application = state.lut else { return nil }
        guard let lut = try await lutRepository.lut(identifier: application.identifier) else {
            throw StudioError.invalidLUT(message: "所选视频 LUT 已不存在。")
        }
        guard lut.kind == .creative else {
            throw StudioError.invalidLUT(message: "视频基础编辑只接受 Creative LUT；Technical LUT 保留给后续独立视频色彩管理阶段。")
        }
        return lut
    }

    private func sourceURL(for asset: LibraryAssetRecord, rootURL: URL) throws -> URL {
        let normalizedRoot = rootURL.standardizedFileURL
        let sourceURL = normalizedRoot.appending(path: asset.relativePath).standardizedFileURL
        let rootPath = normalizedRoot.path(percentEncoded: false).hasSuffix("/")
            ? normalizedRoot.path(percentEncoded: false)
            : normalizedRoot.path(percentEncoded: false) + "/"
        guard sourceURL.path(percentEncoded: false).hasPrefix(rootPath) else {
            throw StudioError.exportFailed(message: "拒绝访问资料库根目录外的媒体路径。")
        }
        return sourceURL
    }
}
