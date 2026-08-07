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
        }
    ]
}
