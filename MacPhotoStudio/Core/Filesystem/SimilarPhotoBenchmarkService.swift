import Foundation

/// A generated Catalog-only benchmark row. No URL in this benchmark points to
/// a real image, so its results are intentionally limited to SQLite candidate
/// retrieval and in-memory BK-tree grouping.
struct SimilarPhotoCatalogOnlyBenchmark: Sendable, Equatable {
    let catalogRecordCount: Int
    let catalogPopulationDuration: TimeInterval
    let candidateFetchDuration: TimeInterval
    let hashReuseCount: Int
    let newHashCount: Int
    let imageIODecodeDuration: TimeInterval
    let groupingDuration: TimeInterval
    let totalMeasuredDuration: TimeInterval
    let groupCount: Int
    let failureCount: Int
    let observedPeakResidentMemoryBytes: UInt64?
}

struct SimilarPhotoBenchmarkReport: Sendable, Equatable {
    let generatedAt: Date
    let liveMediaHashedCount: Int
    let liveMediaReusedHashCount: Int
    let liveMediaMetrics: SimilarPhotoScanMetrics
    let catalogOnlyBenchmarks: [SimilarPhotoCatalogOnlyBenchmark]

    func text() -> String {
        let liveMemory = memoryText(liveMediaMetrics.observedPeakResidentMemoryBytes)
        let catalogRows = catalogOnlyBenchmarks.map { benchmark in
            """
            Catalog-only records: \(benchmark.catalogRecordCount)
            Catalog population: \(durationText(benchmark.catalogPopulationDuration))
            Candidate fetch: \(durationText(benchmark.candidateFetchDuration))
            Hash reuse / new hash: \(benchmark.hashReuseCount) / \(benchmark.newHashCount)
            ImageIO decode: \(durationText(benchmark.imageIODecodeDuration)) (not run for catalog-only records)
            Grouping: \(durationText(benchmark.groupingDuration))
            Total generated benchmark (population + fetch + synthetic record preparation + grouping): \(durationText(benchmark.totalMeasuredDuration))
            Group count / failure count: \(benchmark.groupCount) / \(benchmark.failureCount)
            Observed peak resident memory: \(memoryText(benchmark.observedPeakResidentMemoryBytes))
            """
        }.joined(separator: "\n\n")

        return """
        Mac Photo Studio Similar Photo Benchmark Report
        Generated at: \(generatedAt.ISO8601Format())

        Live-media scan (current catalog; only this section may include actual ImageIO hashing):
        Candidate fetch: \(durationText(liveMediaMetrics.candidateFetchDuration))
        Hash reuse / new hash: \(liveMediaReusedHashCount) / \(liveMediaHashedCount)
        ImageIO decode: \(durationText(liveMediaMetrics.imageIODecodeDuration)) across \(liveMediaMetrics.imageIODecodeCount) decode attempts
        Grouping: \(durationText(liveMediaMetrics.groupingDuration))
        Total scan: \(durationText(liveMediaMetrics.totalScanDuration))
        Group count / failure count: \(liveMediaMetrics.groupCount) / \(liveMediaMetrics.failureCount)
        Observed peak resident memory: \(liveMemory)

        Catalog-only generated scales (these rows do NOT measure real media hashing, ImageIO decode, external storage, or image performance):
        \(catalogRows.isEmpty ? "No generated scales requested." : catalogRows)
        """
    }

    func write(to logsDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let destination = logsDirectory
            .appending(path: "similar-photo-benchmark-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try Data(text().utf8).write(to: destination, options: .atomic)
        return destination
    }

    private func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.3f s", duration)
    }

    private func memoryText(_ bytes: UInt64?) -> String {
        guard let bytes else { return "unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}

enum SimilarPhotoBenchmarkService {
    static let defaultCatalogOnlyScales = [10_000, 50_000, 100_000]

    /// Creates an isolated temporary SQLite catalog for each scale. The
    /// generated rows never become live media roots and are removed afterwards.
    static func runCatalogOnly(
        recordCounts: [Int] = defaultCatalogOnlyScales
    ) async throws -> [SimilarPhotoCatalogOnlyBenchmark] {
        var results: [SimilarPhotoCatalogOnlyBenchmark] = []
        for recordCount in recordCounts {
            guard recordCount > 0 else {
                throw StudioError.databaseExecutionFailed(message: "Catalog-only benchmark record count must be positive.")
            }
            try Task.checkCancellation()
            results.append(try await runCatalogOnlyScale(recordCount: recordCount))
        }
        return results
    }

    private static func runCatalogOnlyScale(
        recordCount: Int
    ) async throws -> SimilarPhotoCatalogOnlyBenchmark {
        let benchmarkStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        var observedPeakMemory = SimilarPhotoPerformanceInstrumentation.residentMemoryBytes()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudio-SimilarBenchmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let catalogStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await catalogStore.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Catalog-only benchmark \(recordCount)",
            bookmarkData: Data("catalog-only-benchmark".utf8),
            lastKnownPath: "/catalog-only-benchmark/\(recordCount)",
            volumeIdentifier: "CATALOG-ONLY",
            availability: .online,
            createdAt: .now,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await catalogStore.saveMediaRoot(root)

        let populationStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        let scanID = UUID()
        try await catalogStore.beginScan(rootID: root.id, scanID: scanID)
        let batchSize = 1_000
        let signatureDate = Date(timeIntervalSince1970: 1_700_000_000)
        for batchStart in stride(from: 0, to: recordCount, by: batchSize) {
            try Task.checkCancellation()
            let upperBound = min(recordCount, batchStart + batchSize)
            let batch = (batchStart..<upperBound).map { index in
                ScannedMediaAsset(
                    rootID: root.id,
                    relativePath: String(format: "synthetic/%06d.jpg", index),
                    fileResourceIdentifier: "catalog-only-\(index)",
                    mediaType: .photo,
                    fileExtension: "jpg",
                    fileSize: Int64(10_000 + index % 701),
                    createdAt: signatureDate,
                    modifiedAt: signatureDate,
                    metadata: .unavailable
                )
            }
            try await catalogStore.applyScanBatch(batch, scanID: scanID)
            SimilarPhotoPerformanceInstrumentation.observePeak(&observedPeakMemory)
            await Task.yield()
        }
        try await catalogStore.finishScan(rootID: root.id, scanID: scanID)
        let catalogPopulationDuration = SimilarPhotoPerformanceInstrumentation.now() - populationStartedAt

        let candidateFetchStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        let candidates = try await catalogStore.perceptualHashCandidates()
        let candidateFetchDuration = SimilarPhotoPerformanceInstrumentation.now() - candidateFetchStartedAt
        guard candidates.count == recordCount else {
            throw StudioError.databaseExecutionFailed(message: "Catalog-only benchmark fetched \(candidates.count) candidates, expected \(recordCount).")
        }

        var records: [PerceptualHashRecord] = []
        records.reserveCapacity(candidates.count)
        for (index, candidate) in candidates.enumerated() {
            if index.isMultiple(of: 2_048) {
                try Task.checkCancellation()
                SimilarPhotoPerformanceInstrumentation.observePeak(&observedPeakMemory)
                await Task.yield()
            }
            records.append(PerceptualHashRecord(candidate: candidate, digest: syntheticDigest(for: index)))
        }

        let groupingStartedAt = SimilarPhotoPerformanceInstrumentation.now()
        let groups = try await SimilarPhotoGrouping.groups(
            from: records,
            maximumHammingDistance: SimilarPhotoScanner.maximumHammingDistance
        )
        let groupingDuration = SimilarPhotoPerformanceInstrumentation.now() - groupingStartedAt
        SimilarPhotoPerformanceInstrumentation.observePeak(&observedPeakMemory)
        return SimilarPhotoCatalogOnlyBenchmark(
            catalogRecordCount: recordCount,
            catalogPopulationDuration: catalogPopulationDuration,
            candidateFetchDuration: candidateFetchDuration,
            hashReuseCount: 0,
            newHashCount: 0,
            imageIODecodeDuration: 0,
            groupingDuration: groupingDuration,
            totalMeasuredDuration: SimilarPhotoPerformanceInstrumentation.now() - benchmarkStartedAt,
            groupCount: groups.count,
            failureCount: 0,
            observedPeakResidentMemoryBytes: observedPeakMemory
        )
    }

    private static func syntheticDigest(for index: Int) -> String {
        let value: UInt64
        switch index % 1_000 {
        case 0:
            value = splitMix64(UInt64(index / 1_000))
        case 1:
            // Eight flips distributed across all four 16-bit blocks.  The
            // pair must be found by the large-library Hamming index without
            // relying on an identical-digest shortcut.
            value = splitMix64(UInt64(index / 1_000)) ^ 0x0003_0003_0003_0003
        default:
            value = splitMix64(UInt64(index) &+ 1_000_000)
        }
        return String(format: "%016llx", value)
    }

    private static func splitMix64(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
