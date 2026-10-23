import Foundation

public enum LSKError: Error, Equatable {
    /// 无法为扩展名推导出 UTI
    case couldNotDeriveUTI(extension: String)
    /// 按名称/路径找不到应用
    case applicationNotFound(String)
    /// Launch Services API 调用失败
    case launchServicesFailed(String)
    /// 找不到 Launch Services 偏好数据库
    case databaseNotFound(String)
    /// 偏好数据库解析失败
    case databaseParseFailed(String)
}

extension LSKError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .couldNotDeriveUTI(let ext):
            return "Could not derive UTI for extension '.\(ext)'"
        case .applicationNotFound(let name):
            return "Application not found: \(name) (searched default locations; use an absolute path)"
        case .launchServicesFailed(let message):
            return "Launch Services error: \(message)"
        case .databaseNotFound(let path):
            return "Launch Services database not found at \(path)"
        case .databaseParseFailed(let message):
            return "Failed to parse Launch Services database: \(message)"
        }
    }
}
