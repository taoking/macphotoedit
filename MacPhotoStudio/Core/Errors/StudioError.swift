import Foundation

enum StudioError: Error, LocalizedError, Sendable, Equatable {
    case applicationSupportUnavailable
    case directoryCreationFailed(path: String)
    case databaseOpenFailed(path: String, code: Int32)
    case databaseExecutionFailed(message: String)
    case invalidTaskTransition
    case bookmarkCreationFailed(path: String)
    case bookmarkResolutionFailed
    case invalidMediaRoot(path: String)
    case directoryEnumerationFailed(path: String)
    case metadataExtractionFailed(path: String)
    case mediaRootNotFound(id: UUID)
    case invalidLUT(message: String)
    case rawDecodingFailed(path: String)
    case exportFailed(message: String)
    case invalidPreset(message: String)

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
        case .invalidMediaRoot(let path):
            return "选择的项目不是可索引的目录：\(path)"
        case .directoryEnumerationFailed(let path):
            return "无法枚举目录：\(path)"
        case .metadataExtractionFailed(let path):
            return "无法读取媒体元数据：\(path)"
        case .mediaRootNotFound(let id):
            return "找不到媒体根目录：\(id.uuidString)"
        case .invalidLUT(let message):
            return "无效的 LUT：\(message)"
        case .rawDecodingFailed(let path):
            return "无法使用系统 RAW 解码器读取：\(path)"
        case .exportFailed(let message):
            return "无法导出媒体：\(message)"
        case .invalidPreset(let message):
            return "无效的预设：\(message)"
        }
    }
}
