import XCTest
@testable import MacPhotoStudio

final class LibraryCatalogTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testRatingFlagTagAndCombinedLibraryFiltersPersist() async throws {
        let (store, root) = try await catalogWithRoot()
        let photo = scannedAsset(root: root, path: "Trips/aurora.jpg", metadata: .photo(PhotoMetadata(
            width: 6048,
            height: 4024,
            captureDate: date,
            cameraMake: "Acme",
            cameraModel: "A1",
            lensModel: "Prime 35",
            focalLength: 35,
            aperture: 1.8,
            shutterSpeed: 0.01,
            iso: 400,
            orientation: 1,
            colorProfile: "Display P3",
            gpsLatitude: 42.1,
            gpsLongitude: 87.2
        )))
        let video = scannedAsset(root: root, path: "Trips/aurora.mov", mediaType: .video, metadata: .video(VideoMetadata(
            width: 3840,
            height: 2160,
            duration: 8,
            frameRate: 30,
            codec: "hvc1",
            creationDate: date
        )))
        try await scan([photo, video], root: root, store: store)

        let initialAssets = try await store.libraryAssets(query: .all, limit: 10, offset: 0)
        let photoRecord = try XCTUnwrap(initialAssets.first(where: { $0.relativePath == photo.relativePath }))
        try await store.updateRating(5, for: [photoRecord.id])
        try await store.updateFlag(.pick, for: [photoRecord.id])
        let tag = try await store.createTag(named: "星空")
        try await store.addTag(tag.id, to: [photoRecord.id])

        let filtered = try await store.libraryAssets(
            query: LibraryQuery(
                rootID: root.id,
                searchText: "aurora",
                mediaType: .photo,
                minimumRating: 5,
                flag: .pick,
                tagID: tag.id,
                captureDateFrom: date.addingTimeInterval(-1),
                captureDateTo: date.addingTimeInterval(1),
                camera: "Acme",
                lens: "35"
            ),
            limit: 10,
            offset: 0
        )

        XCTAssertEqual(filtered.map(\.id), [photoRecord.id])
        XCTAssertEqual(filtered.first?.gpsLatitude, 42.1)
        let assignedTags = try await store.tags(for: photoRecord.id)
        XCTAssertEqual(assignedTags, [tag])

        try await store.renameTag(tag.id, to: "极光")
        let renamedTags = try await store.tags()
        XCTAssertEqual(renamedTags.first?.name, "极光")
        try await store.removeTag(tag.id, from: [photoRecord.id])
        let tagsAfterRemoval = try await store.tags(for: photoRecord.id)
        XCTAssertTrue(tagsAfterRemoval.isEmpty)
    }

    func testTenThousandAssetsAreReadInBoundedPagesWithoutLoadingMediaData() async throws {
        let (store, root) = try await catalogWithRoot()
        let assets = (0..<10_000).map { index in
            scannedAsset(root: root, path: String(format: "Large/%05d.jpg", index), metadata: .unavailable)
        }
        try await scan(assets, root: root, store: store)

        let firstPage = try await store.libraryAssets(query: .all, limit: 250, offset: 0)
        let secondPage = try await store.libraryAssets(query: .all, limit: 250, offset: 250)

        XCTAssertEqual(firstPage.count, 250)
        XCTAssertEqual(secondPage.count, 250)
        XCTAssertTrue(Set(firstPage.map(\.id)).isDisjoint(with: Set(secondPage.map(\.id))))
        XCTAssertTrue(firstPage.allSatisfy { $0.width == nil && $0.height == nil })
    }

    private func catalogWithRoot() async throws -> (CatalogStore, MediaRootRecord) {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Library Root",
            bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false),
            volumeIdentifier: "TEST-VOLUME",
            availability: .online,
            createdAt: date,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await store.saveMediaRoot(root)
        return (store, root)
    }

    private func scan(_ assets: [ScannedMediaAsset], root: MediaRootRecord, store: CatalogStore) async throws {
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch(assets, scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)
    }

    private func scannedAsset(
        root: MediaRootRecord,
        path: String,
        mediaType: MediaType = .photo,
        metadata: ExtractedMetadata
    ) -> ScannedMediaAsset {
        ScannedMediaAsset(
            rootID: root.id,
            relativePath: path,
            fileResourceIdentifier: path,
            mediaType: mediaType,
            fileExtension: URL(filePath: path).pathExtension,
            fileSize: 128,
            createdAt: date,
            modifiedAt: date,
            metadata: metadata
        )
    }
}
