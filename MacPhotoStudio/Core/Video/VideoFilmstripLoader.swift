import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct VideoFilmstripStore {
    let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func data(for assetID: UUID, cacheVersion: String = "0", frameCount: Int) throws -> [Data]? {
        let frameURLs = (0..<frameCount).map { frameURL(for: assetID, cacheVersion: cacheVersion, index: $0) }
        guard frameURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }) else {
            return nil
        }
        return try frameURLs.map { try Data(contentsOf: $0) }
    }

    func store(_ frames: [Data], for assetID: UUID, cacheVersion: String = "0") throws {
        guard !frames.isEmpty else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for (index, frame) in frames.enumerated() {
            try frame.write(to: frameURL(for: assetID, cacheVersion: cacheVersion, index: index), options: .atomic)
        }
    }

    private func frameURL(for assetID: UUID, cacheVersion: String, index: Int) -> URL {
        directoryURL.appending(path: "\(assetID.uuidString.lowercased())-\(cacheVersion)-\(index).jpg")
    }
}

actor VideoFilmstripLoader {
    static let frameCount = 5

    private let diskStore: VideoFilmstripStore
    private let mediaRootStore: MediaRootStore

    init(diskStore: VideoFilmstripStore, mediaRootStore: MediaRootStore) {
        self.diskStore = diskStore
        self.mediaRootStore = mediaRootStore
    }

    func filmstripData(for asset: LibraryAssetRecord, root: MediaRootRecord) async throws -> [Data]? {
        guard asset.mediaType == .video else { return nil }
        let cacheVersion = "\(asset.fileSize)-\(Int64((asset.modifiedAt?.timeIntervalSince1970 ?? 0) * 1_000))"
        if let cached = try diskStore.data(for: asset.id, cacheVersion: cacheVersion, frameCount: Self.frameCount) {
            return cached
        }
        guard asset.availability == .available else { return nil }

        let resolvedRoot = try await mediaRootStore.resolve(root)
        let sourceURL = resolvedRoot.directoryURL.appending(path: asset.relativePath)
        let frames: [Data] = try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolvedRoot.directoryURL) {
            guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else { return [] }
            try Task.checkCancellation()
            return try await VideoFilmstripRenderer.render(sourceURL: sourceURL, frameCount: Self.frameCount)
        }
        try Task.checkCancellation()
        guard !frames.isEmpty else { return nil }
        try diskStore.store(frames, for: asset.id, cacheVersion: cacheVersion)
        return frames
    }
}

enum VideoFilmstripRenderer {
    static func samplePositions(duration: Double, frameCount: Int) -> [Double] {
        let count = max(1, frameCount)
        guard duration.isFinite, duration > 0, count > 1 else { return [0] }
        return (0..<count).map { Double($0) * duration / Double(count - 1) }
    }

    static func render(sourceURL: URL, frameCount: Int, maximumPixelSize: Int = 240) async throws -> [Data] {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.isNumeric ? CMTimeGetSeconds(duration) : 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixelSize, height: maximumPixelSize)

        var frames: [Data] = []
        for seconds in samplePositions(duration: durationSeconds, frameCount: frameCount) {
            try Task.checkCancellation()
            let safeSeconds = min(seconds, max(0, durationSeconds - 1.0 / 600.0))
            do {
                let time = CMTime(seconds: safeSeconds, preferredTimescale: 600)
                let (image, _) = try await generator.image(at: time)
                if let jpeg = try jpegData(for: image) {
                    frames.append(jpeg)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return frames
    }

    private static func jpegData(for image: CGImage) throws -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
