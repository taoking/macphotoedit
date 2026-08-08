import Foundation

/// Contains video-specific service composition and media-root access. Public
/// callers receive real AVFoundation payloads and reports; `ApplicationModel`
/// remains responsible only for UI state, dialogs and task orchestration.
@MainActor
final class VideoEditingCoordinator {
    private let mediaRootStore: MediaRootStore
    private let videoEditingService: VideoEditingService
    private let videoProxyService: VideoProxyService

    init(
        catalogStore: CatalogStore,
        mediaRootStore: MediaRootStore,
        lutDirectory: URL,
        videoProxiesDirectory: URL
    ) {
        self.mediaRootStore = mediaRootStore
        self.videoEditingService = VideoEditingService(
            catalogStore: catalogStore,
            mediaRootStore: mediaRootStore,
            lutRepository: LUTRepository(directoryURL: lutDirectory)
        )
        self.videoProxyService = VideoProxyService(
            catalogStore: catalogStore,
            directoryURL: videoProxiesDirectory
        )
    }

    func makePlaybackSession(
        for asset: LibraryAssetRecord,
        root: MediaRootRecord,
        preferProxy: Bool
    ) async throws -> VideoPlaybackSession {
        let source = try await resolveAvailableSource(for: asset, root: root)
        let proxyURL: URL?
        if preferProxy {
            do {
                proxyURL = try await videoProxyService.proxyURL(for: asset)
            } catch {
                AppLogger.app.debug("Proxy unavailable for \(asset.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                proxyURL = nil
            }
        } else {
            proxyURL = nil
        }
        return VideoPlaybackSession(
            sourceURL: source.sourceURL,
            playbackURL: proxyURL,
            securityScopedRootURL: source.rootURL,
            duration: asset.duration,
            frameRate: asset.frameRate
        )
    }

    func resolveAvailableSource(
        for asset: LibraryAssetRecord,
        root: MediaRootRecord
    ) async throws -> VideoSourceAccess {
        let resolvedRoot = try await mediaRootStore.resolve(root)
        guard let sourceURL = safeMediaURL(for: asset, in: resolvedRoot.directoryURL) else {
            throw StudioError.exportFailed(message: "视频路径无效，已拒绝访问资料库根目录外的媒体。")
        }
        let exists = try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolvedRoot.directoryURL) {
            FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false))
        }
        guard exists else {
            throw StudioError.exportFailed(message: "找不到视频原文件：\(asset.filename)")
        }
        return VideoSourceAccess(sourceURL: sourceURL, rootURL: resolvedRoot.directoryURL)
    }

    func editState(for assetID: UUID) async throws -> VideoEditState {
        try await videoEditingService.editState(for: assetID)
    }

    func save(_ state: VideoEditState, for assetID: UUID) async throws {
        try await videoEditingService.save(state, for: assetID)
    }

    func previewPayload(
        sourceURL: URL,
        state: VideoEditState
    ) async throws -> VideoPreviewPayload {
        try await videoEditingService.previewPayload(sourceURL: sourceURL, state: state)
    }

    func lutLibrary() async throws -> LUTLibrary {
        try await videoEditingService.lutLibrary()
    }

    func export(
        asset: LibraryAssetRecord,
        state: VideoEditState,
        destinationURL: URL,
        options: VideoExportOptions,
        allowsOverwrite: Bool,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> VideoExportReport {
        try await videoEditingService.export(
            asset: asset,
            state: state,
            destinationURL: destinationURL,
            options: options,
            allowsOverwrite: allowsOverwrite,
            reportProgress: reportProgress
        )
    }

    func generateProxy(
        for asset: LibraryAssetRecord,
        sourceURL: URL,
        options: VideoProxyOptions,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> VideoProxyReport {
        try await videoProxyService.generate(
            for: asset,
            sourceURL: sourceURL,
            options: options,
            reportProgress: reportProgress
        )
    }

    func removeProxy(for asset: LibraryAssetRecord) async throws {
        try await videoProxyService.removeProxy(for: asset.id)
    }

    private func safeMediaURL(for asset: LibraryAssetRecord, in rootURL: URL) -> URL? {
        let normalizedRoot = rootURL.standardizedFileURL
        let sourceURL = normalizedRoot.appending(path: asset.relativePath).standardizedFileURL
        let rootPath = normalizedRoot.path(percentEncoded: false).hasSuffix("/")
            ? normalizedRoot.path(percentEncoded: false)
            : normalizedRoot.path(percentEncoded: false) + "/"
        guard sourceURL.path(percentEncoded: false).hasPrefix(rootPath) else { return nil }
        return sourceURL
    }
}

struct VideoSourceAccess: Sendable, Equatable {
    let sourceURL: URL
    let rootURL: URL
}
