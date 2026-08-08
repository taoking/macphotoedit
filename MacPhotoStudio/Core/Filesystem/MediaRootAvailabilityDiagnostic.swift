import Foundation

struct MediaRootResourceSnapshot: Sendable, Equatable {
    let directoryExists: Bool
    let isDirectory: Bool
    let isReadable: Bool?
    let isWritable: Bool?
    let volumeName: String?
    let volumeIdentifier: String?
    let volumeIsLocal: Bool?
    let volumeIsRemovable: Bool?
    let volumeIsEjectable: Bool?
}

/// Observational availability data for a referenced media root. It intentionally
/// includes no file contents: the report is safe to retain in Application
/// Support and helps distinguish an unplugged volume from a failed bookmark.
struct MediaRootAvailabilityDiagnostic: Sendable, Equatable {
    let rootID: UUID
    let displayName: String
    let lastKnownPath: String
    let resolvedPath: String?
    let bookmarkResolved: Bool
    let bookmarkWasStale: Bool?
    let bookmarkResolutionError: String?
    let securityScopedAccessStarted: Bool?
    let resourceSnapshot: MediaRootResourceSnapshot?
    let volumeIdentifierMatchesStoredValue: Bool?
    let availability: MediaRootAvailability
    let errorMessage: String?

    func text() -> String {
        let snapshot = resourceSnapshot
        return """
        Root: \(displayName)
        Root ID: \(rootID.uuidString)
        Last known path: \(lastKnownPath)
        Resolved path: \(resolvedPath ?? "unavailable")
        Bookmark resolved: \(bookmarkResolved ? "yes" : "no")
        Bookmark stale: \(bookmarkWasStale.map { $0 ? "yes" : "no" } ?? "unavailable")
        Bookmark resolution error: \(bookmarkResolutionError ?? "none")
        Security-scoped access started: \(securityScopedAccessStarted.map { $0 ? "yes" : "no" } ?? "unavailable")
        Directory exists: \(snapshot?.directoryExists == true ? "yes" : "no")
        Is directory: \(snapshot?.isDirectory == true ? "yes" : "no")
        Readable: \(snapshot?.isReadable.map { $0 ? "yes" : "no" } ?? "unavailable")
        Writable: \(snapshot?.isWritable.map { $0 ? "yes" : "no" } ?? "unavailable")
        Volume name: \(snapshot?.volumeName ?? "unavailable")
        Volume UUID: \(snapshot?.volumeIdentifier ?? "unavailable")
        Stored volume UUID matches: \(volumeIdentifierMatchesStoredValue.map { $0 ? "yes" : "no" } ?? "unavailable")
        Volume local/removable/ejectable: \(snapshot?.volumeIsLocal.map(String.init) ?? "unavailable") / \(snapshot?.volumeIsRemovable.map(String.init) ?? "unavailable") / \(snapshot?.volumeIsEjectable.map(String.init) ?? "unavailable")
        Availability: \(availability.rawValue)
        Detail: \(errorMessage ?? "none")
        """
    }
}

struct MediaRootAvailabilityReport: Sendable, Equatable {
    let generatedAt: Date
    let diagnostics: [MediaRootAvailabilityDiagnostic]

    func text() -> String {
        let entries = diagnostics.isEmpty
            ? "No media roots are registered."
            : diagnostics.map { $0.text() }.joined(separator: "\n\n")
        return """
        Mac Photo Studio Media Root Availability Report
        Generated at: \(generatedAt.ISO8601Format())

        \(entries)
        """
    }

    func write(to logsDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let destination = logsDirectory
            .appending(path: "media-root-availability-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try Data(text().utf8).write(to: destination, options: .atomic)
        return destination
    }
}
