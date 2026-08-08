import CryptoKit
import CoreGraphics
import Foundation
import ImageIO

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

/// A compact, local 64-bit difference hash. It samples image luminance at
/// 9×8 pixels and records whether each pixel is brighter than its right-hand
/// neighbour. This makes it tolerant of resizing, JPEG recompression and a
/// uniform exposure/colour shift, while deliberately making no semantic claim.
enum PerceptualHash {
    static let algorithm = "dhash-64-v1"
    static let bitCount = 64

    static func digest(of sourceURL: URL) throws -> String {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        return try digest(of: thumbnail)
    }

    static func digest(of image: CGImage) throws -> String {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            throw StudioError.metadataExtractionFailed(path: "Could not rasterize image for local perceptual hashing.")
        }

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let left = luminance(atX: x, y: y, pixels: pixels, width: width)
                let right = luminance(atX: x + 1, y: y, pixels: pixels, width: width)
                let bit = UInt64(y * (width - 1) + x)
                if left >= right {
                    hash |= UInt64(1) << bit
                }
            }
        }
        return String(format: "%016llx", hash)
    }

    static func hammingDistance(_ first: String, _ second: String) -> Int? {
        guard let lhs = UInt64(first, radix: 16), let rhs = UInt64(second, radix: 16) else { return nil }
        return (lhs ^ rhs).nonzeroBitCount
    }

    static func similarityScore(forHammingDistance distance: Int) -> Int {
        let clampedDistance = min(max(distance, 0), bitCount)
        return Int((Double(bitCount - clampedDistance) / Double(bitCount) * 100).rounded())
    }

    private static func luminance(atX x: Int, y: Int, pixels: [UInt8], width: Int) -> Double {
        let offset = (y * width + x) * 4
        return 0.2126 * Double(pixels[offset])
            + 0.7152 * Double(pixels[offset + 1])
            + 0.0722 * Double(pixels[offset + 2])
    }
}

/// Computes and persists local dHash values, then groups photos whose Hamming
/// distance is within the review threshold. It never writes, moves, deletes,
/// uploads or otherwise modifies source media.
actor SimilarPhotoScanner {
    static let maximumHammingDistance = 8

    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore

    init(catalogStore: CatalogStore, mediaRootStore: MediaRootStore) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
    }

    func scan(
        reportProgress: @escaping @Sendable (Double) async -> Void = { _ in }
    ) async throws -> SimilarPhotoScanReport {
        let candidates = try await catalogStore.perceptualHashCandidates()
        guard !candidates.isEmpty else {
            return SimilarPhotoScanReport(candidateCount: 0, hashedCount: 0, reusedHashCount: 0, groups: [], failures: [])
        }

        var cachedRoots: [UUID: ResolvedMediaRoot] = [:]
        var hashedCount = 0
        var reusedHashCount = 0
        var failures: [String] = []

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                if try await catalogStore.perceptualHash(for: candidate) != nil {
                    reusedHashCount += 1
                } else {
                    let root = try await resolvedRoot(
                        for: candidate.rootID,
                        cachedRoots: &cachedRoots
                    )
                    let sourceURL = try sourceURL(for: candidate.relativePath, within: root.directoryURL)
                    let digest = try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: root.directoryURL) {
                        try PerceptualHash.digest(of: sourceURL)
                    }
                    try await catalogStore.savePerceptualHash(digest, for: candidate)
                    hashedCount += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("\(candidate.relativePath)：\(error.localizedDescription)")
            }
            await reportProgress(Double(index + 1) / Double(candidates.count))
        }

        let records = try await catalogStore.currentPerceptualHashes()
        return SimilarPhotoScanReport(
            candidateCount: candidates.count,
            hashedCount: hashedCount,
            reusedHashCount: reusedHashCount,
            groups: SimilarPhotoGrouping.groups(
                from: records,
                maximumHammingDistance: Self.maximumHammingDistance
            ),
            failures: failures
        )
    }

    private func resolvedRoot(
        for rootID: UUID,
        cachedRoots: inout [UUID: ResolvedMediaRoot]
    ) async throws -> ResolvedMediaRoot {
        if let root = cachedRoots[rootID] { return root }
        guard let storedRoot = try await catalogStore.mediaRoot(id: rootID) else {
            throw StudioError.mediaRootNotFound(id: rootID)
        }
        let root = try await mediaRootStore.resolve(storedRoot)
        cachedRoots[rootID] = root
        return root
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
}

private enum SimilarPhotoGrouping {
    static func groups(
        from records: [PerceptualHashRecord],
        maximumHammingDistance: Int
    ) -> [SimilarPhotoGroup] {
        guard records.count > 1 else { return [] }
        let parsedRecords = records.compactMap { record -> (candidate: PerceptualHashCandidate, hash: UInt64)? in
            guard let hash = UInt64(record.digest, radix: 16) else { return nil }
            return (record.candidate, hash)
        }.enumerated().map { index, record in
            ParsedRecord(index: index, candidate: record.candidate, hash: record.hash)
        }
        guard parsedRecords.count > 1 else { return [] }

        var tree = PerceptualHashBKTree()
        var unionFind = UnionFind(count: parsedRecords.count)
        var matches: [SimilarPhotoMatch] = []
        let indexByAssetID = Dictionary(uniqueKeysWithValues: parsedRecords.map { ($0.candidate.id, $0.index) })

        for record in parsedRecords {
            for otherMatch in tree.representatives(within: maximumHammingDistance, of: record.hash) {
                let other = parsedRecords[otherMatch.index]
                let distance = (record.hash ^ otherMatch.hash).nonzeroBitCount
                guard distance <= maximumHammingDistance else { continue }
                matches.append(
                    SimilarPhotoMatch(
                        first: other.candidate,
                        second: record.candidate,
                        hammingDistance: distance,
                        similarityScore: PerceptualHash.similarityScore(forHammingDistance: distance)
                    )
                )
                unionFind.union(other.index, record.index)
            }
            tree.insert(hash: record.hash, index: record.index)
        }

        var assetIndicesByRoot: [Int: [Int]] = [:]
        for record in parsedRecords {
            assetIndicesByRoot[unionFind.find(record.index), default: []].append(record.index)
        }
        var matchesByRoot: [Int: [SimilarPhotoMatch]] = [:]
        for match in matches {
            guard let index = indexByAssetID[match.first.id] else { continue }
            matchesByRoot[unionFind.find(index), default: []].append(match)
        }

        return assetIndicesByRoot.compactMap { root, indices in
            guard indices.count > 1 else { return nil }
            let assets = indices.map { parsedRecords[$0].candidate }
                .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            let componentMatches = (matchesByRoot[root] ?? []).sorted {
                if $0.similarityScore != $1.similarityScore { return $0.similarityScore > $1.similarityScore }
                return $0.id < $1.id
            }
            return SimilarPhotoGroup(assets: assets, matches: componentMatches)
        }
        .sorted {
            if $0.highestSimilarityScore != $1.highestSimilarityScore {
                return $0.highestSimilarityScore > $1.highestSimilarityScore
            }
            return $0.id < $1.id
        }
    }

    private struct ParsedRecord {
        let index: Int
        let candidate: PerceptualHashCandidate
        let hash: UInt64
    }

    private struct UnionFind {
        private var parents: [Int]

        init(count: Int) {
            parents = Array(0..<count)
        }

        mutating func find(_ index: Int) -> Int {
            if parents[index] != index {
                parents[index] = find(parents[index])
            }
            return parents[index]
        }

        mutating func union(_ first: Int, _ second: Int) {
            let firstRoot = find(first)
            let secondRoot = find(second)
            guard firstRoot != secondRoot else { return }
            parents[secondRoot] = firstRoot
        }
    }

    private struct PerceptualHashBKTree {
        private final class Node {
            let hash: UInt64
            var indices: [Int]
            var children: [Int: Node] = [:]

            init(hash: UInt64, index: Int) {
                self.hash = hash
                self.indices = [index]
            }
        }

        private var root: Node?

        mutating func insert(hash: UInt64, index: Int) {
            guard let root else {
                self.root = Node(hash: hash, index: index)
                return
            }
            var node = root
            while true {
                let distance = (hash ^ node.hash).nonzeroBitCount
                if distance == 0 {
                    node.indices.append(index)
                    return
                }
                if let child = node.children[distance] {
                    node = child
                } else {
                    node.children[distance] = Node(hash: hash, index: index)
                    return
                }
            }
        }

        /// Returns one representative per distinct hash. A new item only needs
        /// one edge to connect a same-hash cluster, so returning every prior
        /// identical item would turn a large burst into quadratic work and an
        /// unusable results list.
        func representatives(within radius: Int, of hash: UInt64) -> [(index: Int, hash: UInt64)] {
            guard let root else { return [] }
            var result: [(index: Int, hash: UInt64)] = []
            var pending = [root]
            while let node = pending.popLast() {
                let distance = (hash ^ node.hash).nonzeroBitCount
                if distance <= radius, let index = node.indices.first {
                    result.append((index, node.hash))
                }
                let lower = max(0, distance - radius)
                let upper = min(PerceptualHash.bitCount, distance + radius)
                for (edgeDistance, child) in node.children where (lower...upper).contains(edgeDistance) {
                    pending.append(child)
                }
            }
            return result
        }
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
