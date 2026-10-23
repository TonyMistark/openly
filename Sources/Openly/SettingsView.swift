import AppKit
import SwiftUI

// MARK: - Settings window

/// Single-page settings, three sections top to bottom: Language, Updates,
/// About. Openly has exactly one settings concern per section, so a grouped
/// Form beats a sidebar shell — pages would be one row each.
struct SettingsView: View {
    @EnvironmentObject var updates: UpdateChecker
    @EnvironmentObject var installer: UpdateInstaller

    /// Interface language. The default reads `L10n.defaultLanguage` so the
    /// picker always shows what is actually in effect; "" = "Follow System"
    /// chosen explicitly. Writing here is visible to `L10n.userPreference`,
    /// which reads the same UserDefaults key.
    @AppStorage("openly.language") private var languageChoice = L10n.defaultLanguage.rawValue

    /// Launch-time automatic check. Default on; `UpdateChecker.checkIfDue`
    /// reads the same key through `autoCheckEnabled`.
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheck = true

    var body: some View {
        Form {
            languageSection
            updatesSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 540)
    }

    // MARK: Language

    private var languageSection: some View {
        Section(t("Language")) {
            Picker(t("Interface language"), selection: $languageChoice) {
                Text(t("Follow System")).tag("")
                ForEach(Language.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            Text(t("Takes effect the next time Openly opens — windows are built at launch."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        Section(t("Updates")) {
            Toggle(t("Automatically check for updates"), isOn: $autoCheck)
            Text(t("Checks at most once a day. Nothing is sent from this Mac."))
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent(t("Openly"), value: updates.currentVersion)
            LabeledContent(t("System"), value: systemDescription)

            HStack {
                statusLine
                Spacer()
                updateAction
                Button(updates.isChecking ? t("Checking…") : t("Check Now")) {
                    Task { await updates.check(force: true) }
                }
                .disabled(updates.isChecking || installer.phase.isWorking)
            }
        }
    }

    private var statusLine: some View {
        Text(updates.status.summary ?? t("Not checked yet"))
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var systemDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
        return "macOS \(version)"
    }

    /// Next to "Check Now", swapped for the update action when a new version
    /// is available: install when possible, offer a Finder exit otherwise.
    /// Empty the rest of the time.
    @ViewBuilder
    private var updateAction: some View {
        switch (updates.status, installer.phase) {
        case (.available(let version, let url, let asset), .idle):
            Button(t("Update…")) {
                if let asset {
                    Task { await installer.run(asset: asset, version: version, releaseURL: url) }
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
            .help(t("Download and install v{}, then relaunch", version))
        case (_, .downloading(let fraction)):
            Text(t("Downloading {}%", Int(fraction * 100)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        case (_, .installing):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
                Text(t("Installing…")).font(.callout).foregroundStyle(.secondary)
            }
        case (_, .failed(let reason)):
            if installer.downloadedDMG != nil {
                Button(t("Reveal Download")) {
                    installer.revealFallback()
                }
                .help(reason)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(reason)
            }
        default:
            EmptyView()
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section(t("About")) {
            Button(t("About Openly")) { AboutPanel.show() }
            Button(t("GitHub Repository")) {
                NSWorkspace.shared.open(URL(string: "https://github.com/TonyMistark/openly")!)
            }
            LabeledContent(t("License"), value: t("MIT License"))
        }
    }
}

// MARK: - About panel

/// The standard About panel, shared by the app menu and the settings page.
/// Adds a one-line description and a link to the repository on top of what
/// the bundle's Info.plist provides.
@MainActor
enum AboutPanel {
    static func show() {
        let repository = "https://github.com/TonyMistark/openly"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSMutableAttributedString(
            string: t("A macOS utility for managing default apps — see what opens what, change it in bulk, and take your configuration with you.\n")
                + "github.com/TonyMistark/openly",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        credits.addAttribute(
            .link, value: repository,
            range: (credits.string as NSString).range(of: "github.com/TonyMistark/openly")
        )
        NSApp?.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp?.activate(ignoringOtherApps: true)
    }
}
