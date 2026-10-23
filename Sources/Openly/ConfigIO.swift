import Foundation
import LaunchServicesKit

/// 导入/导出的差异数据
struct ImportDiff: Equatable, Identifiable {
    let id = UUID()
    struct Entry: Equatable, Identifiable {
        let id = UUID()
        let displayID: String
        let kind: AssociationKind
        let appName: String
        let currentAppName: String?   // nil = 当前无默认（新增）
        let isOverwrite: Bool
    }

    var additions: [Entry] = []
    var overwrites: [Entry] = []
    var unchangedCount = 0

    var isEmpty: Bool { additions.isEmpty && overwrites.isEmpty }
}

/// 最近修改记录的持久化（UserDefaults + JSON，量小无需文件）
enum RecentChangeStore {
    private static let key = "openly.recentChanges.v1"

    static func load() -> [RecentChange] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([RawChange].self, from: data) else { return [] }
        return raw.compactMap { entry in
            let kind: AssociationKind
            switch entry.kindKey {
            case let k where k.hasPrefix("ext:"): kind = .fileExtension(String(k.dropFirst(4)))
            case let k where k.hasPrefix("scheme:"): kind = .urlScheme(String(k.dropFirst(7)))
            case let k where k.hasPrefix("type:"):
                guard let t = SuperType.parse(String(k.dropFirst(5))) else { return nil }
                kind = .superType(t)
            case let k where k.hasPrefix("uti:"): kind = .uti(String(k.dropFirst(4)))
            default: return nil
            }
            return RecentChange(
                kind: kind, displayID: entry.displayID,
                fromName: entry.fromName, toName: entry.toName, date: entry.date
            )
        }
    }

    static func save(_ changes: [RecentChange]) {
        let raw = changes.map {
            RawChange(kindKey: $0.kind.kindKey(), displayID: $0.displayID,
                      fromName: $0.fromName, toName: $0.toName, date: $0.date)
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct RawChange: Codable {
        let kindKey: String
        let displayID: String
        let fromName: String?
        let toName: String
        let date: Date
    }
}

extension AssociationStore {

    // MARK: - 导出

    /// 当前全部关联 → infat 兼容 TOML
    func exportTOML() -> String {
        var config = TOMLConfig.Config()
        for row in rows {
            guard let app = row.defaultApp else { continue }
            switch row.kind {
            case .fileExtension(let e):
                config.extensions[e] = app.path ?? app.name
            case .urlScheme(let s):
                config.schemes[s] = app.path ?? app.name
            case .superType(let t):
                config.types[t.rawValue] = app.path ?? app.name
            case .uti(let u):
                config.types[u] = app.path ?? app.name
            }
        }
        return TOMLConfig.encode(config)
    }

    // MARK: - 导入差异

    /// 解析 TOML 文本并与当前状态对比，返回差异（不做任何修改）
    func computeImportDiff(tomlText: String) throws -> ImportDiff {
        let config = try TOMLConfig.decode(tomlText)
        var diff = ImportDiff()

        func compare(displayID: String, kind: AssociationKind, appName: String) {
            guard let row = rows.first(where: { $0.kind.kindKey() == kind.kindKey() }) else { return }
            let currentName = row.defaultApp?.name
            // 名称相同（或路径解析出的名字相同）→ 一致
            if currentName == appName {
                diff.unchangedCount += 1
                return
            }
            let entry = ImportDiff.Entry(
                displayID: displayID, kind: kind, appName: appName,
                currentAppName: currentName, isOverwrite: currentName != nil
            )
            if currentName == nil {
                diff.additions.append(entry)
            } else {
                diff.overwrites.append(entry)
            }
        }

        for (ext, app) in config.extensions.sorted(by: { $0.key < $1.key }) {
            compare(displayID: ".\(ext)", kind: .fileExtension(ext), appName: app)
        }
        for (type, app) in config.types.sorted(by: { $0.key < $1.key }) {
            let kind: AssociationKind = SuperType.parse(type).map { .superType($0) } ?? .uti(type)
            compare(displayID: type, kind: kind, appName: app)
        }
        for (scheme, app) in config.schemes.sorted(by: { $0.key < $1.key }) {
            compare(displayID: "\(scheme):", kind: .urlScheme(scheme), appName: app)
        }
        return diff
    }

    /// 应用导入差异（用户确认后调用）
    func applyImportDiff(_ diff: ImportDiff) {
        let all = diff.additions + diff.overwrites
        guard !all.isEmpty else { return }
        let appGroups = Dictionary(grouping: all, by: \.appName)
        for (appName, entries) in appGroups {
            // appName 可能是路径或名称，两者 LSKAppResolver 都接受
            guard let bundleID = try? LSKAppResolver.bundleID(forApp: appName) else { continue }
            let appRef = LSKAppResolver.appRef(forBundleID: bundleID)
            // 局部变量别叫 rows：会遮蔽 self.rows，旧版编译器推断不出闭包参数类型
            let targetRows: [AssociationRow] = entries.compactMap { entry in
                self.rows.first { $0.kind.kindKey() == entry.kind.kindKey() }
            }
            guard !targetRows.isEmpty else { continue }
            batchChange(targetRows, to: appRef)
        }
        // 未在当前列表中的类型（比较时被跳过的）交给 load() 重建
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(all.count) * 1.5 + 1.0) { [weak self] in
            self?.load()
        }
    }

    // MARK: - 最近修改持久化

    func persistRecentChanges() {
        RecentChangeStore.save(recentChanges)
    }

    func loadPersistedRecentChanges() {
        if recentChanges.isEmpty {
            recentChanges = RecentChangeStore.load()
        }
    }
}
