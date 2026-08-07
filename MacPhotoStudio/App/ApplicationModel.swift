import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class ApplicationModel: ObservableObject {
    enum StartupState: Equatable {
        case starting
        case ready(CatalogPaths)
        case failed(String)
    }

    @Published private(set) var startupState: StartupState = .starting
    @Published private(set) var mediaRoots: [MediaRootRecord] = []
    @Published private(set) var scanStatuses: [ScanStatus] = []
    @Published private(set) var libraryAssets: [LibraryAssetRecord] = []
    @Published private(set) var tags: [TagRecord] = []
    @Published private(set) var selectedAssetTags: [TagRecord] = []
    @Published private(set) var photoPresets: [PhotoPreset] = []
    @Published private(set) var batchTasks: [StudioBackgroundTask] = []
    @Published private(set) var latestBatchEditReport: BatchEditReport?
    @Published private(set) var latestBatchExportReport: BatchExportReport?
    @Published private(set) var hasMoreLibraryAssets = false
    @Published private(set) var isLoadingLibraryAssets = false
    @Published private(set) var libraryError: String?

    private let assetPageSize = 250
    private var hasBootstrapped = false
    private var catalogStore: CatalogStore?
    private var mediaRootStore: MediaRootStore?
    private var scanCoordinator: ScanCoordinator?
    private var thumbnailLoader: ThumbnailLoader?
    private var photoEditingService: PhotoEditingService?
    private var presetRepository: PresetRepository?
    private let batchTaskCenter = BackgroundTaskCenter()
    private var batchWorkerTasks: [UUID: Task<Void, Never>] = [:]
    private var copiedPhotoContent: PhotoPresetContent?
    private var activeLibraryQuery = LibraryQuery.all
    private var nextAssetOffset = 0
    private var libraryRequestID = UUID()
    private var lastLibraryAssetRefreshAt = Date.distantPast

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        do {
            let paths = try CatalogPaths.live()
            let catalogStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
            try await catalogStore.bootstrap()
            let mediaRootStore = MediaRootStore(catalogStore: catalogStore)
            let scanCoordinator = ScanCoordinator(catalogStore: catalogStore, mediaRootStore: mediaRootStore)

            self.catalogStore = catalogStore
            self.mediaRootStore = mediaRootStore
            self.scanCoordinator = scanCoordinator
            self.thumbnailLoader = ThumbnailLoader(
                diskStore: ThumbnailStore(directoryURL: paths.thumbnailsDirectory),
                mediaRootStore: mediaRootStore
            )
            self.photoEditingService = PhotoEditingService(
                catalogStore: catalogStore,
                mediaRootStore: mediaRootStore,
                lutRepository: LUTRepository(directoryURL: paths.lutDirectory)
            )
            self.presetRepository = PresetRepository(catalogStore: catalogStore)
            startupState = .ready(paths)
            await refreshLibrary(validateRoots: true)
            await reloadLibraryAssets(query: .all)
            await reloadPhotoPresets()
            await refreshBatchTasks()
            AppLogger.app.info("Catalog bootstrap completed")
        } catch {
            AppLogger.app.error("Catalog bootstrap failed: \(error.localizedDescription, privacy: .public)")
            startupState = .failed(error.localizedDescription)
        }
    }

    func presentAddFolderPanel() {
        guard case .ready = startupState else { return }

        let panel = NSOpenPanel()
        panel.title = "添加文件夹到资料库"
        panel.message = "Mac Photo Studio 只索引此文件夹，不会复制、移动或修改其中的原始媒体文件。"
        panel.prompt = "添加文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        Task {
            await addMediaRoot(directoryURL)
        }
    }

    func addMediaRoot(_ directoryURL: URL) async {
        guard let mediaRootStore, let scanCoordinator else { return }

        do {
            libraryError = nil
            let root = try await mediaRootStore.add(directoryURL: directoryURL)
            _ = await scanCoordinator.startScan(rootID: root.id)
            await refreshLibrary()
            await reloadLibraryAssets(query: activeLibraryQuery)
        } catch {
            report(error, activity: "Adding media root")
        }
    }

    func startScan(for rootID: UUID) async {
        guard let scanCoordinator else { return }
        _ = await scanCoordinator.startScan(rootID: rootID)
        await refreshLibrary()
    }

    func pause(scanID: UUID) async {
        await scanCoordinator?.pause(scanID: scanID)
        await refreshLibrary()
    }

    func resume(scanID: UUID) async {
        await scanCoordinator?.resume(scanID: scanID)
        await refreshLibrary()
    }

    func cancel(scanID: UUID) async {
        await scanCoordinator?.cancel(scanID: scanID)
        await refreshLibrary()
    }

    func refreshLibrary(validateRoots: Bool = false) async {
        guard let catalogStore, let scanCoordinator else {
            await refreshBatchTasks()
            return
        }
        if validateRoots {
            await scanCoordinator.refreshRootAvailability()
        }

        do {
            mediaRoots = try await catalogStore.mediaRoots()
            scanStatuses = await scanCoordinator.statuses()
            tags = try await catalogStore.tags()
            let shouldReloadAssets = scanStatuses.contains {
                $0.state == .completed && ($0.finishedAt ?? .distantPast) > lastLibraryAssetRefreshAt
            }
            if shouldReloadAssets {
                await reloadLibraryAssets(query: activeLibraryQuery)
            }
        } catch {
            report(error, activity: "Refreshing library")
        }
        await refreshBatchTasks()
    }

    func reloadLibraryAssets(query: LibraryQuery) async {
        guard let catalogStore else { return }
        activeLibraryQuery = query
        nextAssetOffset = 0
        libraryAssets = []
        hasMoreLibraryAssets = false
        let requestID = UUID()
        libraryRequestID = requestID
        isLoadingLibraryAssets = true

        do {
            let records = try await catalogStore.libraryAssets(query: query, limit: assetPageSize + 1, offset: 0)
            guard requestID == libraryRequestID else { return }
            libraryAssets = Array(records.prefix(assetPageSize))
            nextAssetOffset = libraryAssets.count
            hasMoreLibraryAssets = records.count > assetPageSize
            lastLibraryAssetRefreshAt = .now
            isLoadingLibraryAssets = false
        } catch {
            guard requestID == libraryRequestID else { return }
            isLoadingLibraryAssets = false
            report(error, activity: "Loading library assets")
        }
    }

    func loadMoreLibraryAssets() async {
        guard let catalogStore, hasMoreLibraryAssets, !isLoadingLibraryAssets else { return }
        let requestID = libraryRequestID
        let offset = nextAssetOffset
        isLoadingLibraryAssets = true

        do {
            let records = try await catalogStore.libraryAssets(
                query: activeLibraryQuery,
                limit: assetPageSize + 1,
                offset: offset
            )
            guard requestID == libraryRequestID else { return }
            let newRecords = Array(records.prefix(assetPageSize))
            libraryAssets.append(contentsOf: newRecords)
            nextAssetOffset += newRecords.count
            hasMoreLibraryAssets = records.count > assetPageSize
            isLoadingLibraryAssets = false
        } catch {
            guard requestID == libraryRequestID else { return }
            isLoadingLibraryAssets = false
            report(error, activity: "Loading more library assets")
        }
    }

    func thumbnailData(for asset: LibraryAssetRecord, maximumPixelSize: Int) async -> Data? {
        guard let thumbnailLoader, let root = mediaRoots.first(where: { $0.id == asset.rootID }) else { return nil }
        do {
            return try await thumbnailLoader.thumbnailData(
                for: asset,
                root: root,
                maximumPixelSize: maximumPixelSize
            )
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.app.debug("Thumbnail unavailable for \(asset.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func setRating(_ rating: Int, for assetIDs: [UUID]) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.updateRating(rating, for: assetIDs)
            await reloadLibraryAssets(query: activeLibraryQuery)
        } catch {
            report(error, activity: "Updating rating")
        }
    }

    func setFlag(_ flag: AssetFlag, for assetIDs: [UUID]) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.updateFlag(flag, for: assetIDs)
            await reloadLibraryAssets(query: activeLibraryQuery)
        } catch {
            report(error, activity: "Updating flag")
        }
    }

    func createTag(named name: String) async -> TagRecord? {
        guard let catalogStore else { return nil }
        do {
            let tag = try await catalogStore.createTag(named: name)
            tags = try await catalogStore.tags()
            return tag
        } catch {
            report(error, activity: "Creating tag")
            return nil
        }
    }

    func renameTag(_ tag: TagRecord, to name: String) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.renameTag(tag.id, to: name)
            tags = try await catalogStore.tags()
        } catch {
            report(error, activity: "Renaming tag")
        }
    }

    func deleteTag(_ tag: TagRecord) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.deleteTag(tag.id)
            tags = try await catalogStore.tags()
            selectedAssetTags.removeAll { $0.id == tag.id }
            await reloadLibraryAssets(query: activeLibraryQuery.tagID == tag.id ? .all : activeLibraryQuery)
        } catch {
            report(error, activity: "Deleting tag")
        }
    }

    func addTag(_ tag: TagRecord, to assetIDs: [UUID]) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.addTag(tag.id, to: assetIDs)
            if assetIDs.count == 1, let assetID = assetIDs.first {
                selectedAssetTags = try await catalogStore.tags(for: assetID)
            }
        } catch {
            report(error, activity: "Adding tag to assets")
        }
    }

    func removeTag(_ tag: TagRecord, from assetIDs: [UUID]) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.removeTag(tag.id, from: assetIDs)
            if assetIDs.count == 1, let assetID = assetIDs.first {
                selectedAssetTags = try await catalogStore.tags(for: assetID)
            }
        } catch {
            report(error, activity: "Removing tag from assets")
        }
    }

    func loadTags(for assetID: UUID?) async {
        guard let catalogStore, let assetID else {
            selectedAssetTags = []
            return
        }
        do {
            selectedAssetTags = try await catalogStore.tags(for: assetID)
        } catch {
            report(error, activity: "Loading asset tags")
        }
    }

    func photoEditState(for assetID: UUID) async -> PhotoEditState? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.editState(for: assetID)
        } catch {
            report(error, activity: "Loading photo edit state")
            return nil
        }
    }

    func savePhotoEditState(_ state: PhotoEditState, for assetID: UUID) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            try await photoEditingService.save(state, for: assetID)
            return true
        } catch {
            report(error, activity: "Saving photo edit state")
            return false
        }
    }

    func reloadPhotoPresets() async {
        guard let presetRepository else { return }
        do {
            photoPresets = try await presetRepository.presets()
        } catch {
            report(error, activity: "Loading presets")
        }
    }

    func createPhotoPreset(named name: String, from assetID: UUID) async -> Bool {
        guard let presetRepository, let photoEditingService else { return false }
        do {
            let state = try await photoEditingService.editState(for: assetID)
            _ = try await presetRepository.create(named: name, content: state.presetContent)
            await reloadPhotoPresets()
            return true
        } catch {
            report(error, activity: "Creating preset")
            return false
        }
    }

    func renamePhotoPreset(_ preset: PhotoPreset, to name: String) async -> Bool {
        guard let presetRepository else { return false }
        do {
            try await presetRepository.rename(preset, to: name)
            await reloadPhotoPresets()
            return true
        } catch {
            report(error, activity: "Renaming preset")
            return false
        }
    }

    func setPhotoPresetFavorite(_ isFavorite: Bool, preset: PhotoPreset) async -> Bool {
        guard let presetRepository else { return false }
        do {
            try await presetRepository.setFavorite(isFavorite, for: preset)
            await reloadPhotoPresets()
            return true
        } catch {
            report(error, activity: "Updating preset favorite")
            return false
        }
    }

    func deletePhotoPreset(_ preset: PhotoPreset) async -> Bool {
        guard let presetRepository else { return false }
        do {
            try await presetRepository.delete(preset)
            await reloadPhotoPresets()
            return true
        } catch {
            report(error, activity: "Deleting preset")
            return false
        }
    }

    func exportPhotoPreset(_ preset: PhotoPreset, to destinationURL: URL) async -> Bool {
        guard let presetRepository else { return false }
        do {
            try await presetRepository.export(preset, to: destinationURL)
            return true
        } catch {
            report(error, activity: "Exporting preset")
            return false
        }
    }

    func importPhotoPreset(from sourceURL: URL) async -> Bool {
        guard let presetRepository else { return false }
        do {
            _ = try await presetRepository.importPreset(from: sourceURL)
            await reloadPhotoPresets()
            return true
        } catch {
            report(error, activity: "Importing preset")
            return false
        }
    }

    func copyPhotoEdits(from assetID: UUID) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            copiedPhotoContent = try await photoEditingService.editState(for: assetID).presetContent
            return true
        } catch {
            report(error, activity: "Copying photo edits")
            return false
        }
    }

    var hasCopiedPhotoEdits: Bool { copiedPhotoContent != nil }

    func pastePhotoEdits(
        to assetIDs: [UUID],
        components: Set<PhotoEditComponent> = PhotoEditComponent.allPresetComponents
    ) async -> BatchEditReport? {
        guard let copiedPhotoContent else { return nil }
        return await applyPhotoEditContent(
            copiedPhotoContent,
            to: assetIDs,
            components: components,
            activity: "粘贴照片调整"
        )
    }

    func applyPhotoPreset(_ preset: PhotoPreset, to assetIDs: [UUID]) async -> BatchEditReport? {
        await applyPhotoEditContent(preset.content, to: assetIDs, activity: "应用预设")
    }

    func startBatchExport(
        assets: [LibraryAssetRecord],
        outputDirectoryURL: URL,
        options: PhotoExportOptions
    ) async -> UUID? {
        guard let photoEditingService else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: outputDirectoryURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            libraryError = "导出目录不可用。"
            return nil
        }

        let photos = uniquePhotos(from: assets)
        guard !photos.isEmpty else {
            libraryError = "请选择至少一张可导出的照片。"
            return nil
        }
        let task = await batchTaskCenter.enqueue(
            kind: .photoExport,
            title: "导出 \(photos.count) 张照片"
        )
        await refreshBatchTasks()
        let taskCenter = batchTaskCenter
        let worker = Task { [weak self, photoEditingService] in
            let didStartAccess = outputDirectoryURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    outputDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try await taskCenter.start(task.id)
                await self?.refreshBatchTasks()
                let report = try await photoEditingService.batchExport(
                    assets: photos,
                    outputDirectoryURL: outputDirectoryURL,
                    options: options,
                    collisionResolver: { [weak self] collision in
                        guard let self else { return .cancel }
                        return await self.askForExportCollisionResolution(collision)
                    },
                    reportProgress: { progress in
                        try? await taskCenter.updateProgress(progress, for: task.id)
                    }
                )
                try await taskCenter.complete(task.id)
                await self?.finishBatchExport(report, taskID: task.id)
            } catch is CancellationError {
                try? await taskCenter.cancel(task.id)
                await self?.finishCancelledBatchTask(task.id)
            } catch {
                try? await taskCenter.fail(task.id)
                await self?.finishFailedBatchTask(task.id, error: error)
            }
        }
        batchWorkerTasks[task.id] = worker
        return task.id
    }

    func cancelBatchTask(_ taskID: UUID) async {
        batchWorkerTasks[taskID]?.cancel()
        try? await batchTaskCenter.cancel(taskID)
        await refreshBatchTasks()
    }

    func refreshBatchTasks() async {
        batchTasks = await batchTaskCenter.allTasks()
    }

    func rawEditState(for assetID: UUID) async -> RAWEditState? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.rawEditState(for: assetID)
        } catch {
            report(error, activity: "Loading RAW edit state")
            return nil
        }
    }

    func saveRAWEditState(_ state: RAWEditState, for assetID: UUID) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            try await photoEditingService.saveRaw(state, for: assetID)
            return true
        } catch {
            report(error, activity: "Saving RAW edit state")
            return false
        }
    }

    func renderPhotoPreview(
        for asset: LibraryAssetRecord,
        state: PhotoEditState,
        maximumPixelSize: Int = 2_048
    ) async -> PhotoRenderResult? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.renderPreview(
                for: asset,
                state: state,
                maximumPixelSize: maximumPixelSize
            )
        } catch is CancellationError {
            return nil
        } catch {
            report(error, activity: "Rendering photo preview")
            return nil
        }
    }

    func renderRAWPreview(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        maximumPixelSize: Int = 2_048
    ) async -> RAWRenderResult? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.renderRAWPreview(
                for: asset, rawState: rawState, photoState: photoState, maximumPixelSize: maximumPixelSize
            )
        } catch is CancellationError {
            return nil
        } catch {
            report(error, activity: "Rendering RAW preview")
            return nil
        }
    }

    func exportRAW(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        destinationURL: URL,
        format: RAWExportFormat
    ) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            try await photoEditingService.exportRAW(
                for: asset,
                rawState: rawState,
                photoState: photoState,
                destinationURL: destinationURL,
                format: format
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            report(error, activity: "Exporting RAW")
            return false
        }
    }

    func photoLUTLibrary() async -> LUTLibrary? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.lutLibrary()
        } catch {
            report(error, activity: "Loading LUT library")
            return nil
        }
    }

    func importLUT(from url: URL) async -> CubeLUT? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.importLUT(from: url)
        } catch {
            report(error, activity: "Importing LUT")
            return nil
        }
    }

    func renameLUT(identifier: UUID, to title: String) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            try await photoEditingService.renameLUT(identifier: identifier, to: title)
            return true
        } catch {
            report(error, activity: "Renaming LUT")
            return false
        }
    }

    func deleteLUT(identifier: UUID) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            try await photoEditingService.deleteLUT(identifier: identifier)
            return true
        } catch {
            report(error, activity: "Deleting LUT")
            return false
        }
    }

    func setLUTFavorite(_ isFavorite: Bool, identifier: UUID) async -> Bool {
        guard let photoEditingService else { return false }
        do {
            try await photoEditingService.setLUTFavorite(isFavorite, identifier: identifier)
            return true
        } catch {
            report(error, activity: "Updating LUT favorite")
            return false
        }
    }

    private func report(_ error: Error, activity: String) {
        libraryError = error.localizedDescription
        AppLogger.app.error("\(activity, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    private func applyPhotoEditContent(
        _ content: PhotoPresetContent,
        to assetIDs: [UUID],
        components: Set<PhotoEditComponent> = PhotoEditComponent.allPresetComponents,
        activity: String
    ) async -> BatchEditReport? {
        guard let photoEditingService else { return nil }
        let task = await batchTaskCenter.enqueue(kind: .photoBatchEdit, title: "\(activity)（\(assetIDs.count) 张）")
        do {
            try await batchTaskCenter.start(task.id)
            await refreshBatchTasks()
            let result = try await photoEditingService.applyPresetContent(
                content,
                to: assetIDs,
                components: components,
                reportProgress: { [batchTaskCenter] progress in
                    try? await batchTaskCenter.updateProgress(progress, for: task.id)
                }
            )
            try await batchTaskCenter.complete(task.id)
            latestBatchEditReport = result
            await refreshBatchTasks()
            return result
        } catch is CancellationError {
            try? await batchTaskCenter.cancel(task.id)
            await refreshBatchTasks()
            return nil
        } catch {
            try? await batchTaskCenter.fail(task.id)
            await refreshBatchTasks()
            report(error, activity: activity)
            return nil
        }
    }

    private func finishBatchExport(_ report: BatchExportReport, taskID: UUID) async {
        latestBatchExportReport = report
        batchWorkerTasks[taskID] = nil
        await refreshBatchTasks()
    }

    private func finishCancelledBatchTask(_ taskID: UUID) async {
        batchWorkerTasks[taskID] = nil
        await refreshBatchTasks()
    }

    private func finishFailedBatchTask(_ taskID: UUID, error: Error) async {
        batchWorkerTasks[taskID] = nil
        await refreshBatchTasks()
        report(error, activity: "Batch photo export")
    }

    private func askForExportCollisionResolution(_ collision: ExportCollision) -> ExportCollisionResolution {
        let alert = NSAlert()
        alert.messageText = "导出文件已存在"
        alert.informativeText = "“\(collision.destinationURL.lastPathComponent)”已存在。请选择此文件的处理方式。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "自动重命名")
        alert.addButton(withTitle: "跳过")
        alert.addButton(withTitle: "取消批量导出")
        return switch alert.runModal() {
        case .alertFirstButtonReturn: .overwrite
        case .alertSecondButtonReturn: .rename
        case .alertThirdButtonReturn: .skip
        default: .cancel
        }
    }

    private func uniquePhotos(from assets: [LibraryAssetRecord]) -> [LibraryAssetRecord] {
        var identifiers = Set<UUID>()
        return assets.filter { $0.mediaType == .photo && identifiers.insert($0.id).inserted }
    }
}
