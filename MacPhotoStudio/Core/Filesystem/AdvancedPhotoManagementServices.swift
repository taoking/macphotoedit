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
        reportProgress: @escaping @Sendable (Double) async -> Void = { _ in },
        checkpoint: @escaping @Sendable (SimilarPhotoScanCheckpoint, Int) async throws -> Void = { _, _ in }
    ) async throws -> SimilarPhotoScanReport {
        let scanStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        var observedPeakMemory = SimilarPhotoPerformanceInstrumentation.residentMemoryBytes()
        let candidateFetchStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        let candidates = try await catalogStore.perceptualHashCandidates()
        let candidateFetchDuration = SimilarPhotoPerformanceInstrumentation.now() - candidateFetchStartedAt
        SimilarPhotoPerformanceInstrumentation.observePeak(&observedPeakMemory)
        guard !candidates.isEmpty else {
            return SimilarPhotoScanReport(
                candidateCount: 0,
                hashedCount: 0,
                reusedHashCount: 0,
                groups: [],
                failures: [],
                metrics: SimilarPhotoScanMetrics(
                    candidateFetchDuration: candidateFetchDuration,
                    imageIODecodeDuration: 0,
                    groupingDuration: 0,
                    totalScanDuration: SimilarPhotoPerformanceInstrumentation.now() - scanStartedAt,
                    imageIODecodeCount: 0,
                    groupCount: 0,
                    failureCount: 0,
                    observedPeakResidentMemoryBytes: observedPeakMemory
                )
            )
        }

        var cachedRoots: [UUID: ResolvedMediaRoot] = [:]
        var hashedCount = 0
        var reusedHashCount = 0
        var failures: [String] = []
        var imageIODecodeDuration: TimeInterval = 0
        var imageIODecodeCount = 0

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                if try await catalogStore.perceptualHash(for: candidate) != nil {
                    reusedHashCount += 1
                } else {
                    let root = try await resolvedRoot(
                        for: candidate.rootID,
                        cachedRoots: &cachedRoots,
                        candidateIndex: index + 1,
                        checkpoint: checkpoint
                    )
                    let sourceURL = try sourceURL(for: candidate.relativePath, within: root.directoryURL)
                    try Task.checkCancellation()
                    try await checkpoint(.hashing, index + 1)
                    let decodeStartedAt = SimilarPhotoPerformanceInstrumentation.now()
                    let digest: String
                    do {
                        digest = try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: root.directoryURL) {
                            try PerceptualHash.digest(of: sourceURL)
                        }
                    } catch {
                        imageIODecodeDuration += SimilarPhotoPerformanceInstrumentation.now() - decodeStartedAt
                        imageIODecodeCount += 1
                        throw error
                    }
                    imageIODecodeDuration += SimilarPhotoPerformanceInstrumentation.now() - decodeStartedAt
                    imageIODecodeCount += 1
                    SimilarPhotoPerformanceInstrumentation.observePeak(&observedPeakMemory)
                    try Task.checkCancellation()
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
        let groupingStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        let groups = try await SimilarPhotoGrouping.groups(
            from: records,
            maximumHammingDistance: Self.maximumHammingDistance,
            checkpoint: checkpoint
        )
        let groupingDuration = SimilarPhotoPerformanceInstrumentation.now() - groupingStartedAt
        SimilarPhotoPerformanceInstrumentation.observePeak(&observedPeakMemory)
        return SimilarPhotoScanReport(
            candidateCount: candidates.count,
            hashedCount: hashedCount,
            reusedHashCount: reusedHashCount,
            groups: groups,
            failures: failures,
            metrics: SimilarPhotoScanMetrics(
                candidateFetchDuration: candidateFetchDuration,
                imageIODecodeDuration: imageIODecodeDuration,
                groupingDuration: groupingDuration,
                totalScanDuration: SimilarPhotoPerformanceInstrumentation.now() - scanStartedAt,
                imageIODecodeCount: imageIODecodeCount,
                groupCount: groups.count,
                failureCount: failures.count,
                observedPeakResidentMemoryBytes: observedPeakMemory
            ),
        )
    }

    private func resolvedRoot(
        for rootID: UUID,
        cachedRoots: inout [UUID: ResolvedMediaRoot],
        candidateIndex: Int,
        checkpoint: @escaping @Sendable (SimilarPhotoScanCheckpoint, Int) async throws -> Void
    ) async throws -> ResolvedMediaRoot {
        if let root = cachedRoots[rootID] { return root }
        try Task.checkCancellation()
        try await checkpoint(.rootResolution, candidateIndex)
        guard let storedRoot = try await catalogStore.mediaRoot(id: rootID) else {
            throw StudioError.mediaRootNotFound(id: rootID)
        }
        let root = try await mediaRootStore.resolve(storedRoot)
        try Task.checkCancellation()
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

enum SimilarPhotoGrouping {
    static func groups(
        from records: [PerceptualHashRecord],
        maximumHammingDistance: Int,
        checkpoint: @escaping @Sendable (SimilarPhotoScanCheckpoint, Int) async throws -> Void = { _, _ in }
    ) async throws -> [SimilarPhotoGroup] {
        guard records.count > 1 else { return [] }
        let parsedRecords = records.compactMap { record -> (candidate: PerceptualHashCandidate, hash: UInt64)? in
            guard let hash = UInt64(record.digest, radix: 16) else { return nil }
            return (record.candidate, hash)
        }.enumerated().map { index, record in
            ParsedRecord(index: index, candidate: record.candidate, hash: record.hash)
        }
        guard parsedRecords.count > 1 else { return [] }

        let usesLargeLibraryIndex = parsedRecords.count >= 25_000 && maximumHammingDistance <= 8
        let clustering = if usesLargeLibraryIndex {
            try await clusterUsingHammingIndex(
                parsedRecords,
                maximumHammingDistance: maximumHammingDistance,
                checkpoint: checkpoint
            )
        } else {
            try await clusterUsingBKTree(
                parsedRecords,
                maximumHammingDistance: maximumHammingDistance,
                checkpoint: checkpoint
            )
        }

        return makeGroups(
            from: parsedRecords,
            unionFind: clustering.unionFind,
            matches: clustering.matches
        )
    }

    /// BK-trees remain the small-library path.  They offer a compact and
    /// understandable local dHash search when the catalog is below the scale
    /// at which the tree's random-hash traversal becomes pathological.
    private static func clusterUsingBKTree(
        _ parsedRecords: [ParsedRecord],
        maximumHammingDistance: Int,
        checkpoint: @escaping @Sendable (SimilarPhotoScanCheckpoint, Int) async throws -> Void
    ) async throws -> ClusteringResult {
        var tree = PerceptualHashBKTree()
        var unionFind = UnionFind(count: parsedRecords.count)
        var matches: [SimilarPhotoMatch] = []
        var firstIndexByHash: [UInt64: Int] = [:]

        for (recordOffset, record) in parsedRecords.enumerated() {
            try await performGroupingCheckpoint(at: recordOffset, checkpoint: checkpoint)
            if let otherIndex = firstIndexByHash[record.hash] {
                appendMatch(
                    first: parsedRecords[otherIndex],
                    second: record,
                    maximumHammingDistance: maximumHammingDistance,
                    matches: &matches,
                    unionFind: &unionFind
                )
                continue
            }
            for otherMatch in tree.representatives(within: maximumHammingDistance, of: record.hash) {
                appendMatch(
                    first: parsedRecords[otherMatch.index],
                    second: record,
                    maximumHammingDistance: maximumHammingDistance,
                    matches: &matches,
                    unionFind: &unionFind
                )
            }
            tree.insert(hash: record.hash, index: record.index)
            firstIndexByHash[record.hash] = record.index
        }
        return ClusteringResult(unionFind: unionFind, matches: matches)
    }

    /// For large catalogs this exact index is used after profiling showed a
    /// random dHash BK-tree traversal consuming nearly all grouping CPU.  It
    /// splits a 64-bit hash into four 16-bit blocks.  If two hashes differ by
    /// at most eight bits, at least one block differs by at most two bits;
    /// querying every 0...2-bit variant of each block therefore has no false
    /// negatives, and every returned candidate is still distance-checked.
    private static func clusterUsingHammingIndex(
        _ parsedRecords: [ParsedRecord],
        maximumHammingDistance: Int,
        checkpoint: @escaping @Sendable (SimilarPhotoScanCheckpoint, Int) async throws -> Void
    ) async throws -> ClusteringResult {
        var index = PerceptualHashHammingIndex(recordCapacity: parsedRecords.count)
        var unionFind = UnionFind(count: parsedRecords.count)
        var matches: [SimilarPhotoMatch] = []
        var firstIndexByHash: [UInt64: Int] = [:]

        for (recordOffset, record) in parsedRecords.enumerated() {
            try await performGroupingCheckpoint(at: recordOffset, checkpoint: checkpoint)
            if let otherIndex = firstIndexByHash[record.hash] {
                appendMatch(
                    first: parsedRecords[otherIndex],
                    second: record,
                    maximumHammingDistance: maximumHammingDistance,
                    matches: &matches,
                    unionFind: &unionFind
                )
                continue
            }
            for otherIndex in index.candidates(withinTwoBitsPerBlockOf: record.hash, visitToken: recordOffset) {
                appendMatch(
                    first: parsedRecords[otherIndex],
                    second: record,
                    maximumHammingDistance: maximumHammingDistance,
                    matches: &matches,
                    unionFind: &unionFind
                )
            }
            index.insert(hash: record.hash, index: record.index)
            firstIndexByHash[record.hash] = record.index
        }
        return ClusteringResult(unionFind: unionFind, matches: matches)
    }

    private static func performGroupingCheckpoint(
        at recordOffset: Int,
        checkpoint: @escaping @Sendable (SimilarPhotoScanCheckpoint, Int) async throws -> Void
    ) async throws {
        if recordOffset.isMultiple(of: 128) {
            try Task.checkCancellation()
            try await checkpoint(.grouping, recordOffset)
            await Task.yield()
        }
    }

    private static func appendMatch(
        first: ParsedRecord,
        second: ParsedRecord,
        maximumHammingDistance: Int,
        matches: inout [SimilarPhotoMatch],
        unionFind: inout UnionFind
    ) {
        let distance = (first.hash ^ second.hash).nonzeroBitCount
        guard distance <= maximumHammingDistance else { return }
        matches.append(
            SimilarPhotoMatch(
                first: first.candidate,
                second: second.candidate,
                hammingDistance: distance,
                similarityScore: PerceptualHash.similarityScore(forHammingDistance: distance)
            )
        )
        unionFind.union(first.index, second.index)
    }

    private static func makeGroups(
        from parsedRecords: [ParsedRecord],
        unionFind: UnionFind,
        matches: [SimilarPhotoMatch]
    ) -> [SimilarPhotoGroup] {
        var unionFind = unionFind
        let indexByAssetID = Dictionary(uniqueKeysWithValues: parsedRecords.map { ($0.candidate.id, $0.index) })

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

    private struct ClusteringResult {
        var unionFind: UnionFind
        let matches: [SimilarPhotoMatch]
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

    private struct PerceptualHashHammingIndex {
        private struct Entry {
            let recordIndex: Int
            let nextEntry: Int
        }

        private static let masksWithinTwoBits: [UInt16] = {
            var masks: [UInt16] = [0]
            for firstBit in 0..<16 {
                masks.append(UInt16(1) << UInt16(firstBit))
                for secondBit in (firstBit + 1)..<16 {
                    masks.append((UInt16(1) << UInt16(firstBit)) | (UInt16(1) << UInt16(secondBit)))
                }
            }
            return masks
        }()

        private var headEntryByBlockValue: [UInt32: Int]
        private var entries: [Entry] = []
        private var lastVisitedToken: [Int]

        init(recordCapacity: Int) {
            headEntryByBlockValue = [:]
            headEntryByBlockValue.reserveCapacity(recordCapacity * 4)
            entries.reserveCapacity(recordCapacity * 4)
            lastVisitedToken = Array(repeating: -1, count: recordCapacity)
        }

        mutating func insert(hash: UInt64, index: Int) {
            for block in 0..<4 {
                let key = blockValueKey(for: hash, block: block)
                let entryIndex = entries.count
                entries.append(Entry(recordIndex: index, nextEntry: headEntryByBlockValue[key] ?? -1))
                headEntryByBlockValue[key] = entryIndex
            }
        }

        mutating func candidates(withinTwoBitsPerBlockOf hash: UInt64, visitToken: Int) -> [Int] {
            var result: [Int] = []
            result.reserveCapacity(32)
            for block in 0..<4 {
                let value = UInt16(truncatingIfNeeded: hash >> UInt64(block * 16))
                for mask in Self.masksWithinTwoBits {
                    var entryIndex = headEntryByBlockValue[Self.key(block: block, value: value ^ mask)] ?? -1
                    while entryIndex >= 0 {
                        let entry = entries[entryIndex]
                        if lastVisitedToken[entry.recordIndex] != visitToken {
                            lastVisitedToken[entry.recordIndex] = visitToken
                            result.append(entry.recordIndex)
                        }
                        entryIndex = entry.nextEntry
                    }
                }
            }
            return result
        }

        private func blockValueKey(for hash: UInt64, block: Int) -> UInt32 {
            Self.key(block: block, value: UInt16(truncatingIfNeeded: hash >> UInt64(block * 16)))
        }

        private static func key(block: Int, value: UInt16) -> UInt32 {
            UInt32(block) << 16 | UInt32(value)
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
