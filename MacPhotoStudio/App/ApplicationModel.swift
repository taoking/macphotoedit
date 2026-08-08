import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

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
    @Published private(set) var albums: [AlbumRecord] = []
    @Published private(set) var assetStacks: [AssetStackRecord] = []
    @Published private(set) var selectedAssetTags: [TagRecord] = []
    @Published private(set) var photoPresets: [PhotoPreset] = []
    @Published private(set) var batchTasks: [StudioBackgroundTask] = []
    @Published private(set) var latestBatchEditReport: BatchEditReport?
    @Published private(set) var latestBatchExportReport: BatchExportReport?
    @Published private(set) var latestVideoExportReport: VideoExportReport?
    @Published private(set) var latestVideoProxyReport: VideoProxyReport?
    @Published private(set) var latestDuplicateScanReport: DuplicateScanReport?
    @Published private(set) var latestSimilarPhotoScanReport: SimilarPhotoScanReport?
    @Published private(set) var latestTrashMoveReport: TrashMoveReport?
    @Published private(set) var latestRAWDiagnosticReportURL: URL?
    @Published private(set) var latestStillImageColorDiagnosticReportURL: URL?
    @Published private(set) var latestMediaRootAvailabilityReportURL: URL?
    @Published private(set) var latestSimilarPhotoBenchmarkReportURL: URL?
    @Published private(set) var hasMoreLibraryAssets = false
    @Published private(set) var isLoadingLibraryAssets = false
    @Published private(set) var libraryError: String?

    private let assetPageSize = 250
    private var hasBootstrapped = false
    private var catalogStore: CatalogStore?
    private var mediaRootStore: MediaRootStore?
    private var scanCoordinator: ScanCoordinator?
    private var thumbnailLoader: ThumbnailLoader?
    private var videoFilmstripLoader: VideoFilmstripLoader?
    private var videoCoordinator: VideoEditingCoordinator?
    private var photoEditingService: PhotoEditingService?
    private var presetRepository: PresetRepository?
    private var duplicateScanner: ExactDuplicateScanner?
    private var similarPhotoScanner: SimilarPhotoScanner?
    private var mediaTrashService: MediaTrashService?
    private let taskCoordinator = TaskCoordinator()
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
            self.videoFilmstripLoader = VideoFilmstripLoader(
                diskStore: VideoFilmstripStore(directoryURL: paths.videoFilmstripsDirectory),
                mediaRootStore: mediaRootStore
            )
            self.videoCoordinator = VideoEditingCoordinator(
                catalogStore: catalogStore,
                mediaRootStore: mediaRootStore,
                lutDirectory: paths.lutDirectory,
                videoProxiesDirectory: paths.videoProxiesDirectory
            )
            self.photoEditingService = PhotoEditingService(
                catalogStore: catalogStore,
                mediaRootStore: mediaRootStore,
                lutRepository: LUTRepository(directoryURL: paths.lutDirectory)
            )
            self.presetRepository = PresetRepository(catalogStore: catalogStore)
            self.duplicateScanner = ExactDuplicateScanner(catalogStore: catalogStore, mediaRootStore: mediaRootStore)
            self.similarPhotoScanner = SimilarPhotoScanner(catalogStore: catalogStore, mediaRootStore: mediaRootStore)
            self.mediaTrashService = MediaTrashService(catalogStore: catalogStore, mediaRootStore: mediaRootStore)
            startupState = .ready(paths)
            await refreshLibrary(validateRoots: true)
            await reloadLibraryAssets(query: .all)
            await reloadPhotoPresets()
            await reloadAdvancedManagement()
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

    /// Opens a deliberately separate developer action: the selected RAW is
    /// read in place and the only retained result is a text report in the app's
    /// Application Support/logs directory.
    func presentRAWDiagnosticPanel() {
        guard case .ready = startupState else { return }
        let panel = NSOpenPanel()
        panel.title = "运行 RAW 诊断"
        panel.message = "选择 ARW 或 DNG。诊断只读取原始 RAW；临时导出会自动删除，报告写入应用日志目录。"
        panel.prompt = "运行诊断"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "arw"),
            UTType(filenameExtension: "dng")
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        guard let outputColorSpace = chooseRAWDiagnosticOutputColorSpace() else { return }
        Task { await runRAWDiagnostic(for: sourceURL, outputColorSpace: outputColorSpace) }
    }

    func runRAWDiagnostic(
        for sourceURL: URL,
        outputColorSpace: PhotoColorSpace = .sRGB
    ) async {
        guard case let .ready(paths) = startupState else { return }
        let diagnosticReport = await RAWMediaDiagnosticService.inspect(
            sourceURL: sourceURL,
            outputColorSpace: outputColorSpace
        )
        do {
            let reportURL = try diagnosticReport.write(to: paths.logsDirectory)
            latestRAWDiagnosticReportURL = reportURL
            AppLogger.app.info("RAW diagnostic report written to \(reportURL.path(percentEncoded: false), privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([reportURL])
        } catch {
            report(error, activity: "Writing RAW diagnostic report")
        }
    }

    private func chooseRAWDiagnosticOutputColorSpace() -> PhotoColorSpace? {
        let alert = NSAlert()
        alert.messageText = "RAW 诊断输出色彩空间"
        alert.informativeText = "诊断会在临时目录执行一次 full-resolution JPEG 导出并核对嵌入 ICC；原始 RAW 不会被修改。"
        alert.addButton(withTitle: "sRGB")
        alert.addButton(withTitle: "Display P3")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .sRGB
        case .alertSecondButtonReturn: return .displayP3
        default: return nil
        }
    }

    /// Selects a real still image and a user-authorised output directory for
    /// the Phase 16.5 colour validation matrix. The service creates a unique
    /// child directory, so this command never overwrites the selected source
    /// or an existing user export.
    func presentStillImageColorDiagnosticPanels() {
        guard case .ready = startupState else { return }
        let sourcePanel = NSOpenPanel()
        sourcePanel.title = "运行静态图像色彩验证"
        sourcePanel.message = "选择 JPEG、HEIC、PNG 或 TIFF。原始文件只读；验证会为四个 SDR 色彩空间创建新的导出文件。"
        sourcePanel.prompt = "选择图像"
        sourcePanel.canChooseFiles = true
        sourcePanel.canChooseDirectories = false
        sourcePanel.allowsMultipleSelection = false
        sourcePanel.allowedContentTypes = [
            .jpeg,
            .heic,
            .png,
            .tiff,
            UTType(filenameExtension: "heif")
        ].compactMap { $0 }
        guard sourcePanel.runModal() == .OK, let sourceURL = sourcePanel.url else { return }

        let outputPanel = NSOpenPanel()
        outputPanel.title = "选择色彩验证输出文件夹"
        outputPanel.message = "应用将在此文件夹内创建唯一的验证子目录，写入 JPEG、HEIC（如系统支持）和 TIFF 的 sRGB、Display P3、Rec.709、Rec.2020 SDR 新文件。"
        outputPanel.prompt = "选择输出文件夹"
        outputPanel.canChooseFiles = false
        outputPanel.canChooseDirectories = true
        outputPanel.allowsMultipleSelection = false
        outputPanel.canCreateDirectories = false
        guard outputPanel.runModal() == .OK, let outputRootURL = outputPanel.url else { return }

        Task { await runStillImageColorDiagnostic(sourceURL: sourceURL, outputRootURL: outputRootURL) }
    }

    func runStillImageColorDiagnostic(sourceURL: URL, outputRootURL: URL) async {
        guard case let .ready(paths) = startupState else { return }
        let diagnosticReport = await StillImageColorDiagnosticService.validate(
            sourceURL: sourceURL,
            outputRootURL: outputRootURL
        )
        do {
            let reportURL = try diagnosticReport.write(to: paths.logsDirectory)
            latestStillImageColorDiagnosticReportURL = reportURL
            AppLogger.app.info("Still image color validation report written to \(reportURL.path(percentEncoded: false), privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([diagnosticReport.validationDirectoryURL ?? reportURL])
        } catch {
            report(error, activity: "Writing still image color validation report")
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

    func presentRelinkPanel(for root: MediaRootRecord) {
        guard case .ready = startupState else { return }
        let panel = NSOpenPanel()
        panel.title = "重新定位媒体文件夹"
        panel.message = "选择移动后的根文件夹。重新扫描后，匹配的相对路径会保留已有评分、标签与编辑状态。"
        panel.prompt = "重新定位"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        Task { await relinkMediaRoot(root, to: directoryURL) }
    }

    func relinkMediaRoot(_ root: MediaRootRecord, to directoryURL: URL) async {
        guard let mediaRootStore, let scanCoordinator else { return }
        do {
            libraryError = nil
            let relinkedRoot = try await mediaRootStore.relink(root, to: directoryURL)
            _ = await scanCoordinator.startScan(rootID: relinkedRoot.id)
            await refreshLibrary()
        } catch {
            report(error, activity: "Relinking media root")
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
            albums = try await catalogStore.albums()
            assetStacks = try await catalogStore.assetStacks()
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

    func runMediaRootAvailabilityDiagnostics() async {
        guard case .ready(let paths) = startupState,
              let catalogStore,
              let mediaRootStore
        else { return }

        do {
            libraryError = nil
            let roots = try await catalogStore.mediaRoots()
            var diagnostics: [MediaRootAvailabilityDiagnostic] = []
            diagnostics.reserveCapacity(roots.count)
            for root in roots {
                diagnostics.append(await mediaRootStore.diagnoseAccess(to: root))
            }
            let reportURL = try MediaRootAvailabilityReport(
                generatedAt: .now,
                diagnostics: diagnostics
            ).write(to: paths.logsDirectory)
            latestMediaRootAvailabilityReportURL = reportURL
            AppLogger.app.info("Media-root availability report written to \(reportURL.path(percentEncoded: false), privacy: .public)")
            await refreshLibrary()
            NSWorkspace.shared.activateFileViewerSelecting([reportURL])
        } catch {
            report(error, activity: "Diagnosing media-root availability")
        }
    }

    func runSimilarPhotoBenchmark() async {
        guard case .ready(let paths) = startupState,
              let similarPhotoScanner
        else { return }

        do {
            libraryError = nil
            let liveReport = try await similarPhotoScanner.scan()
            let catalogOnlyBenchmarks = try await SimilarPhotoBenchmarkService.runCatalogOnly()
            let reportURL = try SimilarPhotoBenchmarkReport(
                generatedAt: .now,
                liveMediaHashedCount: liveReport.hashedCount,
                liveMediaReusedHashCount: liveReport.reusedHashCount,
                liveMediaMetrics: liveReport.metrics,
                catalogOnlyBenchmarks: catalogOnlyBenchmarks
            ).write(to: paths.logsDirectory)
            latestSimilarPhotoScanReport = liveReport
            latestSimilarPhotoBenchmarkReportURL = reportURL
            AppLogger.app.info("Similar-photo benchmark report written to \(reportURL.path(percentEncoded: false), privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([reportURL])
        } catch is CancellationError {
            libraryError = "相似照片基准已取消。"
        } catch {
            report(error, activity: "Benchmarking similar photos")
        }
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

    /// Loads only Catalog metadata for the Similar Group review sheet. The
    /// sheet obtains visible previews separately through ThumbnailStore.
    func similarPhotoReviewAssets(for assetIDs: [UUID]) async -> [LibraryAssetRecord] {
        guard let catalogStore else { return [] }
        do {
            let records = try await catalogStore.libraryAssets(ids: assetIDs)
            let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return assetIDs.compactMap { recordByID[$0] }
        } catch {
            report(error, activity: "Loading similar-photo review metadata")
            return []
        }
    }

    func videoFilmstripData(for asset: LibraryAssetRecord) async -> [Data]? {
        guard let videoFilmstripLoader,
              let root = mediaRoots.first(where: { $0.id == asset.rootID })
        else { return nil }
        do {
            return try await videoFilmstripLoader.filmstripData(for: asset, root: root)
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.app.debug("Filmstrip unavailable for \(asset.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func makeVideoPlaybackSession(
        for asset: LibraryAssetRecord,
        preferProxy: Bool = true
    ) async -> VideoPlaybackSession? {
        guard asset.mediaType == .video else { return nil }
        guard asset.availability == .available else {
            libraryError = "视频当前不可访问。"
            return nil
        }
        guard let videoCoordinator,
              let root = mediaRoots.first(where: { $0.id == asset.rootID })
        else { return nil }

        do {
            return try await videoCoordinator.makePlaybackSession(
                for: asset,
                root: root,
                preferProxy: preferProxy
            )
        } catch {
            report(error, activity: "Preparing video playback")
            return nil
        }
    }

    func videoEditState(for assetID: UUID) async -> VideoEditState? {
        guard let videoCoordinator else { return nil }
        do {
            return try await videoCoordinator.editState(for: assetID)
        } catch {
            report(error, activity: "Loading video edit state")
            return nil
        }
    }

    func saveVideoEditState(_ state: VideoEditState, for assetID: UUID) async -> Bool {
        guard let videoCoordinator else { return false }
        do {
            try await videoCoordinator.save(state, for: assetID)
            await reloadLibraryAssets(query: activeLibraryQuery)
            return true
        } catch {
            report(error, activity: "Saving video edit state")
            return false
        }
    }

    func videoPreviewPayload(
        for session: VideoPlaybackSession,
        state: VideoEditState
    ) async -> VideoPreviewPayload? {
        guard let videoCoordinator else { return nil }
        do {
            return try await videoCoordinator.previewPayload(sourceURL: session.sourceURL, state: state)
        } catch is CancellationError {
            return nil
        } catch {
            report(error, activity: "Building video preview")
            return nil
        }
    }

    func videoLUTLibrary() async -> LUTLibrary? {
        guard let videoCoordinator else { return nil }
        do {
            return try await videoCoordinator.lutLibrary()
        } catch {
            report(error, activity: "Loading video LUT library")
            return nil
        }
    }

    func startVideoExport(
        asset: LibraryAssetRecord,
        state: VideoEditState,
        outputDirectoryURL: URL,
        options: VideoExportOptions
    ) async -> UUID? {
        guard let videoCoordinator else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: outputDirectoryURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            libraryError = "视频导出目录不可用。"
            return nil
        }
        guard asset.mediaType == .video else {
            libraryError = "请选择一个可导出的视频。"
            return nil
        }
        guard asset.videoIsHDR != true || (HDRVideoCapabilities.supportsEditing && HDRVideoCapabilities.supportsExport) else {
            libraryError = "当前编辑与导出管线仅支持 SDR；HDR 视频保持原生播放，不会用 SDR 管线处理。"
            return nil
        }

        let initialURL = outputDirectoryURL
            .appending(path: options.namingRule.baseFilename(for: asset))
            .appendingPathExtension(options.format.filenameExtension)
        let destination: (url: URL?, allowsOverwrite: Bool)
        do {
            destination = try await ExportDestinationResolver.destination(
                initialURL: initialURL,
                sourceAssetID: asset.id,
                policy: options.collisionPolicy,
                resolver: { [weak self] collision in
                    guard let self else { return .cancel }
                    return await self.askForExportCollisionResolution(collision)
                }
            )
        } catch is CancellationError {
            return nil
        } catch {
            report(error, activity: "Resolving video export destination")
            return nil
        }
        guard let destinationURL = destination.url else { return nil }

        let task = await taskCoordinator.enqueue(kind: .videoExport, title: "导出视频：\(asset.filename)")
        await refreshBatchTasks()
        let taskCoordinator = taskCoordinator
        let worker = Task { [weak self, videoCoordinator] in
            let didStartAccess = outputDirectoryURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    outputDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try await taskCoordinator.start(task.id)
                await self?.refreshBatchTasks()
                let report = try await videoCoordinator.export(
                    asset: asset,
                    state: state,
                    destinationURL: destinationURL,
                    options: options,
                    allowsOverwrite: destination.allowsOverwrite,
                    reportProgress: { progress in
                        try? await taskCoordinator.updateProgress(progress, for: task.id)
                    }
                )
                try await taskCoordinator.complete(task.id)
                await self?.finishVideoExport(report, taskID: task.id)
            } catch is CancellationError {
                try? await taskCoordinator.cancel(task.id)
                await self?.finishCancelledBatchTask(task.id)
            } catch {
                try? await taskCoordinator.fail(task.id)
                await self?.finishFailedVideoExport(task.id, error: error)
            }
        }
        taskCoordinator.register(worker: worker, for: task.id)
        return task.id
    }

    func startVideoProxyGeneration(
        for asset: LibraryAssetRecord,
        options: VideoProxyOptions = .init()
    ) async -> UUID? {
        guard let videoCoordinator else { return nil }
        guard asset.mediaType == .video, asset.availability == .available else {
            libraryError = "请选择一个当前可访问的视频生成 Proxy。"
            return nil
        }
        guard asset.videoIsHDR != true || HDRVideoCapabilities.supportsProxy else {
            libraryError = "HDR 视频 Proxy 需要保留 HDR 色彩契约；当前不会使用 SDR Proxy 替代原视频。"
            return nil
        }
        guard let root = mediaRoots.first(where: { $0.id == asset.rootID }) else { return nil }

        let source: VideoSourceAccess
        do {
            source = try await videoCoordinator.resolveAvailableSource(for: asset, root: root)
        } catch {
            report(error, activity: "Preparing video Proxy")
            return nil
        }

        let task = await taskCoordinator.enqueue(kind: .videoProxyGeneration, title: "生成视频 Proxy：\(asset.filename)")
        await refreshBatchTasks()
        let taskCoordinator = taskCoordinator
        let worker = Task { [weak self, videoCoordinator] in
            let didStartAccess = source.rootURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    source.rootURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try await taskCoordinator.start(task.id)
                await self?.refreshBatchTasks()
                let report = try await videoCoordinator.generateProxy(
                    for: asset,
                    sourceURL: source.sourceURL,
                    options: options,
                    reportProgress: { progress in
                        try? await taskCoordinator.updateProgress(progress, for: task.id)
                    }
                )
                try await taskCoordinator.complete(task.id)
                await self?.finishVideoProxyGeneration(report, taskID: task.id)
            } catch is CancellationError {
                try? await taskCoordinator.cancel(task.id)
                await self?.finishCancelledBatchTask(task.id)
            } catch {
                try? await taskCoordinator.fail(task.id)
                await self?.finishFailedVideoProxyGeneration(task.id, error: error)
            }
        }
        taskCoordinator.register(worker: worker, for: task.id)
        return task.id
    }

    func removeVideoProxy(for asset: LibraryAssetRecord) async -> Bool {
        guard let videoCoordinator else { return false }
        do {
            try await videoCoordinator.removeProxy(for: asset)
            if latestVideoProxyReport?.assetID == asset.id {
                latestVideoProxyReport = nil
            }
            return true
        } catch {
            report(error, activity: "Removing video Proxy")
            return false
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

    func reloadAdvancedManagement() async {
        guard let catalogStore else { return }
        do {
            albums = try await catalogStore.albums()
            assetStacks = try await catalogStore.assetStacks()
        } catch {
            report(error, activity: "Loading advanced photo management")
        }
    }

    func createAlbum(named name: String) async -> Bool {
        guard let catalogStore else { return false }
        do {
            _ = try await catalogStore.createAlbum(named: name)
            await reloadAdvancedManagement()
            return true
        } catch {
            report(error, activity: "Creating album")
            return false
        }
    }

    func createSmartAlbum(named name: String, criteria: SmartAlbumCriteria) async -> Bool {
        guard let catalogStore else { return false }
        do {
            _ = try await catalogStore.createSmartAlbum(named: name, criteria: criteria)
            await reloadAdvancedManagement()
            return true
        } catch {
            report(error, activity: "Creating smart album")
            return false
        }
    }

    func renameAlbum(_ album: AlbumRecord, to name: String) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.renameAlbum(album.id, to: name)
            await reloadAdvancedManagement()
        } catch {
            report(error, activity: "Renaming album")
        }
    }

    func updateSmartAlbum(_ album: AlbumRecord, criteria: SmartAlbumCriteria) async {
        guard let catalogStore, album.kind == .smartAlbum else { return }
        do {
            try await catalogStore.updateSmartAlbum(album.id, criteria: criteria)
            await reloadAdvancedManagement()
            if activeLibraryQuery.smartAlbumCriteria == album.criteria {
                await reloadLibraryAssets(query: LibraryQuery(smartAlbumCriteria: criteria))
            }
        } catch {
            report(error, activity: "Updating smart album")
        }
    }

    func deleteAlbum(_ album: AlbumRecord) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.deleteAlbum(album.id)
            await reloadAdvancedManagement()
            if activeLibraryQuery.albumID == album.id || activeLibraryQuery.smartAlbumCriteria == album.criteria {
                await reloadLibraryAssets(query: .all)
            }
        } catch {
            report(error, activity: "Deleting album")
        }
    }

    func addAssets(_ assetIDs: [UUID], toAlbum album: AlbumRecord) async {
        guard let catalogStore, album.kind == .album else { return }
        do {
            try await catalogStore.addAssets(assetIDs, toAlbum: album.id)
            await reloadLibraryAssets(query: activeLibraryQuery)
        } catch {
            report(error, activity: "Adding assets to album")
        }
    }

    func removeAssets(_ assetIDs: [UUID], fromAlbum album: AlbumRecord) async {
        guard let catalogStore, album.kind == .album else { return }
        do {
            try await catalogStore.removeAssets(assetIDs, fromAlbum: album.id)
            await reloadLibraryAssets(query: activeLibraryQuery)
        } catch {
            report(error, activity: "Removing assets from album")
        }
    }

    func createStack(kind: AssetStackKind, title: String, assets: [LibraryAssetRecord]) async -> Bool {
        guard let catalogStore else { return false }
        let uniqueAssets = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        guard uniqueAssets.count >= 2 else {
            libraryError = "堆栈至少需要两个项目。"
            return false
        }
        if kind == .rawJPEG, !isMatchingRAWJPEGPair(Array(uniqueAssets)) {
            libraryError = "RAW + JPEG 堆栈需要选择同一文件夹、同名的一对 RAW 与 JPEG。"
            return false
        }
        do {
            _ = try await catalogStore.createStack(kind: kind, title: title, assetIDs: Array(uniqueAssets.map(\.id)))
            await reloadAdvancedManagement()
            return true
        } catch {
            report(error, activity: "Creating stack")
            return false
        }
    }

    func deleteStack(_ stack: AssetStackRecord) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.deleteStack(stack.id)
            await reloadAdvancedManagement()
            if activeLibraryQuery.stackID == stack.id {
                await reloadLibraryAssets(query: .all)
            }
        } catch {
            report(error, activity: "Deleting stack")
        }
    }

    func removeAssets(_ assetIDs: [UUID], fromStack stack: AssetStackRecord) async {
        guard let catalogStore else { return }
        do {
            try await catalogStore.removeAssets(assetIDs, fromStack: stack.id)
            await reloadAdvancedManagement()
            await reloadLibraryAssets(query: activeLibraryQuery)
        } catch {
            report(error, activity: "Removing assets from stack")
        }
    }

    func startExactDuplicateScan() async -> UUID? {
        guard let duplicateScanner else { return nil }
        let task = await taskCoordinator.enqueue(kind: .duplicateHashing, title: "查找精确重复项目")
        await refreshBatchTasks()
        let taskCoordinator = taskCoordinator
        let worker = Task { [weak self, duplicateScanner] in
            do {
                try await taskCoordinator.start(task.id)
                await self?.refreshBatchTasks()
                let report = try await duplicateScanner.scan { progress in
                    try? await taskCoordinator.updateProgress(progress, for: task.id)
                }
                try await taskCoordinator.complete(task.id)
                await self?.finishDuplicateScan(report, taskID: task.id)
            } catch is CancellationError {
                try? await taskCoordinator.cancel(task.id)
                await self?.finishCancelledBatchTask(task.id)
            } catch {
                try? await taskCoordinator.fail(task.id)
                await self?.finishFailedDuplicateTask(task.id, error: error)
            }
        }
        taskCoordinator.register(worker: worker, for: task.id)
        return task.id
    }

    func startSimilarPhotoScan() async -> UUID? {
        guard let similarPhotoScanner else { return nil }
        let task = await taskCoordinator.enqueue(kind: .perceptualHashing, title: "查找相似照片")
        await refreshBatchTasks()
        let taskCoordinator = taskCoordinator
        let worker = Task { [weak self, similarPhotoScanner] in
            do {
                try await taskCoordinator.start(task.id)
                await self?.refreshBatchTasks()
                let report = try await similarPhotoScanner.scan { progress in
                    try? await taskCoordinator.updateProgress(progress, for: task.id)
                }
                try await taskCoordinator.complete(task.id)
                await self?.finishSimilarPhotoScan(report, taskID: task.id)
            } catch is CancellationError {
                try? await taskCoordinator.cancel(task.id)
                await self?.finishCancelledBatchTask(task.id)
            } catch {
                try? await taskCoordinator.fail(task.id)
                await self?.finishFailedSimilarPhotoTask(task.id, error: error)
            }
        }
        taskCoordinator.register(worker: worker, for: task.id)
        return task.id
    }

    func moveAssetsToTrash(_ assets: [LibraryAssetRecord]) async -> TrashMoveReport? {
        guard let mediaTrashService, !assets.isEmpty else { return nil }
        do {
            let report = try await mediaTrashService.moveToTrash(assets)
            latestTrashMoveReport = report
            if !report.movedAssetIDs.isEmpty {
                await reloadLibraryAssets(query: activeLibraryQuery)
            }
            if !report.failures.isEmpty {
                libraryError = report.failures.joined(separator: "\n")
            }
            return report
        } catch is CancellationError {
            return nil
        } catch {
            report(error, activity: "Moving media to Trash")
            return nil
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
        let task = await taskCoordinator.enqueue(
            kind: .photoExport,
            title: "导出 \(photos.count) 张照片"
        )
        await refreshBatchTasks()
        let taskCoordinator = taskCoordinator
        let worker = Task { [weak self, photoEditingService] in
            let didStartAccess = outputDirectoryURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    outputDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try await taskCoordinator.start(task.id)
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
                        try? await taskCoordinator.updateProgress(progress, for: task.id)
                    }
                )
                try await taskCoordinator.complete(task.id)
                await self?.finishBatchExport(report, taskID: task.id)
            } catch is CancellationError {
                try? await taskCoordinator.cancel(task.id)
                await self?.finishCancelledBatchTask(task.id)
            } catch {
                try? await taskCoordinator.fail(task.id)
                await self?.finishFailedBatchTask(task.id, error: error)
            }
        }
        taskCoordinator.register(worker: worker, for: task.id)
        return task.id
    }

    func cancelBatchTask(_ taskID: UUID) async {
        taskCoordinator.cancelWorker(for: taskID)
        try? await taskCoordinator.cancel(taskID)
        await refreshBatchTasks()
    }

    func refreshBatchTasks() async {
        batchTasks = await taskCoordinator.allTasks()
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

    func importLUT(
        from url: URL,
        kind: LUTKind = .creative,
        technicalMetadata: TechnicalLUTMetadata? = nil
    ) async -> CubeLUT? {
        guard let photoEditingService else { return nil }
        do {
            return try await photoEditingService.importLUT(
                from: url,
                kind: kind,
                technicalMetadata: technicalMetadata
            )
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
        let task = await taskCoordinator.enqueue(kind: .photoBatchEdit, title: "\(activity)（\(assetIDs.count) 张）")
        do {
            try await taskCoordinator.start(task.id)
            await refreshBatchTasks()
            let result = try await photoEditingService.applyPresetContent(
                content,
                to: assetIDs,
                components: components,
                reportProgress: { [taskCoordinator] progress in
                    try? await taskCoordinator.updateProgress(progress, for: task.id)
                }
            )
            try await taskCoordinator.complete(task.id)
            latestBatchEditReport = result
            await refreshBatchTasks()
            return result
        } catch is CancellationError {
            try? await taskCoordinator.cancel(task.id)
            await refreshBatchTasks()
            return nil
        } catch {
            try? await taskCoordinator.fail(task.id)
            await refreshBatchTasks()
            report(error, activity: activity)
            return nil
        }
    }

    private func finishBatchExport(_ report: BatchExportReport, taskID: UUID) async {
        latestBatchExportReport = report
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
    }

    private func finishVideoExport(_ report: VideoExportReport, taskID: UUID) async {
        latestVideoExportReport = report
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
    }

    private func finishVideoProxyGeneration(_ report: VideoProxyReport, taskID: UUID) async {
        latestVideoProxyReport = report
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
    }

    private func finishDuplicateScan(_ report: DuplicateScanReport, taskID: UUID) async {
        latestDuplicateScanReport = report
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
    }

    private func finishSimilarPhotoScan(_ report: SimilarPhotoScanReport, taskID: UUID) async {
        latestSimilarPhotoScanReport = report
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
    }

    private func finishCancelledBatchTask(_ taskID: UUID) async {
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
    }

    private func finishFailedBatchTask(_ taskID: UUID, error: Error) async {
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
        report(error, activity: "Batch photo export")
    }

    private func finishFailedVideoExport(_ taskID: UUID, error: Error) async {
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
        report(error, activity: "Video export")
    }

    private func finishFailedVideoProxyGeneration(_ taskID: UUID, error: Error) async {
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
        report(error, activity: "Video Proxy generation")
    }

    private func finishFailedDuplicateTask(_ taskID: UUID, error: Error) async {
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
        report(error, activity: "Finding exact duplicates")
    }

    private func finishFailedSimilarPhotoTask(_ taskID: UUID, error: Error) async {
        taskCoordinator.releaseWorker(for: taskID)
        await refreshBatchTasks()
        report(error, activity: "Finding similar photos")
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

    private func isMatchingRAWJPEGPair(_ assets: [LibraryAssetRecord]) -> Bool {
        guard assets.count == 2,
              let raw = assets.first(where: { RAWFormat.isRAW($0.fileExtension) }),
              let jpeg = assets.first(where: { ["jpg", "jpeg"].contains($0.fileExtension.lowercased()) }),
              raw.rootID == jpeg.rootID
        else { return false }
        let rawURL = URL(filePath: raw.relativePath)
        let jpegURL = URL(filePath: jpeg.relativePath)
        return rawURL.deletingLastPathComponent().path(percentEncoded: false) == jpegURL.deletingLastPathComponent().path(percentEncoded: false)
            && rawURL.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(jpegURL.deletingPathExtension().lastPathComponent) == .orderedSame
    }
}
