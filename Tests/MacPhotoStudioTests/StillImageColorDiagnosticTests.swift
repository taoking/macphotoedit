import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import MacPhotoStudio

final class StillImageColorDiagnosticTests: XCTestCase {
    func testValidationRunsPreviewAndEverySupportedExportInAllSDROutputSpaces() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioStillImageColorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appending(path: "source.png")
        let sourceImage = CIImage(color: CIColor(red: 0.23, green: 0.51, blue: 0.78, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 40))
        try CIContext(options: [.useSoftwareRenderer: true]).writePNGRepresentation(
            of: sourceImage,
            to: sourceURL,
            format: .RGBA8,
            colorSpace: PhotoColorSpace.sRGB.cgColorSpace
        )
        let sourceData = try Data(contentsOf: sourceURL)
        let outputRootURL = temporaryDirectory.appending(path: "validation-output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputRootURL, withIntermediateDirectories: true)

        let report = await StillImageColorDiagnosticService.validate(
            sourceURL: sourceURL,
            outputRootURL: outputRootURL,
            previewMaximumPixelSize: 128
        )

        XCTAssertEqual(report.sourceFormat, .png)
        XCTAssertEqual(report.sourceDimensions, RAWDecodedDimensions(width: 64, height: 40))
        XCTAssertEqual(report.sourceProfile?.descriptor, .sRGB)
        XCTAssertTrue(report.sourceSignatureUnchanged ?? false)
        XCTAssertEqual(report.previews.count, PhotoColorSpace.outputSpaces.count)
        XCTAssertTrue(report.previews.allSatisfy { $0.succeeded && $0.matchesRequestedProfile == true })

        let supportedFormats = PhotoExportFormat.allCases.filter(\.isSupported)
        XCTAssertEqual(report.exports.count, PhotoColorSpace.outputSpaces.count * PhotoExportFormat.allCases.count)
        for colorSpace in PhotoColorSpace.outputSpaces {
            for format in supportedFormats {
                let result = try XCTUnwrap(report.exports.first {
                    $0.format == format && $0.requestedColorSpace == colorSpace
                })
                XCTAssertTrue(result.succeeded, "\(format.title) / \(colorSpace.title) 应通过重开 ICC 验证：\(result.detail ?? "无详情")")
                XCTAssertEqual(result.matchesRequestedProfile, true)
                let directory = try XCTUnwrap(report.validationDirectoryURL)
                XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: result.filename).path(percentEncoded: false)))
            }
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertTrue(report.text().contains("Rec.2020 validation is SDR only"))
    }

    func testUnsupportedInputFailsClosedWithoutCreatingValidationOutput() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioStillImageColorUnsupportedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appending(path: "source.gif")
        let sourceData = Data([0x47, 0x49, 0x46, 0x38])
        try sourceData.write(to: sourceURL)
        let outputRootURL = temporaryDirectory.appending(path: "validation-output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputRootURL, withIntermediateDirectories: true)

        let report = await StillImageColorDiagnosticService.validate(
            sourceURL: sourceURL,
            outputRootURL: outputRootURL
        )

        XCTAssertNil(report.sourceFormat)
        XCTAssertNil(report.validationDirectoryURL)
        XCTAssertTrue(report.previews.allSatisfy { !$0.succeeded })
        XCTAssertTrue(report.exports.allSatisfy { !$0.succeeded })
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }
}
