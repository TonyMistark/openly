import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

/// 关联查询与设置 — 对应 infat-lib `association.rs`。
///
/// 特殊路由规则（继承自 infat 踩过的坑，勿删）：
/// - `.html` 扩展名实际由 `http` URL scheme handler 控制
/// - `https` 与 `http` 共享同一个 handler
/// - `com.apple.default-app.web-browser` / `public.html` 类型路由到 `http` scheme
///
/// ⚠️ macOS 26 (Tahoe) 上 legacy LS set API（`LSSetDefaultRoleHandlerForContentType` 等）
/// 返回 noErr 但不实际生效 — infat CLI 在新系统上同样受影响。
/// 因此设置走 NSWorkspace 现代 API，legacy API 仅作兜底；查询 API 不受影响。
public enum LSKAssociation {

    // MARK: - 查询

    /// 查询扩展名的关联信息
    public static func info(forExtension ext: String) throws -> AssociationInfo {
        let uti = try uti(forExtension: ext)
        return AssociationInfo(
            identifier: ".\(ext)",
            uti: uti,
            defaultAppBundleID: try defaultApp(forUTI: uti),
            allAppBundleIDs: try allApps(forUTI: uti)
        )
    }

    /// 查询 URL scheme 的关联信息
    public static func info(forURLScheme scheme: String) throws -> AssociationInfo {
        AssociationInfo(
            identifier: "\(scheme):",
            uti: nil,
            defaultAppBundleID: try defaultApp(forURLScheme: scheme),
            allAppBundleIDs: try allApps(forURLScheme: scheme)
        )
    }

    /// 查询 SuperType 或原生 UTI 的关联信息
    public static func info(forType type: String) throws -> AssociationInfo {
        let uti = Self.uti(forType: type)
        return AssociationInfo(
            identifier: type,
            uti: uti,
            defaultAppBundleID: try defaultApp(forUTI: uti),
            allAppBundleIDs: try allApps(forUTI: uti)
        )
    }

    // MARK: - 设置（LS API 在 macOS 15 SDK 标记 deprecated，但仍是唯一可精确指定
    // viewer role 的公开接口，与 infat 语义保持一致；Apple 推荐的替代 API 行为不同）

    /// 为扩展名设置默认打开应用（应用名 / ~/ 相对路径 / 绝对路径）
    public static func setDefaultApp(_ appName: String, forExtension ext: String) throws {
        let ext = ext.lowercased()

        // .html 实际由 http scheme handler 控制
        if ext == "html" {
            return try setDefaultApp(appName, forURLScheme: "http")
        }

        let uti: String
        if let supertype = SuperType.parse(ext) {
            uti = supertype.utiString
        } else if let derived = Self.uti(forExtensionIfAny: ext) {
            uti = derived
        } else {
            throw LSKError.couldNotDeriveUTI(extension: ext)
        }

        let bundleID = try LSKAppResolver.bundleID(forApp: appName)
        try setDefaultHandler(bundleID: bundleID, forUTI: uti)
    }

    /// 为 URL scheme 设置默认处理应用
    public static func setDefaultApp(_ appName: String, forURLScheme scheme: String) throws {
        // https 与 http 共享 handler
        let actualScheme = scheme.lowercased() == "https" ? "http" : scheme.lowercased()

        let bundleID = try LSKAppResolver.bundleID(forApp: appName)

        // 先注册应用，确保 Launch Services 认识它（对应 infat 的 register 步骤）
        if let appURL = LSKAppResolver.appURL(forApp: appName) {
            try? registerApp(at: appURL)
        }

        // 主路径：NSWorkspace 现代 API
        if let appURL = LSKAppResolver.appURL(forBundleID: bundleID) {
            let nsError = setDefaultAppNSWorkspace(appURL: appURL, scheme: actualScheme)
            if nsError == nil,
               (try? defaultApp(forURLScheme: actualScheme)) == bundleID {
                return
            }
            // macOS 26：需用户在系统弹窗确认，headless 环境自动取消 → 给出可读错误
            if let nsError, isUserCancelled(nsError) {
                throw LSKError.launchServicesFailed(
                    "macOS 需要用户确认修改 \(actualScheme): scheme 的默认应用（headless 环境无法弹出确认框）")
            }
        }

        // 兜底：legacy API
        let status = LSSetDefaultHandlerForURLScheme(actualScheme as CFString, bundleID as CFString)
        guard status == noErr else {
            throw LSKError.launchServicesFailed("LSSetDefaultHandlerForURLScheme(\(actualScheme)) error \(status)")
        }
        let after = try? defaultApp(forURLScheme: actualScheme)
        if after != bundleID {
            throw LSKError.launchServicesFailed(
                "set default for \(actualScheme): did not take effect (now: \(after ?? "nil"))")
        }
    }

    /// 为 SuperType / UTI 设置默认打开应用
    public static func setDefaultApp(_ appName: String, forType type: String) throws {
        // Web 浏览器类型路由到 http scheme
        if type == "com.apple.default-app.web-browser" || type == "public.html" {
            return try setDefaultApp(appName, forURLScheme: "http")
        }

        let uti = Self.uti(forType: type)
        let bundleID = try LSKAppResolver.bundleID(forApp: appName)
        try setDefaultHandler(bundleID: bundleID, forUTI: uti)
    }

    // MARK: - UTI 推导

    /// 扩展名 → UTI（失败抛错，对应 infat 的 `CouldNotDeriveUTI`）
    public static func uti(forExtension ext: String) throws -> String {
        if let uti = uti(forExtensionIfAny: ext) { return uti }
        throw LSKError.couldNotDeriveUTI(extension: ext)
    }

    /// 扩展名 → UTI（失败返回 nil）
    public static func uti(forExtensionIfAny ext: String) -> String? {
        if let supertype = SuperType.parse(ext) {
            return supertype.utiString
        }
        return UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil)?.identifier
    }

    /// SuperType 名称或原生 UTI → UTI
    public static func uti(forType type: String) -> String {
        SuperType.parse(type)?.utiString ?? type
    }

    /// UTI → 首选扩展名
    public static func preferredExtension(forUTI uti: String) -> String? {
        UTType(uti)?.preferredFilenameExtension
    }

    // MARK: - Launch Services 底层封装

    /// 为 UTI 设置默认应用。
    /// 主路径：NSWorkspace 现代 API（macOS 26 上唯一真正生效的公开接口）；
    /// 兜底：legacy `LSSetDefaultRoleHandlerForContentType`（匹配 infat 语义，viewer role）。
    private static func setDefaultHandler(bundleID: String, forUTI uti: String) throws {
        if let appURL = LSKAppResolver.appURL(forBundleID: bundleID),
           let type = UTType(uti) {
            try setDefaultAppViaNSWorkspace(appURL: appURL, contentType: type, legacyUTI: uti, legacyBundleID: bundleID)
            return
        }
        // UTType 无法构造（如 dyn.* 或非标准 UTI 字符串）或应用不在已知位置 → 走 legacy API
        let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .viewer, bundleID as CFString)
        guard status == noErr else {
            throw LSKError.launchServicesFailed("LSSetDefaultRoleHandlerForContentType(\(uti)) error \(status)")
        }
    }

    /// NSWorkspace 设置 + 结果验证；失败时回退 legacy API
    private static func setDefaultAppViaNSWorkspace(
        appURL: URL, contentType: UTType, legacyUTI: String, legacyBundleID: String
    ) throws {
        let nsError = setDefaultAppNSWorkspace(appURL: appURL, contentType: contentType)

        // 读回验证（部分系统版本 completion 不报错但静默失败）
        let readBack = try? defaultApp(forUTI: legacyUTI)
        if nsError == nil && readBack == legacyBundleID {
            return
        }

        // macOS 26：需用户在系统弹窗确认，headless 环境自动取消 → 给出可读错误
        if let nsError, isUserCancelled(nsError) {
            throw LSKError.launchServicesFailed(
                "macOS 需要用户确认修改 \(legacyUTI) 的默认应用（headless 环境无法弹出确认框）")
        }

        // 回退 legacy API
        let status = LSSetDefaultRoleHandlerForContentType(
            legacyUTI as CFString, .viewer, legacyBundleID as CFString)
        guard status == noErr else {
            throw LSKError.launchServicesFailed(
                "set default for \(legacyUTI) failed"
                + (nsError.map { " (NSWorkspace: \($0))" } ?? "")
                + " (LS fallback error \(status))")
        }
        // legacy 成功后仍读不到目标值 → 明确报错，避免静默假成功
        let after = try? defaultApp(forUTI: legacyUTI)
        if after != legacyBundleID {
            throw LSKError.launchServicesFailed(
                "set default for \(legacyUTI) did not take effect (now: \(after ?? "nil"))")
        }
    }

    // MARK: - NSWorkspace 异步 API 的同步包装

    /// completion 版本未导入 Swift，只能用 async 版本 + 信号量转同步
    private static func setDefaultAppNSWorkspace(appURL: URL, contentType: UTType) -> Error? {
        var result: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do { try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType) }
            catch { result = error }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private static func setDefaultAppNSWorkspace(appURL: URL, scheme: String) -> Error? {
        var result: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do { try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) }
            catch { result = error }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// 识别 macOS 26 的「用户取消系统确认框」错误
    private static func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == 256
            && (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(userCanceledErr)
    }

    /// 某个 UTI 的默认应用 bundle ID
    public static func defaultApp(forUTI uti: String) throws -> String? {
        guard let cf = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .viewer)?
            .takeRetainedValue() else { return nil }
        return cf as String
    }

    /// 某个 UTI 的全部注册应用 bundle ID
    public static func allApps(forUTI uti: String) throws -> [String] {
        guard let cfArray = LSCopyAllRoleHandlersForContentType(uti as CFString, .viewer)?
            .takeRetainedValue() else { return [] }
        return cfArray as! [String]
    }

    /// 某个 URL scheme 的默认应用 bundle ID
    public static func defaultApp(forURLScheme scheme: String) throws -> String? {
        guard let cf = LSCopyDefaultHandlerForURLScheme(scheme as CFString)?
            .takeRetainedValue() else { return nil }
        return cf as String
    }

    /// 某个 URL scheme 的全部注册应用 bundle ID
    public static func allApps(forURLScheme scheme: String) throws -> [String] {
        guard let cfArray = LSCopyAllHandlersForURLScheme(scheme as CFString)?
            .takeRetainedValue() else { return [] }
        return cfArray as! [String]
    }

    /// 注册应用到 Launch Services（对应 infat 的 `LSRegisterURL` 调用）
    public static func registerApp(at url: URL) throws {
        let status = LSRegisterURL(url as CFURL, true)
        guard status == noErr else {
            throw LSKError.launchServicesFailed("LSRegisterURL(\(url.path)) error \(status)")
        }
    }
}
