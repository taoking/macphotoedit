import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacPhotoStudio

final class PhotoEditingTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioEditingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testPhotoEditStateRoundTripsThroughCatalogAfterReopen() async throws {
        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let root = MediaRootRecord(
            id: UUID(), displayName: "Test", bookmarkData: Data("bookmark".utf8),
            lastKnownPath: temporaryDirectory.path(percentEncoded: false), volumeIdentifier: nil,
            availability: .online, createdAt: .now, lastScannedAt: nil, lastScanError: nil
        )
        let firstStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await firstStore.bootstrap()
        try await firstStore.saveMediaRoot(root)
        let scanID = UUID()
        try await firstStore.beginScan(rootID: root.id, scanID: scanID)
        try await firstStore.applyScanBatch([ScannedMediaAsset(
            rootID: root.id, relativePath: "edited.png", fileResourceIdentifier: "edited.png", mediaType: .photo,
            fileExtension: "png", fileSize: 8, createdAt: .now, modifiedAt: .now,
            metadata: .photo(PhotoMetadata(width: 2, height: 2, captureDate: nil, cameraMake: nil, cameraModel: nil,
                                           lensModel: nil, focalLength: nil, aperture: nil, shutterSpeed: nil, iso: nil,
                                           orientation: nil, colorProfile: nil, gpsLatitude: nil, gpsLongitude: nil))
        )], scanID: scanID)
        try await firstStore.finishScan(rootID: root.id, scanID: scanID)
        let catalogAssets = try await firstStore.libraryAssets(query: .all, limit: 1, offset: 0)
        let asset = try XCTUnwrap(catalogAssets.first)

        var state = PhotoEditState.identity
        state.light.exposure = 1.25
        state.color.tint = -0.2
        state.transform.crop = NormalizedCrop(x: 0.1, y: 0.15, width: 0.7, height: 0.6)
        state.hsl[.blue] = HSLAdjustment(hue: 0.3, saturation: -0.15, luminance: 0.2)
        state.curves[.red] = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 0.5, y: 0.65), CurvePoint(x: 1, y: 1)]
        try await firstStore.savePhotoEditState(state, for: asset.id)
        var rawState = RAWEditState.identity
        rawState.exposure = 0.75
        rawState.temperature = 5_600
        rawState.lensCorrectionEnabled = true
        try await firstStore.saveRawEditState(rawState, for: asset.id)

        let reopenedStore = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await reopenedStore.bootstrap()
        let version = try await reopenedStore.currentSchemaVersion()
        let restoredState = try await reopenedStore.photoEditState(for: asset.id)
        XCTAssertEqual(version, 6)
        XCTAssertEqual(restoredState, state)
        let restoredRAWState = try await reopenedStore.rawEditState(for: asset.id)
        XCTAssertEqual(restoredRAWState, rawState)
    }

    func testCubeParserAcceptsIdentity17And33AndRejectsBadData() throws {
        for dimension in [17, 33] {
            let lut = try CubeLUTParser.parse(data: identityCubeData(dimension: dimension))
            XCTAssertEqual(lut.dimension, dimension)
            XCTAssertTrue(lut.isIdentity)
        }
        XCTAssertThrowsError(try CubeLUTParser.parse(data: Data("LUT_3D_SIZE 16".utf8)))
        XCTAssertThrowsError(try CubeLUTParser.parse(data: Data("LUT_3D_SIZE 17\n0 0 nope".utf8)))
    }

    func testIdentityLUTProcessorPreservesPixelsAndZeroStrengthBypassesIt() throws {
        let identity = try CubeLUTParser.parse(data: identityCubeData(dimension: 17))
        let source = CIImage(color: CIColor(red: 0.22, green: 0.48, blue: 0.76, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let sourcePixel = try rgba(of: source)
        let identityPixel = try rgba(of: LUTProcessor.apply(identity, to: source, strength: 1))
        let bypassPixel = try rgba(of: LUTProcessor.apply(identity, to: source, strength: 0))
        XCTAssertEqual(identityPixel.x, sourcePixel.x, accuracy: 0.015)
        XCTAssertEqual(identityPixel.y, sourcePixel.y, accuracy: 0.015)
        XCTAssertEqual(identityPixel.z, sourcePixel.z, accuracy: 0.015)
        XCTAssertEqual(bypassPixel, sourcePixel)
    }

    func testLUTRepositoryImportsWithoutChangingOriginalAndSupportsMetadataOperations() async throws {
        let sourceURL = temporaryDirectory.appending(path: "original.cube")
        let sourceData = identityCubeData(dimension: 17)
        try sourceData.write(to: sourceURL)
        let repository = LUTRepository(directoryURL: temporaryDirectory.appending(path: "lut", directoryHint: .isDirectory))

        let imported = try await repository.importLUT(from: sourceURL)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        var library = try await repository.library()
        XCTAssertTrue(library.builtIn.contains(where: \.isIdentity))
        XCTAssertTrue(library.imported.contains(where: { $0.id == imported.id }))
        try await repository.renameImportedLUT(identifier: imported.id, to: "Renamed")
        try await repository.setFavorite(true, identifier: imported.id)
        library = try await repository.library()
        XCTAssertEqual(library.imported.first(where: { $0.id == imported.id })?.title, "Renamed")
        XCTAssertTrue(library.favorites.contains(where: { $0.id == imported.id }))
        try await repository.deleteImportedLUT(identifier: imported.id)
        let deletedLibrary = try await repository.library()
        XCTAssertFalse(deletedLibrary.imported.contains(where: { $0.id == imported.id }))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testHSLCurveWhitesAndCropChangePixelsWithoutChangingSourceImage() throws {
        let source = CIImage(color: CIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        var state = PhotoEditState.identity
        state.hsl[.red] = HSLAdjustment(hue: 0, saturation: -1, luminance: 0)
        state.light.whites = 0.5
        state.curves[.master] = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 1)]
        state.transform.crop = NormalizedCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let output = PhotoImagePipeline.apply(state, to: source)
        let pixel = try rgba(of: output)
        XCTAssertEqual(output.extent.width, 4, accuracy: 0.01)
        XCTAssertEqual(output.extent.height, 4, accuracy: 0.01)
        XCTAssertLessThan(abs(pixel.x - pixel.y), 0.12, "red HSL saturation must affect red hue only")
        XCTAssertLessThan(abs(pixel.y - pixel.z), 0.12)
        XCTAssertEqual(source.extent, CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    func testPreviewAndExportUseSameColorPipelineAndDoNotModifySourceFile() async throws {
        let sourceURL = temporaryDirectory.appending(path: "source.png")
        let originalData = try pngData(width: 64, height: 32, color: CGColor(red: 0.15, green: 0.4, blue: 0.8, alpha: 1))
        try originalData.write(to: sourceURL)
        var state = PhotoEditState.identity
        state.light.exposure = 0.35
        state.color.saturation = 0.15
        state.hsl[.blue] = HSLAdjustment(hue: -0.1, saturation: 0.2, luminance: 0.1)
        state.curves[.master] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.58), CurvePoint(x: 1, y: 1)]

        let preview = try await PreviewRenderer().render(sourceURL: sourceURL, state: state, lut: nil, maximumPixelSize: 1_024)
        let export = try await ExportRenderer().render(sourceURL: sourceURL, state: state, lut: nil)
        XCTAssertEqual(preview.pixelWidth, export.pixelWidth)
        XCTAssertEqual(preview.pixelHeight, export.pixelHeight)
        XCTAssertEqual(preview.histogram?.red.reduce(0, +), UInt32(preview.pixelWidth * preview.pixelHeight))
        let previewPixel = try rgba(ofImageData: preview.imageData)
        let exportPixel = try rgba(ofImageData: export.imageData)
        XCTAssertEqual(previewPixel.x, exportPixel.x, accuracy: 0.05)
        XCTAssertEqual(previewPixel.y, exportPixel.y, accuracy: 0.05)
        XCTAssertEqual(previewPixel.z, exportPixel.z, accuracy: 0.05)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
    }

    func testRAWJPEGPairingMatchesOnlySameRootFolderAndStem() {
        let rootID = UUID()
        let alternateRootID = UUID()
        let raw = libraryAsset(id: UUID(), rootID: rootID, relativePath: "DCIM/DSC00123.ARW")
        let jpeg = libraryAsset(id: UUID(), rootID: rootID, relativePath: "DCIM/dsc00123.JPG")
        let unrelatedFolderJPEG = libraryAsset(id: UUID(), rootID: rootID, relativePath: "Exports/DSC00123.JPG")
        let unrelatedRootJPEG = libraryAsset(id: UUID(), rootID: alternateRootID, relativePath: "DCIM/DSC00123.JPG")
        let ordinaryPhoto = libraryAsset(id: UUID(), rootID: rootID, relativePath: "DCIM/DSC00124.JPG")
        let assets = [raw, jpeg, unrelatedFolderJPEG, unrelatedRootJPEG, ordinaryPhoto]

        XCTAssertEqual(RAWJPEGPairing.visibleAssets(from: assets, preference: .showBoth).map(\.id), assets.map(\.id))
        XCTAssertEqual(
            RAWJPEGPairing.visibleAssets(from: assets, preference: .groupPairs).map(\.id),
            [raw, unrelatedFolderJPEG, unrelatedRootJPEG, ordinaryPhoto].map(\.id)
        )
        XCTAssertEqual(
            RAWJPEGPairing.visibleAssets(from: assets, preference: .preferRAW).map(\.id),
            [raw, unrelatedFolderJPEG, unrelatedRootJPEG, ordinaryPhoto].map(\.id)
        )
        XCTAssertEqual(RAWJPEGPairing.pairedRAWAssetIDs(in: assets), [raw.id])
        XCTAssertEqual(RAWJPEGPairing.pairedJPEGAssetIDs(in: assets), [jpeg.id])
    }

    func testImageFileExporterWritesNewJPEGHEIFAndTIFFFiles() throws {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 12, height: 8))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        for format in RAWExportFormat.allCases {
            let destination = temporaryDirectory.appending(path: "export.\(format.filenameExtension)")
            try ImageFileExporter.write(image: image, context: context, to: destination, format: format)
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
            XCTAssertGreaterThan(try Data(contentsOf: destination).count, 0)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, format.contentType.identifier)
        }
    }

    private func identityCubeData(dimension: Int) -> Data {
        var lines = ["TITLE \"Identity \(dimension)\"", "LUT_3D_SIZE \(dimension)", "DOMAIN_MIN 0 0 0", "DOMAIN_MAX 1 1 1"]
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let divisor = Double(dimension - 1)
                    lines.append("\(Double(red) / divisor) \(Double(green) / divisor) \(Double(blue) / divisor)")
                }
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func rgba(of image: CIImage) throws -> SIMD4<Double> {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var pixels = Array(repeating: UInt8(0), count: 4)
        context.render(image.cropped(to: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1)), toBitmap: &pixels, rowBytes: 4, bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return SIMD4<Double>(Double(pixels[0]) / 255, Double(pixels[1]) / 255, Double(pixels[2]) / 255, Double(pixels[3]) / 255)
    }

    private func rgba(ofImageData data: Data) throws -> SIMD4<Double> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StudioError.metadataExtractionFailed(path: "test image")
        }
        return try rgba(of: CIImage(cgImage: image))
    }

    private func pngData(width: Int, height: Int, color: CGColor) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StudioError.metadataExtractionFailed(path: "test fixture")
        }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw StudioError.metadataExtractionFailed(path: "test fixture") }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw StudioError.metadataExtractionFailed(path: "test fixture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StudioError.metadataExtractionFailed(path: "test fixture") }
        return result as Data
    }

    private func libraryAsset(id: UUID, rootID: UUID, relativePath: String) -> LibraryAssetRecord {
        let fileExtension = URL(filePath: relativePath).pathExtension.lowercased()
        return LibraryAssetRecord(
            id: id, rootID: rootID, rootDisplayName: "Test root", rootPath: "/test",
            relativePath: relativePath, mediaType: .photo, fileExtension: fileExtension,
            fileSize: 1, createdAt: nil, modifiedAt: nil, availability: .available,
            metadataState: .available, rating: 0, flag: .unflagged, width: nil, height: nil,
            captureDate: nil, cameraMake: nil, cameraModel: nil, lensModel: nil,
            focalLength: nil, aperture: nil, shutterSpeed: nil, iso: nil, orientation: nil,
            colorProfile: nil, gpsLatitude: nil, gpsLongitude: nil, duration: nil,
            frameRate: nil, codec: nil, videoCreationDate: nil
        )
    }
}
