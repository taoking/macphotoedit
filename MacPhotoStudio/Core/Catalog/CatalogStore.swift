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
            try connection.execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                try migration.apply(connection)
                try connection.execute(
                    "INSERT INTO schema_migrations (version, name, applied_at) VALUES (\(migration.version), '\(migration.name)', unixepoch());"
                )
                try connection.execute("COMMIT;")
                AppLogger.catalog.info("Applied catalog migration \(migration.version, privacy: .public)")
            } catch {
                try? connection.execute("ROLLBACK;")
                throw error
            }
        }
    }

    func currentSchemaVersion() throws -> Int {
        guard let connection else {
            throw StudioError.databaseExecutionFailed(message: "CatalogStore.bootstrap() must run first.")
        }
        return try schemaVersion(using: connection)
    }

    private func schemaVersion(using connection: SQLiteConnection) throws -> Int {
        try connection.integerValue(for: "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;")
    }
}
