import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import XCTest
@testable import MacPhotoStudio

final class ColorOutputTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioColorOutputTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSDRExportsRoundTripTheRequestedICCProfileForEverySupportedFormat() throws {
        let image = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))
        let context = CIContext(options: [.useSoftwareRenderer: true])

        for format in PhotoExportFormat.allCases where format.isSupported {
            for colorSpace in PhotoColorSpace.outputSpaces {
                let destination = temporaryDirectory
                    .appending(path: "\(format.rawValue)-\(colorSpace.rawValue)")
                    .appendingPathExtension(format.filenameExtension)
                try ImageFileExporter.write(
                    image: image,
                    context: context,
                    sourceURL: nil,
                    to: destination,
                    options: PhotoExportOptions(
                        format: format,
                        outputColorSpace: colorSpace,
                        dynamicRange: .sdr
                    ),
                    allowsOverwrite: false
                )

                let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
                let reopened = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                let actualColorSpace = try XCTUnwrap(reopened.colorSpace)
                XCTAssertTrue(
                    colorSpace.matchesEmbeddedProfile(of: actualColorSpace),
                    "\(format.title) 必须保留 \(colorSpace.title) ICC profile，而不是替换为其他输出空间。"
                )
            }
        }
    }

    func testRec709AndRec2020AreNotSRGBFallbacks() {
        XCTAssertFalse(PhotoColorSpace.rec709.matchesEmbeddedProfile(of: PhotoColorSpace.sRGB.cgColorSpace))
        XCTAssertFalse(PhotoColorSpace.rec2020.matchesEmbeddedProfile(of: PhotoColorSpace.sRGB.cgColorSpace))
        XCTAssertFalse(PhotoColorSpace.rec709.matchesEmbeddedProfile(of: PhotoColorSpace.rec2020.cgColorSpace))
        XCTAssertEqual(PhotoColorSpace.rec709.defaultTransferFunction, .rec709)
        XCTAssertEqual(PhotoColorSpace.rec2020.defaultTransferFunction, .rec709)
    }
}
