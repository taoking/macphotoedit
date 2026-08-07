import Foundation

struct CatalogPaths: Sendable, Equatable {
    let catalogDirectory: URL
    let catalogDatabaseURL: URL
    let thumbnailsDirectory: URL
    let videoFilmstripsDirectory: URL
    let previewsDirectory: URL
    let lutDirectory: URL
    let presetsDirectory: URL
    let logsDirectory: URL

    static func live(
        fileManager: FileManager = .default,
        applicationName: String = "MacPhotoStudio"
    ) throws -> CatalogPaths {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StudioError.applicationSupportUnavailable
        }

        return try create(in: applicationSupport.appending(path: applicationName), fileManager: fileManager)
    }

    static func create(in catalogDirectory: URL, fileManager: FileManager = .default) throws -> CatalogPaths {
        let paths = CatalogPaths(
            catalogDirectory: catalogDirectory,
            catalogDatabaseURL: catalogDirectory.appending(path: "catalog.sqlite"),
            thumbnailsDirectory: catalogDirectory.appending(path: "thumbnails", directoryHint: .isDirectory),
            videoFilmstripsDirectory: catalogDirectory.appending(path: "video-filmstrips", directoryHint: .isDirectory),
            previewsDirectory: catalogDirectory.appending(path: "previews", directoryHint: .isDirectory),
            lutDirectory: catalogDirectory.appending(path: "lut", directoryHint: .isDirectory),
            presetsDirectory: catalogDirectory.appending(path: "presets", directoryHint: .isDirectory),
            logsDirectory: catalogDirectory.appending(path: "logs", directoryHint: .isDirectory)
        )

        for directory in [
            paths.catalogDirectory,
            paths.thumbnailsDirectory,
            paths.videoFilmstripsDirectory,
            paths.previewsDirectory,
            paths.lutDirectory,
            paths.presetsDirectory,
            paths.logsDirectory
        ] {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw StudioError.directoryCreationFailed(path: directory.path(percentEncoded: false))
            }
        }

        return paths
    }
}
