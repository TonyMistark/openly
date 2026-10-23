import AppKit
import SwiftUI

extension Notification.Name {
    /// ⌘F：把焦点交给工具栏搜索框。`searchable` 被换掉后得自己补上这条。
    static let focusAssociationSearch = Notification.Name("Openly.focusAssociationSearch")
}

/// 工具栏正中的固定宽度搜索框。
///
/// 不用 `.searchable(placement: .toolbar)`：那个实现在聚焦时会把搜索框展开，
/// 顺手把右侧按钮挤成折叠菜单——点一次搜索，导出/导入/刷新全要重新找一遍。
/// 这里的宽度是固定的，聚焦只多一圈描边，按钮位置一动不动。
struct ToolbarSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索扩展名、UTI 或应用", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onExitCommand { text = "" }

            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),
                    lineWidth: 1
                )
        )
        .frame(width: 240)
        .onReceive(NotificationCenter.default.publisher(for: .focusAssociationSearch)) { _ in
            focused = true
        }
    }
}
