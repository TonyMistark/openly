import SwiftUI

@main
struct OpenlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AssociationStore()

    var body: some Scene {
        WindowGroup("Openly") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 780, minHeight: 500)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}

/// SPM 可执行目标跑 SwiftUI 需要 regular 激活策略，否则没有菜单栏、无法获得焦点
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
