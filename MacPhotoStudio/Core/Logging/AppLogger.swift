import OSLog

enum AppLogger {
    private static let subsystem = "com.macphotostudio.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
    static let tasks = Logger(subsystem: subsystem, category: "tasks")
}
