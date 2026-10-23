import AppKit
import SwiftUI

/// 「点了 Dock 图标，窗口却不出来」的修复。
///
/// 应用被激活时，系统只会把它**记得的那扇窗**拿到前面——那扇窗已经被 ⌘W
/// 关掉的话，菜单栏换了名字，屏幕上一个像素都不会动。这里自己接手：
/// 有窗可举就举，一扇都不剩就走 `openWindow(id:)` 开一扇新的。
enum AppActivation {
    /// 没有窗可举时开主窗的通道。由窗口里的隐藏桥视图装进来——
    /// `openWindow` 只在场景环境里读得到，AppDelegate 拿不到。
    static var openMain: (() -> Void)?

    /// 最近一次成为 key 的窗口。弱引用：窗关掉之后不能拽着它不放。
    private(set) static weak var lastKey: NSWindow?

    static func remember(_ window: NSWindow?) {
        guard let window, window.sheetParent == nil else { return }
        lastKey = window
    }

    /// 挑一扇能当主的窗口举到前面并激活应用。一扇都没有返回 false。
    ///
    /// 顺序：上次用的那扇 > 看得见的普通窗 > 缩在 Dock 里的窗。
    @MainActor
    @discardableResult
    static func raiseFrontWindow() -> Bool {
        let app = NSApplication.shared
        let candidates = app.windows.filter {
            !($0 is NSPanel) && $0.canBecomeKey && $0.sheetParent == nil
        }
        guard let target = preferredWindow(among: candidates) else { return false }

        if app.isHidden { app.unhide(nil) }
        activate(app)
        target.makeKeyAndOrderFront(nil)
        return true
    }

    private static func preferredWindow(among candidates: [NSWindow]) -> NSWindow? {
        if let last = lastKey, last.isVisible, candidates.contains(last) {
            return last
        }
        return candidates.first(where: { $0.isVisible })
    }

    /// 所有能当主的窗口都缩在 Dock 里吗？是的话交给系统——只有系统那条路
    /// 能给出「神灯」动画，自己 deminiaturize 出来的窗没有动画。
    static func defersToSystem(_ windows: [NSWindow]) -> Bool {
        let eligible = windows.filter {
            !($0 is NSPanel) && $0.canBecomeKey && $0.sheetParent == nil
        }
        guard !eligible.isEmpty else { return false }
        return eligible.allSatisfy(\.isMiniaturized)
    }

    private static func activate(_ app: NSApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(ignoringOtherApps: true)
        }
    }
}

/// 隐藏桥视图：把 `openWindow` 包成闭包交给 `AppActivation`，
/// AppDelegate 与菜单命令层在场景之外，读不到这个环境值。
struct OpenWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                AppActivation.openMain = { openWindow(id: "main") }
            }
    }
}
