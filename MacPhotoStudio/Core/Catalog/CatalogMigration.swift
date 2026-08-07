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
        }
    ]
}
