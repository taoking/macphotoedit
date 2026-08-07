import CryptoKit
import Foundation

/// Calculates exact duplicate groups without reading any source file until it
/// has first been placed in a same-size candidate group by the catalog.
actor ExactDuplicateScanner {
    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore

    init(catalogStore: CatalogStore, mediaRootStore: MediaRootStore) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
    }

    func scan(
        reportProgress: @escaping @Sendable (Double) async -> Void = { _ in }
    ) async throws -> DuplicateScanReport {
        let candidates = try await catalogStore.duplicateHashCandidates()
        guard !candidates.isEmpty else {
            return DuplicateScanReport(candidateCount: 0, hashedCount: 0, reusedHashCount: 0, groups: [], failures: [])
        }

        var cachedRoots: [UUID: ResolvedMediaRoot] = [:]
        var hashedCount = 0
        var reusedHashCount = 0
        var failures: [String] = []

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                if try await catalogStore.contentHash(for: candidate) != nil {
                    reusedHashCount += 1
                } else {
                    let root: ResolvedMediaRoot
                    if let cachedRoot = cachedRoots[candidate.rootID] {
                        root = cachedRoot
                    } else {
                        guard let storedRoot = try await catalogStore.mediaRoot(id: candidate.rootID) else {
                            throw StudioError.mediaRootNotFound(id: candidate.rootID)
                        }
                        let resolvedRoot = try await mediaRootStore.resolve(storedRoot)
                        cachedRoots[candidate.rootID] = resolvedRoot
                        root = resolvedRoot
                    }
                    let sourceURL = try sourceURL(for: candidate.relativePath, within: root.directoryURL)
                    let digest = try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: root.directoryURL) {
                        try ExactDuplicateScanner.sha256(of: sourceURL)
                    }
                    try await catalogStore.saveContentHash(digest, for: candidate)
                    hashedCount += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(candidate.relativePath)：\(error.localizedDescription)")
            }
            await reportProgress(Double(index + 1) / Double(candidates.count))
        }

        return DuplicateScanReport(
            candidateCount: candidates.count,
            hashedCount: hashedCount,
            reusedHashCount: reusedHashCount,
            groups: try await catalogStore.exactDuplicateGroups(),
            failures: failures
        )
    }

    private func sourceURL(for relativePath: String, within rootURL: URL) throws -> URL {
        let standardizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let sourceURL = rootURL.appending(path: relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = standardizedRoot.path(percentEncoded: false)
        let sourcePath = sourceURL.path(percentEncoded: false)
        guard sourcePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw StudioError.databaseExecutionFailed(message: "Catalog asset path escaped its media root.")
        }
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw StudioError.directoryEnumerationFailed(path: sourcePath)
        }
        return sourceURL
    }

    nonisolated private static func sha256(of sourceURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !chunk.isEmpty else { break }
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Moves explicitly selected media files to the macOS Trash. Catalog records
/// are retained and marked missing so tags, ratings and edits can be recovered
/// if the user restores a source file or relinks its media root later.
actor MediaTrashService {
    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore

    init(catalogStore: CatalogStore, mediaRootStore: MediaRootStore) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
    }

    func moveToTrash(_ assets: [LibraryAssetRecord]) async throws -> TrashMoveReport {
        let uniqueAssets = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        var cachedRoots: [UUID: ResolvedMediaRoot] = [:]
        var movedAssetIDs: [UUID] = []
        var failures: [String] = []

        for asset in uniqueAssets {
            try Task.checkCancellation()
            do {
                let root: ResolvedMediaRoot
                if let cachedRoot = cachedRoots[asset.rootID] {
                    root = cachedRoot
                } else {
                    guard let storedRoot = try await catalogStore.mediaRoot(id: asset.rootID) else {
                        throw StudioError.mediaRootNotFound(id: asset.rootID)
                    }
                    let resolvedRoot = try await mediaRootStore.resolve(storedRoot)
                    cachedRoots[asset.rootID] = resolvedRoot
                    root = resolvedRoot
                }
                let sourceURL = try sourceURL(for: asset.relativePath, within: root.directoryURL)
                try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: root.directoryURL) {
                    try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
                }
                movedAssetIDs.append(asset.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(asset.relativePath)：\(error.localizedDescription)")
            }
        }

        if !movedAssetIDs.isEmpty {
            do {
                try await catalogStore.markAssetsMissing(movedAssetIDs)
            } catch {
                failures.append("已移入废纸篓的项目无法更新 Catalog：\(error.localizedDescription)")
            }
        }
        return TrashMoveReport(movedAssetIDs: movedAssetIDs, failures: failures)
    }

    private func sourceURL(for relativePath: String, within rootURL: URL) throws -> URL {
        let standardizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let sourceURL = rootURL.appending(path: relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = standardizedRoot.path(percentEncoded: false)
        let sourcePath = sourceURL.path(percentEncoded: false)
        guard sourcePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw StudioError.databaseExecutionFailed(message: "Catalog asset path escaped its media root.")
        }
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw StudioError.databaseExecutionFailed(message: "Only a catalogued media file can be moved to Trash.")
        }
        return sourceURL
    }
}
