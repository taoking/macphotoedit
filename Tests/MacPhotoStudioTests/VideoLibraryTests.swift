import XCTest
@testable import MacPhotoStudio

final class VideoLibraryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudioVideoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testFilmstripSamplingCoversVideoTimelineIncludingPosterFrame() {
        XCTAssertEqual(
            VideoFilmstripRenderer.samplePositions(duration: 12, frameCount: 5),
            [0, 3, 6, 9, 12]
        )
        XCTAssertEqual(VideoFilmstripRenderer.samplePositions(duration: 0, frameCount: 5), [0])
        XCTAssertEqual(VideoFilmstripRenderer.samplePositions(duration: 12, frameCount: 1), [0])
    }

    func testFilmstripStorePersistsOnlyDerivedFrames() throws {
        let store = VideoFilmstripStore(directoryURL: temporaryDirectory)
        let assetID = UUID()
        let frames = [Data([0xFF, 0xD8, 0x01]), Data([0xFF, 0xD8, 0x02])]

        try store.store(frames, for: assetID)

        XCTAssertEqual(try store.data(for: assetID, frameCount: 2), frames)
        XCTAssertNil(try store.data(for: UUID(), frameCount: 2))

        let updatedFrames = [Data([0xFF, 0xD8, 0x03]), Data([0xFF, 0xD8, 0x04])]
        try store.store(updatedFrames, for: assetID, cacheVersion: "changed-source")
        XCTAssertEqual(try store.data(for: assetID, cacheVersion: "changed-source", frameCount: 2), updatedFrames)
        XCTAssertEqual(try store.data(for: assetID, frameCount: 2), frames)
    }
}
