import Foundation

struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

struct BookmarkStore: Sendable {
    func createBookmark(for directoryURL: URL) throws -> Data {
        do {
            return try directoryURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw StudioError.bookmarkCreationFailed(path: directoryURL.path(percentEncoded: false))
        }
    }

    func resolve(_ bookmarkData: Data) throws -> ResolvedBookmark {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedBookmark(url: url, isStale: isStale)
        } catch {
            throw StudioError.bookmarkResolutionFailed
        }
    }

    func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
