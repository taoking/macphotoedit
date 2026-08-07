import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacPhotoStudio

final class ThumbnailLoaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioThumbnailTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testPhotoThumbnailRendererProducesJPEGDataAtBothLibrarySizes() async throws {
        let sourceURL = temporaryDirectory.appending(path: "source.png")
        try makePNGData().write(to: sourceURL)

        let thumbnail256 = try await ThumbnailRenderer.render(
            sourceURL: sourceURL,
            mediaType: .photo,
            maximumPixelSize: 256
        )
        let thumbnail512 = try await ThumbnailRenderer.render(
            sourceURL: sourceURL,
            mediaType: .photo,
            maximumPixelSize: 512
        )

        XCTAssertNotNil(thumbnail256)
        XCTAssertNotNil(thumbnail512)
        XCTAssertTrue(thumbnail256?.starts(with: Data([0xFF, 0xD8])) == true)
        XCTAssertTrue(thumbnail512?.starts(with: Data([0xFF, 0xD8])) == true)
    }

    private func makePNGData() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StudioError.metadataExtractionFailed(path: "test fixture")
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let image = context.makeImage() else {
            throw StudioError.metadataExtractionFailed(path: "test fixture")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw StudioError.metadataExtractionFailed(path: "test fixture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StudioError.metadataExtractionFailed(path: "test fixture")
        }
        return output as Data
    }
}
