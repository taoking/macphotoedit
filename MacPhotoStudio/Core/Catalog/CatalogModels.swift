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
    var audioTrackCount: Int? = nil
    var colorPrimaries: String? = nil
    var transferFunction: String? = nil
    var yCbCrMatrix: String? = nil
    var isHDR: Bool? = nil
}

struct VideoProxyRecord: Sendable, Equatable {
    let assetID: UUID
    let sourceFileSize: Int64
    let sourceModifiedAt: Date?
    let relativePath: String
    let width: Int?
    let height: Int?
    let createdAt: Date
    let updatedAt: Date
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

enum AlbumKind: String, Codable, Sendable, CaseIterable, Hashable {
    case album
    case smartAlbum
}

struct SmartAlbumCriteria: Codable, Sendable, Equatable, Hashable {
    var minimumRating: Int? = nil
    var captureDateFrom: Date? = nil
    var captureDateTo: Date? = nil
    var camera: String? = nil
    var lens: String? = nil
    var tagID: UUID? = nil
    var mediaType: MediaType? = nil
    var isEdited: Bool? = nil
    var isRAW: Bool? = nil

    static let all = SmartAlbumCriteria()
}

struct AlbumRecord: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    var name: String
    let kind: AlbumKind
    var criteria: SmartAlbumCriteria?
    let createdAt: Date
    var updatedAt: Date
}

enum AssetStackKind: String, Codable, Sendable, CaseIterable, Hashable {
    case burst
    case rawJPEG
    case user

    var title: String {
        switch self {
        case .burst: "连拍"
        case .rawJPEG: "RAW + JPEG"
        case .user: "自定义"
        }
    }
}

struct AssetStackRecord: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    var title: String
    let kind: AssetStackKind
    let createdAt: Date
    var updatedAt: Date
    var assetCount: Int
}

struct DuplicateHashCandidate: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    let rootID: UUID
    let relativePath: String
    let fileSize: Int64
    let modifiedAt: Date?
}

struct ExactDuplicateGroup: Identifiable, Sendable, Equatable {
    let digest: String
    let fileSize: Int64
    let assets: [DuplicateHashCandidate]

    var id: String { "\(fileSize)-\(digest)" }
}

struct DuplicateScanReport: Sendable, Equatable {
    let candidateCount: Int
    let hashedCount: Int
    let reusedHashCount: Int
    let groups: [ExactDuplicateGroup]
    let failures: [String]
}

/// A photo eligible for local perceptual hashing. Unlike exact duplicate
/// hashing, visual similarity intentionally considers every available photo
/// so resized or re-encoded copies are not excluded by file size.
struct PerceptualHashCandidate: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    let rootID: UUID
    let relativePath: String
    let fileSize: Int64
    let modifiedAt: Date?
}

struct PerceptualHashRecord: Sendable, Equatable, Hashable {
    let candidate: PerceptualHashCandidate
    let digest: String
}

/// One pair within a visual-similarity group. The score is derived solely from
/// a 64-bit dHash Hamming distance; it is a review aid, not semantic identity
/// or a deletion recommendation.
struct SimilarPhotoMatch: Identifiable, Sendable, Equatable, Hashable {
    let first: PerceptualHashCandidate
    let second: PerceptualHashCandidate
    let hammingDistance: Int
    let similarityScore: Int

    var id: String {
        let identifiers = [first.id.uuidString, second.id.uuidString].sorted()
        return "\(identifiers[0])-\(identifiers[1])"
    }
}

struct SimilarPhotoGroup: Identifiable, Sendable, Equatable {
    let assets: [PerceptualHashCandidate]
    let matches: [SimilarPhotoMatch]

    var id: String { assets.map(\.id.uuidString).sorted().joined(separator: "-") }
    var highestSimilarityScore: Int { matches.map(\.similarityScore).max() ?? 0 }
}

struct SimilarPhotoScanReport: Sendable, Equatable {
    let candidateCount: Int
    let hashedCount: Int
    let reusedHashCount: Int
    let groups: [SimilarPhotoGroup]
    let failures: [String]
}

struct TrashMoveReport: Sendable, Equatable {
    let movedAssetIDs: [UUID]
    let failures: [String]
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
    var albumID: UUID? = nil
    var stackID: UUID? = nil
    var smartAlbumCriteria: SmartAlbumCriteria? = nil
    var isEdited: Bool? = nil
    var isRAW: Bool? = nil

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
    let audioTrackCount: Int?
    let videoColorPrimaries: String?
    let videoTransferFunction: String?
    let videoYCbCrMatrix: String?
    let videoIsHDR: Bool?

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
