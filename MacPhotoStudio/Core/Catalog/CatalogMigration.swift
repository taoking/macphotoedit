import Foundation

struct CatalogMigration: Sendable {
    let version: Int
    let name: String
    let apply: @Sendable (SQLiteConnection) throws -> Void
}

enum CatalogMigrations {
    static let all: [CatalogMigration] = [
        CatalogMigration(version: 1, name: "createFoundationSchema") { connection in
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS media_roots (
                    id TEXT PRIMARY KEY NOT NULL,
                    display_name TEXT NOT NULL,
                    bookmark_data BLOB NOT NULL,
                    created_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS background_tasks (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    state TEXT NOT NULL,
                    progress REAL NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                """
            )
        },
        CatalogMigration(version: 2, name: "createCatalogIndexingSchema") { connection in
            try connection.execute(
                """
                ALTER TABLE media_roots ADD COLUMN last_known_path TEXT NOT NULL DEFAULT '';
                ALTER TABLE media_roots ADD COLUMN volume_identifier TEXT;
                ALTER TABLE media_roots ADD COLUMN availability TEXT NOT NULL DEFAULT 'online';
                ALTER TABLE media_roots ADD COLUMN last_scanned_at REAL;
                ALTER TABLE media_roots ADD COLUMN last_scan_error TEXT;

                CREATE TABLE media_assets (
                    id TEXT PRIMARY KEY NOT NULL,
                    root_id TEXT NOT NULL REFERENCES media_roots(id) ON DELETE RESTRICT,
                    relative_path TEXT NOT NULL,
                    file_resource_identifier TEXT,
                    media_type TEXT NOT NULL,
                    file_extension TEXT NOT NULL,
                    file_size INTEGER NOT NULL,
                    created_at REAL,
                    modified_at REAL,
                    availability TEXT NOT NULL DEFAULT 'available',
                    metadata_state TEXT NOT NULL DEFAULT 'unavailable',
                    last_seen_scan_id TEXT,
                    UNIQUE(root_id, relative_path)
                );

                CREATE TABLE photo_metadata (
                    asset_id TEXT PRIMARY KEY NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    width INTEGER,
                    height INTEGER,
                    capture_date REAL,
                    camera_make TEXT,
                    camera_model TEXT,
                    lens_model TEXT,
                    focal_length REAL,
                    aperture REAL,
                    shutter_speed REAL,
                    iso INTEGER,
                    orientation INTEGER,
                    color_profile TEXT
                );

                CREATE TABLE video_metadata (
                    asset_id TEXT PRIMARY KEY NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    width INTEGER,
                    height INTEGER,
                    duration REAL,
                    frame_rate REAL,
                    codec TEXT,
                    creation_date REAL
                );

                CREATE INDEX media_assets_root_id_index ON media_assets(root_id);
                CREATE INDEX media_assets_root_relative_path_index ON media_assets(root_id, relative_path);
                CREATE INDEX media_assets_type_index ON media_assets(media_type);
                CREATE INDEX media_assets_availability_index ON media_assets(availability);
                CREATE INDEX photo_metadata_capture_date_index ON photo_metadata(capture_date);
                """
            )
        },
        CatalogMigration(version: 3, name: "repairPartialIndexingSchema") { connection in
            if try !connection.hasColumn(named: "last_known_path", inTable: "media_roots") {
                try connection.execute("ALTER TABLE media_roots ADD COLUMN last_known_path TEXT NOT NULL DEFAULT '';")
            }
            if try !connection.hasColumn(named: "volume_identifier", inTable: "media_roots") {
                try connection.execute("ALTER TABLE media_roots ADD COLUMN volume_identifier TEXT;")
            }
            if try !connection.hasColumn(named: "availability", inTable: "media_roots") {
                try connection.execute("ALTER TABLE media_roots ADD COLUMN availability TEXT NOT NULL DEFAULT 'online';")
            }
            if try !connection.hasColumn(named: "last_scanned_at", inTable: "media_roots") {
                try connection.execute("ALTER TABLE media_roots ADD COLUMN last_scanned_at REAL;")
            }
            if try !connection.hasColumn(named: "last_scan_error", inTable: "media_roots") {
                try connection.execute("ALTER TABLE media_roots ADD COLUMN last_scan_error TEXT;")
            }
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS background_tasks (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    state TEXT NOT NULL,
                    progress REAL NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS media_assets (
                    id TEXT PRIMARY KEY NOT NULL,
                    root_id TEXT NOT NULL REFERENCES media_roots(id) ON DELETE RESTRICT,
                    relative_path TEXT NOT NULL,
                    file_resource_identifier TEXT,
                    media_type TEXT NOT NULL,
                    file_extension TEXT NOT NULL,
                    file_size INTEGER NOT NULL,
                    created_at REAL,
                    modified_at REAL,
                    availability TEXT NOT NULL DEFAULT 'available',
                    metadata_state TEXT NOT NULL DEFAULT 'unavailable',
                    last_seen_scan_id TEXT,
                    UNIQUE(root_id, relative_path)
                );

                CREATE TABLE IF NOT EXISTS photo_metadata (
                    asset_id TEXT PRIMARY KEY NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    width INTEGER, height INTEGER, capture_date REAL, camera_make TEXT,
                    camera_model TEXT, lens_model TEXT, focal_length REAL, aperture REAL,
                    shutter_speed REAL, iso INTEGER, orientation INTEGER, color_profile TEXT
                );

                CREATE TABLE IF NOT EXISTS video_metadata (
                    asset_id TEXT PRIMARY KEY NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    width INTEGER, height INTEGER, duration REAL, frame_rate REAL,
                    codec TEXT, creation_date REAL
                );

                CREATE INDEX IF NOT EXISTS media_assets_root_id_index ON media_assets(root_id);
                CREATE INDEX IF NOT EXISTS media_assets_root_relative_path_index ON media_assets(root_id, relative_path);
                CREATE INDEX IF NOT EXISTS media_assets_type_index ON media_assets(media_type);
                CREATE INDEX IF NOT EXISTS media_assets_availability_index ON media_assets(availability);
                CREATE INDEX IF NOT EXISTS photo_metadata_capture_date_index ON photo_metadata(capture_date);
                """
            )
        },
        CatalogMigration(version: 4, name: "addLibraryManagementSchema") { connection in
            if try !connection.hasColumn(named: "rating", inTable: "media_assets") {
                try connection.execute(
                    "ALTER TABLE media_assets ADD COLUMN rating INTEGER NOT NULL DEFAULT 0 CHECK (rating BETWEEN 0 AND 5);"
                )
            }
            if try !connection.hasColumn(named: "flag", inTable: "media_assets") {
                try connection.execute(
                    "ALTER TABLE media_assets ADD COLUMN flag TEXT NOT NULL DEFAULT 'unflagged' CHECK (flag IN ('unflagged', 'pick', 'reject'));"
                )
            }
            if try !connection.hasColumn(named: "gps_latitude", inTable: "photo_metadata") {
                try connection.execute("ALTER TABLE photo_metadata ADD COLUMN gps_latitude REAL;")
            }
            if try !connection.hasColumn(named: "gps_longitude", inTable: "photo_metadata") {
                try connection.execute("ALTER TABLE photo_metadata ADD COLUMN gps_longitude REAL;")
            }
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS tags (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                    created_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS asset_tags (
                    asset_id TEXT NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY (asset_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS media_assets_rating_index ON media_assets(rating);
                CREATE INDEX IF NOT EXISTS media_assets_flag_index ON media_assets(flag);
                CREATE INDEX IF NOT EXISTS asset_tags_tag_id_index ON asset_tags(tag_id);
                """
            )
        },
        CatalogMigration(version: 5, name: "addPhotoEditStateSchema") { connection in
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS photo_edit_states (
                    asset_id TEXT PRIMARY KEY NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    state_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS photo_edit_states_updated_at_index ON photo_edit_states(updated_at);
                """
            )
        },
        CatalogMigration(version: 6, name: "addRawEditStateSchema") { connection in
            try connection.execute(
                """
                CREATE TABLE IF NOT EXISTS raw_edit_states (
                    asset_id TEXT PRIMARY KEY NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
                    state_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS raw_edit_states_updated_at_index ON raw_edit_states(updated_at);
                """
            )
        }
    ]
}
