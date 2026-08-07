import Foundation

struct ScanProgress: Sendable, Equatable {
    let rootID: UUID
    let inspectedFiles: Int
    let discoveredMedia: Int
    let indexedMedia: Int
    let metadataFailures: Int
}

struct ScanSummary: Sendable, Equatable {
    let inspectedFiles: Int
    let discoveredMedia: Int
    let indexedMedia: Int
    let metadataFailures: Int
}

struct MediaScanner: Sendable {
    private let metadataExtractor = MediaMetadataExtractor()
    private let batchSize = 64

    func scan(
        rootURL: URL,
        rootID: UUID,
        knownFingerprints: [String: AssetFingerprint],
        control: ScanControl,
        commitBatch: @escaping @Sendable ([ScannedMediaAsset]) async throws -> Void,
        reportProgress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ScanSummary {
        try await Task.detached(priority: .utility) {
            let resourceKeys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .fileResourceIdentifierKey
            ]
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            let standardizedRoot = rootURL.standardizedFileURL
            let rootPath = MediaScanner.normalizedPath(standardizedRoot)
            let rootPathPrefix = rootPath == "/" ? "/" : rootPath + "/"
            guard let enumerator = FileManager.default.enumerator(
                at: standardizedRoot,
                includingPropertiesForKeys: Array(resourceKeys),
                options: options,
                errorHandler: { url, error in
                    AppLogger.app.error("Unable to enumerate \(url.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return true
                }
            ) else {
                throw StudioError.directoryEnumerationFailed(path: rootPath)
            }

            var inspectedFiles = 0
            var discoveredMedia = 0
            var indexedMedia = 0
            var metadataFailures = 0
            var batch: [ScannedMediaAsset] = []

            while let fileURL = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                try await control.checkpoint()

                let values: URLResourceValues
                do {
                    values = try fileURL.resourceValues(forKeys: resourceKeys)
                } catch {
                    AppLogger.app.error("Unable to read file attributes: \(fileURL.path(percentEncoded: false), privacy: .public)")
                    continue
                }

                guard values.isRegularFile == true else { continue }
                inspectedFiles += 1

                let fileExtension = fileURL.pathExtension.lowercased()
                guard let mediaType = MediaScanner.mediaType(for: fileExtension) else { continue }
                let fullPath = MediaScanner.normalizedPath(fileURL.standardizedFileURL)
                guard fullPath.hasPrefix(rootPathPrefix) else { continue }
                let relativePath = rootPath == "/"
                    ? String(fullPath.dropFirst())
                    : String(fullPath.dropFirst(rootPathPrefix.count))
                let fileSize = Int64(values.fileSize ?? 0)
                let modifiedAt = values.contentModificationDate
                let resourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }

                let metadata: ExtractedMetadata
                if knownFingerprints[relativePath]?.matches(
                    fileSize: fileSize,
                    modifiedAt: modifiedAt,
                    fileResourceIdentifier: resourceIdentifier
                ) == true {
                    metadata = .unchanged
                } else {
                    do {
                        metadata = switch mediaType {
                        case .photo:
                            .photo(try metadataExtractor.extractPhoto(from: fileURL))
                        case .video:
                            .video(try await metadataExtractor.extractVideo(from: fileURL))
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        metadataFailures += 1
                        AppLogger.app.error("Metadata extraction failed for \(relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        metadata = .unavailable
                    }
                }

                batch.append(
                    ScannedMediaAsset(
                        rootID: rootID,
                        relativePath: relativePath,
                        fileResourceIdentifier: resourceIdentifier,
                        mediaType: mediaType,
                        fileExtension: fileExtension,
                        fileSize: fileSize,
                        createdAt: values.creationDate,
                        modifiedAt: modifiedAt,
                        metadata: metadata
                    )
                )
                discoveredMedia += 1

                if batch.count >= batchSize {
                    try await commitBatch(batch)
                    indexedMedia += batch.count
                    batch.removeAll(keepingCapacity: true)
                    await reportProgress(
                        ScanProgress(
                            rootID: rootID,
                            inspectedFiles: inspectedFiles,
                            discoveredMedia: discoveredMedia,
                            indexedMedia: indexedMedia,
                            metadataFailures: metadataFailures
                        )
                    )
                }
            }

            try Task.checkCancellation()
            try await control.checkpoint()
            if !batch.isEmpty {
                try await commitBatch(batch)
                indexedMedia += batch.count
            }
            let progress = ScanProgress(
                rootID: rootID,
                inspectedFiles: inspectedFiles,
                discoveredMedia: discoveredMedia,
                indexedMedia: indexedMedia,
                metadataFailures: metadataFailures
            )
            await reportProgress(progress)
            return ScanSummary(
                inspectedFiles: inspectedFiles,
                discoveredMedia: discoveredMedia,
                indexedMedia: indexedMedia,
                metadataFailures: metadataFailures
            )
        }.value
    }

    static func mediaType(for fileExtension: String) -> MediaType? {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng", "arw":
            return .photo
        case "mov", "mp4", "m4v":
            return .video
        default:
            return nil
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
