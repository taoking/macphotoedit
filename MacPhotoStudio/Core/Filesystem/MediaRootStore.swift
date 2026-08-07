import Foundation

struct ResolvedMediaRoot: Sendable {
    var root: MediaRootRecord
    let directoryURL: URL
}

struct MediaRootStore: Sendable {
    let catalogStore: CatalogStore
    let bookmarkStore: BookmarkStore

    init(catalogStore: CatalogStore, bookmarkStore: BookmarkStore = BookmarkStore()) {
        self.catalogStore = catalogStore
        self.bookmarkStore = bookmarkStore
    }

    func add(directoryURL: URL, now: Date = .now) async throws -> MediaRootRecord {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .volumeUUIDStringKey])
        guard values.isDirectory == true else {
            throw StudioError.invalidMediaRoot(path: directoryURL.path(percentEncoded: false))
        }

        let bookmarkData = try bookmarkStore.createBookmark(for: directoryURL)
        let displayName = directoryURL.lastPathComponent.isEmpty
            ? directoryURL.path(percentEncoded: false)
            : directoryURL.lastPathComponent
        let root = MediaRootRecord(
            id: UUID(),
            displayName: displayName,
            bookmarkData: bookmarkData,
            lastKnownPath: directoryURL.path(percentEncoded: false),
            volumeIdentifier: values.volumeUUIDString,
            availability: .online,
            createdAt: now,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await catalogStore.saveMediaRoot(root)
        return root
    }

    func resolve(_ root: MediaRootRecord) async throws -> ResolvedMediaRoot {
        let resolvedBookmark = try bookmarkStore.resolve(root.bookmarkData)
        var updatedRoot = root

        if resolvedBookmark.isStale {
            let refreshedBookmark = try bookmarkStore.createBookmark(for: resolvedBookmark.url)
            let values = try? resolvedBookmark.url.resourceValues(forKeys: [.volumeUUIDStringKey])
            updatedRoot.bookmarkData = refreshedBookmark
            updatedRoot.lastKnownPath = resolvedBookmark.url.path(percentEncoded: false)
            updatedRoot.volumeIdentifier = values?.volumeUUIDString
            try await catalogStore.updateBookmark(
                refreshedBookmark,
                lastKnownPath: updatedRoot.lastKnownPath,
                volumeIdentifier: updatedRoot.volumeIdentifier,
                for: root.id
            )
        }

        return ResolvedMediaRoot(root: updatedRoot, directoryURL: resolvedBookmark.url)
    }

    func validateAccess(to root: MediaRootRecord) async -> MediaRootAvailability {
        do {
            let resolved = try await resolve(root)
            let isAccessible = try await bookmarkStore.withSecurityScopedAccess(to: resolved.directoryURL) {
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: resolved.directoryURL.path(percentEncoded: false),
                    isDirectory: &isDirectory
                )
                return exists && isDirectory.boolValue
            }
            let availability: MediaRootAvailability = isAccessible ? .online : .offline
            try? await catalogStore.updateRootAvailability(availability, rootID: root.id)
            return availability
        } catch {
            try? await catalogStore.updateRootAvailability(
                .permissionRequired,
                errorMessage: error.localizedDescription,
                rootID: root.id
            )
            return .permissionRequired
        }
    }
}
