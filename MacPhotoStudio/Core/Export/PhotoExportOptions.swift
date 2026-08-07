import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoExportFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case jpeg
    case heif
    case tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .heif: "HEIF（HEIC）"
        case .tiff: "TIFF"
        }
    }

    var filenameExtension: String { self == .heif ? "heic" : rawValue }

    var contentType: UTType {
        switch self {
        case .jpeg: .jpeg
        // HEIC is the still-image profile exposed by ImageIO for HEIF encoding.
        case .heif: .heic
        case .tiff: .tiff
        }
    }

    var isSupported: Bool {
        let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return supportedTypes.contains(contentType.identifier)
    }
}

/// Kept as a source-compatible name for the Phase 4 RAW editor. RAW and
/// ordinary photos intentionally share the same concrete output formats.
typealias RAWExportFormat = PhotoExportFormat

struct PhotoExportResize: Codable, Sendable, Equatable {
    var maximumPixelSize: Int?

    static let original = PhotoExportResize(maximumPixelSize: nil)

    static func maximum(_ pixelSize: Int) -> PhotoExportResize {
        PhotoExportResize(maximumPixelSize: max(1, pixelSize))
    }

    var isOriginal: Bool { maximumPixelSize == nil }
}

enum PhotoExportNamingRule: String, Codable, CaseIterable, Sendable, Identifiable {
    case originalName
    case editedName
    case sequence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalName: "原始文件名"
        case .editedName: "原始文件名 - Edited"
        case .sequence: "连续编号"
        }
    }

    func baseFilename(for asset: LibraryAssetRecord, sequenceNumber: Int) -> String {
        let original = URL(filePath: asset.filename).deletingPathExtension().lastPathComponent
        let safeOriginal = original.isEmpty ? "photo" : original
        return switch self {
        case .originalName:
            safeOriginal
        case .editedName:
            "\(safeOriginal)-edited"
        case .sequence:
            String(format: "photo-%04d", max(1, sequenceNumber))
        }
    }
}

enum ExportCollisionPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case overwrite
    case skip
    case rename
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite: "覆盖"
        case .skip: "跳过"
        case .rename: "自动重命名"
        case .ask: "每次询问"
        }
    }
}

enum ExportCollisionResolution: String, Sendable, Equatable {
    case overwrite
    case skip
    case rename
    case cancel
}

struct PhotoExportOptions: Codable, Sendable, Equatable {
    var format: PhotoExportFormat
    var resize: PhotoExportResize
    var quality: Double
    var namingRule: PhotoExportNamingRule
    var keepsMetadata: Bool
    var removesGPS: Bool
    var collisionPolicy: ExportCollisionPolicy
    var outputColorSpace: PhotoColorSpace
    var dynamicRange: PhotoDynamicRange

    private enum CodingKeys: String, CodingKey {
        case format, resize, quality, namingRule, keepsMetadata, removesGPS, collisionPolicy, outputColorSpace, dynamicRange
    }

    init(
        format: PhotoExportFormat = .jpeg,
        resize: PhotoExportResize = .original,
        quality: Double = 0.92,
        namingRule: PhotoExportNamingRule = .editedName,
        keepsMetadata: Bool = true,
        removesGPS: Bool = false,
        collisionPolicy: ExportCollisionPolicy = .rename,
        outputColorSpace: PhotoColorSpace = .sRGB,
        dynamicRange: PhotoDynamicRange = .sdr
    ) {
        self.format = format
        self.resize = resize
        self.quality = min(max(quality, 0), 1)
        self.namingRule = namingRule
        self.keepsMetadata = keepsMetadata
        self.removesGPS = removesGPS
        self.collisionPolicy = collisionPolicy
        self.outputColorSpace = outputColorSpace
        self.dynamicRange = dynamicRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            format: try container.decodeIfPresent(PhotoExportFormat.self, forKey: .format) ?? .jpeg,
            resize: try container.decodeIfPresent(PhotoExportResize.self, forKey: .resize) ?? .original,
            quality: try container.decodeIfPresent(Double.self, forKey: .quality) ?? 0.92,
            namingRule: try container.decodeIfPresent(PhotoExportNamingRule.self, forKey: .namingRule) ?? .editedName,
            keepsMetadata: try container.decodeIfPresent(Bool.self, forKey: .keepsMetadata) ?? true,
            removesGPS: try container.decodeIfPresent(Bool.self, forKey: .removesGPS) ?? false,
            collisionPolicy: try container.decodeIfPresent(ExportCollisionPolicy.self, forKey: .collisionPolicy) ?? .rename,
            outputColorSpace: try container.decodeIfPresent(PhotoColorSpace.self, forKey: .outputColorSpace) ?? .sRGB,
            dynamicRange: try container.decodeIfPresent(PhotoDynamicRange.self, forKey: .dynamicRange) ?? .sdr
        )
    }
}

struct ExportCollision: Sendable, Equatable {
    let sourceAssetID: UUID
    let destinationURL: URL
}

struct BatchExportItemFailure: Sendable, Equatable, Identifiable {
    let assetID: UUID
    let message: String

    var id: UUID { assetID }
}

struct BatchExportReport: Sendable, Equatable {
    let attempted: Int
    let succeeded: Int
    let skipped: Int
    let failures: [BatchExportItemFailure]

    var failed: Int { failures.count }
}

enum ExportDestinationResolver {
    static func destination(
        initialURL: URL,
        sourceAssetID: UUID,
        policy: ExportCollisionPolicy,
        resolver: (@Sendable (ExportCollision) async -> ExportCollisionResolution)?
    ) async throws -> (url: URL?, allowsOverwrite: Bool) {
        guard FileManager.default.fileExists(atPath: initialURL.path(percentEncoded: false)) else {
            return (initialURL, false)
        }

        let resolution: ExportCollisionResolution
        switch policy {
        case .overwrite:
            resolution = .overwrite
        case .skip:
            resolution = .skip
        case .rename:
            resolution = .rename
        case .ask:
            guard let resolver else {
                throw StudioError.exportFailed(message: "输出文件已存在，且没有可用的冲突处理选择。")
            }
            resolution = await resolver(ExportCollision(sourceAssetID: sourceAssetID, destinationURL: initialURL))
        }

        switch resolution {
        case .overwrite:
            return (initialURL, true)
        case .skip:
            return (nil, false)
        case .rename:
            return (uniqueURL(basedOn: initialURL), false)
        case .cancel:
            throw CancellationError()
        }
    }

    static func uniqueURL(basedOn existingURL: URL) -> URL {
        let directory = existingURL.deletingLastPathComponent()
        let base = existingURL.deletingPathExtension().lastPathComponent
        let extensionName = existingURL.pathExtension
        var suffix = 2
        while true {
            let name = "\(base) (\(suffix))"
            let candidate = directory.appending(path: name).appendingPathExtension(extensionName)
            if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            suffix += 1
        }
    }
}
