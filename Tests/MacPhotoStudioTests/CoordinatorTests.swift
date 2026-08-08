import Foundation
import XCTest
@testable import MacPhotoStudio

final class CoordinatorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testTaskCoordinatorPublishesRealTaskLifecycle() async throws {
        let coordinator = await MainActor.run { TaskCoordinator() }
        let task = await coordinator.enqueue(kind: .videoExport, title: "导出视频")

        try await coordinator.start(task.id)
        try await coordinator.updateProgress(0.4, for: task.id)
        try await coordinator.complete(task.id)

        let tasks = await coordinator.allTasks()
        let completed = try XCTUnwrap(tasks.first)
        XCTAssertEqual(completed.id, task.id)
        XCTAssertEqual(completed.kind, .videoExport)
        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(completed.progress, 1)
    }

    func testVideoEditingCoordinatorPersistsVideoEditStateThroughCatalog() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Coordinator Root",
            bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false),
            volumeIdentifier: nil,
            availability: .online,
            createdAt: .now,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await store.saveMediaRoot(root)
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch([
            ScannedMediaAsset(
                rootID: root.id,
                relativePath: "coordinator.mov",
                fileResourceIdentifier: "coordinator-video",
                mediaType: .video,
                fileExtension: "mov",
                fileSize: 1,
                createdAt: .now,
                modifiedAt: .now,
                metadata: .video(
                    VideoMetadata(
                        width: 64,
                        height: 48,
                        duration: 1,
                        frameRate: 30,
                        codec: "avc1",
                        creationDate: nil
                    )
                )
            )
        ], scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)
        let assets = try await store.libraryAssets(query: .all, limit: 1, offset: 0)
        let asset = try XCTUnwrap(assets.first)

        let mediaRootStore = MediaRootStore(catalogStore: store)
        let coordinator = await MainActor.run {
            VideoEditingCoordinator(
                catalogStore: store,
                mediaRootStore: mediaRootStore,
                lutDirectory: paths.lutDirectory,
                videoProxiesDirectory: paths.videoProxiesDirectory
            )
        }
        var state = VideoEditState.identity
        state.trimStart = 0.15
        state.speed = 1.5
        state.audioGain = -6

        try await coordinator.save(state, for: asset.id)
        let restored = try await coordinator.editState(for: asset.id)
        XCTAssertEqual(restored, state)
    }

    func testPhotoEditingCoordinatorOwnsPhotoRAWAndPresetBoundaries() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let root = MediaRootRecord(
            id: UUID(),
            displayName: "Photo Coordinator Root",
            bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false),
            volumeIdentifier: nil,
            availability: .online,
            createdAt: .now,
            lastScannedAt: nil,
            lastScanError: nil
        )
        try await store.saveMediaRoot(root)
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch([
            ScannedMediaAsset(
                rootID: root.id,
                relativePath: "coordinator.dng",
                fileResourceIdentifier: "coordinator-photo",
                mediaType: .photo,
                fileExtension: "dng",
                fileSize: 1,
                createdAt: .now,
                modifiedAt: .now,
                metadata: .unavailable
            )
        ], scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)
        let indexedAssets = try await store.libraryAssets(query: .all, limit: 1, offset: 0)
        let asset = try XCTUnwrap(indexedAssets.first)

        let coordinator = await MainActor.run {
            PhotoEditingCoordinator(
                catalogStore: store,
                mediaRootStore: MediaRootStore(catalogStore: store),
                lutDirectory: paths.lutDirectory
            )
        }
        var photoState = PhotoEditState.identity
        photoState.light.exposure = 0.75
        try await coordinator.save(photoState, for: asset.id)
        let restoredPhotoState = try await coordinator.editState(for: asset.id)
        XCTAssertEqual(restoredPhotoState, photoState)

        var rawState = RAWEditState.identity
        rawState.exposure = 1.25
        rawState.lensCorrectionEnabled = true
        try await coordinator.saveRaw(rawState, for: asset.id)
        let restoredRawState = try await coordinator.rawEditState(for: asset.id)
        XCTAssertEqual(restoredRawState, rawState)

        let preset = try await coordinator.createPreset(named: "Coordinator Preset", from: asset.id)
        XCTAssertEqual(preset.content, photoState.presetContent)
        try await coordinator.renamePreset(preset, to: "Renamed Preset")
        try await coordinator.setPresetFavorite(true, preset: preset)
        let storedPresets = try await coordinator.presets()
        let storedPreset = try XCTUnwrap(storedPresets.first)
        XCTAssertEqual(storedPreset.name, "Renamed Preset")
        XCTAssertTrue(storedPreset.isFavorite)

        var replacement = PhotoEditState.identity
        replacement.light.exposure = -0.5
        let report = try await coordinator.applyPresetContent(replacement.presetContent, to: [asset.id])
        XCTAssertEqual(report.succeeded, 1)
        let appliedPhotoState = try await coordinator.editState(for: asset.id)
        XCTAssertEqual(appliedPhotoState.light.exposure, -0.5)
    }
}
