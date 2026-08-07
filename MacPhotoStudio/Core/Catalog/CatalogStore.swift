import Foundation

actor CatalogStore {
    private let databaseURL: URL
    private var connection: SQLiteConnection?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func bootstrap() throws {
        if connection == nil {
            connection = try SQLiteConnection(databaseURL: databaseURL)
        }
        guard let connection else { return }

        try connection.execute("PRAGMA foreign_keys = ON;")
        try connection.execute("PRAGMA journal_mode = WAL;")
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                applied_at REAL NOT NULL
            );
            """
        )

        let appliedVersion = try schemaVersion(using: connection)
        for migration in CatalogMigrations.all where migration.version > appliedVersion {
            try connection.transaction {
                try migration.apply(connection)
                try connection.execute(
                    "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);",
                    bindings: [.integer(Int64(migration.version)), .text(migration.name), .real(Date.now.timeIntervalSince1970)]
                )
            }
            AppLogger.catalog.info("Applied catalog migration \(migration.version, privacy: .public)")
        }
    }

    func currentSchemaVersion() throws -> Int {
        try requireConnection().query("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;")
            .first?
            .integer(at: 0)
            .map(Int.init) ?? 0
    }

    func saveMediaRoot(_ root: MediaRootRecord) throws {
        let connection = try requireConnection()
        try connection.execute(
            """
            INSERT INTO media_roots (
                id, display_name, bookmark_data, created_at, last_known_path,
                volume_identifier, availability, last_scanned_at, last_scan_error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                bookmark_data = excluded.bookmark_data,
                last_known_path = excluded.last_known_path,
                volume_identifier = excluded.volume_identifier,
                availability = excluded.availability,
                last_scanned_at = excluded.last_scanned_at,
                last_scan_error = excluded.last_scan_error;
            """,
            bindings: [
                .text(root.id.uuidString), .text(root.displayName), .blob(root.bookmarkData),
                .real(root.createdAt.timeIntervalSince1970), .text(root.lastKnownPath),
                sql(root.volumeIdentifier), .text(root.availability.rawValue), sql(root.lastScannedAt),
                sql(root.lastScanError)
            ]
        )
    }

    func mediaRoots() throws -> [MediaRootRecord] {
        let rows = try requireConnection().query(
            """
            SELECT id, display_name, bookmark_data, last_known_path, volume_identifier,
                   availability, created_at, last_scanned_at, last_scan_error
            FROM media_roots
            ORDER BY created_at ASC;
            """
        )
        return rows.compactMap(mediaRoot(from:))
    }

    func mediaRoot(id: UUID) throws -> MediaRootRecord? {
        let rows = try requireConnection().query(
            """
            SELECT id, display_name, bookmark_data, last_known_path, volume_identifier,
                   availability, created_at, last_scanned_at, last_scan_error
            FROM media_roots WHERE id = ? LIMIT 1;
            """,
            bindings: [.text(id.uuidString)]
        )
        return rows.first.flatMap(mediaRoot(from:))
    }

    func updateBookmark(_ bookmarkData: Data, lastKnownPath: String, volumeIdentifier: String?, for rootID: UUID) throws {
        try requireConnection().execute(
            """
            UPDATE media_roots
            SET bookmark_data = ?, last_known_path = ?, volume_identifier = ?
            WHERE id = ?;
            """,
            bindings: [.blob(bookmarkData), .text(lastKnownPath), sql(volumeIdentifier), .text(rootID.uuidString)]
        )
    }

    func updateRootAvailability(
        _ availability: MediaRootAvailability,
        errorMessage: String? = nil,
        rootID: UUID
    ) throws {
        let connection = try requireConnection()
        try connection.transaction {
            try connection.execute(
                "UPDATE media_roots SET availability = ?, last_scan_error = ? WHERE id = ?;",
                bindings: [.text(availability.rawValue), sql(errorMessage), .text(rootID.uuidString)]
            )
            if availability != .online {
                try connection.execute(
                    "UPDATE media_assets SET availability = ? WHERE root_id = ?;",
                    bindings: [.text(MediaAssetAvailability.offline.rawValue), .text(rootID.uuidString)]
                )
            }
        }
    }

    func assetFingerprints(for rootID: UUID) throws -> [String: AssetFingerprint] {
        let rows = try requireConnection().query(
            """
            SELECT relative_path, file_size, modified_at, file_resource_identifier
            FROM media_assets WHERE root_id = ?;
            """,
            bindings: [.text(rootID.uuidString)]
        )

        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let relativePath = row.text(at: 0), let fileSize = row.integer(at: 1) else { return nil }
            return (
                relativePath,
                AssetFingerprint(
                    fileSize: fileSize,
                    modifiedAt: date(from: row.real(at: 2)),
                    fileResourceIdentifier: row.text(at: 3)
                )
            )
        })
    }

    func beginScan(rootID: UUID, scanID: UUID, startedAt: Date = .now) throws {
        try requireConnection().execute(
            """
            UPDATE media_roots
            SET availability = ?, last_scan_error = NULL, last_scanned_at = ?
            WHERE id = ?;
            """,
            bindings: [.text(MediaRootAvailability.online.rawValue), .real(startedAt.timeIntervalSince1970), .text(rootID.uuidString)]
        )
        AppLogger.catalog.info("Started scan \(scanID.uuidString, privacy: .public)")
    }

    func applyScanBatch(_ assets: [ScannedMediaAsset], scanID: UUID) throws {
        guard !assets.isEmpty else { return }
        let connection = try requireConnection()

        try connection.transaction {
            for asset in assets {
                try upsert(asset, scanID: scanID, using: connection)
            }
        }
    }

    func finishScan(rootID: UUID, scanID: UUID, finishedAt: Date = .now) throws {
        let connection = try requireConnection()
        try connection.transaction {
            try connection.execute(
                """
                UPDATE media_assets
                SET availability = ?
                WHERE root_id = ? AND (last_seen_scan_id IS NULL OR last_seen_scan_id != ?);
                """,
                bindings: [.text(MediaAssetAvailability.missing.rawValue), .text(rootID.uuidString), .text(scanID.uuidString)]
            )
            try connection.execute(
                """
                UPDATE media_roots
                SET availability = ?, last_scanned_at = ?, last_scan_error = NULL
                WHERE id = ?;
                """,
                bindings: [.text(MediaRootAvailability.online.rawValue), .real(finishedAt.timeIntervalSince1970), .text(rootID.uuidString)]
            )
        }
        AppLogger.catalog.info("Finished scan \(scanID.uuidString, privacy: .public)")
    }

    func assets(for rootID: UUID) throws -> [MediaAssetRecord] {
        let rows = try requireConnection().query(
            """
            SELECT id, root_id, relative_path, media_type, file_extension, file_size,
                   created_at, modified_at, availability, metadata_state
            FROM media_assets WHERE root_id = ? ORDER BY relative_path ASC;
            """,
            bindings: [.text(rootID.uuidString)]
        )
        return rows.compactMap { row in
            guard
                let idText = row.text(at: 0), let id = UUID(uuidString: idText),
                let rootText = row.text(at: 1), let rootID = UUID(uuidString: rootText),
                let path = row.text(at: 2), let mediaTypeText = row.text(at: 3),
                let mediaType = MediaType(rawValue: mediaTypeText), let fileExtension = row.text(at: 4),
                let fileSize = row.integer(at: 5), let availabilityText = row.text(at: 8),
                let availability = MediaAssetAvailability(rawValue: availabilityText),
                let metadataStateText = row.text(at: 9), let metadataState = MetadataState(rawValue: metadataStateText)
            else { return nil }

            return MediaAssetRecord(
                id: id,
                rootID: rootID,
                relativePath: path,
                mediaType: mediaType,
                fileExtension: fileExtension,
                fileSize: fileSize,
                createdAt: date(from: row.real(at: 6)),
                modifiedAt: date(from: row.real(at: 7)),
                availability: availability,
                metadataState: metadataState
            )
        }
    }

    private func upsert(_ asset: ScannedMediaAsset, scanID: UUID, using connection: SQLiteConnection) throws {
        try connection.execute(
            """
            INSERT INTO media_assets (
                id, root_id, relative_path, file_resource_identifier, media_type,
                file_extension, file_size, created_at, modified_at, availability,
                metadata_state, last_seen_scan_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(root_id, relative_path) DO UPDATE SET
                file_resource_identifier = excluded.file_resource_identifier,
                media_type = excluded.media_type,
                file_extension = excluded.file_extension,
                file_size = excluded.file_size,
                created_at = excluded.created_at,
                modified_at = excluded.modified_at,
                availability = excluded.availability,
                metadata_state = CASE
                    WHEN excluded.metadata_state = 'unchanged' THEN media_assets.metadata_state
                    ELSE excluded.metadata_state
                END,
                last_seen_scan_id = excluded.last_seen_scan_id;
            """,
            bindings: [
                .text(UUID().uuidString), .text(asset.rootID.uuidString), .text(asset.relativePath),
                sql(asset.fileResourceIdentifier), .text(asset.mediaType.rawValue), .text(asset.fileExtension),
                .integer(asset.fileSize), sql(asset.createdAt), sql(asset.modifiedAt),
                .text(MediaAssetAvailability.available.rawValue), .text(asset.metadata.state.rawValue),
                .text(scanID.uuidString)
            ]
        )

        switch asset.metadata {
        case .photo(let metadata):
            try connection.execute(deleteVideoMetadataSQL, bindings: assetIdentityBindings(for: asset))
            try upsertPhotoMetadata(metadata, for: asset, using: connection)
        case .video(let metadata):
            try connection.execute(deletePhotoMetadataSQL, bindings: assetIdentityBindings(for: asset))
            try upsertVideoMetadata(metadata, for: asset, using: connection)
        case .unavailable:
            try connection.execute(deletePhotoMetadataSQL, bindings: assetIdentityBindings(for: asset))
            try connection.execute(deleteVideoMetadataSQL, bindings: assetIdentityBindings(for: asset))
        case .unchanged:
            break
        }
    }

    private func upsertPhotoMetadata(_ metadata: PhotoMetadata, for asset: ScannedMediaAsset, using connection: SQLiteConnection) throws {
        try connection.execute(
            """
            INSERT INTO photo_metadata (
                asset_id, width, height, capture_date, camera_make, camera_model, lens_model,
                focal_length, aperture, shutter_speed, iso, orientation, color_profile
            ) VALUES ((SELECT id FROM media_assets WHERE root_id = ? AND relative_path = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                width = excluded.width, height = excluded.height, capture_date = excluded.capture_date,
                camera_make = excluded.camera_make, camera_model = excluded.camera_model,
                lens_model = excluded.lens_model, focal_length = excluded.focal_length,
                aperture = excluded.aperture, shutter_speed = excluded.shutter_speed, iso = excluded.iso,
                orientation = excluded.orientation, color_profile = excluded.color_profile;
            """,
            bindings: assetIdentityBindings(for: asset) + [
                sql(metadata.width), sql(metadata.height), sql(metadata.captureDate), sql(metadata.cameraMake),
                sql(metadata.cameraModel), sql(metadata.lensModel), sql(metadata.focalLength),
                sql(metadata.aperture), sql(metadata.shutterSpeed), sql(metadata.iso), sql(metadata.orientation),
                sql(metadata.colorProfile)
            ]
        )
    }

    private func upsertVideoMetadata(_ metadata: VideoMetadata, for asset: ScannedMediaAsset, using connection: SQLiteConnection) throws {
        try connection.execute(
            """
            INSERT INTO video_metadata (
                asset_id, width, height, duration, frame_rate, codec, creation_date
            ) VALUES ((SELECT id FROM media_assets WHERE root_id = ? AND relative_path = ?), ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                width = excluded.width, height = excluded.height, duration = excluded.duration,
                frame_rate = excluded.frame_rate, codec = excluded.codec, creation_date = excluded.creation_date;
            """,
            bindings: assetIdentityBindings(for: asset) + [
                sql(metadata.width), sql(metadata.height), sql(metadata.duration), sql(metadata.frameRate),
                sql(metadata.codec), sql(metadata.creationDate)
            ]
        )
    }

    private func mediaRoot(from row: SQLiteRow) -> MediaRootRecord? {
        guard
            let idString = row.text(at: 0), let id = UUID(uuidString: idString),
            let displayName = row.text(at: 1), let bookmarkData = row.blob(at: 2),
            let lastKnownPath = row.text(at: 3), let availabilityValue = row.text(at: 5),
            let availability = MediaRootAvailability(rawValue: availabilityValue),
            let createdAtValue = row.real(at: 6)
        else { return nil }

        return MediaRootRecord(
            id: id,
            displayName: displayName,
            bookmarkData: bookmarkData,
            lastKnownPath: lastKnownPath,
            volumeIdentifier: row.text(at: 4),
            availability: availability,
            createdAt: Date(timeIntervalSince1970: createdAtValue),
            lastScannedAt: date(from: row.real(at: 7)),
            lastScanError: row.text(at: 8)
        )
    }

    private func schemaVersion(using connection: SQLiteConnection) throws -> Int {
        try connection.query("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;")
            .first?
            .integer(at: 0)
            .map(Int.init) ?? 0
    }

    private func requireConnection() throws -> SQLiteConnection {
        guard let connection else {
            throw StudioError.databaseExecutionFailed(message: "CatalogStore.bootstrap() must run first.")
        }
        return connection
    }

    private func assetIdentityBindings(for asset: ScannedMediaAsset) -> [SQLiteValue] {
        [.text(asset.rootID.uuidString), .text(asset.relativePath)]
    }
}

private let deletePhotoMetadataSQL = "DELETE FROM photo_metadata WHERE asset_id = (SELECT id FROM media_assets WHERE root_id = ? AND relative_path = ?);"
private let deleteVideoMetadataSQL = "DELETE FROM video_metadata WHERE asset_id = (SELECT id FROM media_assets WHERE root_id = ? AND relative_path = ?);"

private func date(from value: Double?) -> Date? {
    value.map(Date.init(timeIntervalSince1970:))
}

private func sql(_ value: String?) -> SQLiteValue { value.map(SQLiteValue.text) ?? .null }
private func sql(_ value: Int?) -> SQLiteValue { value.map { .integer(Int64($0)) } ?? .null }
private func sql(_ value: Double?) -> SQLiteValue { value.map(SQLiteValue.real) ?? .null }
private func sql(_ value: Date?) -> SQLiteValue { value.map { .real($0.timeIntervalSince1970) } ?? .null }
