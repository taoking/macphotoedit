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
}
