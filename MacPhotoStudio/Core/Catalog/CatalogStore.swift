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

    func libraryAssets(query: LibraryQuery, limit: Int, offset: Int) throws -> [LibraryAssetRecord] {
        let pageSize = max(1, min(limit, 1_000))
        let pageOffset = max(0, offset)
        var conditions: [String] = []
        var bindings: [SQLiteValue] = []
        appendLibraryFilters(query, conditions: &conditions, bindings: &bindings)

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        bindings.append(.integer(Int64(pageSize)))
        bindings.append(.integer(Int64(pageOffset)))
        let rows = try requireConnection().query(
            """
            SELECT
                a.id, a.root_id, r.display_name, r.last_known_path, a.relative_path,
                a.media_type, a.file_extension, a.file_size, a.created_at, a.modified_at,
                a.availability, a.metadata_state, a.rating, a.flag,
                p.width, p.height, p.capture_date, p.camera_make, p.camera_model,
                p.lens_model, p.focal_length, p.aperture, p.shutter_speed, p.iso,
                p.orientation, p.color_profile, p.gps_latitude, p.gps_longitude,
                v.width, v.height, v.duration, v.frame_rate, v.codec, v.creation_date
            FROM media_assets a
            JOIN media_roots r ON r.id = a.root_id
            LEFT JOIN photo_metadata p ON p.asset_id = a.id
            LEFT JOIN video_metadata v ON v.asset_id = a.id
            \(whereClause)
            ORDER BY COALESCE(p.capture_date, v.creation_date, a.created_at) DESC, a.relative_path COLLATE NOCASE ASC
            LIMIT ? OFFSET ?;
            """,
            bindings: bindings
        )
        return rows.compactMap(libraryAsset(from:))
    }

    func updateRating(_ rating: Int, for assetIDs: [UUID]) throws {
        guard (0...5).contains(rating) else {
            throw StudioError.databaseExecutionFailed(message: "Rating must be between 0 and 5.")
        }
        try updateAssets(assetIDs) { connection, id in
            try connection.execute(
                "UPDATE media_assets SET rating = ? WHERE id = ?;",
                bindings: [.integer(Int64(rating)), .text(id.uuidString)]
            )
        }
    }

    func updateFlag(_ flag: AssetFlag, for assetIDs: [UUID]) throws {
        try updateAssets(assetIDs) { connection, id in
            try connection.execute(
                "UPDATE media_assets SET flag = ? WHERE id = ?;",
                bindings: [.text(flag.rawValue), .text(id.uuidString)]
            )
        }
    }

    func tags() throws -> [TagRecord] {
        try requireConnection().query(
            "SELECT id, name, created_at FROM tags ORDER BY name COLLATE NOCASE ASC;"
        ).compactMap(tag(from:))
    }

    func tags(for assetID: UUID) throws -> [TagRecord] {
        try requireConnection().query(
            """
            SELECT t.id, t.name, t.created_at
            FROM tags t JOIN asset_tags at ON at.tag_id = t.id
            WHERE at.asset_id = ? ORDER BY t.name COLLATE NOCASE ASC;
            """,
            bindings: [.text(assetID.uuidString)]
        ).compactMap(tag(from:))
    }

    func createTag(named proposedName: String, now: Date = .now) throws -> TagRecord {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw StudioError.databaseExecutionFailed(message: "Tag name cannot be empty.")
        }
        let tag = TagRecord(id: UUID(), name: name, createdAt: now)
        try requireConnection().execute(
            "INSERT INTO tags (id, name, created_at) VALUES (?, ?, ?);",
            bindings: [.text(tag.id.uuidString), .text(tag.name), .real(tag.createdAt.timeIntervalSince1970)]
        )
        return tag
    }

    func renameTag(_ tagID: UUID, to proposedName: String) throws {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw StudioError.databaseExecutionFailed(message: "Tag name cannot be empty.")
        }
        try requireConnection().execute(
            "UPDATE tags SET name = ? WHERE id = ?;",
            bindings: [.text(name), .text(tagID.uuidString)]
        )
    }

    func deleteTag(_ tagID: UUID) throws {
        try requireConnection().execute("DELETE FROM tags WHERE id = ?;", bindings: [.text(tagID.uuidString)])
    }

    func addTag(_ tagID: UUID, to assetIDs: [UUID]) throws {
        try updateAssets(assetIDs) { connection, assetID in
            try connection.execute(
                "INSERT OR IGNORE INTO asset_tags (asset_id, tag_id) VALUES (?, ?);",
                bindings: [.text(assetID.uuidString), .text(tagID.uuidString)]
            )
        }
    }

    func removeTag(_ tagID: UUID, from assetIDs: [UUID]) throws {
        try updateAssets(assetIDs) { connection, assetID in
            try connection.execute(
                "DELETE FROM asset_tags WHERE asset_id = ? AND tag_id = ?;",
                bindings: [.text(assetID.uuidString), .text(tagID.uuidString)]
            )
        }
    }

    func photoEditState(for assetID: UUID) throws -> PhotoEditState? {
        let rows = try requireConnection().query(
            "SELECT state_json FROM photo_edit_states WHERE asset_id = ? LIMIT 1;",
            bindings: [.text(assetID.uuidString)]
        )
        guard let json = rows.first?.text(at: 0) else { return nil }
        do {
            return try JSONDecoder().decode(PhotoEditState.self, from: Data(json.utf8))
        } catch {
            throw StudioError.databaseExecutionFailed(message: "Unable to decode photo edit state: \(error.localizedDescription)")
        }
    }

    func savePhotoEditState(_ state: PhotoEditState, for assetID: UUID, now: Date = .now) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json: String
        do {
            json = String(decoding: try encoder.encode(state), as: UTF8.self)
        } catch {
            throw StudioError.databaseExecutionFailed(message: "Unable to encode photo edit state: \(error.localizedDescription)")
        }
        try requireConnection().execute(
            """
            INSERT INTO photo_edit_states (asset_id, state_json, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                state_json = excluded.state_json,
                updated_at = excluded.updated_at;
            """,
            bindings: [.text(assetID.uuidString), .text(json), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)]
        )
    }

    func rawEditState(for assetID: UUID) throws -> RAWEditState? {
        let rows = try requireConnection().query(
            "SELECT state_json FROM raw_edit_states WHERE asset_id = ? LIMIT 1;",
            bindings: [.text(assetID.uuidString)]
        )
        guard let json = rows.first?.text(at: 0) else { return nil }
        do {
            return try JSONDecoder().decode(RAWEditState.self, from: Data(json.utf8))
        } catch {
            throw StudioError.databaseExecutionFailed(message: "Unable to decode RAW edit state: \(error.localizedDescription)")
        }
    }

    func saveRawEditState(_ state: RAWEditState, for assetID: UUID, now: Date = .now) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json: String
        do {
            json = String(decoding: try encoder.encode(state), as: UTF8.self)
        } catch {
            throw StudioError.databaseExecutionFailed(message: "Unable to encode RAW edit state: \(error.localizedDescription)")
        }
        try requireConnection().execute(
            """
            INSERT INTO raw_edit_states (asset_id, state_json, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                state_json = excluded.state_json,
                updated_at = excluded.updated_at;
            """,
            bindings: [.text(assetID.uuidString), .text(json), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)]
        )
    }

    func photoPresets() throws -> [PhotoPreset] {
        try requireConnection().query(
            "SELECT id, name, content_json, is_favorite, created_at, updated_at FROM photo_presets ORDER BY is_favorite DESC, name COLLATE NOCASE ASC;"
        ).compactMap(photoPreset(from:))
    }

    func createPhotoPreset(
        named proposedName: String,
        content: PhotoPresetContent,
        isFavorite: Bool = false,
        now: Date = .now
    ) throws -> PhotoPreset {
        let name = try validatedPresetName(proposedName)
        let preset = PhotoPreset(
            id: UUID(), name: name, content: content, isFavorite: isFavorite,
            createdAt: now, updatedAt: now
        )
        try requireConnection().execute(
            "INSERT INTO photo_presets (id, name, content_json, is_favorite, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);",
            bindings: [
                .text(preset.id.uuidString), .text(preset.name), .text(try encodedPresetContent(preset.content)),
                .integer(preset.isFavorite ? 1 : 0), .real(preset.createdAt.timeIntervalSince1970),
                .real(preset.updatedAt.timeIntervalSince1970)
            ]
        )
        return preset
    }

    func renamePhotoPreset(_ presetID: UUID, to proposedName: String, now: Date = .now) throws {
        let name = try validatedPresetName(proposedName)
        try requireConnection().execute(
            "UPDATE photo_presets SET name = ?, updated_at = ? WHERE id = ?;",
            bindings: [.text(name), .real(now.timeIntervalSince1970), .text(presetID.uuidString)]
        )
    }

    func setPhotoPresetFavorite(_ isFavorite: Bool, for presetID: UUID, now: Date = .now) throws {
        try requireConnection().execute(
            "UPDATE photo_presets SET is_favorite = ?, updated_at = ? WHERE id = ?;",
            bindings: [.integer(isFavorite ? 1 : 0), .real(now.timeIntervalSince1970), .text(presetID.uuidString)]
        )
    }

    func deletePhotoPreset(_ presetID: UUID) throws {
        try requireConnection().execute("DELETE FROM photo_presets WHERE id = ?;", bindings: [.text(presetID.uuidString)])
    }

    func albums() throws -> [AlbumRecord] {
        try requireConnection().query(
            "SELECT id, name, kind, criteria_json, created_at, updated_at FROM albums ORDER BY kind ASC, name COLLATE NOCASE ASC;"
        ).compactMap(album(from:))
    }

    func createAlbum(named proposedName: String, now: Date = .now) throws -> AlbumRecord {
        try createAlbum(named: proposedName, kind: .album, criteria: nil, now: now)
    }

    func createSmartAlbum(
        named proposedName: String,
        criteria: SmartAlbumCriteria,
        now: Date = .now
    ) throws -> AlbumRecord {
        try createAlbum(named: proposedName, kind: .smartAlbum, criteria: criteria, now: now)
    }

    func renameAlbum(_ albumID: UUID, to proposedName: String, now: Date = .now) throws {
        let name = try validatedCollectionName(proposedName)
        try requireConnection().execute(
            "UPDATE albums SET name = ?, updated_at = ? WHERE id = ?;",
            bindings: [.text(name), .real(now.timeIntervalSince1970), .text(albumID.uuidString)]
        )
    }

    func updateSmartAlbum(
        _ albumID: UUID,
        criteria: SmartAlbumCriteria,
        now: Date = .now
    ) throws {
        try requireConnection().execute(
            "UPDATE albums SET criteria_json = ?, updated_at = ? WHERE id = ? AND kind = 'smartAlbum';",
            bindings: [.text(try encodedSmartAlbumCriteria(criteria)), .real(now.timeIntervalSince1970), .text(albumID.uuidString)]
        )
    }

    func deleteAlbum(_ albumID: UUID) throws {
        try requireConnection().execute("DELETE FROM albums WHERE id = ?;", bindings: [.text(albumID.uuidString)])
    }

    func addAssets(_ assetIDs: [UUID], toAlbum albumID: UUID, now: Date = .now) throws {
        try requireManualAlbum(id: albumID)
        try updateAssets(assetIDs) { connection, assetID in
            try connection.execute(
                "INSERT OR IGNORE INTO album_assets (album_id, asset_id, added_at) VALUES (?, ?, ?);",
                bindings: [.text(albumID.uuidString), .text(assetID.uuidString), .real(now.timeIntervalSince1970)]
            )
        }
    }

    func removeAssets(_ assetIDs: [UUID], fromAlbum albumID: UUID) throws {
        try requireManualAlbum(id: albumID)
        try updateAssets(assetIDs) { connection, assetID in
            try connection.execute(
                "DELETE FROM album_assets WHERE album_id = ? AND asset_id = ?;",
                bindings: [.text(albumID.uuidString), .text(assetID.uuidString)]
            )
        }
    }

    func assetStacks() throws -> [AssetStackRecord] {
        try requireConnection().query(
            """
            SELECT s.id, s.title, s.kind, s.created_at, s.updated_at, COUNT(m.asset_id)
            FROM asset_stacks s
            LEFT JOIN asset_stack_members m ON m.stack_id = s.id
            GROUP BY s.id
            ORDER BY s.updated_at DESC, s.title COLLATE NOCASE ASC;
            """
        ).compactMap(assetStack(from:))
    }

    func createStack(
        kind: AssetStackKind,
        title proposedTitle: String,
        assetIDs: [UUID],
        now: Date = .now
    ) throws -> AssetStackRecord {
        let uniqueAssetIDs = Array(Set(assetIDs))
        guard uniqueAssetIDs.count >= 2 else {
            throw StudioError.databaseExecutionFailed(message: "A stack requires at least two assets.")
        }
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let stack = AssetStackRecord(
            id: UUID(),
            title: title.isEmpty ? "\(kind.title)堆栈" : title,
            kind: kind,
            createdAt: now,
            updatedAt: now,
            assetCount: uniqueAssetIDs.count
        )
        let connection = try requireConnection()
        try connection.transaction {
            try connection.execute(
                "INSERT INTO asset_stacks (id, title, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
                bindings: [.text(stack.id.uuidString), .text(stack.title), .text(stack.kind.rawValue), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)]
            )
            for (position, assetID) in uniqueAssetIDs.enumerated() {
                try connection.execute(
                    "INSERT INTO asset_stack_members (stack_id, asset_id, position) VALUES (?, ?, ?);",
                    bindings: [.text(stack.id.uuidString), .text(assetID.uuidString), .integer(Int64(position))]
                )
            }
        }
        return stack
    }

    func addAssets(_ assetIDs: [UUID], toStack stackID: UUID, now: Date = .now) throws {
        let connection = try requireConnection()
        let startingPosition = try connection.query(
            "SELECT COALESCE(MAX(position), -1) FROM asset_stack_members WHERE stack_id = ?;",
            bindings: [.text(stackID.uuidString)]
        ).first?.integer(at: 0).map(Int.init) ?? -1
        try connection.transaction {
            for (offset, assetID) in Set(assetIDs).enumerated() {
                try connection.execute(
                    "INSERT OR IGNORE INTO asset_stack_members (stack_id, asset_id, position) VALUES (?, ?, ?);",
                    bindings: [.text(stackID.uuidString), .text(assetID.uuidString), .integer(Int64(startingPosition + offset + 1))]
                )
            }
            try connection.execute(
                "UPDATE asset_stacks SET updated_at = ? WHERE id = ?;",
                bindings: [.real(now.timeIntervalSince1970), .text(stackID.uuidString)]
            )
        }
    }

    func removeAssets(_ assetIDs: [UUID], fromStack stackID: UUID, now: Date = .now) throws {
        try updateAssets(assetIDs) { connection, assetID in
            try connection.execute(
                "DELETE FROM asset_stack_members WHERE stack_id = ? AND asset_id = ?;",
                bindings: [.text(stackID.uuidString), .text(assetID.uuidString)]
            )
        }
        try requireConnection().execute(
            "UPDATE asset_stacks SET updated_at = ? WHERE id = ?;",
            bindings: [.real(now.timeIntervalSince1970), .text(stackID.uuidString)]
        )
    }

    func deleteStack(_ stackID: UUID) throws {
        try requireConnection().execute("DELETE FROM asset_stacks WHERE id = ?;", bindings: [.text(stackID.uuidString)])
    }

    func markAssetsMissing(_ assetIDs: [UUID]) throws {
        try updateAssets(assetIDs) { connection, assetID in
            try connection.execute(
                "UPDATE media_assets SET availability = ? WHERE id = ?;",
                bindings: [.text(MediaAssetAvailability.missing.rawValue), .text(assetID.uuidString)]
            )
        }
    }

    func duplicateHashCandidates() throws -> [DuplicateHashCandidate] {
        let rows = try requireConnection().query(
            """
            SELECT a.id, a.root_id, a.relative_path, a.file_size, a.modified_at
            FROM media_assets a
            WHERE a.availability = 'available'
              AND a.file_size > 0
              AND a.file_size IN (
                  SELECT file_size
                  FROM media_assets
                  WHERE availability = 'available' AND file_size > 0
                  GROUP BY file_size
                  HAVING COUNT(*) > 1
              )
            ORDER BY a.file_size ASC, a.root_id ASC, a.relative_path COLLATE NOCASE ASC;
            """
        )
        return rows.compactMap { duplicateHashCandidate(from: $0) }
    }

    func contentHash(for candidate: DuplicateHashCandidate, algorithm: String = "sha256") throws -> String? {
        let rows = try requireConnection().query(
            """
            SELECT digest FROM asset_content_hashes
            WHERE asset_id = ? AND algorithm = ? AND file_size = ?
              AND ((modified_at IS NULL AND ? IS NULL) OR ABS(modified_at - ?) < 0.001)
            LIMIT 1;
            """,
            bindings: [
                .text(candidate.id.uuidString), .text(algorithm), .integer(candidate.fileSize),
                sql(candidate.modifiedAt), sql(candidate.modifiedAt)
            ]
        )
        return rows.first?.text(at: 0)
    }

    func saveContentHash(
        _ digest: String,
        for candidate: DuplicateHashCandidate,
        algorithm: String = "sha256",
        now: Date = .now
    ) throws {
        try requireConnection().execute(
            """
            INSERT INTO asset_content_hashes (asset_id, algorithm, file_size, modified_at, digest, computed_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                algorithm = excluded.algorithm,
                file_size = excluded.file_size,
                modified_at = excluded.modified_at,
                digest = excluded.digest,
                computed_at = excluded.computed_at;
            """,
            bindings: [.text(candidate.id.uuidString), .text(algorithm), .integer(candidate.fileSize), sql(candidate.modifiedAt), .text(digest), .real(now.timeIntervalSince1970)]
        )
    }

    func exactDuplicateGroups() throws -> [ExactDuplicateGroup] {
        let rows = try requireConnection().query(
            """
            SELECT h.digest, h.file_size, a.id, a.root_id, a.relative_path, a.file_size, a.modified_at
            FROM asset_content_hashes h
            JOIN media_assets a ON a.id = h.asset_id
            WHERE h.algorithm = 'sha256'
              AND a.availability = 'available'
              AND h.file_size = a.file_size
              AND ((h.modified_at IS NULL AND a.modified_at IS NULL) OR ABS(h.modified_at - a.modified_at) < 0.001)
            ORDER BY h.file_size ASC, h.digest ASC, a.relative_path COLLATE NOCASE ASC;
            """
        )
        var grouped: [String: (digest: String, fileSize: Int64, assets: [DuplicateHashCandidate])] = [:]
        for row in rows {
            guard let digest = row.text(at: 0), let fileSize = row.integer(at: 1),
                  let candidate = duplicateHashCandidate(from: row, offset: 2) else { continue }
            let key = "\(fileSize)-\(digest)"
            var group = grouped[key, default: (digest, fileSize, [])]
            group.assets.append(candidate)
            grouped[key] = group
        }
        return grouped.values
            .filter { $0.assets.count > 1 }
            .map { ExactDuplicateGroup(digest: $0.digest, fileSize: $0.fileSize, assets: $0.assets) }
            .sorted { lhs, rhs in
                lhs.fileSize == rhs.fileSize ? lhs.digest < rhs.digest : lhs.fileSize < rhs.fileSize
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
                focal_length, aperture, shutter_speed, iso, orientation, color_profile, gps_latitude, gps_longitude
            ) VALUES ((SELECT id FROM media_assets WHERE root_id = ? AND relative_path = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                width = excluded.width, height = excluded.height, capture_date = excluded.capture_date,
                camera_make = excluded.camera_make, camera_model = excluded.camera_model,
                lens_model = excluded.lens_model, focal_length = excluded.focal_length,
                aperture = excluded.aperture, shutter_speed = excluded.shutter_speed, iso = excluded.iso,
                orientation = excluded.orientation, color_profile = excluded.color_profile,
                gps_latitude = excluded.gps_latitude, gps_longitude = excluded.gps_longitude;
            """,
            bindings: assetIdentityBindings(for: asset) + [
                sql(metadata.width), sql(metadata.height), sql(metadata.captureDate), sql(metadata.cameraMake),
                sql(metadata.cameraModel), sql(metadata.lensModel), sql(metadata.focalLength),
                sql(metadata.aperture), sql(metadata.shutterSpeed), sql(metadata.iso), sql(metadata.orientation),
                sql(metadata.colorProfile), sql(metadata.gpsLatitude), sql(metadata.gpsLongitude)
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

    private func appendLibraryFilters(
        _ query: LibraryQuery,
        conditions: inout [String],
        bindings: inout [SQLiteValue]
    ) {
        if let albumID = query.albumID {
            conditions.append("EXISTS (SELECT 1 FROM album_assets album_filter WHERE album_filter.asset_id = a.id AND album_filter.album_id = ?)")
            bindings.append(.text(albumID.uuidString))
        }
        if let stackID = query.stackID {
            conditions.append("EXISTS (SELECT 1 FROM asset_stack_members stack_filter WHERE stack_filter.asset_id = a.id AND stack_filter.stack_id = ?)")
            bindings.append(.text(stackID.uuidString))
        }
        if let smartAlbumCriteria = query.smartAlbumCriteria {
            appendSmartAlbumFilters(smartAlbumCriteria, conditions: &conditions, bindings: &bindings)
        }
        if let rootID = query.rootID {
            conditions.append("a.root_id = ?")
            bindings.append(.text(rootID.uuidString))
        }
        if let mediaType = query.mediaType {
            conditions.append("a.media_type = ?")
            bindings.append(.text(mediaType.rawValue))
        }
        if let minimumRating = query.minimumRating {
            conditions.append("a.rating >= ?")
            bindings.append(.integer(Int64(minimumRating)))
        }
        if let flag = query.flag {
            conditions.append("a.flag = ?")
            bindings.append(.text(flag.rawValue))
        }
        if let tagID = query.tagID {
            conditions.append("EXISTS (SELECT 1 FROM asset_tags filter_at WHERE filter_at.asset_id = a.id AND filter_at.tag_id = ?)")
            bindings.append(.text(tagID.uuidString))
        }
        if let startDate = query.captureDateFrom {
            conditions.append("COALESCE(p.capture_date, v.creation_date, a.created_at) >= ?")
            bindings.append(.real(startDate.timeIntervalSince1970))
        }
        if let endDate = query.captureDateTo {
            conditions.append("COALESCE(p.capture_date, v.creation_date, a.created_at) < ?")
            bindings.append(.real(endDate.timeIntervalSince1970))
        }
        if let searchText = query.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty {
            let pattern = "%\(searchText)%"
            conditions.append("(a.relative_path LIKE ? COLLATE NOCASE OR r.last_known_path LIKE ? COLLATE NOCASE OR COALESCE(p.camera_make, '') LIKE ? COLLATE NOCASE OR COALESCE(p.camera_model, '') LIKE ? COLLATE NOCASE OR COALESCE(p.lens_model, '') LIKE ? COLLATE NOCASE)")
            bindings += Array(repeating: .text(pattern), count: 5)
        }
        if let camera = query.camera?.trimmingCharacters(in: .whitespacesAndNewlines), !camera.isEmpty {
            let pattern = "%\(camera)%"
            conditions.append("(COALESCE(p.camera_make, '') LIKE ? COLLATE NOCASE OR COALESCE(p.camera_model, '') LIKE ? COLLATE NOCASE)")
            bindings += [.text(pattern), .text(pattern)]
        }
        if let lens = query.lens?.trimmingCharacters(in: .whitespacesAndNewlines), !lens.isEmpty {
            conditions.append("COALESCE(p.lens_model, '') LIKE ? COLLATE NOCASE")
            bindings.append(.text("%\(lens)%"))
        }
        appendManagedStateFilters(
            isEdited: query.isEdited,
            isRAW: query.isRAW,
            conditions: &conditions,
            bindings: &bindings
        )
    }

    private func appendSmartAlbumFilters(
        _ criteria: SmartAlbumCriteria,
        conditions: inout [String],
        bindings: inout [SQLiteValue]
    ) {
        if let minimumRating = criteria.minimumRating {
            conditions.append("a.rating >= ?")
            bindings.append(.integer(Int64(minimumRating)))
        }
        if let startDate = criteria.captureDateFrom {
            conditions.append("COALESCE(p.capture_date, v.creation_date, a.created_at) >= ?")
            bindings.append(.real(startDate.timeIntervalSince1970))
        }
        if let endDate = criteria.captureDateTo {
            conditions.append("COALESCE(p.capture_date, v.creation_date, a.created_at) < ?")
            bindings.append(.real(endDate.timeIntervalSince1970))
        }
        if let camera = criteria.camera?.trimmingCharacters(in: .whitespacesAndNewlines), !camera.isEmpty {
            let pattern = "%\(camera)%"
            conditions.append("(COALESCE(p.camera_make, '') LIKE ? COLLATE NOCASE OR COALESCE(p.camera_model, '') LIKE ? COLLATE NOCASE)")
            bindings += [.text(pattern), .text(pattern)]
        }
        if let lens = criteria.lens?.trimmingCharacters(in: .whitespacesAndNewlines), !lens.isEmpty {
            conditions.append("COALESCE(p.lens_model, '') LIKE ? COLLATE NOCASE")
            bindings.append(.text("%\(lens)%"))
        }
        if let tagID = criteria.tagID {
            conditions.append("EXISTS (SELECT 1 FROM asset_tags smart_tag_filter WHERE smart_tag_filter.asset_id = a.id AND smart_tag_filter.tag_id = ?)")
            bindings.append(.text(tagID.uuidString))
        }
        if let mediaType = criteria.mediaType {
            conditions.append("a.media_type = ?")
            bindings.append(.text(mediaType.rawValue))
        }
        appendManagedStateFilters(
            isEdited: criteria.isEdited,
            isRAW: criteria.isRAW,
            conditions: &conditions,
            bindings: &bindings
        )
    }

    private func appendManagedStateFilters(
        isEdited: Bool?,
        isRAW: Bool?,
        conditions: inout [String],
        bindings: inout [SQLiteValue]
    ) {
        if let isEdited {
            let editedCondition = "(EXISTS (SELECT 1 FROM photo_edit_states edit_filter WHERE edit_filter.asset_id = a.id) OR EXISTS (SELECT 1 FROM raw_edit_states raw_edit_filter WHERE raw_edit_filter.asset_id = a.id))"
            conditions.append(isEdited ? editedCondition : "NOT \(editedCondition)")
        }
        if let isRAW {
            let placeholders = Array(repeating: "?", count: RAWFormat.extensions.count).joined(separator: ", ")
            let rawCondition = "LOWER(a.file_extension) IN (\(placeholders))"
            conditions.append(isRAW ? rawCondition : "NOT \(rawCondition)")
            bindings += RAWFormat.extensions.sorted().map(SQLiteValue.text)
        }
    }

    private func libraryAsset(from row: SQLiteRow) -> LibraryAssetRecord? {
        guard
            let idText = row.text(at: 0), let id = UUID(uuidString: idText),
            let rootText = row.text(at: 1), let rootID = UUID(uuidString: rootText),
            let rootDisplayName = row.text(at: 2), let rootPath = row.text(at: 3),
            let relativePath = row.text(at: 4), let mediaTypeText = row.text(at: 5),
            let mediaType = MediaType(rawValue: mediaTypeText), let fileExtension = row.text(at: 6),
            let fileSize = row.integer(at: 7), let availabilityText = row.text(at: 10),
            let availability = MediaAssetAvailability(rawValue: availabilityText),
            let metadataStateText = row.text(at: 11), let metadataState = MetadataState(rawValue: metadataStateText),
            let ratingValue = row.integer(at: 12), let flagText = row.text(at: 13),
            let flag = AssetFlag(rawValue: flagText)
        else { return nil }

        return LibraryAssetRecord(
            id: id, rootID: rootID, rootDisplayName: rootDisplayName, rootPath: rootPath,
            relativePath: relativePath, mediaType: mediaType, fileExtension: fileExtension,
            fileSize: fileSize, createdAt: date(from: row.real(at: 8)), modifiedAt: date(from: row.real(at: 9)),
            availability: availability, metadataState: metadataState, rating: Int(ratingValue), flag: flag,
            width: row.integer(at: 14).map(Int.init), height: row.integer(at: 15).map(Int.init),
            captureDate: date(from: row.real(at: 16)), cameraMake: row.text(at: 17), cameraModel: row.text(at: 18),
            lensModel: row.text(at: 19), focalLength: row.real(at: 20), aperture: row.real(at: 21),
            shutterSpeed: row.real(at: 22), iso: row.integer(at: 23).map(Int.init),
            orientation: row.integer(at: 24).map(Int.init), colorProfile: row.text(at: 25),
            gpsLatitude: row.real(at: 26), gpsLongitude: row.real(at: 27),
            duration: row.real(at: 30), frameRate: row.real(at: 31), codec: row.text(at: 32),
            videoCreationDate: date(from: row.real(at: 33))
        )
    }

    private func tag(from row: SQLiteRow) -> TagRecord? {
        guard let idText = row.text(at: 0), let id = UUID(uuidString: idText),
              let name = row.text(at: 1), let createdAt = row.real(at: 2) else { return nil }
        return TagRecord(id: id, name: name, createdAt: Date(timeIntervalSince1970: createdAt))
    }

    private func photoPreset(from row: SQLiteRow) -> PhotoPreset? {
        guard
            let idText = row.text(at: 0), let id = UUID(uuidString: idText),
            let name = row.text(at: 1), let contentJSON = row.text(at: 2),
            let favorite = row.integer(at: 3), let createdAt = row.real(at: 4), let updatedAt = row.real(at: 5)
        else { return nil }
        do {
            return PhotoPreset(
                id: id,
                name: name,
                content: try JSONDecoder().decode(PhotoPresetContent.self, from: Data(contentJSON.utf8)),
                isFavorite: favorite != 0,
                createdAt: Date(timeIntervalSince1970: createdAt),
                updatedAt: Date(timeIntervalSince1970: updatedAt)
            )
        } catch {
            AppLogger.catalog.error("Skipping invalid preset \(idText, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func album(from row: SQLiteRow) -> AlbumRecord? {
        guard
            let idText = row.text(at: 0), let id = UUID(uuidString: idText),
            let name = row.text(at: 1), let kindText = row.text(at: 2), let kind = AlbumKind(rawValue: kindText),
            let createdAt = row.real(at: 4), let updatedAt = row.real(at: 5)
        else { return nil }
        let criteria: SmartAlbumCriteria?
        if let json = row.text(at: 3) {
            do {
                criteria = try JSONDecoder().decode(SmartAlbumCriteria.self, from: Data(json.utf8))
            } catch {
                AppLogger.catalog.error("Skipping invalid smart album \(idText, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        } else {
            criteria = nil
        }
        return AlbumRecord(
            id: id, name: name, kind: kind, criteria: criteria,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    private func assetStack(from row: SQLiteRow) -> AssetStackRecord? {
        guard
            let idText = row.text(at: 0), let id = UUID(uuidString: idText),
            let title = row.text(at: 1), let kindText = row.text(at: 2), let kind = AssetStackKind(rawValue: kindText),
            let createdAt = row.real(at: 3), let updatedAt = row.real(at: 4), let count = row.integer(at: 5)
        else { return nil }
        return AssetStackRecord(
            id: id, title: title, kind: kind,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt), assetCount: Int(count)
        )
    }

    private func duplicateHashCandidate(from row: SQLiteRow, offset: Int = 0) -> DuplicateHashCandidate? {
        guard
            let idText = row.text(at: offset), let id = UUID(uuidString: idText),
            let rootText = row.text(at: offset + 1), let rootID = UUID(uuidString: rootText),
            let relativePath = row.text(at: offset + 2), let fileSize = row.integer(at: offset + 3)
        else { return nil }
        return DuplicateHashCandidate(
            id: id, rootID: rootID, relativePath: relativePath,
            fileSize: fileSize, modifiedAt: date(from: row.real(at: offset + 4))
        )
    }

    private func validatedPresetName(_ proposedName: String) throws -> String {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw StudioError.invalidPreset(message: "预设名称不能为空。")
        }
        return name
    }

    private func createAlbum(
        named proposedName: String,
        kind: AlbumKind,
        criteria: SmartAlbumCriteria?,
        now: Date
    ) throws -> AlbumRecord {
        let album = AlbumRecord(
            id: UUID(), name: try validatedCollectionName(proposedName), kind: kind, criteria: criteria,
            createdAt: now, updatedAt: now
        )
        let criteriaJSON = try album.criteria.map(encodedSmartAlbumCriteria)
        try requireConnection().execute(
            "INSERT INTO albums (id, name, kind, criteria_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);",
            bindings: [
                .text(album.id.uuidString), .text(album.name), .text(album.kind.rawValue),
                sql(criteriaJSON),
                .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
            ]
        )
        return album
    }

    private func requireManualAlbum(id: UUID) throws {
        let kind = try requireConnection().query(
            "SELECT kind FROM albums WHERE id = ? LIMIT 1;",
            bindings: [.text(id.uuidString)]
        ).first?.text(at: 0)
        guard kind == AlbumKind.album.rawValue else {
            throw StudioError.databaseExecutionFailed(message: "Only a standard album can contain manually selected assets.")
        }
    }

    private func validatedCollectionName(_ proposedName: String) throws -> String {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw StudioError.databaseExecutionFailed(message: "Album name cannot be empty.")
        }
        return name
    }

    private func encodedSmartAlbumCriteria(_ criteria: SmartAlbumCriteria) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return String(decoding: try encoder.encode(criteria), as: UTF8.self)
        } catch {
            throw StudioError.databaseExecutionFailed(message: "Unable to encode smart album criteria: \(error.localizedDescription)")
        }
    }

    private func encodedPresetContent(_ content: PhotoPresetContent) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return String(decoding: try encoder.encode(content), as: UTF8.self)
        } catch {
            throw StudioError.invalidPreset(message: "无法编码预设：\(error.localizedDescription)")
        }
    }

    private func updateAssets(
        _ assetIDs: [UUID],
        operation: (SQLiteConnection, UUID) throws -> Void
    ) throws {
        guard !assetIDs.isEmpty else { return }
        let connection = try requireConnection()
        try connection.transaction {
            for assetID in Set(assetIDs) {
                try operation(connection, assetID)
            }
        }
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
