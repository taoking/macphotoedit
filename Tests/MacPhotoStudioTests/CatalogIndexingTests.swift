import XCTest
@testable import MacPhotoStudio

final class CatalogIndexingTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testIncrementalUpsertPreservesAssetAndMissingFilesRemainInCatalog() async throws {
        let (store, root) = try await configuredCatalog()
        let firstScanID = UUID()
        let firstCandidate = asset(root: root, metadata: .photo(PhotoMetadata(
            width: 1,
            height: 1,
            captureDate: modificationDate,
            cameraMake: "Test",
            cameraModel: "Camera",
            lensModel: nil,
            focalLength: nil,
            aperture: nil,
            shutterSpeed: nil,
            iso: nil,
            orientation: 1,
            colorProfile: "sRGB"
        )))

        try await store.beginScan(rootID: root.id, scanID: firstScanID)
        try await store.applyScanBatch([firstCandidate], scanID: firstScanID)
        try await store.finishScan(rootID: root.id, scanID: firstScanID)
        let firstAssets = try await store.assets(for: root.id)
        XCTAssertEqual(firstAssets.count, 1)
        XCTAssertEqual(firstAssets[0].availability, .available)
        XCTAssertEqual(firstAssets[0].metadataState, .available)

        let secondScanID = UUID()
        let unchangedCandidate = asset(root: root, metadata: .unchanged)
        try await store.beginScan(rootID: root.id, scanID: secondScanID)
        try await store.applyScanBatch([unchangedCandidate], scanID: secondScanID)
        try await store.finishScan(rootID: root.id, scanID: secondScanID)
        let secondAssets = try await store.assets(for: root.id)
        XCTAssertEqual(secondAssets.count, 1)
        XCTAssertEqual(secondAssets[0].id, firstAssets[0].id)
        XCTAssertEqual(secondAssets[0].metadataState, .available)

        let thirdScanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: thirdScanID)
        try await store.finishScan(rootID: root.id, scanID: thirdScanID)
        let missingAssets = try await store.assets(for: root.id)
        XCTAssertEqual(missingAssets.count, 1)
        XCTAssertEqual(missingAssets[0].availability, .missing)
    }

    func testOfflineRootRetainsAssetsAndMarksThemOffline() async throws {
        let (store, root) = try await configuredCatalog()
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch([asset(root: root, metadata: .unavailable)], scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)

        try await store.updateRootAvailability(.offline, errorMessage: "卷已断开", rootID: root.id)

        let storedRoot = try await store.mediaRoot(id: root.id)
        let assets = try await store.assets(for: root.id)
        XCTAssertEqual(storedRoot?.availability, .offline)
        XCTAssertEqual(storedRoot?.lastScanError, "卷已断开")
        XCTAssertEqual(assets.first?.availability, .offline)
    }

    func testPersistedBookmarkCanBeResolvedAfterCatalogReopen() async throws {
        let bookmarkStore = BookmarkStore()
        let bookmarkData = try bookmarkStore.createBookmark(for: temporaryDirectory)
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let firstStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await firstStore.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Bookmark Root",
            bookmarkData: bookmarkData,
            lastKnownPath: temporaryDirectory.path(percentEncoded: false),
            volumeIdentifier: nil,
            availability: .online,
            createdAt: modificationDate,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await firstStore.saveMediaRoot(root)

        let reopenedStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await reopenedStore.bootstrap()
        let restoredRoot = try await reopenedStore.mediaRoot(id: root.id)
        let resolvedBookmark = try bookmarkStore.resolve(try XCTUnwrap(restoredRoot?.bookmarkData))

        XCTAssertEqual(
            resolvedBookmark.url.standardizedFileURL.path(percentEncoded: false),
            temporaryDirectory.standardizedFileURL.path(percentEncoded: false)
        )
    }

    func testMediaRootStorePersistsSelectedDirectoryWithoutCopyingIt() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let mediaRootStore = MediaRootStore(catalogStore: store)

        let root = try await mediaRootStore.add(directoryURL: temporaryDirectory)
        let persistedRoot = try await store.mediaRoot(id: root.id)

        XCTAssertEqual(persistedRoot?.lastKnownPath, temporaryDirectory.path(percentEncoded: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.catalogDirectory.appending(path: temporaryDirectory.lastPathComponent).path(percentEncoded: false)))
    }

    func testMediaRootRegistrationReusesExistingFolderWithoutCreatingDuplicateRoot() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let mediaRootStore = MediaRootStore(catalogStore: store)

        let firstRegistration = try await mediaRootStore.register(directoryURL: temporaryDirectory)
        let secondRegistration = try await mediaRootStore.register(directoryURL: temporaryDirectory)
        let roots = try await store.mediaRoots()

        XCTAssertFalse(firstRegistration.wasAlreadyRegistered)
        XCTAssertTrue(secondRegistration.wasAlreadyRegistered)
        XCTAssertEqual(secondRegistration.root.id, firstRegistration.root.id)
        XCTAssertEqual(roots.map(\.id), [firstRegistration.root.id])
    }

    private func configuredCatalog() async throws -> (CatalogStore, MediaRootRecord) {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Test Root",
            bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false),
            volumeIdentifier: "TEST-VOLUME",
            availability: .online,
            createdAt: modificationDate,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await store.saveMediaRoot(root)
        return (store, root)
    }

    private func asset(root: MediaRootRecord, metadata: ExtractedMetadata) -> ScannedMediaAsset {
        ScannedMediaAsset(
            rootID: root.id,
            relativePath: "nested/image.png",
            fileResourceIdentifier: "file-id-1",
            mediaType: .photo,
            fileExtension: "png",
            fileSize: 68,
            createdAt: modificationDate,
            modifiedAt: modificationDate,
            metadata: metadata
        )
    }
}
