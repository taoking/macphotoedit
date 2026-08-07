import XCTest
@testable import MacPhotoStudio

final class AdvancedPhotoManagementTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioAdvancedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testAlbumsSmartAlbumsStacksAndMissingAssetsPersistWithoutMovingSources() async throws {
        let (store, root) = try await catalogWithRoot()
        try await scan([
            scannedAsset(root: root, path: "Trips/hero.jpg", fileSize: 500, metadata: photoMetadata(camera: "Acme", lens: "Prime 35")),
            scannedAsset(root: root, path: "Trips/pair.dng", fileSize: 900, fileExtension: "dng", metadata: photoMetadata(camera: "Acme", lens: "Prime 35")),
            scannedAsset(root: root, path: "Trips/pair.jpg", fileSize: 320, metadata: photoMetadata(camera: "Acme", lens: "Prime 35"))
        ], root: root, store: store)

        let assets = try await store.libraryAssets(query: .all, limit: 10, offset: 0)
        let hero = try XCTUnwrap(assets.first(where: { $0.relativePath == "Trips/hero.jpg" }))
        let raw = try XCTUnwrap(assets.first(where: { $0.relativePath == "Trips/pair.dng" }))
        let jpeg = try XCTUnwrap(assets.first(where: { $0.relativePath == "Trips/pair.jpg" }))
        try await store.updateRating(5, for: [hero.id])
        try await store.savePhotoEditState(.identity, for: hero.id)
        let tag = try await store.createTag(named: "精选")
        try await store.addTag(tag.id, to: [hero.id])

        let album = try await store.createAlbum(named: "旅行")
        try await store.addAssets([hero.id], toAlbum: album.id)
        let albumAssets = try await store.libraryAssets(query: LibraryQuery(albumID: album.id), limit: 10, offset: 0)
        XCTAssertEqual(albumAssets.map(\.id), [hero.id])
        try await store.removeAssets([hero.id], fromAlbum: album.id)
        let removedAlbumAssets = try await store.libraryAssets(query: LibraryQuery(albumID: album.id), limit: 10, offset: 0)
        XCTAssertTrue(removedAlbumAssets.isEmpty)
        try await store.addAssets([hero.id], toAlbum: album.id)

        let smartCriteria = SmartAlbumCriteria(
            minimumRating: 5,
            captureDateFrom: date.addingTimeInterval(-1),
            captureDateTo: date.addingTimeInterval(1),
            camera: "Acme",
            lens: "35",
            tagID: tag.id,
            mediaType: .photo,
            isEdited: true,
            isRAW: false
        )
        let smartAlbum = try await store.createSmartAlbum(named: "已编辑精选", criteria: smartCriteria)
        XCTAssertEqual(smartAlbum.kind, .smartAlbum)
        XCTAssertEqual(smartAlbum.criteria, smartCriteria)
        let smartAssets = try await store.libraryAssets(
            query: LibraryQuery(smartAlbumCriteria: smartCriteria),
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(smartAssets.map(\.id), [hero.id])

        let stack = try await store.createStack(kind: .rawJPEG, title: "Pair", assetIDs: [raw.id, jpeg.id])
        let stackAssets = try await store.libraryAssets(query: LibraryQuery(stackID: stack.id), limit: 10, offset: 0)
        XCTAssertEqual(Set(stackAssets.map(\.id)), Set([raw.id, jpeg.id]))
        let storedStacks = try await store.assetStacks()
        XCTAssertEqual(storedStacks.first?.assetCount, 2)

        try await store.removeAssets([jpeg.id], fromStack: stack.id)
        let reducedStackAssets = try await store.libraryAssets(query: LibraryQuery(stackID: stack.id), limit: 10, offset: 0)
        XCTAssertEqual(reducedStackAssets.map(\.id), [raw.id])
        try await store.markAssetsMissing([hero.id])
        let recordsAfterTrashMove = try await store.assets(for: root.id)
        let heroTags = try await store.tags(for: hero.id)
        let heroEditState = try await store.photoEditState(for: hero.id)
        XCTAssertEqual(recordsAfterTrashMove.first(where: { $0.id == hero.id })?.availability, .missing)
        XCTAssertEqual(heroTags.map(\.id), [tag.id])
        XCTAssertEqual(heroEditState, .identity)
    }

    func testExactDuplicateGroupsUseSameSizeCandidatesAndPersistContentHashes() async throws {
        let (store, root) = try await catalogWithRoot()
        try await scan([
            scannedAsset(root: root, path: "one.jpg", fileSize: 256, metadata: .unavailable),
            scannedAsset(root: root, path: "two.jpg", fileSize: 256, metadata: .unavailable),
            scannedAsset(root: root, path: "different.jpg", fileSize: 256, metadata: .unavailable),
            scannedAsset(root: root, path: "alone.jpg", fileSize: 128, metadata: .unavailable)
        ], root: root, store: store)

        let candidates = try await store.duplicateHashCandidates()
        XCTAssertEqual(Set(candidates.map(\.relativePath)), Set(["one.jpg", "two.jpg", "different.jpg"]))
        for candidate in candidates {
            let digest = candidate.relativePath == "different.jpg" ? "different" : "same"
            try await store.saveContentHash(digest, for: candidate)
        }

        let groups = try await store.exactDuplicateGroups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.digest, "same")
        XCTAssertEqual(Set(groups.first?.assets.map(\.relativePath) ?? []), Set(["one.jpg", "two.jpg"]))
        let cachedCandidate = try XCTUnwrap(candidates.first)
        let cachedDigest = try await store.contentHash(for: cachedCandidate)
        XCTAssertEqual(cachedDigest, cachedCandidate.relativePath == "different.jpg" ? "different" : "same")
    }

    func testDuplicateScannerHashesOnlySameSizeCandidatesAndReusesValidHashes() async throws {
        let mediaDirectory = temporaryDirectory.appending(path: "Media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try Data("matching-content".utf8).write(to: mediaDirectory.appending(path: "one.jpg"))
        try Data("matching-content".utf8).write(to: mediaDirectory.appending(path: "two.jpg"))
        try Data("different-content".utf8).write(to: mediaDirectory.appending(path: "different.jpg"))
        try Data("short".utf8).write(to: mediaDirectory.appending(path: "alone.jpg"))

        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let rootStore = MediaRootStore(catalogStore: store)
        let root = try await rootStore.add(directoryURL: mediaDirectory)
        try await scan([
            scannedAsset(root: root, path: "one.jpg", fileSize: 16, metadata: .unavailable),
            scannedAsset(root: root, path: "two.jpg", fileSize: 16, metadata: .unavailable),
            scannedAsset(root: root, path: "different.jpg", fileSize: 17, metadata: .unavailable),
            scannedAsset(root: root, path: "alone.jpg", fileSize: 5, metadata: .unavailable)
        ], root: root, store: store)

        let scanner = ExactDuplicateScanner(catalogStore: store, mediaRootStore: rootStore)
        let firstReport = try await scanner.scan()
        XCTAssertEqual(firstReport.candidateCount, 2)
        XCTAssertEqual(firstReport.hashedCount, 2)
        XCTAssertTrue(firstReport.failures.isEmpty)
        XCTAssertEqual(firstReport.groups.count, 1)
        let firstGroup = try XCTUnwrap(firstReport.groups.first)
        XCTAssertEqual(Set(firstGroup.assets.map(\.relativePath)), Set(["one.jpg", "two.jpg"]))

        let secondReport = try await scanner.scan()
        XCTAssertEqual(secondReport.hashedCount, 0)
        XCTAssertEqual(secondReport.reusedHashCount, 2)
        XCTAssertEqual(secondReport.groups.count, 1)
    }

    func testRelinkingRootPreservesIdentityAndUpdatesOnlyRootMapping() async throws {
        let oldDirectory = temporaryDirectory.appending(path: "Old", directoryHint: .isDirectory)
        let newDirectory = temporaryDirectory.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let rootStore = MediaRootStore(catalogStore: store)
        let root = try await rootStore.add(directoryURL: oldDirectory)

        let relinked = try await rootStore.relink(root, to: newDirectory)
        let persisted = try await store.mediaRoot(id: root.id)

        XCTAssertEqual(relinked.id, root.id)
        XCTAssertEqual(persisted?.id, root.id)
        XCTAssertEqual(persisted?.lastKnownPath, newDirectory.path(percentEncoded: false))
        XCTAssertEqual(persisted?.availability, .online)
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
        fileSize: Int64,
        fileExtension: String = "jpg",
        metadata: ExtractedMetadata
    ) -> ScannedMediaAsset {
        ScannedMediaAsset(
            rootID: root.id,
            relativePath: path,
            fileResourceIdentifier: path,
            mediaType: .photo,
            fileExtension: fileExtension,
            fileSize: fileSize,
            createdAt: date,
            modifiedAt: date,
            metadata: metadata
        )
    }

    private func photoMetadata(camera: String, lens: String) -> ExtractedMetadata {
        .photo(PhotoMetadata(
            width: 1,
            height: 1,
            captureDate: date,
            cameraMake: camera,
            cameraModel: "A1",
            lensModel: lens,
            focalLength: 35,
            aperture: 1.8,
            shutterSpeed: 0.01,
            iso: 100,
            orientation: 1,
            colorProfile: "sRGB"
        ))
    }
}
