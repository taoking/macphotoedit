import Foundation
import XCTest
@testable import MacPhotoStudio

final class SimilarPhotoBenchmarkTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioSimilarBenchmarkTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCatalogOnlyBenchmarkRunsPublishedScalesWithoutClaimingImageIODecode() async throws {
        let benchmarks = try await SimilarPhotoBenchmarkService.runCatalogOnly()
        XCTAssertEqual(
            benchmarks.map(\.catalogRecordCount),
            SimilarPhotoBenchmarkService.defaultCatalogOnlyScales
        )
        for benchmark in benchmarks {
            XCTAssertEqual(benchmark.hashReuseCount, 0)
            XCTAssertEqual(benchmark.newHashCount, 0)
            XCTAssertEqual(benchmark.imageIODecodeDuration, 0)
            XCTAssertEqual(benchmark.failureCount, 0)
            XCTAssertGreaterThan(benchmark.groupCount, 0)
            XCTAssertGreaterThanOrEqual(benchmark.candidateFetchDuration, 0)
            XCTAssertGreaterThanOrEqual(benchmark.groupingDuration, 0)
            XCTAssertGreaterThanOrEqual(benchmark.totalMeasuredDuration, benchmark.catalogPopulationDuration)
        }

        let report = SimilarPhotoBenchmarkReport(
            generatedAt: .now,
            liveMediaHashedCount: 0,
            liveMediaReusedHashCount: 0,
            liveMediaMetrics: .empty,
            catalogOnlyBenchmarks: benchmarks
        )
        let reportURL = try report.write(to: temporaryDirectory)
        let text = try String(contentsOf: reportURL, encoding: .utf8)
        XCTAssertTrue(text.contains("Catalog-only generated scales"))
        XCTAssertTrue(text.contains("100000"))
        XCTAssertTrue(text.contains("not run for catalog-only records"))
    }
}
