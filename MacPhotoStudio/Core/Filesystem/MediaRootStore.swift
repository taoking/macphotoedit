import Foundation

struct ResolvedMediaRoot: Sendable {
    var root: MediaRootRecord
    let directoryURL: URL
    let bookmarkWasStale: Bool
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

    /// Replaces only the security-scoped root mapping. Existing media asset
    /// records keep their root ID, so a subsequent scan can match unchanged
    /// relative paths and preserve catalog-only organization and edits.
    func relink(_ root: MediaRootRecord, to directoryURL: URL) async throws -> MediaRootRecord {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .volumeUUIDStringKey])
        guard values.isDirectory == true else {
            throw StudioError.invalidMediaRoot(path: directoryURL.path(percentEncoded: false))
        }
        let bookmarkData = try bookmarkStore.createBookmark(for: directoryURL)
        var updatedRoot = root
        updatedRoot.displayName = directoryURL.lastPathComponent.isEmpty
            ? directoryURL.path(percentEncoded: false)
            : directoryURL.lastPathComponent
        updatedRoot.bookmarkData = bookmarkData
        updatedRoot.lastKnownPath = directoryURL.path(percentEncoded: false)
        updatedRoot.volumeIdentifier = values.volumeUUIDString
        updatedRoot.availability = .online
        updatedRoot.lastScanError = nil
        try await catalogStore.saveMediaRoot(updatedRoot)
        return updatedRoot
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

        return ResolvedMediaRoot(
            root: updatedRoot,
            directoryURL: resolvedBookmark.url,
            bookmarkWasStale: resolvedBookmark.isStale
        )
    }

    func validateAccess(to root: MediaRootRecord) async -> MediaRootAvailability {
        await diagnoseAccess(to: root).availability
    }

    /// Resolves a bookmark and performs a real directory read under a balanced
    /// security-scoped access session. A missing last-known path is offline;
    /// an unresolved bookmark for an existing path is permission-required.
    /// Neither case deletes catalog assets or derived thumbnails.
    func diagnoseAccess(to root: MediaRootRecord) async -> MediaRootAvailabilityDiagnostic {
        do {
            let resolved = try await resolve(root)
            let accessResult = try await bookmarkStore.withSecurityScopedAccessResult(to: resolved.directoryURL) {
                resourceSnapshot(for: resolved.directoryURL)
            }
            let snapshot = accessResult.value
            let availability: MediaRootAvailability = snapshot.directoryExists && snapshot.isDirectory ? .online : .offline
            let errorMessage = availability == .offline ? "目录或卷当前不可用。" : nil
            try? await catalogStore.updateRootAvailability(
                availability,
                errorMessage: errorMessage,
                rootID: root.id
            )
            return MediaRootAvailabilityDiagnostic(
                rootID: root.id,
                displayName: root.displayName,
                lastKnownPath: root.lastKnownPath,
                resolvedPath: resolved.directoryURL.path(percentEncoded: false),
                bookmarkResolved: true,
                bookmarkWasStale: resolved.bookmarkWasStale,
                bookmarkResolutionError: nil,
                securityScopedAccessStarted: accessResult.didStartAccess,
                resourceSnapshot: snapshot,
                volumeIdentifierMatchesStoredValue: matchesStoredVolume(
                    stored: resolved.root.volumeIdentifier,
                    observed: snapshot.volumeIdentifier
                ),
                availability: availability,
                errorMessage: errorMessage
            )
        } catch {
            let snapshot = resourceSnapshot(for: URL(filePath: root.lastKnownPath, directoryHint: .isDirectory))
            let availability: MediaRootAvailability = snapshot.directoryExists && snapshot.isDirectory
                ? .permissionRequired
                : .offline
            let errorMessage = "书签无法解析：\(error.localizedDescription)"
            try? await catalogStore.updateRootAvailability(
                availability,
                errorMessage: errorMessage,
                rootID: root.id
            )
            return MediaRootAvailabilityDiagnostic(
                rootID: root.id,
                displayName: root.displayName,
                lastKnownPath: root.lastKnownPath,
                resolvedPath: nil,
                bookmarkResolved: false,
                bookmarkWasStale: nil,
                bookmarkResolutionError: error.localizedDescription,
                securityScopedAccessStarted: nil,
                resourceSnapshot: snapshot,
                volumeIdentifierMatchesStoredValue: nil,
                availability: availability,
                errorMessage: errorMessage
            )
        }
    }

    private func resourceSnapshot(for directoryURL: URL) -> MediaRootResourceSnapshot {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: directoryURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        let values = try? directoryURL.resourceValues(forKeys: [
            .isReadableKey,
            .isWritableKey,
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeIsLocalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ])
        return MediaRootResourceSnapshot(
            directoryExists: exists,
            isDirectory: isDirectory.boolValue,
            isReadable: values?.isReadable,
            isWritable: values?.isWritable,
            volumeName: values?.volumeName,
            volumeIdentifier: values?.volumeUUIDString,
            volumeIsLocal: values?.volumeIsLocal,
            volumeIsRemovable: values?.volumeIsRemovable,
            volumeIsEjectable: values?.volumeIsEjectable
        )
    }

    private func matchesStoredVolume(stored: String?, observed: String?) -> Bool? {
        guard let stored, let observed else { return nil }
        return stored == observed
    }
}
