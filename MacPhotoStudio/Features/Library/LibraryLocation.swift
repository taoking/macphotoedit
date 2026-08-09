import Foundation

enum LibraryLocation: Hashable {
    case all
    case photos
    case videos
    case root(UUID)
    case album(UUID)
    case smartAlbum(UUID)
    case stack(UUID)
    case tag(UUID)

    func libraryQuery(albums: [AlbumRecord]) -> LibraryQuery {
        switch self {
        case .all:
            return .all
        case .photos:
            return LibraryQuery(mediaType: .photo)
        case .videos:
            return LibraryQuery(mediaType: .video)
        case .root(let rootID):
            return LibraryQuery(rootID: rootID)
        case .album(let albumID):
            return LibraryQuery(albumID: albumID)
        case .smartAlbum(let albumID):
            guard let criteria = albums.first(where: { $0.id == albumID && $0.kind == .smartAlbum })?.criteria else {
                return .all
            }
            return LibraryQuery(smartAlbumCriteria: criteria)
        case .stack(let stackID):
            return LibraryQuery(stackID: stackID)
        case .tag(let tagID):
            return LibraryQuery(tagID: tagID)
        }
    }

    func title(
        mediaRoots: [MediaRootRecord],
        albums: [AlbumRecord],
        stacks: [AssetStackRecord],
        tags: [TagRecord]
    ) -> String {
        switch self {
        case .all:
            "所有媒体"
        case .photos:
            "照片"
        case .videos:
            "视频"
        case .root(let rootID):
            mediaRoots.first(where: { $0.id == rootID })?.displayName ?? "资料来源"
        case .album(let albumID), .smartAlbum(let albumID):
            albums.first(where: { $0.id == albumID })?.name ?? "相册"
        case .stack(let stackID):
            stacks.first(where: { $0.id == stackID })?.title ?? "堆栈"
        case .tag(let tagID):
            tags.first(where: { $0.id == tagID })?.name ?? "标签"
        }
    }
}
