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

    func testLocationTitleUsesTheCurrentRecordNameAndSafeFallback() {
        let rootID = UUID()
        let albumID = UUID()
        let stackID = UUID()
        let tagID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let root = MediaRootRecord(
            id: rootID,
            displayName: "旅行照片",
            bookmarkData: Data(),
            lastKnownPath: "/Volumes/Photos",
            volumeIdentifier: nil,
            availability: .online,
            createdAt: date,
            lastScannedAt: nil,
            lastScanError: nil
        )
        let album = AlbumRecord(
            id: albumID,
            name: "精选",
            kind: .album,
            criteria: nil,
            createdAt: date,
            updatedAt: date
        )
        let stack = AssetStackRecord(
            id: stackID,
            title: "连拍",
            kind: .burst,
            createdAt: date,
            updatedAt: date,
            assetCount: 3
        )
        let tag = TagRecord(id: tagID, name: "家庭", createdAt: date)

        XCTAssertEqual(LibraryLocation.photos.title(mediaRoots: [], albums: [], stacks: [], tags: []), "照片")
        XCTAssertEqual(LibraryLocation.root(rootID).title(mediaRoots: [root], albums: [], stacks: [], tags: []), "旅行照片")
        XCTAssertEqual(LibraryLocation.album(albumID).title(mediaRoots: [], albums: [album], stacks: [], tags: []), "精选")
        XCTAssertEqual(LibraryLocation.stack(stackID).title(mediaRoots: [], albums: [], stacks: [stack], tags: []), "连拍")
        XCTAssertEqual(LibraryLocation.tag(tagID).title(mediaRoots: [], albums: [], stacks: [], tags: [tag]), "家庭")
        XCTAssertEqual(LibraryLocation.tag(UUID()).title(mediaRoots: [], albums: [], stacks: [], tags: []), "标签")
    }
}
