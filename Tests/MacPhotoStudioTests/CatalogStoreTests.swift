import XCTest
@testable import MacPhotoStudio

final class CatalogStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testBootstrapCreatesCatalogAndAppliesMigration() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)

        try await store.bootstrap()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.catalogDatabaseURL.path(percentEncoded: false)))
        let version = try await store.currentSchemaVersion()
        XCTAssertEqual(version, 11)
    }

    func testBootstrapIsIdempotent() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let firstStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await firstStore.bootstrap()

        let secondStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await secondStore.bootstrap()

        let version = try await secondStore.currentSchemaVersion()
        XCTAssertEqual(version, 11)
    }
}
