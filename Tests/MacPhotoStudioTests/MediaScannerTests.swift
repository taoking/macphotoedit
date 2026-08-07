import XCTest
@testable import MacPhotoStudio

private actor ScanCollector {
    private var assets: [ScannedMediaAsset] = []

    func append(_ batch: [ScannedMediaAsset]) {
        assets.append(contentsOf: batch)
    }

    func allAssets() -> [ScannedMediaAsset] {
        assets
    }
}

private actor ScanCounter {
    private var count = 0

    func append(_ batch: [ScannedMediaAsset]) {
        count += batch.count
    }

    func value() -> Int {
        count
    }
}

final class MediaScannerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testScannerRecursivelyFindsPhotosAndVideosWithoutFailingOnBadVideoMetadata() async throws {
        let nestedDirectory = temporaryDirectory.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try validPNGData.write(to: nestedDirectory.appending(path: "photo.PNG"))
        try Data([0, 1, 2, 3]).write(to: temporaryDirectory.appending(path: "unreadable.MP4"))
        try Data("not media".utf8).write(to: temporaryDirectory.appending(path: "notes.txt"))

        let collector = ScanCollector()
        let scanner = MediaScanner()
        let rootID = UUID()
        let summary = try await scanner.scan(
            rootURL: temporaryDirectory,
            rootID: rootID,
            knownFingerprints: [:],
            control: ScanControl(),
            commitBatch: { batch in await collector.append(batch) },
            reportProgress: { _ in }
        )
        let scannedAssets = await collector.allAssets()

        XCTAssertEqual(summary.discoveredMedia, 2)
        XCTAssertEqual(scannedAssets.map(\.mediaType).sorted { $0.rawValue < $1.rawValue }, [.photo, .video])
        XCTAssertEqual(scannedAssets.first(where: { $0.mediaType == .photo })?.relativePath, "nested/photo.PNG")
        XCTAssertEqual(scannedAssets.first(where: { $0.mediaType == .video })?.metadata, .unavailable)
    }

    func testScannerSkipsMetadataExtractionForUnchangedFingerprint() async throws {
        let imageURL = temporaryDirectory.appending(path: "photo.png")
        try validPNGData.write(to: imageURL)
        let values = try imageURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        let fileSize = Int64(values.fileSize ?? 0)
        let identifier = values.fileResourceIdentifier.map { String(describing: $0) }
        let collector = ScanCollector()

        _ = try await MediaScanner().scan(
            rootURL: temporaryDirectory,
            rootID: UUID(),
            knownFingerprints: [
                "photo.png": AssetFingerprint(
                    fileSize: fileSize,
                    modifiedAt: values.contentModificationDate,
                    fileResourceIdentifier: identifier
                )
            ],
            control: ScanControl(),
            commitBatch: { batch in await collector.append(batch) },
            reportProgress: { _ in }
        )

        let scannedAssets = await collector.allAssets()
        XCTAssertEqual(scannedAssets.first?.metadata, .unchanged)
    }

    func testCancelledScanStopsBeforeItEnumeratesFiles() async throws {
        try validPNGData.write(to: temporaryDirectory.appending(path: "photo.png"))
        let control = ScanControl()
        await control.cancel()

        do {
            _ = try await MediaScanner().scan(
                rootURL: temporaryDirectory,
                rootID: UUID(),
                knownFingerprints: [:],
                control: control,
                commitBatch: { _ in },
                reportProgress: { _ in }
            )
            XCTFail("Cancelled scans must not report success")
        } catch is CancellationError {
            // Expected: cancellation is observed before metadata work or database writes.
        }
    }

    func testPhotoMetadataExtractorReadsImageDimensions() throws {
        let imageURL = temporaryDirectory.appending(path: "photo.png")
        try validPNGData.write(to: imageURL)

        let metadata = try MediaMetadataExtractor().extractPhoto(from: imageURL)

        XCTAssertEqual(metadata.width, 1)
        XCTAssertEqual(metadata.height, 1)
    }

    func testScannerProcessesTwoThousandTemporaryAssetsInBatches() async throws {
        for index in 0..<2_000 {
            try validPNGData.write(to: temporaryDirectory.appending(path: "asset-\(index).png"))
        }

        let counter = ScanCounter()
        let summary = try await MediaScanner().scan(
            rootURL: temporaryDirectory,
            rootID: UUID(),
            knownFingerprints: [:],
            control: ScanControl(),
            commitBatch: { batch in await counter.append(batch) },
            reportProgress: { _ in }
        )

        XCTAssertEqual(summary.discoveredMedia, 2_000)
        XCTAssertEqual(summary.indexedMedia, 2_000)
        let indexedCount = await counter.value()
        XCTAssertEqual(indexedCount, 2_000)
    }

    private var validPNGData: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL7WAAAAABJRU5ErkJggg==")!
    }
}
