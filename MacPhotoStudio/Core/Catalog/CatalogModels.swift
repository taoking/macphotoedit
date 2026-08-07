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

enum AssetFlag: String, Codable, Sendable, CaseIterable {
    case unflagged
    case pick
    case reject
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
    var gpsLatitude: Double? = nil
    var gpsLongitude: Double? = nil
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

struct TagRecord: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
}

struct LibraryQuery: Sendable, Equatable {
    var rootID: UUID? = nil
    var searchText: String? = nil
    var mediaType: MediaType? = nil
    var minimumRating: Int? = nil
    var flag: AssetFlag? = nil
    var tagID: UUID? = nil
    var captureDateFrom: Date? = nil
    var captureDateTo: Date? = nil
    var camera: String? = nil
    var lens: String? = nil

    static let all = LibraryQuery()
}

struct LibraryAssetRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    let rootID: UUID
    let rootDisplayName: String
    let rootPath: String
    let relativePath: String
    let mediaType: MediaType
    let fileExtension: String
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let availability: MediaAssetAvailability
    let metadataState: MetadataState
    let rating: Int
    let flag: AssetFlag
    let width: Int?
    let height: Int?
    let captureDate: Date?
    let cameraMake: String?
    let cameraModel: String?
    let lensModel: String?
    let focalLength: Double?
    let aperture: Double?
    let shutterSpeed: Double?
    let iso: Int?
    let orientation: Int?
    let colorProfile: String?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let duration: Double?
    let frameRate: Double?
    let codec: String?
    let videoCreationDate: Date?

    var filename: String {
        URL(filePath: relativePath).lastPathComponent
    }

    var folderPath: String {
        URL(filePath: relativePath).deletingLastPathComponent().path(percentEncoded: false)
    }

    var displayDate: Date? {
        captureDate ?? videoCreationDate ?? createdAt
    }
}
