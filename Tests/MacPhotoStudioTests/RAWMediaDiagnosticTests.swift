import Foundation
import XCTest
@testable import MacPhotoStudio

final class RAWMediaDiagnosticTests: XCTestCase {
    func testUnsupportedSourceFailsClosedWritesOnlyTextReportAndPreservesSource() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioRAWDiagnosticTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appending(path: "not-a-raw.png")
        let originalData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try originalData.write(to: sourceURL)

        let report = await RAWMediaDiagnosticService.inspect(sourceURL: sourceURL)

        XCTAssertEqual(report.fileExtension, "png")
        XCTAssertEqual(report.fileSize, Int64(originalData.count))
        XCTAssertFalse(report.cirawFilterAvailable)
        XCTAssertFalse(report.previewRender.succeeded)
        XCTAssertFalse(report.export.succeeded)
        XCTAssertNil(report.recognizedDecoderDescriptor)
        XCTAssertTrue(report.sourceSignatureUnchanged ?? false)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)

        let logsDirectory = temporaryDirectory.appending(path: "logs", directoryHint: .isDirectory)
        let reportURL = try report.write(to: logsDirectory)
        let reportText = try String(contentsOf: reportURL, encoding: .utf8)
        XCTAssertTrue(reportText.contains("CIRAWFilter availability: unavailable"))
        XCTAssertTrue(reportText.contains("Decoder ICC payload match:"))
        XCTAssertTrue(reportText.contains("Pipeline normalized working descriptor:"))
        XCTAssertTrue(reportText.contains("Available RAW controls:"))
        XCTAssertTrue(reportText.contains("Output ICC profile:"))
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
    }

    func testCapabilityListingContainsOnlyControlsExposedByThePipeline() {
        let capabilities = RAWCapabilities(
            lensCorrection: true,
            luminanceNoiseReduction: true,
            sharpness: true
        )

        XCTAssertEqual(
            capabilities.availableControlNames,
            ["曝光", "色温", "色调", "阴影偏移", "亮度降噪", "RAW 锐化", "镜头校正"]
        )
        XCTAssertFalse(capabilities.availableControlNames.contains("高光恢复"))
        XCTAssertFalse(capabilities.availableControlNames.contains("局部色调"))
    }
}
