import Foundation

/// Composes the photo editing and preset services behind a stable boundary.
/// `ApplicationModel` owns presentation state, errors, background-task UI and
/// collision dialogs; this coordinator owns the concrete photo/RAW/LUT work.
@MainActor
final class PhotoEditingCoordinator {
    private let photoEditingService: PhotoEditingService
    private let presetRepository: PresetRepository

    init(
        catalogStore: CatalogStore,
        mediaRootStore: MediaRootStore,
        lutDirectory: URL
    ) {
        photoEditingService = PhotoEditingService(
            catalogStore: catalogStore,
            mediaRootStore: mediaRootStore,
            lutRepository: LUTRepository(directoryURL: lutDirectory)
        )
        presetRepository = PresetRepository(catalogStore: catalogStore)
    }

    func editState(for assetID: UUID) async throws -> PhotoEditState {
        try await photoEditingService.editState(for: assetID)
    }

    func save(_ state: PhotoEditState, for assetID: UUID) async throws {
        try await photoEditingService.save(state, for: assetID)
    }

    func rawEditState(for assetID: UUID) async throws -> RAWEditState {
        try await photoEditingService.rawEditState(for: assetID)
    }

    func saveRaw(_ state: RAWEditState, for assetID: UUID) async throws {
        try await photoEditingService.saveRaw(state, for: assetID)
    }

    func applyPresetContent(
        _ content: PhotoPresetContent,
        to assetIDs: [UUID],
        components: Set<PhotoEditComponent> = PhotoEditComponent.allPresetComponents,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> BatchEditReport {
        try await photoEditingService.applyPresetContent(
            content,
            to: assetIDs,
            components: components,
            reportProgress: reportProgress
        )
    }

    func presets() async throws -> [PhotoPreset] {
        try await presetRepository.presets()
    }

    func createPreset(named name: String, from assetID: UUID) async throws -> PhotoPreset {
        let state = try await photoEditingService.editState(for: assetID)
        return try await presetRepository.create(named: name, content: state.presetContent)
    }

    func renamePreset(_ preset: PhotoPreset, to name: String) async throws {
        try await presetRepository.rename(preset, to: name)
    }

    func setPresetFavorite(_ isFavorite: Bool, preset: PhotoPreset) async throws {
        try await presetRepository.setFavorite(isFavorite, for: preset)
    }

    func deletePreset(_ preset: PhotoPreset) async throws {
        try await presetRepository.delete(preset)
    }

    func exportPreset(_ preset: PhotoPreset, to destinationURL: URL) async throws {
        try await presetRepository.export(preset, to: destinationURL)
    }

    func importPreset(from sourceURL: URL) async throws -> PhotoPreset {
        try await presetRepository.importPreset(from: sourceURL)
    }

    func renderPreview(
        for asset: LibraryAssetRecord,
        state: PhotoEditState,
        maximumPixelSize: Int
    ) async throws -> PhotoRenderResult {
        try await photoEditingService.renderPreview(
            for: asset,
            state: state,
            maximumPixelSize: maximumPixelSize
        )
    }

    func renderRAWPreview(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        maximumPixelSize: Int
    ) async throws -> RAWRenderResult {
        try await photoEditingService.renderRAWPreview(
            for: asset,
            rawState: rawState,
            photoState: photoState,
            maximumPixelSize: maximumPixelSize
        )
    }

    func exportRAW(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        destinationURL: URL,
        format: RAWExportFormat
    ) async throws {
        try await photoEditingService.exportRAW(
            for: asset,
            rawState: rawState,
            photoState: photoState,
            destinationURL: destinationURL,
            format: format
        )
    }

    func batchExport(
        assets: [LibraryAssetRecord],
        outputDirectoryURL: URL,
        options: PhotoExportOptions,
        collisionResolver: (@Sendable (ExportCollision) async -> ExportCollisionResolution)? = nil,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> BatchExportReport {
        try await photoEditingService.batchExport(
            assets: assets,
            outputDirectoryURL: outputDirectoryURL,
            options: options,
            collisionResolver: collisionResolver,
            reportProgress: reportProgress
        )
    }

    func lutLibrary() async throws -> LUTLibrary {
        try await photoEditingService.lutLibrary()
    }

    func importLUT(
        from url: URL,
        kind: LUTKind = .creative,
        technicalMetadata: TechnicalLUTMetadata? = nil
    ) async throws -> CubeLUT {
        try await photoEditingService.importLUT(
            from: url,
            kind: kind,
            technicalMetadata: technicalMetadata
        )
    }

    func renameLUT(identifier: UUID, to title: String) async throws {
        try await photoEditingService.renameLUT(identifier: identifier, to: title)
    }

    func deleteLUT(identifier: UUID) async throws {
        try await photoEditingService.deleteLUT(identifier: identifier)
    }

    func setLUTFavorite(_ isFavorite: Bool, identifier: UUID) async throws {
        try await photoEditingService.setLUTFavorite(isFavorite, identifier: identifier)
    }
}
