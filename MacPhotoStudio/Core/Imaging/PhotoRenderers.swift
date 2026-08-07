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
}

/// Preview rendering is isolated from export rendering. It keeps one Metal-backed
/// CIContext alive and only accepts a downsampled image into the edit pipeline.
actor PreviewRenderer {
    private let context = RendererContextFactory.makeContext()

    func render(
        sourceURL: URL,
        state: PhotoEditState,
        lut: CubeLUT?,
        maximumPixelSize: Int = 2_048
    ) throws -> PhotoRenderResult {
        guard let source = CIImage(contentsOf: sourceURL, options: [.applyOrientationProperty: true]) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        return try render(source: source, state: state, lut: lut, maximumPixelSize: maximumPixelSize)
    }

    func render(
        source: CIImage,
        state: PhotoEditState,
        lut: CubeLUT?,
        maximumPixelSize: Int = 2_048
    ) throws -> PhotoRenderResult {
        try Task.checkCancellation()
        let preview = PhotoImagePipeline.previewImage(from: source, maximumPixelSize: max(128, maximumPixelSize))
        try Task.checkCancellation()
        let edited = PhotoImagePipeline.apply(state, to: preview, lut: lut)
        return try RendererOutput.make(from: edited, context: context, calculateHistogram: true)
    }
}

/// Export rendering deliberately has a distinct context and never downscales the
/// source. Phase 5 owns writing exports to a user-selected destination.
actor ExportRenderer {
    private let context = RendererContextFactory.makeContext()

    func render(sourceURL: URL, state: PhotoEditState, lut: CubeLUT?) throws -> PhotoRenderResult {
        guard let source = CIImage(contentsOf: sourceURL, options: [.applyOrientationProperty: true]) else {
            throw StudioError.metadataExtractionFailed(path: sourceURL.path(percentEncoded: false))
        }
        return try render(source: source, state: state, lut: lut)
    }

    func render(source: CIImage, state: PhotoEditState, lut: CubeLUT?) throws -> PhotoRenderResult {
        try Task.checkCancellation()
        return try RendererOutput.make(from: PhotoImagePipeline.apply(state, to: source, lut: lut), context: context, calculateHistogram: false)
    }
}

actor PhotoEditingService {
    private let catalogStore: CatalogStore
    private let mediaRootStore: MediaRootStore
    private let previewRenderer: PreviewRenderer
    private let exportRenderer: ExportRenderer
    private let lutRepository: LUTRepository

    init(
        catalogStore: CatalogStore,
        mediaRootStore: MediaRootStore,
        previewRenderer: PreviewRenderer = PreviewRenderer(),
        exportRenderer: ExportRenderer = ExportRenderer(),
        lutRepository: LUTRepository
    ) {
        self.catalogStore = catalogStore
        self.mediaRootStore = mediaRootStore
        self.previewRenderer = previewRenderer
        self.exportRenderer = exportRenderer
        self.lutRepository = lutRepository
    }

    func editState(for assetID: UUID) async throws -> PhotoEditState {
        try await catalogStore.photoEditState(for: assetID) ?? .identity
    }

    func save(_ state: PhotoEditState, for assetID: UUID) async throws {
        try await catalogStore.savePhotoEditState(state, for: assetID)
    }

    func lutLibrary() async throws -> LUTLibrary { try await lutRepository.library() }
    func importLUT(from url: URL) async throws -> CubeLUT { try await lutRepository.importLUT(from: url) }
    func renameLUT(identifier: UUID, to title: String) async throws { try await lutRepository.renameImportedLUT(identifier: identifier, to: title) }
    func deleteLUT(identifier: UUID) async throws { try await lutRepository.deleteImportedLUT(identifier: identifier) }
    func setLUTFavorite(_ isFavorite: Bool, identifier: UUID) async throws { try await lutRepository.setFavorite(isFavorite, identifier: identifier) }

    func renderPreview(for asset: LibraryAssetRecord, state: PhotoEditState, maximumPixelSize: Int) async throws -> PhotoRenderResult {
        try await render(for: asset, state: state, maximumPixelSize: maximumPixelSize, preview: true)
    }

    func renderExport(for asset: LibraryAssetRecord, state: PhotoEditState) async throws -> PhotoRenderResult {
        try await render(for: asset, state: state, maximumPixelSize: nil, preview: false)
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
        let selectedLUT: CubeLUT?
        if let application = state.lut {
            selectedLUT = try await lutRepository.lut(identifier: application.identifier)
        } else {
            selectedLUT = nil
        }
        return try await mediaRootStore.bookmarkStore.withSecurityScopedAccess(to: resolved.directoryURL) {
            if let maximumPixelSize {
                return try await self.previewRenderer.render(
                    sourceURL: sourceURL,
                    state: state,
                    lut: selectedLUT,
                    maximumPixelSize: maximumPixelSize
                )
            }
            return try await self.exportRenderer.render(sourceURL: sourceURL, state: state, lut: selectedLUT)
        }
    }
}

private enum RendererContextFactory {
    static func makeContext() -> CIContext {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: true])
        }
        return CIContext(options: [.cacheIntermediates: true])
    }
}

private enum RendererOutput {
    static func make(from image: CIImage, context: CIContext, calculateHistogram: Bool) throws -> PhotoRenderResult {
        try Task.checkCancellation()
        let extent = image.extent.integral
        guard !extent.isEmpty, let cgImage = context.createCGImage(image, from: extent) else {
            throw StudioError.metadataExtractionFailed(path: "无法渲染编辑预览")
        }
        let data = try jpegData(from: cgImage)
        let histogram = calculateHistogram ? makeHistogram(image: image, extent: extent, context: context) : nil
        return PhotoRenderResult(
            imageData: data,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            histogram: histogram
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
