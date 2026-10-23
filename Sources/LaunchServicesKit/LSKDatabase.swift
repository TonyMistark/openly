import Foundation

/// Launch Services 偏好数据库解析 — 对应 infat-lib `launch_services_db.rs`。
///
/// 该 plist 只包含「用户显式设置过」的关联，是 GUI 首屏总览列表的主数据源。
public enum LSKDatabase {

    /// LSHandlers 中的一条记录（仅保留 GUI 需要的字段）
    public struct HandlerRecord: Equatable, Sendable {
        public var contentType: String?
        public var contentTag: String?
        public var contentTagClass: String?
        public var urlScheme: String?
        public var roleAll: String?
        public var roleViewer: String?
        public var roleEditor: String?

        /// 记录对应的关联类别与键（对应 infat `generate_config_from_launch_services` 的分类逻辑）
        public var associationKind: AssociationKind? {
            if let tag = contentTag, let tagClass = contentTagClass,
               tagClass == "public.filename-extension" {
                return .fileExtension(tag)
            }
            if let scheme = urlScheme {
                return .urlScheme(scheme)
            }
            if let contentType = contentType {
                if let supertype = SuperType.from(utiString: contentType) {
                    return .superType(supertype)
                }
                if contentType.contains(".") {
                    return .uti(contentType)
                }
            }
            return nil
        }

        /// 该记录指定的处理应用 bundle ID（role 优先级 all > viewer > editor，同 infat）
        public var handlerBundleID: String? {
            roleAll ?? roleViewer ?? roleEditor
        }
    }

    /// secure plist 默认路径
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
    }

    /// 读取并解析全部 handler 记录
    public static func handlers(atURL url: URL? = nil) throws -> [HandlerRecord] {
        let url = url ?? defaultURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LSKError.databaseNotFound(url.path)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw LSKError.databaseParseFailed("unreadable file at \(url.path)")
        }

        let formatHint = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        guard let root = formatHint as? [String: Any],
              let rawHandlers = root["LSHandlers"] as? [[String: Any]] else {
            throw LSKError.databaseParseFailed("unexpected structure (missing LSHandlers)")
        }

        return rawHandlers.compactMap { raw in
            let record = HandlerRecord(
                contentType: raw["LSHandlerContentType"] as? String,
                contentTag: raw["LSHandlerContentTag"] as? String,
                contentTagClass: raw["LSHandlerContentTagClass"] as? String,
                urlScheme: raw["LSHandlerURLScheme"] as? String,
                roleAll: raw["LSHandlerRoleAll"] as? String,
                roleViewer: raw["LSHandlerRoleViewer"] as? String,
                roleEditor: raw["LSHandlerRoleEditor"] as? String
            )
            // 跳过既无应用也无类别字段可识别的脏记录
            return record.associationKind != nil ? record : nil
        }
    }
}
