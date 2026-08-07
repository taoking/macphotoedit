import Foundation

struct VideoEditState: Codable, Sendable, Equatable {
    var version = 1
    var trimStart: Double = 0
    /// A nil end uses the complete source duration. Keeping it nil avoids
    /// baking the source duration into a non-destructive edit state.
    var trimEnd: Double?
    var transform = VideoTransformAdjustments()
    var adjustments = VideoColorAdjustments()
    var lut: LUTApplication?
    var isMuted = false
    /// Gain in dB. The export pipeline converts this to a linear AVAudioMix volume.
    var audioGain: Double = 0
    var speed: Double = 1

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, trimStart, trimEnd, transform, adjustments, lut, isMuted, audioGain, speed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        trimStart = try container.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(Double.self, forKey: .trimEnd)
        transform = try container.decodeIfPresent(VideoTransformAdjustments.self, forKey: .transform) ?? .init()
        adjustments = try container.decodeIfPresent(VideoColorAdjustments.self, forKey: .adjustments) ?? .init()
        lut = try container.decodeIfPresent(LUTApplication.self, forKey: .lut)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        audioGain = try container.decodeIfPresent(Double.self, forKey: .audioGain) ?? 0
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1
    }

    static let identity = VideoEditState()

    var clampedSpeed: Double { min(max(speed, 0.25), 4) }
    var clampedAudioGain: Double { min(max(audioGain, -60), 12) }

    func resolvedTrim(for sourceDuration: Double) throws -> VideoTrimRange {
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw StudioError.exportFailed(message: "视频时长不可用，无法创建编辑时间范围。")
        }
        let start = min(max(trimStart, 0), max(0, sourceDuration - 0.01))
        let end = min(max(trimEnd ?? sourceDuration, start + 0.01), sourceDuration)
        guard end - start >= 0.01 else {
            throw StudioError.exportFailed(message: "裁剪结束时间必须晚于开始时间。")
        }
        return VideoTrimRange(start: start, end: end)
    }
}

struct VideoTrimRange: Sendable, Equatable {
    let start: Double
    let end: Double

    var duration: Double { end - start }
}

struct VideoTransformAdjustments: Codable, Sendable, Equatable {
    var crop = NormalizedCrop.identity
    /// Quarter-turns keep AVFoundation output geometry and metadata deterministic.
    var rotationDegrees: Int = 0
    var flipHorizontal = false
    var flipVertical = false

    var normalizedRotationDegrees: Int {
        let normalized = ((rotationDegrees % 360) + 360) % 360
        let quarterTurns = Int((Double(normalized) / 90).rounded()) % 4
        return quarterTurns * 90
    }
}

struct VideoColorAdjustments: Codable, Sendable, Equatable {
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var temperature: Double = 0
    var tint: Double = 0
}

enum VideoExportFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC (H.265)"
        }
    }

    var filenameExtension: String { "mp4" }
}

enum VideoExportQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "高质量"
        case .medium: "中等质量"
        case .low: "较小文件"
        }
    }
}

struct VideoExportResize: Codable, Sendable, Equatable {
    var maximumPixelSize: Int?

    static let original = VideoExportResize(maximumPixelSize: nil)

    static func maximum(_ pixelSize: Int) -> VideoExportResize {
        VideoExportResize(maximumPixelSize: max(1, pixelSize))
    }
}

enum VideoExportNamingRule: String, Codable, CaseIterable, Sendable, Identifiable {
    case originalName
    case editedName

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalName: "原始文件名"
        case .editedName: "原始文件名 - Edited"
        }
    }

    func baseFilename(for asset: LibraryAssetRecord) -> String {
        let original = URL(filePath: asset.filename).deletingPathExtension().lastPathComponent
        let safeOriginal = original.isEmpty ? "video" : original
        return self == .editedName ? "\(safeOriginal)-edited" : safeOriginal
    }
}

struct VideoExportOptions: Codable, Sendable, Equatable {
    var format: VideoExportFormat = .h264
    var quality: VideoExportQuality = .high
    var resize: VideoExportResize = .original
    var namingRule: VideoExportNamingRule = .editedName
    var collisionPolicy: ExportCollisionPolicy = .rename
}

struct VideoExportReport: Sendable, Equatable {
    let destinationURL: URL
    let duration: Double
    let format: VideoExportFormat
}
