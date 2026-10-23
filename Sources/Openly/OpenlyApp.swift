import AppKit
import SwiftUI

@main
struct OpenlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AssociationStore()
    /// App-level services: update checking and one-click installation.
    @StateObject private var updates = UpdateChecker()
    @StateObject private var installer = UpdateInstaller(steps: UpdateInstaller.productionSteps())

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(updates)
                .frame(minWidth: 780, minHeight: 500)
                .background(OpenWindowBridge())
                .task { await updates.checkIfDue() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environmentObject(updates)
                .environmentObject(installer)
        }
        .commands {
            AppMenus(store: store, updates: updates)
        }
    }
}

/// Replaces the default About item with our panel (it adds the repository
/// link and description), slots "Check for Updates…" right below it, and
/// takes over the Undo slot — system text undo is useless here, while the
/// association undo stack is this app's real ⌘Z.
struct AppMenus: Commands {
    @ObservedObject var store: AssociationStore
    let updates: UpdateChecker

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(store.undoMenuTitle ?? "撤销") {
                store.undoLast()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!store.canUndo)
        }
        CommandGroup(replacing: .appInfo) {
            Button(t("About Openly")) { AboutPanel.show() }
        }
        CommandGroup(after: .appInfo) {
            Button(updates.isChecking ? t("Checking…") : t("Check for Updates…")) {
                Task { await updates.check(force: true) }
            }
            .disabled(updates.isChecking)
        }
    }
}

/// SPM 可执行目标跑 SwiftUI 需要 regular 激活策略，否则没有菜单栏、无法获得焦点。
/// 同时接管 Dock 图标的 reopen：SwiftUI 的默认实现只认「上一次那扇窗」，
/// 那扇窗关了就什么都不做——这里自己举窗，一扇都不剩就开新的。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            MainActor.assumeIsolated {
                AppActivation.remember(note.object as? NSWindow)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppActivation.remember(NSApplication.shared.keyWindow)
    }

    /// 返回值是「这件事我处理完了」。举不出一扇窗（全关了）就交给
    /// `AppActivation.openMain` 开一扇新的；通道没装好时返回 false，
    /// 让系统按自己的规矩兜底。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 全缩在 Dock 里：交回系统，只有它能给出神灯展开动画。
        if AppActivation.defersToSystem(sender.windows) { return false }

        if AppActivation.raiseFrontWindow() { return true }
        guard let open = AppActivation.openMain else { return false }
        open()
        return true
    }

    deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }
}
