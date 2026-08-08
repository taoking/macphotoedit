import XCTest
@testable import MacPhotoStudio

final class SimilarPhotoReviewTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let captureDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioSimilarReviewTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testReviewMetadataFetchesLargeGroupsFromCatalogWithoutOriginalMedia() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Review Library",
            bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false),
            volumeIdentifier: "TEST-VOLUME",
            availability: .online,
            createdAt: captureDate,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await store.saveMediaRoot(root)

        let scanID = UUID()
        let assetCount = 901
        var scannedAssets: [ScannedMediaAsset] = []
        scannedAssets.reserveCapacity(assetCount)
        for index in 0..<assetCount {
            scannedAssets.append(makeScannedAsset(index: index, root: root))
        }
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch(scannedAssets, scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)

        let indexedAssets = try await store.libraryAssets(query: .all, limit: assetCount, offset: 0)
        XCTAssertEqual(indexedAssets.count, assetCount)
        let rawAsset = try XCTUnwrap(indexedAssets.first(where: { $0.fileExtension == "arw" }))
        try await store.updateRating(4, for: [rawAsset.id])
        try await store.updateFlag(.pick, for: [rawAsset.id])

        // No media files are created for this test. This path must therefore
        // obtain all card fields from the Catalog and support a group larger
        // than one SQLite bind-variable batch.
        let reviewAssets = try await store.libraryAssets(ids: indexedAssets.map(\.id) + [UUID()])
        XCTAssertEqual(Set(reviewAssets.map(\.id)), Set(indexedAssets.map(\.id)))

        let reviewItem = SimilarPhotoReviewItem(asset: try XCTUnwrap(reviewAssets.first(where: { $0.id == rawAsset.id })))
        XCTAssertEqual(reviewItem.dimensionsText, "4000 × 3000")
        XCTAssertEqual(reviewItem.ratingText, "4 星")
        XCTAssertEqual(reviewItem.flagText, "选取")
        XCTAssertEqual(reviewItem.formatText, "RAW · ARW")
        XCTAssertEqual(reviewItem.asset.captureDate, captureDate)
        XCTAssertFalse(reviewItem.fileSizeText.isEmpty)
    }

    private func makeScannedAsset(index: Int, root: MediaRootRecord) -> ScannedMediaAsset {
        let fileExtension = index == 0 ? "arw" : "jpg"
        let filename = String(format: "Review/IMG_%04d.%@", index, fileExtension)
        let metadata = PhotoMetadata(
            width: 4_000,
            height: 3_000,
            captureDate: captureDate,
            cameraMake: "Test Camera",
            cameraModel: "Review",
            lensModel: "50 mm",
            focalLength: 50,
            aperture: 2,
            shutterSpeed: 0.01,
            iso: 100,
            orientation: 1,
            colorProfile: "Display P3"
        )
        return ScannedMediaAsset(
            rootID: root.id,
            relativePath: filename,
            fileResourceIdentifier: "review-\(index)",
            mediaType: .photo,
            fileExtension: fileExtension,
            fileSize: Int64(2_000_000 + index),
            createdAt: captureDate,
            modifiedAt: captureDate,
            metadata: .photo(metadata)
        )
    }
}
