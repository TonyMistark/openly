import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 导出 Sheet

struct ExportSheet: View {
    @EnvironmentObject private var store: AssociationStore
    @Environment(\.dismiss) private var dismiss
    @State private var copyState = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("导出关联配置").font(.headline)
                Text("infat 兼容的 TOML — 可放入 dotfiles，新机器上 infat --config 一键还原")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)
            .padding(.bottom, 12)
            Divider()

            ScrollView {
                Text(store.exportTOML())
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }

            Divider()
            HStack {
                Button("关闭") { dismiss() }
                Spacer()
                Button(copyState ? "已拷贝 ✓" : "拷贝到剪贴板") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.exportTOML(), forType: .string)
                    copyState = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyState = false }
                }
                Button("存储…") { saveToFile() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.toml]
        panel.nameFieldStringValue = "infat-config.toml"
        panel.message = "存储 Openly 导出的关联配置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportTOML().write(to: url, atomically: true, encoding: .utf8)
            store.showToast("已存储到 \(url.lastPathComponent)")
            dismiss()
        } catch {
            store.showToast("存储失败：\(error.localizedDescription)")
        }
    }
}

extension UTType {
    static var toml: UTType { UTType(filenameExtension: "toml") ?? .plainText }
}

// MARK: - 导入差异 Sheet

struct ImportDiffSheet: View {
    @EnvironmentObject private var store: AssociationStore
    @Environment(\.dismiss) private var dismiss

    let diff: ImportDiff

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("导入 infat 配置").font(.headline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)
            .padding(.bottom, 12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !diff.additions.isEmpty {
                        sectionLabel("新增（当前无默认）", color: .green, count: diff.additions.count)
                        ForEach(diff.additions) { entry in
                            diffRow(entry)
                        }
                    }
                    if !diff.overwrites.isEmpty {
                        sectionLabel("覆盖已有默认", color: .orange, count: diff.overwrites.count)
                        ForEach(diff.overwrites) { entry in
                            diffRow(entry)
                        }
                    }
                    if diff.unchangedCount > 0 {
                        Text("其余 \(diff.unchangedCount) 条与当前系统一致，保持不变")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("应用变更（\(diff.additions.count + diff.overwrites.count)）") {
                    store.applyImportDiff(diff)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(diff.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
    }

    private var summaryText: String {
        let total = diff.additions.count + diff.overwrites.count
        if diff.isEmpty { return "配置与当前系统状态一致，无需变更" }
        return "将更新 \(total) 条关联；系统会逐项弹出确认框"
    }

    private func sectionLabel(_ title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) · \(count) 条")
                .font(.callout.weight(.semibold))
        }
        .padding(.top, 6)
    }

    private func diffRow(_ entry: ImportDiff.Entry) -> some View {
        HStack(spacing: 8) {
            Text(entry.displayID)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .frame(width: 110, alignment: .leading)
            if let current = entry.currentAppName {
                Text(current)
                    .foregroundStyle(.tertiary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.appName)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 导入文件选择

enum ImportPanel {
    /// 打开 NSOpenPanel 选 TOML，返回 (URL, 文本)；用户取消返回 nil
    static func pickAndRead() -> (URL, String)? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.toml]
        panel.message = "选择 infat 格式的 TOML 配置文件"
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (url, text)
    }
}
