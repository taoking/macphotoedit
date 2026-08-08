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
        XCTAssertEqual(firstReport.metrics.imageIODecodeCount, 4)
        XCTAssertEqual(firstReport.metrics.groupCount, firstReport.groups.count)
        XCTAssertEqual(firstReport.metrics.failureCount, firstReport.failures.count)
        XCTAssertGreaterThanOrEqual(firstReport.metrics.candidateFetchDuration, 0)
        XCTAssertGreaterThanOrEqual(firstReport.metrics.imageIODecodeDuration, 0)
        XCTAssertGreaterThanOrEqual(firstReport.metrics.groupingDuration, 0)
        XCTAssertGreaterThanOrEqual(firstReport.metrics.totalScanDuration, 0)
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

        let changedModifiedDate = timestamp.addingTimeInterval(60)
        try await scan(
            [originalURL, resizedURL, adjustedURL, differentURL].map { url in
                scannedAsset(root: root, url: url, date: url == originalURL ? changedModifiedDate : timestamp)
            },
            root: root,
            store: store
        )
        let modifiedReport = try await scanner.scan()
        XCTAssertEqual(modifiedReport.hashedCount, 1)
        XCTAssertEqual(modifiedReport.reusedHashCount, 3)

        let fileHandle = try FileHandle(forWritingTo: originalURL)
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: Data([0]))
        try fileHandle.close()
        let enlargedOriginalSize = Int64(try Data(contentsOf: originalURL).count)
        XCTAssertEqual(enlargedOriginalSize, Int64(originalBytes.count + 1))
        try await scan(
            [originalURL, resizedURL, adjustedURL, differentURL].map { url in
                scannedAsset(
                    root: root,
                    url: url,
                    date: url == originalURL ? changedModifiedDate : timestamp,
                    fileSizeOverride: url == originalURL ? enlargedOriginalSize : nil
                )
            },
            root: root,
            store: store
        )
        let resizedReport = try await scanner.scan()
        XCTAssertEqual(resizedReport.hashedCount, 1)
        XCTAssertEqual(resizedReport.reusedHashCount, 3)

        try await store.updateRootAvailability(.offline, errorMessage: "test offline", rootID: root.id)
        let offlineReport = try await scanner.scan()
        XCTAssertEqual(offlineReport.candidateCount, 0)
        XCTAssertEqual(offlineReport.hashedCount, 0)
        XCTAssertEqual(offlineReport.reusedHashCount, 0)
        let offlineHashes = try await store.currentPerceptualHashes()
        XCTAssertTrue(offlineHashes.isEmpty)
    }

    func testSimilarPhotoScannerCancellationCheckpointsCoverHashingRootSwitchingAndGrouping() async throws {
        let firstDirectory = temporaryDirectory.appending(path: "First", directoryHint: .isDirectory)
        let secondDirectory = temporaryDirectory.appending(path: "Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstURL = firstDirectory.appending(path: "first.jpg")
        let secondURL = secondDirectory.appending(path: "second.jpg")
        try writeJPEG(try makePatternImage(width: 144, height: 96, brightnessShift: 0, inverted: false), to: firstURL, quality: 0.9)
        try writeJPEG(try makePatternImage(width: 144, height: 96, brightnessShift: 0.1, inverted: false), to: secondURL, quality: 0.9)

        let paths = try CatalogPaths.create(in: temporaryDirectory)
        let store = CatalogStore(databaseURL: paths.catalogDatabaseURL)
        try await store.bootstrap()
        let rootStore = MediaRootStore(catalogStore: store)
        let firstRoot = try await rootStore.add(directoryURL: firstDirectory)
        let secondRoot = try await rootStore.add(directoryURL: secondDirectory)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await scan([scannedAsset(root: firstRoot, url: firstURL, date: timestamp)], root: firstRoot, store: store)
        try await scan([scannedAsset(root: secondRoot, url: secondURL, date: timestamp)], root: secondRoot, store: store)
        let scanner = SimilarPhotoScanner(catalogStore: store, mediaRootStore: rootStore)

        try await assertScannerCancellation(scanner, target: .hashing)
        let hashesAfterHashCancellation = try await store.currentPerceptualHashes()
        XCTAssertTrue(hashesAfterHashCancellation.isEmpty)

        try await assertScannerCancellation(scanner, target: .secondRootResolution)
        let hashesAfterRootCancellation = try await store.currentPerceptualHashes()
        XCTAssertEqual(hashesAfterRootCancellation.count, 1)

        _ = try await scanner.scan()
        let hashesBeforeGroupingCancellation = try await store.currentPerceptualHashes()
        XCTAssertEqual(hashesBeforeGroupingCancellation.count, 2)
        try await assertScannerCancellation(scanner, target: .grouping)
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

    private func scannedAsset(
        root: MediaRootRecord,
        url: URL,
        date: Date,
        fileSizeOverride: Int64? = nil
    ) -> ScannedMediaAsset {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return ScannedMediaAsset(
            rootID: root.id,
            relativePath: url.lastPathComponent,
            fileResourceIdentifier: url.lastPathComponent,
            mediaType: .photo,
            fileExtension: url.pathExtension,
            fileSize: fileSizeOverride ?? Int64(values?.fileSize ?? 0),
            createdAt: date,
            modifiedAt: date,
            metadata: .unavailable
        )
    }

    private func assertScannerCancellation(
        _ scanner: SimilarPhotoScanner,
        target: SimilarPhotoScanCancellationTarget
    ) async throws {
        let gate = SimilarPhotoScanCancellationGate(target: target)
        do {
            _ = try await scanner.scan(checkpoint: { stage, _ in
                try await gate.checkpoint(stage)
            })
            XCTFail("Expected scan cancellation at \(target).")
        } catch is CancellationError {
            // Expected: the scanner must propagate cancellation rather than
            // convert it into a partial-success failure entry.
        }
    }
}

private enum SimilarPhotoScanCancellationTarget: Sendable {
    case hashing
    case secondRootResolution
    case grouping
}

private actor SimilarPhotoScanCancellationGate {
    private let target: SimilarPhotoScanCancellationTarget
    private var rootResolutionCount = 0

    init(target: SimilarPhotoScanCancellationTarget) {
        self.target = target
    }

    func checkpoint(_ stage: SimilarPhotoScanCheckpoint) throws {
        switch (target, stage) {
        case (.hashing, .hashing), (.grouping, .grouping):
            throw CancellationError()
        case (.secondRootResolution, .rootResolution):
            rootResolutionCount += 1
            if rootResolutionCount == 2 {
                throw CancellationError()
            }
        default:
            break
        }
    }
}
