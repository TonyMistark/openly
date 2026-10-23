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

    // MARK: - 恢复系统默认

    /// 一条 LSHandlers 原始记录是否属于给定的关联类别。
    ///
    /// 扩展名要匹配两种落盘形态：系统可能写 `LSHandlerContentTag`
    /// （class = public.filename-extension），也可能直接解析成 UTI 写
    /// `LSHandlerContentType`——两种都要摘掉才算删干净。
    public static func recordMatches(
        _ raw: [String: Any], kind: AssociationKind, resolvedUTI: String?
    ) -> Bool {
        let tag = raw["LSHandlerContentTag"] as? String
        let tagClass = raw["LSHandlerContentTagClass"] as? String
        let contentType = raw["LSHandlerContentType"] as? String
        let scheme = raw["LSHandlerURLScheme"] as? String

        switch kind {
        case .fileExtension(let ext):
            if tagClass == "public.filename-extension",
               tag?.lowercased() == ext.lowercased() { return true }
            return resolvedUTI != nil && contentType?.lowercased() == resolvedUTI!.lowercased()
        case .urlScheme(let s):
            return scheme?.lowercased() == s.lowercased()
        case .superType(let t):
            return contentType?.lowercased() == t.utiString.lowercased()
        case .uti(let u):
            return contentType?.lowercased() == u.lowercased()
        }
    }

    /// 纯函数：从 LSHandlers 原始数组里摘掉属于 `kind` 的记录。
    /// 与「读取」分离，测试不必碰真实的偏好域。
    public static func filteredHandlers(
        _ rawHandlers: [[String: Any]], removing kind: AssociationKind, resolvedUTI: String?
    ) -> [[String: Any]] {
        rawHandlers.filter { !recordMatches($0, kind: kind, resolvedUTI: resolvedUTI) }
    }

    /// 从 secure plist 的 LSHandlers 里删除属于 `kind` 的用户显式记录。
    ///
    /// **必须走 CFPreferences 而不是直接改文件**：plist 的真实持有者是
    /// cfprefsd，绕过它写文件，下一次任何进程同步偏好时改动会被缓存值
    /// 静默覆盖回去。域 ID 就是带斜杠的那个容器路径。
    ///
    /// 没有匹配记录时是空操作（本来就是系统默认）；lsd 的缓存何时刷新
    /// 没有公开保证——界面上的即时回读可能仍显示旧值，注销后必然生效。
    /// - Throws: 记录存在但写回失败时抛错。
    public static func removeUserHandler(
        for kind: AssociationKind, resolvedUTI: String?
    ) throws {
        let domain = "com.apple.LaunchServices/com.apple.launchservices.secure" as CFString
        let key = "LSHandlers" as CFString
        guard let current = CFPreferencesCopyAppValue(key, domain),
              let handlers = current as? [[String: Any]] else {
            return // 没有任何用户记录 = 已经是系统默认
        }
        let kept = filteredHandlers(handlers, removing: kind, resolvedUTI: resolvedUTI)
        guard kept.count != handlers.count else { return } // 没有匹配的记录
        CFPreferencesSetAppValue(key, kept as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
