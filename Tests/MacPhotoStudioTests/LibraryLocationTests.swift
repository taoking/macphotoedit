import XCTest
@testable import MacPhotoStudio

final class LibraryLocationTests: XCTestCase {
    func testStandardLocationsMapToExistingLibraryQueries() {
        let rootID = UUID()
        let albumID = UUID()
        let stackID = UUID()
        let tagID = UUID()

        XCTAssertEqual(LibraryLocation.all.libraryQuery(albums: []), .all)
        XCTAssertEqual(LibraryLocation.photos.libraryQuery(albums: []), LibraryQuery(mediaType: .photo))
        XCTAssertEqual(LibraryLocation.videos.libraryQuery(albums: []), LibraryQuery(mediaType: .video))
        XCTAssertEqual(LibraryLocation.root(rootID).libraryQuery(albums: []), LibraryQuery(rootID: rootID))
        XCTAssertEqual(LibraryLocation.album(albumID).libraryQuery(albums: []), LibraryQuery(albumID: albumID))
        XCTAssertEqual(LibraryLocation.stack(stackID).libraryQuery(albums: []), LibraryQuery(stackID: stackID))
        XCTAssertEqual(LibraryLocation.tag(tagID).libraryQuery(albums: []), LibraryQuery(tagID: tagID))
    }

    func testSmartAlbumUsesItsExistingCriteriaAndFailsClosedWhenMissing() {
        let smartAlbumID = UUID()
        let criteria = SmartAlbumCriteria(minimumRating: 4, mediaType: .photo)
        let smartAlbum = AlbumRecord(
            id: smartAlbumID,
            name: "精选照片",
            kind: .smartAlbum,
            criteria: criteria,
            createdAt: .now,
            updatedAt: .now
        )

        XCTAssertEqual(
            LibraryLocation.smartAlbum(smartAlbumID).libraryQuery(albums: [smartAlbum]),
            LibraryQuery(smartAlbumCriteria: criteria)
        )
        XCTAssertEqual(LibraryLocation.smartAlbum(UUID()).libraryQuery(albums: [smartAlbum]), .all)
    }
}
