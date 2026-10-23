import AppKit
import Foundation

/// 应用解析 — 名称 ↔ bundle ID ↔ 路径。
/// 对应 infat-lib `workspace.rs`：应用可写名称（在默认位置查找）、
/// `~/` 相对路径或绝对路径，大小写敏感，可带可不带 `.app` 后缀。
public enum LSKAppResolver {

    /// 默认应用搜索位置（对应 infat 的查找顺序）
    public static var searchDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            URL(fileURLWithPath: "/Applications/Setapp"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications"),
        ]
    }

    /// 按名称或路径定位 .app bundle（找不到返回 nil）
    public static func appURL(forApp name: String) -> URL? {
        var name = name.trimmingCharacters(in: .whitespaces)

        // 1. 绝对路径
        if name.hasPrefix("/") {
            let url = URL(fileURLWithPath: name.hasSuffix(".app") ? name : name + ".app")
            return url.hasDirectoryPath && FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        // 2. ~/ 相对路径
        if name.hasPrefix("~") {
            let expanded = (name as NSString).expandingTildeInPath
            let path = expanded.hasSuffix(".app") ? expanded : expanded + ".app"
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }

        if name.hasSuffix(".app") {
            name.removeLast(4)
        }

        // 3. 默认位置精确匹配（大小写敏感，与 infat 一致）
        for dir in searchDirectories where FileManager.default.fileExists(atPath: dir.path) {
            let candidate = dir.appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 4. 默认位置大小写不敏感兜底（GUI 输入容错）
        let lower = name.lowercased()
        for dir in searchDirectories {
            guard FileManager.default.fileExists(atPath: dir.path),
                  let entries = try? FileManager.default.contentsOfDirectory(
                      at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for entry in entries
            where entry.pathExtension == "app"
                && entry.deletingPathExtension().lastPathComponent.lowercased() == lower {
                return entry
            }
        }

        return nil
    }

    /// 应用名/路径 → bundle ID
    public static func bundleID(forApp name: String) throws -> String {
        guard let url = appURL(forApp: name) else {
            throw LSKError.applicationNotFound(name)
        }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
            throw LSKError.applicationNotFound(name)
        }
        return bundleID
    }

    /// bundle ID → 应用路径（Launch Services 查询，能找到已注册的非默认位置应用）
    public static func appURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// bundle ID → AppRef（名称取自 bundle 的本地化显示名，找不到名称时回退 bundle ID）
    public static func appRef(forBundleID bundleID: String) -> AppRef {
        let url = appURL(forBundleID: bundleID)
        let bundle = url.flatMap(Bundle.init(url:))
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleID
        return AppRef(bundleID: bundleID, name: name, path: url?.path)
    }
}
