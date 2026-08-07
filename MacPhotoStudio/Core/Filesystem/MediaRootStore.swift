import Foundation

struct MediaRoot: Identifiable, Sendable, Equatable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data
    let createdAt: Date
}

/// Owns the stable identity and security-scoped bookmark representation of a referenced root.
/// Catalog persistence is added with the indexing workflow in Phase 1.
struct MediaRootStore: Sendable {
    let bookmarkStore: BookmarkStore

    init(bookmarkStore: BookmarkStore = BookmarkStore()) {
        self.bookmarkStore = bookmarkStore
    }

    func makeRoot(for directoryURL: URL, id: UUID = UUID(), createdAt: Date = .now) throws -> MediaRoot {
        let bookmarkData = try bookmarkStore.createBookmark(for: directoryURL)
        let displayName = directoryURL.lastPathComponent.isEmpty ? directoryURL.path(percentEncoded: false) : directoryURL.lastPathComponent
        return MediaRoot(id: id, displayName: displayName, bookmarkData: bookmarkData, createdAt: createdAt)
    }
}
