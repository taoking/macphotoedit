import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacPhotoStudio

final class SimilarPhotoDetectionTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioSimilarTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDHashTreatsResizedAndUniformlyAdjustedImageAsSimilarButSeparatesDifferentStructure() throws {
        let base = try makePatternImage(width: 144, height: 96, brightnessShift: 0, inverted: false)
        let resized = try makePatternImage(width: 288, height: 192, brightnessShift: 0, inverted: false)
        let adjusted = try makePatternImage(width: 144, height: 96, brightnessShift: 0.12, inverted: false)
        let different = try makePatternImage(width: 144, height: 96, brightnessShift: 0, inverted: true)

        let baseHash = try PerceptualHash.digest(of: base)
        let resizedDistance = try XCTUnwrap(PerceptualHash.hammingDistance(baseHash, try PerceptualHash.digest(of: resized)))
        let adjustedDistance = try XCTUnwrap(PerceptualHash.hammingDistance(baseHash, try PerceptualHash.digest(of: adjusted)))
        let differentDistance = try XCTUnwrap(PerceptualHash.hammingDistance(baseHash, try PerceptualHash.digest(of: different)))

        XCTAssertLessThanOrEqual(resizedDistance, SimilarPhotoScanner.maximumHammingDistance)
        XCTAssertLessThanOrEqual(adjustedDistance, SimilarPhotoScanner.maximumHammingDistance)
        XCTAssertGreaterThan(differentDistance, SimilarPhotoScanner.maximumHammingDistance)
        XCTAssertEqual(PerceptualHash.similarityScore(forHammingDistance: 0), 100)
        XCTAssertLessThan(PerceptualHash.similarityScore(forHammingDistance: differentDistance), 88)
    }

    func testSimilarPhotoScannerCachesHashesGroupsOnlySimilarPhotosAndPreservesSources() async throws {
        let mediaDirectory = temporaryDirectory.appending(path: "Media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let originalURL = mediaDirectory.appending(path: "original.jpg")
        let resizedURL = mediaDirectory.appending(path: "resized.jpg")
        let adjustedURL = mediaDirectory.appending(path: "adjusted.jpg")
        let differentURL = mediaDirectory.appending(path: "different.jpg")
        try writeJPEG(try makePatternImage(width: 144, height: 96, brightnessShift: 0, inverted: false), to: originalURL, quality: 0.95)
        try writeJPEG(try makePatternImage(width: 288, height: 192, brightnessShift: 0, inverted: false), to: resizedURL, quality: 0.75)
        try writeJPEG(try makePatternImage(width: 144, height: 96, brightnessShift: 0.10, inverted: false), to: adjustedURL, quality: 0.85)
        try writeJPEG(try makePatternImage(width: 144, height: 96, brightnessShift: 0, inverted: true), to: differentURL, quality: 0.95)
        let originalBytes = try Data(contentsOf: originalURL)

        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let rootStore = MediaRootStore(catalogStore: store)
        let root = try await rootStore.add(directoryURL: mediaDirectory)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await scan(
            [originalURL, resizedURL, adjustedURL, differentURL].map {
                scannedAsset(root: root, url: $0, date: timestamp)
            },
            root: root,
            store: store
        )

        let scanner = SimilarPhotoScanner(catalogStore: store, mediaRootStore: rootStore)
        let firstReport = try await scanner.scan()
        XCTAssertEqual(firstReport.candidateCount, 4)
        XCTAssertEqual(firstReport.hashedCount, 4)
        XCTAssertEqual(firstReport.reusedHashCount, 0)
        XCTAssertTrue(firstReport.failures.isEmpty)
        let group = try XCTUnwrap(firstReport.groups.first)
        XCTAssertEqual(Set(group.assets.map(\.relativePath)), Set(["original.jpg", "resized.jpg", "adjusted.jpg"]))
        XCTAssertFalse(group.matches.isEmpty)
        XCTAssertFalse(group.assets.contains(where: { $0.relativePath == "different.jpg" }))
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes)

        let secondReport = try await scanner.scan()
        XCTAssertEqual(secondReport.hashedCount, 0)
        XCTAssertEqual(secondReport.reusedHashCount, 4)
        XCTAssertEqual(secondReport.groups.count, 1)
        let persistedHashes = try await store.currentPerceptualHashes()
        XCTAssertEqual(persistedHashes.count, 4)
    }

    private func makePatternImage(
        width: Int,
        height: Int,
        brightnessShift: CGFloat,
        inverted: Bool
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StudioError.exportFailed(message: "Could not create test bitmap.") }
        let columns = 12
        let rows = 8
        for row in 0..<rows {
            for column in 0..<columns {
                let raw = CGFloat((column * 37 + row * 19 + column * row * 11) % 180) / 255 + 0.10
                let adjusted = min(max(raw * 0.72 + brightnessShift, 0), 1)
                let value = inverted ? 1 - adjusted : adjusted
                context.setFillColor(red: value, green: value * 0.92, blue: value * 0.84, alpha: 1)
                context.fill(CGRect(
                    x: CGFloat(column) * CGFloat(width) / CGFloat(columns),
                    y: CGFloat(row) * CGFloat(height) / CGFloat(rows),
                    width: CGFloat(width) / CGFloat(columns) + 1,
                    height: CGFloat(height) / CGFloat(rows) + 1
                ))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw StudioError.exportFailed(message: "Could not create test JPEG.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StudioError.exportFailed(message: "Could not write test JPEG.")
        }
    }

    private func scan(_ assets: [ScannedMediaAsset], root: MediaRootRecord, store: CatalogStore) async throws {
        let scanID = UUID()
        try await store.beginScan(rootID: root.id, scanID: scanID)
        try await store.applyScanBatch(assets, scanID: scanID)
        try await store.finishScan(rootID: root.id, scanID: scanID)
    }

    private func scannedAsset(root: MediaRootRecord, url: URL, date: Date) -> ScannedMediaAsset {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return ScannedMediaAsset(
            rootID: root.id,
            relativePath: url.lastPathComponent,
            fileResourceIdentifier: url.lastPathComponent,
            mediaType: .photo,
            fileExtension: url.pathExtension,
            fileSize: Int64(values?.fileSize ?? 0),
            createdAt: date,
            modifiedAt: date,
            metadata: .unavailable
        )
    }
}
