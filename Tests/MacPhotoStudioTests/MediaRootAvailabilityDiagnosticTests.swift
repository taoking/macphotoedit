import XCTest
@testable import MacPhotoStudio

final class MediaRootAvailabilityDiagnosticTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioMediaRootDiagnosticTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDiagnosticReadsBookmarkScopeAndVolumeValuesForOnlineRoot() async throws {
        let (store, rootStore) = try await configuredStore()
        let mediaDirectory = temporaryDirectory.appending(path: "online-root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let root = try await rootStore.add(directoryURL: mediaDirectory)

        let diagnostic = await rootStore.diagnoseAccess(to: root)
        let persisted = try await store.mediaRoot(id: root.id)
        let reportURL = try MediaRootAvailabilityReport(generatedAt: .now, diagnostics: [diagnostic])
            .write(to: temporaryDirectory.appending(path: "logs", directoryHint: .isDirectory))
        let report = try String(contentsOf: reportURL, encoding: .utf8)

        XCTAssertEqual(diagnostic.availability, .online)
        XCTAssertTrue(diagnostic.bookmarkResolved)
        let resolvedPath = try XCTUnwrap(diagnostic.resolvedPath)
        XCTAssertEqual(URL(filePath: resolvedPath).lastPathComponent, mediaDirectory.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedPath))
        XCTAssertEqual(diagnostic.resourceSnapshot?.directoryExists, true)
        XCTAssertEqual(diagnostic.resourceSnapshot?.isDirectory, true)
        XCTAssertNil(diagnostic.bookmarkResolutionError)
        XCTAssertEqual(persisted?.availability, .online)
        XCTAssertTrue(report.contains("Security-scoped access started:"))
        XCTAssertTrue(report.contains("Volume UUID:"))
    }

    func testDisconnectedRootKeepsCatalogAssetsAndReportsOffline() async throws {
        let (store, rootStore) = try await configuredStore()
        let mediaDirectory = temporaryDirectory.appending(path: "disconnectable-root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let root = try await rootStore.add(directoryURL: mediaDirectory)
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch([
            ScannedMediaAsset(
                rootID: root.id,
                relativePath: "kept-in-catalog.jpg",
                fileResourceIdentifier: "diagnostic-asset",
                mediaType: .photo,
                fileExtension: "jpg",
                fileSize: 42,
                createdAt: nil,
                modifiedAt: nil,
                metadata: .unavailable
            )
        ], scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)

        try FileManager.default.removeItem(at: mediaDirectory)
        let diagnostic = await rootStore.diagnoseAccess(to: root)
        let persisted = try await store.mediaRoot(id: root.id)
        let assets = try await store.assets(for: root.id)

        XCTAssertEqual(diagnostic.availability, .offline)
        XCTAssertNotNil(diagnostic.errorMessage)
        XCTAssertEqual(persisted?.availability, .offline)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.relativePath, "kept-in-catalog.jpg")
        XCTAssertEqual(assets.first?.availability, .offline)
    }

    func testOfflineScanFailsWithoutConvertingRetainedAssetsToMissing() async throws {
        let (store, rootStore) = try await configuredStore()
        let mediaDirectory = temporaryDirectory.appending(path: "scan-offline-root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let root = try await rootStore.add(directoryURL: mediaDirectory)
        let initialScanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: initialScanID)
        try await store.applyScanBatch([
            ScannedMediaAsset(
                rootID: root.id,
                relativePath: "must-not-become-missing.jpg",
                fileResourceIdentifier: "retained-asset",
                mediaType: .photo,
                fileExtension: "jpg",
                fileSize: 42,
                createdAt: nil,
                modifiedAt: nil,
                metadata: .unavailable
            )
        ], scanID: initialScanID)
        try await store.finishScan(rootID: root.id, scanID: initialScanID)
        try FileManager.default.removeItem(at: mediaDirectory)

        let coordinator = ScanCoordinator(catalogStore: store, mediaRootStore: rootStore)
        let startedScanID = await coordinator.startScan(rootID: root.id)
        let scanID = try XCTUnwrap(startedScanID)
        var status: ScanStatus?
        for _ in 0..<100 {
            let statuses = await coordinator.statuses()
            status = statuses.first(where: { $0.id == scanID })
            if status?.state == .failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let assets = try await store.assets(for: root.id)
        XCTAssertEqual(status?.state, .failed)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.availability, .offline)
    }

    private func configuredStore() async throws -> (CatalogStore, MediaRootStore) {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        return (store, MediaRootStore(catalogStore: store))
    }
}
