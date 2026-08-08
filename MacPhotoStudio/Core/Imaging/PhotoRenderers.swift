import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct PreviewHistogram: Sendable, Equatable {
    static let binCount = 256
    let red: [UInt32]
    let green: [UInt32]
    let blue: [UInt32]
    let luminance: [UInt32]

    static let empty = PreviewHistogram(
        red: Array(repeating: 0, count: binCount),
        green: Array(repeating: 0, count: binCount),
        blue: Array(repeating: 0, count: binCount),
        luminance: Array(repeating: 0, count: binCount)
    )
}

struct PhotoRenderResult: Sendable {
    let imageData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let histogram: PreviewHistogram?
    let colorPipeline: ColorPipelinePlan?
}

/// Preview rendering is isolated from export rendering. It keeps one Metal-backed
/// CIContext alive and only accepts a downsampled image into the edit pipeline.
actor PreviewRenderer {
    private let context = RendererContextFactory.makeContext()
    private let subjectMaskProvider: SubjectMaskProvider

    init(subjectMaskProvider: SubjectMaskProvider = SubjectMaskProvider(capacity: 8)) {
        self.subjectMaskProvider = subjectMaskProvider
    }

    func render(
        sourceURL: URL,
        state: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        sourceColor: PhotoColorDescriptor = .sRGB,
        maximumPixelSize: Int = 2_048
    ) throws -> PhotoRenderResult {
        guard let source = CIImage(contentsOf: sourceURL, options: [.applyOrientationProperty: true]) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        let preview = PhotoImagePipeline.previewImage(from: source, maximumPixelSize: max(128, maximumPixelSize))
        return try render(
            source: preview,
            state: state,
            lut: lut,
            technicalLUT: technicalLUT,
            sourceColor: sourceColor,
            maximumPixelSize: maximumPixelSize,
            subjectMaskCacheKey: SubjectMaskCacheKey(
                sourceURL: sourceURL,
                rendition: .preview,
                extent: preview.extent
            )
        )
    }

    func render(
        source: CIImage,
        state: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        sourceColor: PhotoColorDescriptor = .sRGB,
        maximumPixelSize: Int = 2_048,
        subjectMaskCacheKey: SubjectMaskCacheKey? = nil
    ) throws -> PhotoRenderResult {
        try Task.checkCancellation()
        let preview = PhotoImagePipeline.previewImage(from: source, maximumPixelSize: max(128, maximumPixelSize))
        try Task.checkCancellation()
        let output = try PhotoColorPipeline.apply(
            source: preview,
            state: state,
            sourceColor: sourceColor,
            technicalLUT: technicalLUT,
            creativeLUT: lut,
            subjectMaskProvider: subjectMaskProvider,
            subjectMaskCacheKey: subjectMaskCacheKey ?? .transient(for: preview.extent)
        )
        return try RendererOutput.make(from: output.image, context: context, calculateHistogram: true, pipeline: output.plan)
    }
}

/// Export rendering deliberately has a distinct context and never downscales the
/// source. Phase 5 owns writing exports to a user-selected destination.
actor ExportRenderer {
    private let context = RendererContextFactory.makeContext()
    private let subjectMaskProvider: SubjectMaskProvider

    init(subjectMaskProvider: SubjectMaskProvider = SubjectMaskProvider(capacity: 1)) {
        self.subjectMaskProvider = subjectMaskProvider
    }

    func render(
        sourceURL: URL,
        state: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        sourceColor: PhotoColorDescriptor = .sRGB
    ) throws -> PhotoRenderResult {
        guard let source = CIImage(contentsOf: sourceURL, options: [.applyOrientationProperty: true]) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        return try render(
            source: source,
            state: state,
            lut: lut,
            technicalLUT: technicalLUT,
            sourceColor: sourceColor,
            subjectMaskCacheKey: SubjectMaskCacheKey(
                sourceURL: sourceURL,
                rendition: .export,
                extent: source.extent
            )
        )
    }

    func render(
        source: CIImage,
        state: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        sourceColor: PhotoColorDescriptor = .sRGB,
        subjectMaskCacheKey: SubjectMaskCacheKey? = nil
    ) throws -> PhotoRenderResult {
        try Task.checkCancellation()
        let output = try PhotoColorPipeline.apply(
            source: source,
            state: state,
            sourceColor: sourceColor,
            technicalLUT: technicalLUT,
            creativeLUT: lut,
            subjectMaskProvider: subjectMaskProvider,
            subjectMaskCacheKey: subjectMaskCacheKey ?? .transient(for: source.extent)
        )
        return try RendererOutput.make(from: output.image, context: context, calculateHistogram: false, pipeline: output.plan)
    }
}

struct RAWRenderResult: Sendable {
    let render: PhotoRenderResult
    let capabilities: RAWCapabilities
}

/// Encodes a rendered image directly to a newly selected destination. It never
/// writes beside, replaces, or otherwise changes the referenced source media.
enum ImageFileExporter {
    static func write(
        image: CIImage,
        context: CIContext,
        to destinationURL: URL,
        format: RAWExportFormat,
        quality: Double = 0.92
    ) throws {
        try write(
            image: image,
            context: context,
            sourceURL: nil,
            to: destinationURL,
            options: PhotoExportOptions(format: format, quality: quality),
            allowsOverwrite: false
        )
    }

    static func write(
        image: CIImage,
        context: CIContext,
        sourceURL: URL?,
        to destinationURL: URL,
        options: PhotoExportOptions,
        allowsOverwrite: Bool
    ) throws {
        try Task.checkCancellation()
        guard options.format.isSupported else {
            throw StudioError.exportFailed(message: "系统不支持 \(options.format.title) 编码。")
        }
        if options.dynamicRange == .hdr, !HDRPhotoCapabilities.supportsHDRGainMapExport {
            throw StudioError.exportFailed(message: "HDR still / gain-map 导出不受支持（Unsupported）：此 macOS ImageIO 路径无法可靠写入 HDR gain map；请导出 SDR 色调映射结果，避免生成被误标为 HDR 的文件。")
        }
        if let sourceURL,
           sourceURL.standardizedFileURL.resolvingSymlinksInPath() == destinationURL.standardizedFileURL.resolvingSymlinksInPath() {
            throw StudioError.exportFailed(message: "导出目标不能覆盖原始媒体文件：\(destinationURL.lastPathComponent)")
        }
        let destinationExists = FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false))
        guard !destinationExists || allowsOverwrite else {
            throw StudioError.exportFailed(message: "目标文件已存在：\(destinationURL.lastPathComponent)")
        }
        let extent = image.extent.integral
        guard !extent.isEmpty, let cgImage = context.createCGImage(
            image,
            from: extent,
            format: .RGBA8,
            colorSpace: options.outputColorSpace.cgColorSpace
        ) else {
            throw StudioError.exportFailed(message: "无法生成输出图像。")
        }
        let directoryURL = destinationURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appending(path: ".mps-export-\(UUID().uuidString)").appendingPathExtension("tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            options.format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw StudioError.exportFailed(message: "系统不支持 \(options.format.title) 编码。")
        }
        var properties = outputProperties(
            sourceURL: sourceURL,
            keepsMetadata: options.keepsMetadata,
            removesGPS: options.removesGPS
        )
        if options.format == .jpeg || options.format == .heif {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StudioError.exportFailed(message: "无法写入 \(destinationURL.lastPathComponent)。")
        }
        try verifyEmbeddedColorProfile(
            at: temporaryURL,
            expected: options.outputColorSpace
        )
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            guard allowsOverwrite else {
                throw StudioError.exportFailed(message: "目标文件已存在：\(destinationURL.lastPathComponent)")
            }
            do {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } catch {
                throw StudioError.exportFailed(message: "无法替换已明确选择覆盖的文件：\(destinationURL.lastPathComponent)")
            }
        } else {
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                throw StudioError.exportFailed(message: "无法保存 \(destinationURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }
    }

    private static func outputProperties(
        sourceURL: URL?,
        keepsMetadata: Bool,
        removesGPS: Bool
    ) -> [CFString: Any] {
        guard keepsMetadata,
              let sourceURL,
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        // Pixels have already been normalized with ImageIO/Core Image orientation.
        properties[kCGImagePropertyOrientation] = 1
        // The rendered CGImage owns the requested output colour space. Retaining
        // a copied source profile here could make a Display P3/Rec.709 export be
        // tagged as its original source profile, so it is removed deliberately.
        properties.removeValue(forKey: kCGImagePropertyProfileName)
        if removesGPS {
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        }
        return properties
    }

    /// ImageIO normally preserves the profile carried by `cgImage`, but this
    /// post-write readback is the safety boundary for colour-managed export. A
    /// file that cannot retain the chosen ICC profile is never moved to the
    /// user's output directory and is not presented as a successful export.
    private static func verifyEmbeddedColorProfile(
        at url: URL,
        expected: PhotoColorSpace
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let outputColorSpace = image.colorSpace
        else {
            throw StudioError.exportFailed(message: "无法重新读取导出文件的 ICC profile。")
        }
        guard expected.matchesEmbeddedProfile(of: outputColorSpace) else {
            throw StudioError.exportFailed(
                message: "\(expected.title) profile 无法由当前 ImageIO \(url.pathExtension.uppercased()) 导出器可靠保留；文件未写入目标位置。"
            )
        }
    }
}

/// Full-resolution ordinary-photo encoder. It owns a dedicated CIContext, so a
/// batch releases each image before it advances to the next asset.
actor PhotoFileExportRenderer {
    private let context = RendererContextFactory.makeContext()

    func export(
        sourceURL: URL,
        state: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        sourceColor: PhotoColorDescriptor = .sRGB,
        destinationURL: URL,
        options: PhotoExportOptions,
        allowsOverwrite: Bool
    ) throws {
        try Task.checkCancellation()
        guard let source = CIImage(contentsOf: sourceURL, options: [.applyOrientationProperty: true]) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        var outputSettings = state.colorPipeline
        outputSettings.outputColorSpace = options.outputColorSpace
        outputSettings.dynamicRange = options.dynamicRange
        var output = try PhotoColorPipeline.apply(
            source: source,
            state: state,
            sourceColor: sourceColor,
            technicalLUT: technicalLUT,
            creativeLUT: lut,
            settings: outputSettings
        ).image
        if let maximumPixelSize = options.resize.maximumPixelSize {
            output = PhotoImagePipeline.previewImage(from: output, maximumPixelSize: maximumPixelSize)
        }
        try ImageFileExporter.write(
            image: output,
            context: context,
            sourceURL: sourceURL,
            to: destinationURL,
            options: options,
            allowsOverwrite: allowsOverwrite
        )
    }
}

/// Decodes RAW once through `CIRAWFilter`, then hands the result to the same
/// standard photo pipeline used by JPEG/HEIC. Preview uses draft/scaled RAW;
/// export always restarts the RAW decode at full resolution.
actor RAWPreviewRenderer {
    private let renderer = PreviewRenderer()

    func render(
        sourceURL: URL,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        maximumPixelSize: Int = 2_048
    ) async throws -> RAWRenderResult {
        try Task.checkCancellation()
        let decoded = try RAWImagePipeline.decode(
            sourceURL: sourceURL,
            state: rawState,
            maximumPixelSize: maximumPixelSize,
            draft: true
        )
        try Task.checkCancellation()
        let render = try await renderer.render(
            source: decoded.image,
            state: photoState,
            lut: lut,
            technicalLUT: technicalLUT,
            sourceColor: decoded.pipelineInputColor,
            maximumPixelSize: maximumPixelSize
        )
        return RAWRenderResult(render: render, capabilities: decoded.capabilities)
    }
}

actor RAWExportRenderer {
    private let renderer = ExportRenderer()
    private let context = RendererContextFactory.makeContext()

    func render(
        sourceURL: URL,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil
    ) async throws -> RAWRenderResult {
        try Task.checkCancellation()
        let decoded = try RAWImagePipeline.decode(
            sourceURL: sourceURL,
            state: rawState,
            maximumPixelSize: nil,
            draft: false
        )
        try Task.checkCancellation()
        let render = try await renderer.render(
            source: decoded.image,
            state: photoState,
            lut: lut,
            technicalLUT: technicalLUT,
            sourceColor: decoded.pipelineInputColor
        )
        return RAWRenderResult(render: render, capabilities: decoded.capabilities)
    }

    func export(
        sourceURL: URL,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        lut: CubeLUT?,
        technicalLUT: CubeLUT? = nil,
        destinationURL: URL,
        options: PhotoExportOptions,
        allowsOverwrite: Bool = false
    ) throws {
        try Task.checkCancellation()
        let decoded = try RAWImagePipeline.decode(
            sourceURL: sourceURL,
            state: rawState,
            maximumPixelSize: nil,
            draft: false
        )
        try Task.checkCancellation()
        var outputSettings = photoState.colorPipeline
        outputSettings.outputColorSpace = options.outputColorSpace
        outputSettings.dynamicRange = options.dynamicRange
        var output = try PhotoColorPipeline.apply(
            source: decoded.image,
            state: photoState,
            sourceColor: decoded.pipelineInputColor,
            technicalLUT: technicalLUT,
            creativeLUT: lut,
            settings: outputSettings
        ).image
        if let maximumPixelSize = options.resize.maximumPixelSize {
            output = PhotoImagePipeline.previewImage(from: output, maximumPixelSize: maximumPixelSize)
        }
        try ImageFileExporter.write(
            image: output,
            context: context,
            sourceURL: sourceURL,
            to: destinationURL,
            options: options,
            allowsOverwrite: allowsOverwrite
        )
    }
}

actor PhotoEditingService {
    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore
    private let previewRenderer: PreviewRenderer
    private let exportRenderer: ExportRenderer
    private let photoFileExportRenderer: PhotoFileExportRenderer
    private let rawPreviewRenderer: RAWPreviewRenderer
    private let rawExportRenderer: RAWExportRenderer
    private let lutRepository: LUTRepository

    init(
        catalogStore: CatalogStore,
        mediaRootStore: MediaRootStore,
        previewRenderer: PreviewRenderer = PreviewRenderer(),
        exportRenderer: ExportRenderer = ExportRenderer(),
        photoFileExportRenderer: PhotoFileExportRenderer = PhotoFileExportRenderer(),
        rawPreviewRenderer: RAWPreviewRenderer = RAWPreviewRenderer(),
        rawExportRenderer: RAWExportRenderer = RAWExportRenderer(),
        lutRepository: LUTRepository
    ) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
        self.previewRenderer = previewRenderer
        self.exportRenderer = exportRenderer
        self.photoFileExportRenderer = photoFileExportRenderer
        self.rawPreviewRenderer = rawPreviewRenderer
        self.rawExportRenderer = rawExportRenderer
        self.lutRepository = lutRepository
    }

    func editState(for assetID: UUID) async throws -> PhotoEditState {
        try await catalogStore.photoEditState(for: assetID) ?? .identity
    }

    func save(_ state: PhotoEditState, for assetID: UUID) async throws {
        try await catalogStore.savePhotoEditState(state, for: assetID)
    }

    func rawEditState(for assetID: UUID) async throws -> RAWEditState {
        try await catalogStore.rawEditState(for: assetID) ?? .identity
    }

    func saveRaw(_ state: RAWEditState, for assetID: UUID) async throws {
        try await catalogStore.saveRawEditState(state, for: assetID)
    }

    /// Applies only the preset-safe adjustment groups. This intentionally runs
    /// sequentially: it keeps memory bounded and writes Catalog state only.
    func applyPresetContent(
        _ content: PhotoPresetContent,
        to assetIDs: [UUID],
        components: Set<PhotoEditComponent> = PhotoEditComponent.allPresetComponents,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> BatchEditReport {
        var seenIDs = Set<UUID>()
        let uniqueIDs = assetIDs.filter { seenIDs.insert($0).inserted }
        var succeeded = 0
        var failures: [BatchItemFailure] = []
        for (index, assetID) in uniqueIDs.enumerated() {
            try Task.checkCancellation()
            do {
                let current = try await catalogStore.photoEditState(for: assetID) ?? .identity
                try await catalogStore.savePhotoEditState(current.applying(content, components: components), for: assetID)
                succeeded += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(BatchItemFailure(assetID: assetID, message: error.localizedDescription))
            }
            if let reportProgress {
                await reportProgress(Double(index + 1) / Double(max(uniqueIDs.count, 1)))
            }
        }
        return BatchEditReport(attempted: uniqueIDs.count, succeeded: succeeded, failures: failures)
    }

    func lutLibrary() async throws -> LUTLibrary { try await lutRepository.library() }
    func importLUT(
        from url: URL,
        kind: LUTKind = .creative,
        technicalMetadata: TechnicalLUTMetadata? = nil
    ) async throws -> CubeLUT {
        try await lutRepository.importLUT(from: url, kind: kind, technicalMetadata: technicalMetadata)
    }
    func renameLUT(identifier: UUID, to title: String) async throws { try await lutRepository.renameImportedLUT(identifier: identifier, to: title) }
    func deleteLUT(identifier: UUID) async throws { try await lutRepository.deleteImportedLUT(identifier: identifier) }
    func setLUTFavorite(_ isFavorite: Bool, identifier: UUID) async throws { try await lutRepository.setFavorite(isFavorite, identifier: identifier) }

    func renderPreview(for asset: LibraryAssetRecord, state: PhotoEditState, maximumPixelSize: Int) async throws -> PhotoRenderResult {
        try await render(for: asset, state: state, maximumPixelSize: maximumPixelSize, preview: true)
    }

    func renderExport(for asset: LibraryAssetRecord, state: PhotoEditState) async throws -> PhotoRenderResult {
        try await render(for: asset, state: state, maximumPixelSize: nil, preview: false)
    }

    func renderRAWPreview(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        maximumPixelSize: Int
    ) async throws -> RAWRenderResult {
        try await renderRAW(for: asset, rawState: rawState, photoState: photoState, maximumPixelSize: maximumPixelSize)
    }

    func renderRAWExport(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState
    ) async throws -> RAWRenderResult {
        try await renderRAW(for: asset, rawState: rawState, photoState: photoState, maximumPixelSize: nil)
    }

    func exportRAW(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        destinationURL: URL,
        format: RAWExportFormat
    ) async throws {
        guard RAWFormat.isRAW(asset.fileExtension) else {
            throw StudioError.rawDecodingFailed(path: asset.relativePath)
        }
        guard let root = try await catalogStore.mediaRoot(id: asset.rootID) else {
            throw StudioError.mediaRootNotFound(id: asset.rootID)
        }
        let resolved = try await mediaRootStore.resolve(root)
        let sourceURL = resolved.directoryURL.appending(path: asset.relativePath)
        let selectedLUTs = try await selectedLUTs(for: photoState)
        try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolved.directoryURL) {
            try await self.rawExportRenderer.export(
                sourceURL: sourceURL,
                rawState: rawState,
                photoState: photoState,
                lut: selectedLUTs.creative,
                technicalLUT: selectedLUTs.technical,
                destinationURL: destinationURL,
                options: PhotoExportOptions(format: format)
            )
        }
    }

    /// Writes one rendered photo to the caller-selected directory. The source
    /// remains referenced and read-only; only a temporary output file is ever
    /// created, then atomically moved into the requested destination.
    func exportPhoto(
        for asset: LibraryAssetRecord,
        destinationURL: URL,
        options: PhotoExportOptions,
        allowsOverwrite: Bool = false
    ) async throws {
        guard asset.mediaType == .photo else {
            throw StudioError.exportFailed(message: "只能导出照片：\(asset.filename)")
        }
        guard let root = try await catalogStore.mediaRoot(id: asset.rootID) else {
            throw StudioError.mediaRootNotFound(id: asset.rootID)
        }
        let photoState = try await editState(for: asset.id)
        let selectedLUTs = try await selectedLUTs(for: photoState)
        let sourceColor = PhotoColorDescriptor.inferred(fromProfileName: asset.colorProfile)
        let resolved = try await mediaRootStore.resolve(root)
        let sourceURL = resolved.directoryURL.appending(path: asset.relativePath)

        try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolved.directoryURL) {
            if RAWFormat.isRAW(asset.fileExtension) {
                let rawState = try await self.rawEditState(for: asset.id)
                try await self.rawExportRenderer.export(
                    sourceURL: sourceURL,
                    rawState: rawState,
                    photoState: photoState,
                    lut: selectedLUTs.creative,
                    technicalLUT: selectedLUTs.technical,
                    destinationURL: destinationURL,
                    options: options,
                    allowsOverwrite: allowsOverwrite
                )
            } else {
                try await self.photoFileExportRenderer.export(
                    sourceURL: sourceURL,
                    state: photoState,
                    lut: selectedLUTs.creative,
                    technicalLUT: selectedLUTs.technical,
                    sourceColor: sourceColor,
                    destinationURL: destinationURL,
                    options: options,
                    allowsOverwrite: allowsOverwrite
                )
            }
        }
    }

    /// Bounded-memory batch export. Each source is decoded, rendered and
    /// released before the next begins; a bad asset is reported without losing
    /// the rest of the batch.
    func batchExport(
        assets: [LibraryAssetRecord],
        outputDirectoryURL: URL,
        options: PhotoExportOptions,
        collisionResolver: (@Sendable (ExportCollision) async -> ExportCollisionResolution)? = nil,
        reportProgress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> BatchExportReport {
        let uniqueAssets = uniquePhotoAssets(assets)
        var succeeded = 0
        var skipped = 0
        var failures: [BatchExportItemFailure] = []

        for (index, asset) in uniqueAssets.enumerated() {
            try Task.checkCancellation()
            let baseName = options.namingRule.baseFilename(for: asset, sequenceNumber: index + 1)
            let requestedURL = outputDirectoryURL
                .appending(path: baseName)
                .appendingPathExtension(options.format.filenameExtension)
            do {
                let destination = try await ExportDestinationResolver.destination(
                    initialURL: requestedURL,
                    sourceAssetID: asset.id,
                    policy: options.collisionPolicy,
                    resolver: collisionResolver
                )
                if let destinationURL = destination.url {
                    try await exportPhoto(
                        for: asset,
                        destinationURL: destinationURL,
                        options: options,
                        allowsOverwrite: destination.allowsOverwrite
                    )
                    succeeded += 1
                } else {
                    skipped += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(BatchExportItemFailure(assetID: asset.id, message: error.localizedDescription))
            }
            if let reportProgress {
                await reportProgress(Double(index + 1) / Double(max(uniqueAssets.count, 1)))
            }
        }
        return BatchExportReport(
            attempted: uniqueAssets.count,
            succeeded: succeeded,
            skipped: skipped,
            failures: failures
        )
    }

    private func render(
        for asset: LibraryAssetRecord,
        state: PhotoEditState,
        maximumPixelSize: Int?,
        preview: Bool
    ) async throws -> PhotoRenderResult {
        guard asset.mediaType == .photo else {
            throw StudioError.metadataExtractionFailed(path: asset.relativePath)
        }
        guard let root = try await catalogStore.mediaRoot(id: asset.rootID) else {
            throw StudioError.mediaRootNotFound(id: asset.rootID)
        }
        let resolved = try await mediaRootStore.resolve(root)
        let sourceURL = resolved.directoryURL.appending(path: asset.relativePath)
        let selectedLUTs = try await selectedLUTs(for: state)
        let sourceColor = PhotoColorDescriptor.inferred(fromProfileName: asset.colorProfile)
        return try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolved.directoryURL) {
            if let maximumPixelSize {
                return try await self.previewRenderer.render(
                    sourceURL: sourceURL,
                    state: state,
                    lut: selectedLUTs.creative,
                    technicalLUT: selectedLUTs.technical,
                    sourceColor: sourceColor,
                    maximumPixelSize: maximumPixelSize
                )
            }
            return try await self.exportRenderer.render(
                sourceURL: sourceURL,
                state: state,
                lut: selectedLUTs.creative,
                technicalLUT: selectedLUTs.technical,
                sourceColor: sourceColor
            )
        }
    }

    private func renderRAW(
        for asset: LibraryAssetRecord,
        rawState: RAWEditState,
        photoState: PhotoEditState,
        maximumPixelSize: Int?
    ) async throws -> RAWRenderResult {
        guard RAWFormat.isRAW(asset.fileExtension) else {
            throw StudioError.rawDecodingFailed(path: asset.relativePath)
        }
        guard let root = try await catalogStore.mediaRoot(id: asset.rootID) else {
            throw StudioError.mediaRootNotFound(id: asset.rootID)
        }
        let resolved = try await mediaRootStore.resolve(root)
        let sourceURL = resolved.directoryURL.appending(path: asset.relativePath)
        let selectedLUTs = try await selectedLUTs(for: photoState)
        return try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolved.directoryURL) {
            if let maximumPixelSize {
                return try await self.rawPreviewRenderer.render(
                    sourceURL: sourceURL, rawState: rawState, photoState: photoState,
                    lut: selectedLUTs.creative,
                    technicalLUT: selectedLUTs.technical,
                    maximumPixelSize: maximumPixelSize
                )
            }
            return try await self.rawExportRenderer.render(
                sourceURL: sourceURL,
                rawState: rawState,
                photoState: photoState,
                lut: selectedLUTs.creative,
                technicalLUT: selectedLUTs.technical
            )
        }
    }

    private func selectedLUTs(for state: PhotoEditState) async throws -> (technical: CubeLUT?, creative: CubeLUT?) {
        let technical: CubeLUT?
        if let application = state.technicalLUT {
            guard let lut = try await lutRepository.lut(identifier: application.identifier) else {
                throw StudioError.invalidLUT(message: "找不到已选择的 Technical LUT。")
            }
            guard lut.kind == .technical, lut.technicalMetadata != nil else {
                throw StudioError.invalidLUT(message: "已选择的 Technical LUT 缺少色彩元数据。")
            }
            technical = lut
        } else {
            technical = nil
        }

        let creative: CubeLUT?
        if let application = state.lut {
            guard let lut = try await lutRepository.lut(identifier: application.identifier) else {
                throw StudioError.invalidLUT(message: "找不到已选择的创意 LUT。")
            }
            guard lut.kind == .creative else {
                throw StudioError.invalidLUT(message: "Technical LUT 不能被作为创意 LUT 使用。")
            }
            creative = lut
        } else {
            creative = nil
        }
        return (technical, creative)
    }

    private func uniquePhotoAssets(_ assets: [LibraryAssetRecord]) -> [LibraryAssetRecord] {
        var seenIDs = Set<UUID>()
        return assets.filter { $0.mediaType == .photo && seenIDs.insert($0.id).inserted }
    }
}

enum RendererContextFactory {
    static func makeContext() -> CIContext {
        let options: [CIContextOption: Any] = [
            .cacheIntermediates: true,
            .workingColorSpace: PhotoColorPipeline.workingColorSpace,
            .workingFormat: CIFormat.RGBAh.rawValue
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }
}

private enum RendererOutput {
    static func make(
        from image: CIImage,
        context: CIContext,
        calculateHistogram: Bool,
        pipeline: ColorPipelinePlan
    ) throws -> PhotoRenderResult {
        try Task.checkCancellation()
        let extent = image.extent.integral
        let format: CIFormat = pipeline.dynamicRange == .hdr ? .RGBAh : .RGBA8
        guard !extent.isEmpty, let cgImage = context.createCGImage(
            image,
            from: extent,
            format: format,
            colorSpace: pipeline.output.colorSpace.cgColorSpace
        ) else {
            throw StudioError.metadataExtractionFailed(path: "无法渲染编辑预览")
        }
        // TIFF retains a half-float extended-range preview. The AppKit view opts
        // into EDR display; on an SDR monitor this remains a system tone-mapped
        // preview rather than clipping the working image earlier in the graph.
        let data = try pipeline.dynamicRange == .hdr ? tiffData(from: cgImage) : jpegData(from: cgImage)
        let histogram = calculateHistogram ? makeHistogram(image: image, extent: extent, context: context) : nil
        return PhotoRenderResult(
            imageData: data,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            histogram: histogram,
            colorPipeline: pipeline
        )
    }

    private static func jpegData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw StudioError.metadataExtractionFailed(path: "无法编码 JPEG 预览")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StudioError.metadataExtractionFailed(path: "无法完成 JPEG 预览编码")
        }
        return data as Data
    }

    private static func tiffData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil) else {
            throw StudioError.metadataExtractionFailed(path: "无法编码 HDR TIFF 预览")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StudioError.metadataExtractionFailed(path: "无法完成 HDR TIFF 预览")
        }
        return data as Data
    }

    private static func makeHistogram(image: CIImage, extent: CGRect, context: CIContext) -> PreviewHistogram {
        let maximumSide: CGFloat = 512
        let scale = min(1, maximumSide / max(extent.width, extent.height))
        let sampled = scale < 1 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        let bounds = sampled.extent.integral
        guard !bounds.isEmpty else { return .empty }
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return .empty }
        var pixels = Array(repeating: UInt8(0), count: width * height * 4)
        context.render(
            sampled,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var red = Array(repeating: UInt32(0), count: PreviewHistogram.binCount)
        var green = red
        var blue = red
        var luminance = red
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            red[r] += 1
            green[g] += 1
            blue[b] += 1
            let luma = Double(r) * 0.2126 + Double(g) * 0.7152 + Double(b) * 0.0722
            let lumaIndex = min(255, max(0, Int(luma)))
            luminance[lumaIndex] += 1
        }
        return PreviewHistogram(red: red, green: green, blue: blue, luminance: luminance)
    }
}
