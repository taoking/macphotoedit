@preconcurrency import AVFoundation
import Foundation

struct VideoProxyOptions: Sendable, Equatable {
    var maximumPixelSize: Int = 1_280

    var clampedMaximumPixelSize: Int { min(max(maximumPixelSize, 480), 1_920) }
}

struct VideoProxyReport: Sendable, Equatable {
    let assetID: UUID
    let proxyURL: URL
    let width: Int?
    let height: Int?
}

actor VideoProxyService {
    private let catalogStore: CatalogStore
    private let directoryURL: URL
    private let exportService = VideoExportService()

    init(catalogStore: CatalogStore, directoryURL: URL) {
        self.catalogStore = catalogStore
        self.directoryURL = directoryURL.standardizedFileURL
    }

    func proxyURL(for asset: LibraryAssetRecord) async throws -> URL? {
        guard asset.mediaType == .video, asset.videoIsHDR != true,
              let record = try await catalogStore.videoProxy(for: asset.id),
              record.sourceFileSize == asset.fileSize,
              datesMatch(record.sourceModifiedAt, asset.modifiedAt)
        else { return nil }
        let url = directoryURL.appending(path: record.relativePath).standardizedFileURL
        guard isInsideProxyDirectory(url),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return url
    }

    func generate(
        for asset: LibraryAssetRecord,
        sourceURL: URL,
        options: VideoProxyOptions = .init(),
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> VideoProxyReport {
        guard asset.mediaType == .video else {
            throw StudioError.exportFailed(message: "只能为视频生成 Proxy。")
        }
        guard asset.videoIsHDR != true else {
            throw StudioError.exportFailed(message: "HDR 视频 Proxy 需要保留 HDR 色彩契约，将在后续 HDR 视频路径中实现。")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            throw StudioError.exportFailed(message: "找不到需要生成 Proxy 的原始视频。")
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let relativePath = proxyFilename(for: asset)
        let destinationURL = directoryURL.appending(path: relativePath).standardizedFileURL
        guard isInsideProxyDirectory(destinationURL) else {
            throw StudioError.exportFailed(message: "Proxy 输出路径无效。")
        }
        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        let state = VideoEditState.identity
        _ = try await exportService.export(
            sourceURL: sourceURL,
            state: state,
            lut: nil,
            destinationURL: destinationURL,
            options: VideoExportOptions(
                format: .h264,
                quality: .medium,
                resize: .maximum(options.clampedMaximumPixelSize),
                namingRule: .originalName,
                collisionPolicy: .rename
            ),
            allowsOverwrite: false,
            reportProgress: reportProgress
        )

        let proxyAsset = AVURLAsset(url: destinationURL)
        let tracks = try await proxyAsset.loadTracks(withMediaType: .video)
        let track = tracks.first
        let naturalSize = try await track?.load(.naturalSize)
        let now = Date.now
        let record = VideoProxyRecord(
            assetID: asset.id,
            sourceFileSize: asset.fileSize,
            sourceModifiedAt: asset.modifiedAt,
            relativePath: relativePath,
            width: naturalSize.map { Int($0.width.rounded()) },
            height: naturalSize.map { Int($0.height.rounded()) },
            createdAt: now,
            updatedAt: now
        )
        try await catalogStore.saveVideoProxy(record)
        return VideoProxyReport(assetID: asset.id, proxyURL: destinationURL, width: record.width, height: record.height)
    }

    func removeProxy(for assetID: UUID) async throws {
        if let record = try await catalogStore.videoProxy(for: assetID) {
            let url = directoryURL.appending(path: record.relativePath).standardizedFileURL
            if isInsideProxyDirectory(url), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
        }
        try await catalogStore.deleteVideoProxy(for: assetID)
    }

    private func proxyFilename(for asset: LibraryAssetRecord) -> String {
        let modified = Int64((asset.modifiedAt?.timeIntervalSince1970 ?? 0).rounded())
        return "\(asset.id.uuidString)-\(asset.fileSize)-\(modified).mp4"
    }

    private func isInsideProxyDirectory(_ url: URL) -> Bool {
        let root = directoryURL.path(percentEncoded: false).hasSuffix("/")
            ? directoryURL.path(percentEncoded: false)
            : directoryURL.path(percentEncoded: false) + "/"
        return url.path(percentEncoded: false).hasPrefix(root)
    }

    private func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (.some(lhs), .some(rhs)): abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.001
        default: false
        }
    }
}
