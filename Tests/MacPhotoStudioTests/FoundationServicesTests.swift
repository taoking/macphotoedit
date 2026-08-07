import XCTest
@testable import MacPhotoStudio

final class FoundationServicesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCatalogPathsCreatesAllRequiredDirectories() throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let expectedDirectories = [
            paths.catalogDirectory,
            paths.thumbnailsDirectory,
            paths.previewsDirectory,
            paths.lutDirectory,
            paths.presetsDirectory,
            paths.logsDirectory
        ]

        for directory in expectedDirectories {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testThumbnailStoreWritesAndRemovesCacheData() throws {
        let store = ThumbnailStore(directoryURL: temporaryDirectory)
        let assetID = UUID()
        let expectedData = Data([0, 1, 2, 3])

        try store.store(expectedData, for: assetID, maximumPixelSize: 256)
        XCTAssertEqual(try store.data(for: assetID, maximumPixelSize: 256), expectedData)

        try store.remove(for: assetID, maximumPixelSize: 256)
        XCTAssertNil(try store.data(for: assetID, maximumPixelSize: 256))
    }

    func testBackgroundTaskCancellationIsObservable() async throws {
        let center = BackgroundTaskCenter()
        let task = await center.enqueue(kind: .scan, title: "扫描媒体库")

        try await center.start(task.id)
        try await center.updateProgress(0.4, for: task.id)
        try await center.cancel(task.id)

        let cancelledTask = await center.task(for: task.id)
        XCTAssertEqual(cancelledTask?.state, .cancelled)
        XCTAssertEqual(cancelledTask?.progress, 0.4)
    }

    func testPhotoExportTaskCompletesWithProgressAndBatchKindIsSupported() async throws {
        let center = BackgroundTaskCenter()
        let exportTask = await center.enqueue(kind: .photoExport, title: "导出照片")
        let editTask = await center.enqueue(kind: .photoBatchEdit, title: "批量粘贴")

        try await center.start(exportTask.id)
        try await center.updateProgress(0.5, for: exportTask.id)
        try await center.complete(exportTask.id)

        let completedExport = await center.task(for: exportTask.id)
        let queuedEdit = await center.task(for: editTask.id)
        XCTAssertEqual(completedExport?.state, .completed)
        XCTAssertEqual(completedExport?.progress, 1)
        XCTAssertEqual(queuedEdit?.state, .queued)
    }
}
