import Foundation

struct ScanStatus: Identifiable, Sendable, Equatable {
    let id: UUID
    let rootID: UUID
    var state: BackgroundTaskState
    var progress: ScanProgress
    var errorMessage: String?
    let startedAt: Date
    var finishedAt: Date?
}

private actor ScanRunState {
    private var status: ScanStatus

    init(id: UUID, rootID: UUID, startedAt: Date) {
        status = ScanStatus(
            id: id,
            rootID: rootID,
            state: .queued,
            progress: ScanProgress(rootID: rootID, inspectedFiles: 0, discoveredMedia: 0, indexedMedia: 0, metadataFailures: 0),
            errorMessage: nil,
            startedAt: startedAt,
            finishedAt: nil
        )
    }

    func update(state: BackgroundTaskState) {
        status.state = state
    }

    func update(progress: ScanProgress) {
        status.progress = progress
    }

    func finish(state: BackgroundTaskState, errorMessage: String? = nil, at date: Date = .now) {
        status.state = state
        status.errorMessage = errorMessage
        status.finishedAt = date
    }

    func snapshot() -> ScanStatus {
        status
    }
}

private struct ActiveScanRun: Sendable {
    let rootID: UUID
    let control: ScanControl
    let state: ScanRunState
    let worker: Task<Void, Never>
}

actor ScanCoordinator {
    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore
    private let bookmarkStore: BookmarkStore
    private let taskCenter: BackgroundTaskCenter
    private let scanner: MediaScanner

    private var runs: [UUID: ActiveScanRun] = [:]
    private var activeRoots: Set<UUID> = []

    init(
        catalogStore: CatalogStore,
        mediaRootStore: MediaRootStore,
        bookmarkStore: BookmarkStore = BookmarkStore(),
        taskCenter: BackgroundTaskCenter = BackgroundTaskCenter(),
        scanner: MediaScanner = MediaScanner()
    ) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
        self.bookmarkStore = bookmarkStore
        self.taskCenter = taskCenter
        self.scanner = scanner
    }

    func startScan(rootID: UUID, now: Date = .now) async -> UUID? {
        guard !activeRoots.contains(rootID) else { return nil }

        let scanID = UUID()
        let control = ScanControl()
        let state = ScanRunState(id: scanID, rootID: rootID, startedAt: now)
        _ = await taskCenter.enqueue(kind: .scan, title: "扫描媒体库", id: scanID, now: now)
        try? await taskCenter.start(scanID, now: now)
        await state.update(state: .running)
        activeRoots.insert(rootID)

        let worker = Task.detached(priority: .utility) { [weak self, catalogStore, mediaRootStore, bookmarkStore, taskCenter, scanner] in
            await Self.runScan(
                scanID: scanID,
                rootID: rootID,
                catalogStore: catalogStore,
                mediaRootStore: mediaRootStore,
                bookmarkStore: bookmarkStore,
                taskCenter: taskCenter,
                scanner: scanner,
                control: control,
                state: state
            )
            await self?.markScanFinished(rootID: rootID)
        }
        runs[scanID] = ActiveScanRun(rootID: rootID, control: control, state: state, worker: worker)
        return scanID
    }

    func pause(scanID: UUID) async {
        guard let run = runs[scanID] else { return }
        await run.control.pause()
        guard (try? await taskCenter.pause(scanID)) != nil else { return }
        await run.state.update(state: .paused)
    }

    func resume(scanID: UUID) async {
        guard let run = runs[scanID] else { return }
        await run.control.resume()
        guard (try? await taskCenter.start(scanID)) != nil else { return }
        await run.state.update(state: .running)
    }

    func cancel(scanID: UUID) async {
        guard let run = runs[scanID] else { return }
        await run.control.cancel()
        run.worker.cancel()
        _ = try? await taskCenter.cancel(scanID)
        await run.state.finish(state: .cancelled)
    }

    func statuses() async -> [ScanStatus] {
        let snapshots = await runs.values.asyncMap { await $0.state.snapshot() }
        return snapshots.sorted { $0.startedAt > $1.startedAt }
    }

    func refreshRootAvailability() async {
        guard let roots = try? await catalogStore.mediaRoots() else { return }
        for root in roots {
            _ = await mediaRootStore.validateAccess(to: root)
        }
    }

    private func markScanFinished(rootID: UUID) {
        activeRoots.remove(rootID)
    }

    private static func runScan(
        scanID: UUID,
        rootID: UUID,
        catalogStore: CatalogStore,
        mediaRootStore: MediaRootStore,
        bookmarkStore: BookmarkStore,
        taskCenter: BackgroundTaskCenter,
        scanner: MediaScanner,
        control: ScanControl,
        state: ScanRunState
    ) async {
        do {
            guard let root = try await catalogStore.mediaRoot(id: rootID) else {
                throw StudioError.mediaRootNotFound(id: rootID)
            }
            let diagnostic = await mediaRootStore.diagnoseAccess(to: root)
            guard diagnostic.availability == .online else {
                try await taskCenter.fail(scanID)
                await state.finish(state: .failed, errorMessage: diagnostic.errorMessage)
                return
            }
            let resolvedRoot = try await mediaRootStore.resolve(root)

            let fingerprints = try await catalogStore.assetFingerprints(for: rootID)
            try await catalogStore.beginScan(rootID: rootID, scanID: scanID)
            let summary = try await bookmarkStore.withSecurityScopedAccess(to: resolvedRoot.directoryURL) {
                try await scanner.scan(
                    rootURL: resolvedRoot.directoryURL,
                    rootID: rootID,
                    knownFingerprints: fingerprints,
                    control: control,
                    commitBatch: { batch in
                        try await catalogStore.applyScanBatch(batch, scanID: scanID)
                    },
                    reportProgress: { progress in
                        await state.update(progress: progress)
                    }
                )
            }
            try await catalogStore.finishScan(rootID: rootID, scanID: scanID)
            try await taskCenter.complete(scanID)
            await state.update(progress: ScanProgress(
                rootID: rootID,
                inspectedFiles: summary.inspectedFiles,
                discoveredMedia: summary.discoveredMedia,
                indexedMedia: summary.indexedMedia,
                metadataFailures: summary.metadataFailures
            ))
            await state.finish(state: .completed)
        } catch is CancellationError {
            let currentTask = await taskCenter.task(for: scanID)
            if currentTask?.state != .cancelled {
                _ = try? await taskCenter.cancel(scanID)
            }
            await state.finish(state: .cancelled)
        } catch {
            try? await catalogStore.updateRootAvailability(
                .permissionRequired,
                errorMessage: error.localizedDescription,
                rootID: rootID
            )
            let currentTask = await taskCenter.task(for: scanID)
            if currentTask?.state == .running {
                _ = try? await taskCenter.fail(scanID)
            }
            await state.finish(state: .failed, errorMessage: error.localizedDescription)
            AppLogger.app.error("Scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension Collection {
    func asyncMap<T: Sendable>(_ transform: @escaping (Element) async -> T) async -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}
