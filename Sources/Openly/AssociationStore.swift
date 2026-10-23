import Foundation
import LaunchServicesKit
import UniformTypeIdentifiers

/// 侧栏分类
enum Category: String, CaseIterable, Identifiable, Hashable {
    case document = "文档"
    case image = "图片"
    case audio = "音频"
    case video = "视频"
    case archive = "归档"
    case code = "源代码"
    case system = "系统"
    case scheme = "URL Scheme"
    case other = "其他"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .document: return "doc.text"
        case .image: return "photo"
        case .audio: return "music.note"
        case .video: return "film"
        case .archive: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .system: return "gearshape"
        case .scheme: return "link"
        case .other: return "tray"
        }
    }

    /// UTI → 分类（基于 UTType 继承关系）
    static func forUTI(_ uti: String?) -> Category {
        guard let uti, let type = UTType(uti) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .text) { return .document }
        if type.conforms(to: .directory) || type.conforms(to: .bundle)
            || type.conforms(to: .diskImage) { return .system }
        return .other
    }
}

/// 列表行模型（视图层）
struct AssociationRow: Identifiable, Hashable {
    let id: UUID
    let kind: AssociationKind
    let displayID: String      // ".md" / "mailto:" / "plain-text"
    let uti: String?
    var defaultApp: AppRef?
    var registered: [AppRef]
    let category: Category
    /// 用户在 secure plist 里显式设置过（决定「恢复系统默认」是否可用）
    let isUserSet: Bool

    var kindKey: String {
        kind.kindKey()
    }
}

/// 侧栏选中项
enum SidebarFilter: Hashable {
    case all
    case noDefault
    case recent
    case category(Category)
}

/// 顶栏视图模式
enum ViewMode: Hashable {
    case byType
    case byApp
}

/// 最近修改的一条记录
struct RecentChange: Identifiable, Equatable {
    let id = UUID()
    let kind: AssociationKind
    let displayID: String
    let fromName: String?
    let toName: String
    let date: Date
}

/// 撤销栈的一条记录：修改**之前**的默认是什么。
/// `previousAppKey == nil` 表示之前没有用户显式默认——撤销动作等价于
/// 「恢复系统默认」（从 secure plist 摘记录）。
struct UndoRecord {
    let kind: AssociationKind
    let displayID: String
    let previousAppKey: String?
    let previousName: String?
}

/// 常用扩展名兜底清单：LS plist 只含「用户显式设置过」的关联，
/// 与这份清单合并才能撑起首屏总览（三层兜底的第二层，第三层是搜索）
let curatedExtensions: [String] = [
    "txt", "md", "rtf", "pdf", "doc", "docx", "pages", "csv", "html",
    "png", "jpg", "jpeg", "gif", "svg", "heic", "webp", "tiff",
    "mp3", "wav", "flac", "m4a", "aiff",
    "mp4", "mov", "mkv", "avi", "webm",
    "zip", "tar", "gz", "dmg", "pkg",
    "json", "yml", "yaml", "toml", "xml", "plist",
    "swift", "rs", "py", "sh", "js", "ts", "go", "c", "m", "h",
    "app", "scpt", "conf", "log",
]

@MainActor
final class AssociationStore: ObservableObject {
    @Published var rows: [AssociationRow] = []
    @Published var query = ""
    @Published var filter: SidebarFilter = .all
    @Published var viewMode: ViewMode = .byType
    /// 按应用视图选中的 bundleID
    @Published var selectedAppBundleID: String?
    /// 批量勾选的行（AssociationRow.kind 去重键）
    @Published var selectedKinds: Set<String> = []
    /// 最近修改记录（仅本次会话；持久化在 M3 一并做）
    @Published var recentChanges: [RecentChange] = []
    /// 撤销栈：每次成功的修改压入一条，⌘Z 逐条回退
    @Published private(set) var undoStack: [UndoRecord] = []
    var canUndo: Bool { !undoStack.isEmpty }
    /// 菜单项标题：栈顶那条要撤的是什么
    var undoMenuTitle: String? {
        guard let record = undoStack.last else { return nil }
        let target = record.previousName ?? "系统默认"
        return "撤销 \(record.displayID) → \(target)"
    }
    @Published var editingRow: AssociationRow?
    @Published var batchSheetRow: AssociationRow?
    @Published var toast: String?
    @Published var isLoading = false
    @Published var lastError: String?

    private var toastTask: Task<Void, Never>?

    // MARK: - 加载

    func load() {
        isLoading = true
        lastError = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let loaded = Self.loadRows()
            await MainActor.run { [weak self] in
                self?.rows = loaded
                self?.isLoading = false
            }
        }
    }

    /// DB 关联 ∪ 常用扩展名 → 逐条只读查询
    nonisolated private static func loadRows() -> [AssociationRow] {
        var seen = Set<String>()
        var rows: [AssociationRow] = []

        // 用户显式设置过的 kind 键集合：secure plist 是「用户改过」的唯一凭证，
        // 「恢复系统默认」按钮只对这些行显示
        let userSetKeys: Set<String> = Set((try? LSKDatabase.handlers())?
            .compactMap { $0.associationKind?.kindKey() } ?? [])

        func add(_ kind: AssociationKind, displayID: String, uti: String?) {
            let key = displayID.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)

            let info: AssociationInfo?
            do {
                switch kind {
                case .fileExtension(let e):
                    info = try? LSKAssociation.info(forExtension: e)
                case .urlScheme(let s):
                    info = try? LSKAssociation.info(forURLScheme: s)
                case .superType, .uti:
                    let typeName = kindKeyString(kind)
                    info = try? LSKAssociation.info(forType: typeName)
                }
            }
            rows.append(makeRow(
                kind: kind, displayID: displayID, uti: uti ?? info?.uti, info: info,
                isUserSet: userSetKeys.contains(kind.kindKey())
            ))
        }

        // 1. 用户设置过的关联（secure plist）
        if let records = try? LSKDatabase.handlers() {
            for record in records {
                guard let kind = record.associationKind else { continue }
                switch kind {
                case .fileExtension(let e):
                    add(.fileExtension(e), displayID: ".\(e)", uti: nil)
                case .urlScheme(let s):
                    add(.urlScheme(s), displayID: "\(s):", uti: nil)
                case .superType(let t):
                    add(.superType(t), displayID: t.rawValue, uti: t.utiString)
                case .uti(let u):
                    add(.uti(u), displayID: u, uti: u)
                }
            }
        }

        // 2. 常用扩展名兜底
        for ext in curatedExtensions {
            add(.fileExtension(ext), displayID: ".\(ext)", uti: nil)
        }

        return rows.sorted { $0.displayID.localizedCaseInsensitiveCompare($1.displayID) == .orderedAscending }
    }

    nonisolated private static func kindKeyString(_ kind: AssociationKind) -> String {
        switch kind {
        case .fileExtension(let e): return e
        case .urlScheme(let s): return s
        case .superType(let t): return t.rawValue
        case .uti(let u): return u
        }
    }

    nonisolated private static func makeRow(
        kind: AssociationKind, displayID: String, uti: String?, info: AssociationInfo?,
        isUserSet: Bool = false
    ) -> AssociationRow {
        let registered = (info?.allAppBundleIDs ?? []).map { LSKAppResolver.appRef(forBundleID: $0) }
        let defaultRef = info?.defaultAppBundleID.map { LSKAppResolver.appRef(forBundleID: $0) }
        let category: Category = {
            if case .urlScheme = kind { return .scheme }
            if case .superType = kind { return .system }
            return .forUTI(uti)
        }()
        return AssociationRow(
            id: UUID(),
            kind: kind,
            displayID: displayID,
            uti: uti,
            defaultApp: defaultRef,
            registered: registered,
            category: category,
            isUserSet: isUserSet
        )
    }

    // MARK: - 过滤

    var filteredRows: [AssociationRow] {
        var result = rows
        switch filter {
        case .all: break
        case .noDefault: result = result.filter { $0.defaultApp == nil }
        case .recent:
            let byKind = Dictionary(uniqueKeysWithValues: recentChanges.map { ($0.kind.kindKey(), $0) })
            result = rows.filter { byKind[$0.kind.kindKey()] != nil }
        case .category(let c): result = result.filter { $0.category == c }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { row in
                row.displayID.localizedCaseInsensitiveContains(q)
                || (row.uti?.localizedCaseInsensitiveContains(q) ?? false)
                || (row.defaultApp?.name.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        return result
    }

    var categoryCounts: [Category: Int] {
        var counts: [Category: Int] = [:]
        for row in rows { counts[row.category, default: 0] += 1 }
        return counts
    }

    // MARK: - 批量选择

    var selectedRows: [AssociationRow] {
        rows.filter { selectedKinds.contains($0.kind.kindKey()) }
    }

    func toggleSelection(_ row: AssociationRow) {
        let key = row.kind.kindKey()
        if selectedKinds.contains(key) { selectedKinds.remove(key) } else { selectedKinds.insert(key) }
    }

    func clearSelection() {
        selectedKinds.removeAll()
    }

    /// 全选/取消当前可见行
    var allVisibleSelected: Bool {
        !filteredRows.isEmpty && filteredRows.allSatisfy { selectedKinds.contains($0.kind.kindKey()) }
    }

    func toggleSelectAllVisible() {
        if allVisibleSelected {
            filteredRows.forEach { selectedKinds.remove($0.kind.kindKey()) }
        } else {
            filteredRows.forEach { selectedKinds.insert($0.kind.kindKey()) }
        }
    }

    // MARK: - 按应用视图

    /// 应用 → 它作为默认打开方式的类型列表（按接管数降序）
    var appsWithCounts: [(app: AppRef, count: Int)] {
        var groups: [String: (app: AppRef, count: Int)] = [:]
        for row in rows {
            guard let app = row.defaultApp else { continue }
            var entry = groups[app.bundleID] ?? (app, 0)
            entry.count += 1
            groups[app.bundleID] = entry
        }
        return groups.values.sorted { $0.count > $1.count }
    }

    /// 按应用视图的主区行
    var rowsForSelectedApp: [AssociationRow] {
        guard let id = selectedAppBundleID else { return [] }
        return rows.filter { $0.defaultApp?.bundleID == id }
    }

    // MARK: - 修改（仅由用户在 GUI 手动触发；macOS 26 会弹系统确认框）

    func changeDefault(_ row: AssociationRow, to app: AppRef) {
        editingRow = nil
        showToast("正在修改 \(row.displayID) → \(app.name)…（请在系统弹窗中确认）")

        // 用路径最稳（应用可能重名），退回名称
        let appKey = app.path ?? app.name
        let kind = row.kind
        let displayID = row.displayID
        let fromName = row.defaultApp?.name
        // 撤销要回到的地方：修改前的默认（可能为 nil = 无显式默认）
        let previous = row.defaultApp

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await Self.applyChange(appKey: appKey, kind: kind)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.pushUndo(UndoRecord(
                        kind: kind, displayID: displayID,
                        previousAppKey: previous.map { $0.path ?? $0.name },
                        previousName: previous?.name
                    ))
                    self.recordChange(kind: kind, displayID: displayID, fromName: fromName, toName: app.name)
                    self.showToast("\(displayID) → \(app.name) ✓")
                    self.refreshRow(kind: kind)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showToast("修改失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 批量修改：逐条执行，汇总结果（跳过不支持该类型的应用）
    /// - Parameter rows: 目标行；传 nil 时使用当前勾选
    func batchChange(_ targetRows: [AssociationRow]?, to app: AppRef) {
        let targets = targetRows ?? selectedRows
        guard !targets.isEmpty else { return }
        batchSheetRow = nil

        let appKey = app.path ?? app.name
        let appRef = app
        let total = targets.count
        showToast("开始批量修改 \(total) 项 → \(app.name)（系统会逐项弹确认框，请留意）")

        Task.detached(priority: .userInitiated) { [weak self] in
            var ok: [(kind: AssociationKind, displayID: String, previous: AppRef?)] = []
            var skipped: [String] = []
            var failed: [String] = []

            for row in targets {
                do {
                    try await Self.applyChange(appKey: appKey, kind: row.kind)
                    ok.append((row.kind, row.displayID, row.defaultApp))
                } catch let error as LSKError {
                    // 应用不声明支持该类型 → 系统拒绝，计为跳过
                    if case .launchServicesFailed = error {
                        skipped.append(row.displayID)
                    } else {
                        failed.append(row.displayID)
                    }
                } catch {
                    failed.append(row.displayID)
                }
            }

            // 拷贝为 let 以满足并发安全（var 捕获在 Swift 6 模式下是错误）
            let okResults = ok
            let skippedList = skipped
            let failedList = failed

            await MainActor.run { [weak self] in
                guard let self else { return }
                for entry in okResults {
                    self.pushUndo(UndoRecord(
                        kind: entry.kind, displayID: entry.displayID,
                        previousAppKey: entry.previous.map { $0.path ?? $0.name },
                        previousName: entry.previous?.name
                    ))
                    self.recordChange(kind: entry.kind, displayID: entry.displayID,
                                      fromName: entry.previous?.name, toName: appRef.name)
                    self.refreshRow(kind: entry.kind)
                }
                self.clearSelection()
                var summary = "批量完成：成功 \(okResults.count)"
                if !skippedList.isEmpty {
                    summary += "，跳过 \(skippedList.count) 项（应用不支持：\(skippedList.joined(separator: "、"))）"
                }
                if !failedList.isEmpty {
                    summary += "，失败 \(failedList.count) 项"
                }
                self.showToast(summary)
            }
        }
    }

    // MARK: - 恢复系统默认与撤销

    private func pushUndo(_ record: UndoRecord) {
        undoStack.append(record)
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
    }

    /// 清掉该类型用户显式设置的默认，交还系统决定。
    /// 恢复动作本身也可撤销：压入一条「恢复前默认」的记录。
    func restoreSystemDefault(_ row: AssociationRow) {
        editingRow = nil
        let kind = row.kind
        let displayID = row.displayID
        let previous = row.defaultApp
        showToast("正在恢复 \(displayID) 的系统默认…")

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try LSKAssociation.clearUserDefault(for: kind)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.pushUndo(UndoRecord(
                        kind: kind, displayID: displayID,
                        previousAppKey: previous.map { $0.path ?? $0.name },
                        previousName: previous?.name
                    ))
                    self.recordChange(kind: kind, displayID: displayID,
                                      fromName: previous?.name, toName: "系统默认")
                    self.refreshRow(kind: kind)
                    self.showToast("\(displayID) 已恢复系统默认（⌘Z 可撤销）")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showToast("恢复失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// ⌘Z：回退栈顶那条修改。之前有显式默认就设回去（系统会弹确认框），
    /// 之前没有就摘记录恢复系统默认。回退动作不再压栈——撤销链只单向走，
    /// 要再改回来请重新设置。
    func undoLast() {
        guard let record = undoStack.popLast() else { return }
        let kind = record.kind
        let displayID = record.displayID
        let targetKey = record.previousAppKey
        let targetName = record.previousName

        showToast(targetKey != nil
            ? "正在撤销 \(displayID) → \(targetName ?? "")…（请在系统弹窗中确认）"
            : "正在撤销 \(displayID)，恢复系统默认…")

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if let targetKey {
                    try await Self.applyChange(appKey: targetKey, kind: kind)
                } else {
                    try LSKAssociation.clearUserDefault(for: kind)
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // 撤销前该行此刻的默认，作为最近修改记录的 from
                    let currentName = self.rows.first { $0.kind == kind }?.defaultApp?.name
                    self.recordChange(kind: kind, displayID: displayID,
                                      fromName: currentName, toName: targetName ?? "系统默认")
                    self.refreshRow(kind: kind)
                    self.showToast("已撤销：\(displayID) → \(targetName ?? "系统默认")")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showToast("撤销失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func recordChange(kind: AssociationKind, displayID: String, fromName: String?, toName: String) {
        recentChanges.removeAll { $0.kind.kindKey() == kind.kindKey() }
        recentChanges.insert(
            RecentChange(kind: kind, displayID: displayID, fromName: fromName, toName: toName, date: Date()),
            at: 0
        )
        if recentChanges.count > 50 { recentChanges.removeLast(recentChanges.count - 50) }
        persistRecentChanges()
    }

    nonisolated private static func applyChange(appKey: String, kind: AssociationKind) async throws {
        switch kind {
        case .fileExtension(let e):
            try LSKAssociation.setDefaultApp(appKey, forExtension: e)
        case .urlScheme(let s):
            try LSKAssociation.setDefaultApp(appKey, forURLScheme: s)
        case .superType(let t):
            try LSKAssociation.setDefaultApp(appKey, forType: t.rawValue)
        case .uti(let u):
            try LSKAssociation.setDefaultApp(appKey, forType: u)
        }
    }

    /// 单行刷新（避免全量重载闪烁）；顺带重算 isUserSet，
    /// 「恢复系统默认」按钮随恢复动作即时消失
    private func refreshRow(kind: AssociationKind) {
        guard let index = rows.firstIndex(where: { $0.kind == kind }) else { return }
        let row = rows[index]
        Task.detached(priority: .userInitiated) { [weak self] in
            let info: AssociationInfo?
            switch kind {
            case .fileExtension(let e): info = try? LSKAssociation.info(forExtension: e)
            case .urlScheme(let s): info = try? LSKAssociation.info(forURLScheme: s)
            case .superType(let t): info = try? LSKAssociation.info(forType: t.rawValue)
            case .uti(let u): info = try? LSKAssociation.info(forType: u)
            }
            let userSet = ((try? LSKDatabase.handlers()) ?? [])
                .contains { $0.associationKind?.kindKey() == kind.kindKey() }
            let updated = Self.makeRow(
                kind: row.kind, displayID: row.displayID, uti: info?.uti ?? row.uti, info: info,
                isUserSet: userSet)
            await MainActor.run { [weak self] in
                self?.rows[index] = updated
            }
        }
    }

    // MARK: - Toast

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
