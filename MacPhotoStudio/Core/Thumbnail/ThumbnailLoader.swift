import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ThumbnailLoader {
    private let diskStore: ThumbnailStore
    private let mediaRootStore: MediaRootStore
    private let memoryByteLimit: Int
    private var memoryCache: [String: Data] = [:]
    private var memoryOrder: [String] = []
    private var memoryCost = 0

    init(
        diskStore: ThumbnailStore,
        mediaRootStore: MediaRootStore,
        memoryByteLimit: Int = 64 * 1024 * 1024
    ) {
        self.diskStore = diskStore
        self.mediaRootStore = mediaRootStore
        self.memoryByteLimit = max(memoryByteLimit, 1)
    }

    func thumbnailData(
        for asset: LibraryAssetRecord,
        root: MediaRootRecord,
        maximumPixelSize: Int
    ) async throws -> Data? {
        let pixelSize = normalizedPixelSize(maximumPixelSize)
        let key = cacheKey(assetID: asset.id, maximumPixelSize: pixelSize)
        if let cached = memoryCache[key] {
            touch(key)
            return cached
        }

        if let diskData = try diskStore.data(for: asset.id, maximumPixelSize: pixelSize) {
            insert(diskData, for: key)
            return diskData
        }

        guard asset.availability == .available else { return nil }
        try Task.checkCancellation()
        let resolvedRoot = try await mediaRootStore.resolve(root)
        let sourceURL = resolvedRoot.directoryURL.appending(path: asset.relativePath)
        let generatedData: Data? = try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolvedRoot.directoryURL) {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else { return nil }
            return try await ThumbnailRenderer.render(
                sourceURL: sourceURL,
                mediaType: asset.mediaType,
                maximumPixelSize: pixelSize
            )
        }
        try Task.checkCancellation()
        guard let generatedData else { return nil }
        try diskStore.store(generatedData, for: asset.id, maximumPixelSize: pixelSize)
        insert(generatedData, for: key)
        return generatedData
    }

    func removeCachedThumbnail(for assetID: UUID, maximumPixelSize: Int) throws {
        let pixelSize = normalizedPixelSize(maximumPixelSize)
        let key = cacheKey(assetID: assetID, maximumPixelSize: pixelSize)
        if let data = memoryCache.removeValue(forKey: key) {
            memoryCost -= data.count
        }
        memoryOrder.removeAll { $0 == key }
        try diskStore.remove(for: assetID, maximumPixelSize: pixelSize)
    }

    private func normalizedPixelSize(_ requested: Int) -> Int {
        requested <= 256 ? 256 : 512
    }

    private func cacheKey(assetID: UUID, maximumPixelSize: Int) -> String {
        "\(assetID.uuidString.lowercased())-\(maximumPixelSize)"
    }

    private func touch(_ key: String) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }

    private func insert(_ data: Data, for key: String) {
        if let oldData = memoryCache.updateValue(data, forKey: key) {
            memoryCost -= oldData.count
        }
        memoryCost += data.count
        touch(key)

        while memoryCost > memoryByteLimit, let oldestKey = memoryOrder.first {
            memoryOrder.removeFirst()
            if let evicted = memoryCache.removeValue(forKey: oldestKey) {
                memoryCost -= evicted.count
            }
        }
    }
}

enum ThumbnailRenderer {
    static func render(
        sourceURL: URL,
        mediaType: MediaType,
        maximumPixelSize: Int
    ) async throws -> Data? {
        let image: CGImage?
        switch mediaType {
        case .photo:
            image = photoImage(sourceURL: sourceURL, maximumPixelSize: maximumPixelSize)
        case .video:
            image = try await videoImage(sourceURL: sourceURL, maximumPixelSize: maximumPixelSize)
        }
        guard let image else { return nil }
        return try jpegData(for: image)
    }

    private static func photoImage(sourceURL: URL, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func videoImage(sourceURL: URL, maximumPixelSize: Int) async throws -> CGImage? {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixelSize, height: maximumPixelSize)
        let (image, _) = try await generator.image(at: .zero)
        return image
    }

    private static func jpegData(for image: CGImage) throws -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
