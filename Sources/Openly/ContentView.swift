import AppKit
import LaunchServicesKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AssociationStore
    @State private var showExport = false
    @State private var importDiff: ImportDiff?

    var body: some View {
        NavigationSplitView {
            if store.viewMode == .byType {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            } else {
                AppSidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            }
        } detail: {
            if store.viewMode == .byType {
                AssociationListView()
            } else {
                AppDetailView()
            }
        }
        .navigationTitle("Openly")
        .searchable(
            text: $store.query,
            placement: .toolbar,
            prompt: "搜索扩展名、UTI 或应用"
        )
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Picker("视图", selection: $store.viewMode) {
                    Text("按类型").tag(ViewMode.byType)
                    Text("按应用").tag(ViewMode.byApp)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            ToolbarItemGroup {
                Button {
                    showExport = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .help("导出当前关联为 infat 兼容 TOML")
                Button {
                    startImport()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("从 infat TOML 配置导入")
                Button {
                    store.load()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新读取 Launch Services 数据")
            }
        }
        .overlay(alignment: .bottom) {
            if store.toast != nil {
                ToastView(text: store.toast ?? "")
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $store.batchSheetRow) { row in
            BatchAppPickerSheet(sourceRow: row)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet()
        }
        .sheet(item: $importDiff) { diff in
            ImportDiffSheet(diff: diff)
        }
        .onAppear {
            store.load()
            store.loadPersistedRecentChanges()
        }
    }

    private func startImport() {
        guard let (_, text) = ImportPanel.pickAndRead() else { return }
        do {
            importDiff = try store.computeImportDiff(tomlText: text)
        } catch {
            store.showToast("配置解析失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 侧栏

private struct SidebarView: View {
    @EnvironmentObject private var store: AssociationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarSection("智能列表") {
                    row("全部关联", "tray.2", .all, store.rows.count)
                    row("无默认应用", "exclamationmark.triangle", .noDefault,
                        store.rows.filter { $0.defaultApp == nil }.count)
                    row("最近修改", "clock.arrow.circlepath", .recent, store.recentChanges.count)
                }
                sidebarSection("文件类别") {
                    ForEach(Category.allCases.filter { $0 != .scheme && $0 != .other }) { category in
                        row(category.rawValue, category.symbol,
                            .category(category), store.categoryCounts[category] ?? 0)
                    }
                }
                sidebarSection("链接协议") {
                    row("URL Scheme", "link", .category(.scheme), store.categoryCounts[.scheme] ?? 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
    }

    private func sidebarSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 显式按钮行 — 不依赖 List selection（macOS 26 上绑定不生效）
    private func row(_ title: String, _ symbol: String, _ filter: SidebarFilter, _ count: Int) -> some View {
        let isSelected = store.filter == filter
        return Button {
            store.filter = filter
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 主列表

private struct AssociationListView: View {
    @EnvironmentObject private var store: AssociationStore
    @State private var focusedRowID: AssociationRow.ID?

    var body: some View {
        Group {
            if store.isLoading && store.rows.isEmpty {
                ProgressView("正在读取 Launch Services 数据…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.filteredRows.isEmpty {
                EmptyStateView()
            } else {
                VStack(spacing: 0) {
                    tableList
                    if !store.selectedKinds.isEmpty {
                        BatchBar()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveFocus(1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
        .onKeyPress(.return) {
            if let id = focusedRowID,
               let row = store.filteredRows.first(where: { $0.id == id }) {
                store.editingRow = row
                return .handled
            }
            return .ignored
        }
    }

    private func moveFocus(_ delta: Int) {
        let rows = store.filteredRows
        guard !rows.isEmpty else { return }
        guard let current = focusedRowID,
              let index = rows.firstIndex(where: { $0.id == current }) else {
            focusedRowID = rows[0].id
            return
        }
        let next = rows.index(index, offsetBy: delta, limitedBy: rows.startIndex)
            .flatMap { rows.indices.contains($0) ? $0 : nil }
            ?? (delta > 0 ? rows.count - 1 : 0)
        focusedRowID = rows[next].id
    }

    private var tableList: some View {
        List {
            HStack(spacing: 10) {
                CheckboxView(isOn: Binding(
                    get: { store.allVisibleSelected },
                    set: { _ in store.toggleSelectAllVisible() }
                ))
                Text("类型 / 扩展名")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("默认打开应用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("注册")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 64, alignment: .trailing)
                Color.clear.frame(width: 12)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            ForEach(store.filteredRows) { row in
                RowView(row: row, isFocused: focusedRowID == row.id)
                    .popover(
                        isPresented: Binding(
                            get: { store.editingRow?.id == row.id },
                            set: { if !$0 && store.editingRow?.id == row.id { store.editingRow = nil } }
                        ),
                        arrowEdge: .bottom
                    ) {
                        EditPopoverContent(row: row)
                            .frame(width: 320)
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - 复选框

struct CheckboxView: View {
    @Binding var isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundStyle(isOn ? Color.accentColor : .secondary)
            .onTapGesture { isOn.toggle() }
    }
}

// MARK: - 批量操作条

private struct BatchBar: View {
    @EnvironmentObject private var store: AssociationStore

    var body: some View {
        HStack(spacing: 12) {
            Text("已选 \(store.selectedRows.count) 项")
                .font(.callout.weight(.medium))
            Button("设为默认应用…") {
                store.batchSheetRow = store.selectedRows.first
            }
            .controlSize(.regular)
            Spacer()
            Button("取消选择") {
                store.clearSelection()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("没有匹配的关联").foregroundStyle(.secondary)
            Text("试试搜索其他扩展名，或切换侧栏分类")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 行

private struct RowView: View {
    @EnvironmentObject private var store: AssociationStore
    let row: AssociationRow
    var isFocused: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // 批量勾选框
            CheckboxView(isOn: Binding(
                get: { store.selectedKinds.contains(row.kind.kindKey()) },
                set: { _ in store.toggleSelection(row) }
            ))

            // 类型徽标：扩展名首段文字
            Text(badgeText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 34, height: 26)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayID)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                    if let change = recentChange {
                        Text("\(change.fromName ?? "无") → \(change.toName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
                if let uti = row.uti {
                    Text(uti)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 16)

            if let app = row.defaultApp {
                // 只显示图标：名称长度不一会导致列参差；悬浮 tooltip 展示名称与路径
                AppIconView(app: app, size: 24)
                    .help(tooltipText(for: app))
            } else {
                Text("无默认")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.1), in: Capsule())
                    .help("该类型尚未设置默认打开应用")
            }

            Text("\(row.registered.count) 个应用")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.editingRow = row }
    }

    private var recentChange: RecentChange? {
        store.recentChanges.first { $0.kind.kindKey() == row.kind.kindKey() }
    }

    /// 悬浮提示：名称 + 路径（多行）
    private func tooltipText(for app: AppRef) -> String {
        var lines = [app.name]
        if let path = app.path { lines.append(path) }
        return lines.joined(separator: "\n")
    }

    private var badgeText: String {
        switch row.kind {
        case .fileExtension(let e): return String(e.prefix(4))
        case .urlScheme: return "://"
        case .superType, .uti: return "UTI"
        }
    }

    private var badgeColor: Color {
        switch row.category {
        case .document: return .blue
        case .image: return .orange
        case .audio: return .pink
        case .video: return .red
        case .archive: return .purple
        case .code: return .green
        case .system: return .gray
        case .scheme: return .cyan
        case .other: return .secondary
        }
    }
}

// MARK: - 应用图标

struct AppIconView: View {
    let app: AppRef
    var size: CGFloat = 24

    var body: some View {
        if let path = app.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: size, height: size)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 编辑弹窗

private struct EditPopoverContent: View {
    @EnvironmentObject private var store: AssociationStore
    let row: AssociationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayID)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                if let uti = row.uti {
                    Text(uti)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            if row.registered.isEmpty {
                Text("没有应用注册此类型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(row.registered, id: \.bundleID) { app in
                            AppPickerRow(
                                app: app,
                                isCurrent: app.bundleID == row.defaultApp?.bundleID
                            ) {
                                store.changeDefault(row, to: app)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 264)
            }

            Divider()

            Button {
                browseForApp()
            } label: {
                Label("浏览其他应用…", systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// NSOpenPanel 选择任意位置的 .app，注册后由用户确认设置为默认
    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择一个应用作为 \(row.displayID) 的默认打开方式"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // 先注册到 Launch Services（非破坏性操作，不改变任何默认值）
        do {
            try LSKAssociation.registerApp(at: url)
            let bundleID = try LSKAppResolver.bundleID(forApp: url.path)
            let ref = LSKAppResolver.appRef(forBundleID: bundleID)
            store.changeDefault(row, to: ref)
        } catch {
            store.showToast("无法使用该应用：\(error.localizedDescription)")
        }
    }
}

private struct AppPickerRow: View {
    let app: AppRef
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(app: app, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.callout)
                Text(app.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Toast

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(.init(text))
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.black.opacity(0.82), in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}

// MARK: - 按应用视图 · 侧栏

private struct AppSidebarView: View {
    @EnvironmentObject private var store: AssociationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("应用（按接管数量）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                ForEach(store.appsWithCounts, id: \.app.bundleID) { entry in
                    appRow(entry.app, count: entry.count, dimmed: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
        .onAppear {
            if store.selectedAppBundleID == nil {
                store.selectedAppBundleID = store.appsWithCounts.first?.app.bundleID
            }
        }
    }

    private func appRow(_ app: AppRef, count: Int, dimmed: Bool) -> some View {
        let isSelected = store.selectedAppBundleID == app.bundleID
        return Button {
            store.selectedAppBundleID = app.bundleID
        } label: {
            HStack(spacing: 7) {
                AppIconView(app: app, size: 22)
                Text(app.name)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.45 : 1)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 按应用视图 · 主区

private struct AppDetailView: View {
    @EnvironmentObject private var store: AssociationStore

    var body: some View {
        Group {
            if let app = store.appsWithCounts.first(where: { $0.app.bundleID == store.selectedAppBundleID })?.app {
                VStack(spacing: 0) {
                    appHero(app)
                    Divider()
                    if store.rowsForSelectedApp.isEmpty {
                        EmptyStateView()
                    } else {
                        List(store.rowsForSelectedApp) { row in
                            AppDetailRow(row: row)
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                    }
                }
            } else {
                EmptyStateView()
            }
        }
    }

    private func appHero(_ app: AppRef) -> some View {
        HStack(spacing: 12) {
            AppIconView(app: app, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title3.weight(.semibold))
                Text(app.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("接管 \(store.rowsForSelectedApp.count) 个类型的默认打开方式")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !store.rowsForSelectedApp.isEmpty {
                Button("全部转移给…") {
                    store.batchSheetRow = store.rowsForSelectedApp.first
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct AppDetailRow: View {
    @EnvironmentObject private var store: AssociationStore
    let row: AssociationRow

    var body: some View {
        HStack(spacing: 10) {
            Text(row.displayID)
                .font(.system(.body, design: .monospaced).weight(.medium))
            if let uti = row.uti {
                Text(uti)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let change = store.recentChanges.first(where: { $0.kind.kindKey() == row.kind.kindKey() }) {
                Text("原为 \(change.fromName ?? "无")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 批量应用选择 Sheet

/// 从一组行的注册应用并集中选一个，批量应用到全部目标行。
/// sourceRow 仅用于 sheet(item:) 的 Identifiable 触发。
private struct BatchAppPickerSheet: View {
    @EnvironmentObject private var store: AssociationStore
    let sourceRow: AssociationRow

    /// 批量目标：按应用视图打开时 = 该应用的全部行；否则 = 当前勾选
    private var targets: [AssociationRow] {
        store.viewMode == .byApp ? store.rowsForSelectedApp : store.selectedRows
    }

    /// 目标行注册应用的并集（候选）
    private var candidates: [AppRef] {
        var seen = Set<String>()
        var result: [AppRef] = []
        for row in targets {
            for app in row.registered where !seen.contains(app.bundleID) {
                seen.insert(app.bundleID)
                result.append(app)
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @State private var picked: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("设为默认应用")
                    .font(.headline)
                Text("将对 \(targets.count) 个类型应用所选应用；系统会逐项弹出确认框，应用不支持的项目将跳过")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(candidates, id: \.bundleID) { app in
                        BatchCandidateRow(
                            app: app,
                            isSelected: picked == app.bundleID
                        ) {
                            picked = app.bundleID
                        }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 200, maxHeight: 340)

            Divider()

            HStack {
                Button("取消") {
                    store.batchSheetRow = nil
                }
                Spacer()
                Button("应用（\(targets.count) 项）") {
                    if let id = picked,
                       let app = candidates.first(where: { $0.bundleID == id }) {
                        store.batchChange(targets, to: app)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked == nil)
            }
            .padding(16)
        }
        .frame(width: 420)
    }
}

private struct BatchCandidateRow: View {
    let app: AppRef
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(app: app, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.callout)
                Text(app.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .onTapGesture(perform: action)
    }
}
