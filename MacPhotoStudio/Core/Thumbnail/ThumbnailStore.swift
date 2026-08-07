import Foundation

struct ThumbnailStore {
    let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func url(for assetID: UUID, maximumPixelSize: Int) -> URL {
        directoryURL.appending(path: "\(assetID.uuidString.lowercased())-\(maximumPixelSize).jpg")
    }

    func data(for assetID: UUID, maximumPixelSize: Int) throws -> Data? {
        let fileURL = url(for: assetID, maximumPixelSize: maximumPixelSize)
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func store(_ data: Data, for assetID: UUID, maximumPixelSize: Int) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: url(for: assetID, maximumPixelSize: maximumPixelSize), options: .atomic)
    }

    func remove(for assetID: UUID, maximumPixelSize: Int) throws {
        let fileURL = url(for: assetID, maximumPixelSize: maximumPixelSize)
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
