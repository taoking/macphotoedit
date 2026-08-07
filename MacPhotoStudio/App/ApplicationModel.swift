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
    @Published private(set) var libraryError: String?

    private var hasBootstrapped = false
    private var catalogStore: CatalogStore?
    private var mediaRootStore: MediaRootStore?
    private var scanCoordinator: ScanCoordinator?

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
            startupState = .ready(paths)
            await refreshLibrary(validateRoots: true)
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
        } catch {
            libraryError = error.localizedDescription
            AppLogger.app.error("Adding media root failed: \(error.localizedDescription, privacy: .public)")
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
        guard let catalogStore, let scanCoordinator else { return }
        if validateRoots {
            await scanCoordinator.refreshRootAvailability()
        }

        do {
            mediaRoots = try await catalogStore.mediaRoots()
            scanStatuses = await scanCoordinator.statuses()
        } catch {
            libraryError = error.localizedDescription
        }
    }
}
