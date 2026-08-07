import Foundation

enum MediaType: String, Codable, Sendable, CaseIterable {
    case photo
    case video
}

enum MediaRootAvailability: String, Codable, Sendable, CaseIterable {
    case online
    case offline
    case permissionRequired
}

enum MediaAssetAvailability: String, Codable, Sendable, CaseIterable {
    case available
    case missing
    case offline
}

enum MetadataState: String, Codable, Sendable {
    case available
    case unavailable
    case unchanged
}

struct MediaRootRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    var displayName: String
    var bookmarkData: Data
    var lastKnownPath: String
    var volumeIdentifier: String?
    var availability: MediaRootAvailability
    var createdAt: Date
    var lastScannedAt: Date?
    var lastScanError: String?
}

struct AssetFingerprint: Sendable, Equatable {
    let fileSize: Int64
    let modifiedAt: Date?
    let fileResourceIdentifier: String?

    func matches(
        fileSize: Int64,
        modifiedAt: Date?,
        fileResourceIdentifier: String?
    ) -> Bool {
        guard self.fileSize == fileSize else { return false }

        if let modifiedAt, let currentModifiedAt = self.modifiedAt,
           abs(modifiedAt.timeIntervalSince1970 - currentModifiedAt.timeIntervalSince1970) > 0.001 {
            return false
        }

        if let identifier = self.fileResourceIdentifier,
           let currentIdentifier = fileResourceIdentifier,
           identifier != currentIdentifier {
            return false
        }

        return modifiedAt != nil || fileResourceIdentifier != nil
    }
}

struct PhotoMetadata: Sendable, Equatable {
    var width: Int?
    var height: Int?
    var captureDate: Date?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: Double?
    var iso: Int?
    var orientation: Int?
    var colorProfile: String?
}

struct VideoMetadata: Sendable, Equatable {
    var width: Int?
    var height: Int?
    var duration: Double?
    var frameRate: Double?
    var codec: String?
    var creationDate: Date?
}

enum ExtractedMetadata: Sendable, Equatable {
    case photo(PhotoMetadata)
    case video(VideoMetadata)
    case unavailable
    case unchanged

    var state: MetadataState {
        switch self {
        case .photo, .video:
            return .available
        case .unavailable:
            return .unavailable
        case .unchanged:
            return .unchanged
        }
    }
}

struct ScannedMediaAsset: Sendable, Equatable {
    let rootID: UUID
    let relativePath: String
    let fileResourceIdentifier: String?
    let mediaType: MediaType
    let fileExtension: String
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let metadata: ExtractedMetadata
}

struct MediaAssetRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    let rootID: UUID
    let relativePath: String
    let mediaType: MediaType
    let fileExtension: String
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let availability: MediaAssetAvailability
    let metadataState: MetadataState
}
