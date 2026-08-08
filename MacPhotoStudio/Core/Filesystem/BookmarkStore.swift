import Foundation

struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

struct SecurityScopedAccessResult<Value: Sendable>: Sendable {
    let didStartAccess: Bool
    let value: Value
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

    func withSecurityScopedAccess<T: Sendable>(
        to url: URL,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await withSecurityScopedAccessResult(to: url, operation: operation).value
    }

    /// Keeps the start/stop lifecycle balanced while making the result visible
    /// to diagnostics. `false` is valid for an already-accessible local URL,
    /// so callers must combine it with an actual directory read rather than
    /// treating it as a permission failure on its own.
    func withSecurityScopedAccessResult<T: Sendable>(
        to url: URL,
        operation: @Sendable () async throws -> T
    ) async throws -> SecurityScopedAccessResult<T> {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return SecurityScopedAccessResult(
            didStartAccess: didStartAccess,
            value: try await operation()
        )
    }
}
