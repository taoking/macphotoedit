import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import MacPhotoStudio

final class RAWColorPipelineTests: XCTestCase {
    func testRAWDecoderOutputIsMaterializedIntoExplicitLinearWorkingSpace() throws {
        let sourceColorSpace = PhotoColorSpace.displayP3.cgColorSpace
        let decodedImage = try image(colorSpace: sourceColorSpace)
        let result = try RAWColorPipeline.prepare(
            decoderOutput: decodedImage,
            sourceURL: URL(filePath: "/tmp/test-input.dng")
        )

        XCTAssertEqual(result.decoderOutputColor, .displayP3)
        XCTAssertEqual(result.pipelineInputColor, .linearWorking)
        let normalizedColorSpace = try XCTUnwrap(result.image.colorSpace)
        XCTAssertTrue(PhotoColorSpace.extendedLinearSRGB.matchesEmbeddedProfile(of: normalizedColorSpace))
        XCTAssertNotEqual(result.pipelineInputColor, .sRGB)
    }

    func testRAWDecoderOutputWithUnknownProfileIsRejectedWithoutSRGBFallback() throws {
        let genericLinear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericRGBLinear))
        let decodedImage = try image(colorSpace: genericLinear)

        XCTAssertThrowsError(try RAWColorPipeline.prepare(
            decoderOutput: decodedImage,
            sourceURL: URL(filePath: "/tmp/unknown-profile.arw")
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("拒绝按 sRGB 假设"))
        }
    }

    private func image(colorSpace: CGColorSpace) throws -> CIImage {
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StudioError.metadataExtractionFailed(path: "RAW color test")
        }
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return CIImage(cgImage: try XCTUnwrap(context.makeImage()))
    }
}
