import Foundation

enum StudioError: Error, LocalizedError, Sendable, Equatable {
    case applicationSupportUnavailable
    case directoryCreationFailed(path: String)
    case databaseOpenFailed(path: String, code: Int32)
    case databaseExecutionFailed(message: String)
    case invalidTaskTransition
    case bookmarkCreationFailed(path: String)
    case bookmarkResolutionFailed

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "无法找到 Application Support 目录。"
        case .directoryCreationFailed(let path):
            return "无法创建应用目录：\(path)"
        case .databaseOpenFailed(let path, let code):
            return "无法打开 Catalog 数据库（SQLite 错误 \(code)）：\(path)"
        case .databaseExecutionFailed(let message):
            return "Catalog 数据库操作失败：\(message)"
        case .invalidTaskTransition:
            return "后台任务状态转换无效。"
        case .bookmarkCreationFailed(let path):
            return "无法为目录创建访问书签：\(path)"
        case .bookmarkResolutionFailed:
            return "无法恢复目录访问书签。"
        }
    }
}
