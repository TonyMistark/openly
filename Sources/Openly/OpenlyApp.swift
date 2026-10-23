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
        WindowGroup("Openly") {
            ContentView()
                .environmentObject(store)
                .environmentObject(updates)
                .frame(minWidth: 780, minHeight: 500)
                .task { await updates.checkIfDue() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environmentObject(updates)
                .environmentObject(installer)
        }
        .commands {
            AppMenus(updates: updates)
        }
    }
}

/// Replaces the default About item with our panel (it adds the repository
/// link and description) and slots "Check for Updates…" right below it.
struct AppMenus: Commands {
    let updates: UpdateChecker

    var body: some Commands {
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

/// SPM 可执行目标跑 SwiftUI 需要 regular 激活策略，否则没有菜单栏、无法获得焦点
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
