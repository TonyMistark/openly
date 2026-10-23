import AppKit
import Foundation
import SwiftUI

// MARK: - One-click update

/// One click = update done: download → mount → install into /Applications → relaunch.
///
/// Three iron rules, inherited from the wtmd design:
/// 1. **The installed version is sacred** — the new app is first assembled
///    and verified inside the destination directory (bundle version must
///    equal the promised version); only after everything passes may the old
///    installed copy be touched. Any failure mid-flight leaves the old copy
///    byte-for-byte intact.
/// 2. **Never force a downgrade** — if installation is impossible, fall back
///    to Finder (reveal the dmg); whether and when to drag it is the user's call.
/// 3. **Injectable** — download, mount, install and relaunch are step
///    closures; tests touch neither the network, nor /Applications, and
///    never actually relaunch.
@MainActor
final class UpdateInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// 0..<1, from Content-Length.
        case downloading(fraction: Double)
        case installing
        /// Why installation failed; the UI offers a "reveal in Finder" exit.
        case failed(reason: String)

        var isWorking: Bool {
            switch self {
            case .downloading, .installing: return true
            case .idle, .failed: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// Where downloads land and where installs go. Production: temp dir and /Applications.
    struct Locations {
        var downloads: URL
        var applications: URL
        /// The name the installed app carries afterwards.
        var appName = "Openly.app"

        static let production = Locations(
            downloads: FileManager.default.temporaryDirectory,
            applications: URL(fileURLWithPath: "/Applications", isDirectory: true)
        )
    }

    // MARK: Injectable steps

    struct Steps {
        /// Download locally, report progress in 0..<1; returns the dmg path.
        var download: @MainActor (_ from: URL, _ progress: @MainActor @escaping (Double) -> Void) async throws -> URL
        /// Mount the dmg, return the `.app` path inside the volume.
        var mount: @MainActor (_ dmg: URL) async throws -> URL
        /// Install the `.app` into the destination, return the landing spot.
        /// **The implementation must guarantee: on failure the old copy is untouched.**
        var install: @MainActor (_ app: URL, _ locations: Locations, _ expectedVersion: String) async throws -> URL
        /// Relaunch into the freshly installed copy.
        var relaunch: @MainActor (_ installed: URL) async throws -> Void
        /// Fallback: reveal the dmg in Finder.
        var reveal: @MainActor (_ dmg: URL) -> Void
    }

    private var steps: Steps
    private let locations: Locations

    init(steps: Steps, locations: Locations = .production) {
        self.steps = steps
        self.locations = locations
    }

    /// Needed by the fallback: the last successfully landed dmg.
    private(set) var downloadedDMG: URL?

    /// The release page of the mirror the user last tried to download from.
    /// The UI's fallback exit when download or install fails — a working
    /// mirror in a browser beats a dead progress bar.
    private(set) var lastReleaseURL: URL?

    // MARK: Flow

    /// The press from the menu or the settings page. `version` verifies the landing spot afterwards.
    func run(asset: UpdateAsset, version: String, releaseURL: URL) async {
        guard !phase.isWorking else { return }
        lastReleaseURL = releaseURL

        do {
            phase = .downloading(fraction: 0)
            let dmg = try await steps.download(asset.url) { [weak self] fraction in
                self?.phase = .downloading(fraction: fraction)
            }
            downloadedDMG = dmg

            phase = .installing
            let app = try await steps.mount(dmg)
            let installed = try await steps.install(app, locations, version)
            try await steps.relaunch(installed)
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(reason: Failure.describe(error))
        }
    }

    /// Fallback when installation fails: reveal the dmg in Finder, let the user drag.
    func revealFallback() {
        guard let dmg = downloadedDMG else { return }
        steps.reveal(dmg)
    }

    func reset() {
        phase = .idle
    }

    // MARK: Failure wording

    enum Failure: Error {
        case noAppInVolume
        case mountFailed(underlying: Error)
        case copyFailed(underlying: Error)
        case verifyFailed(expected: String, found: String?)
        case swapFailed(underlying: Error)

        static func describe(_ error: Error) -> String {
            if let failure = error as? Failure {
                switch failure {
                case .noAppInVolume:
                    return t("No app found in the downloaded image.")
                case .mountFailed:
                    return t("The download could not be mounted.")
                case .copyFailed:
                    return t("Could not stage the new app.")
                case .verifyFailed:
                    return t("The downloaded app is not the promised version.")
                case .swapFailed:
                    return t("Could not replace the installed app.")
                }
            }
            return error.localizedDescription
        }
    }

    // MARK: Default steps

    static func productionSteps() -> Steps {
        Steps(
            download: { url, progress in
                try await Self.download(url, progress: progress)
            },
            mount: { dmg in
                try await Self.mount(dmg)
            },
            install: { app, locations, version in
                try Self.install(app: app, into: locations, expectedVersion: version)
            },
            relaunch: { installed in
                try await Self.relaunch(into: installed)
            },
            reveal: { dmg in
                NSWorkspace.shared.activateFileViewerSelecting([dmg])
            }
        )
    }

    // MARK: Download

    nonisolated static func download(
        _ url: URL,
        progress: @MainActor @escaping (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = response.expectedContentLength
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("openly-update-\(UUID().uuidString).dmg")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)

        // Write in chunks: per-byte write syscalls on a multi-MB dmg make
        // progress reporting unwatchable
        let chunkSize = 256 * 1024
        var chunk = Data()
        chunk.reserveCapacity(chunkSize)
        var received: Int64 = 0
        var lastReported = -1.0

        func flush() throws {
            guard !chunk.isEmpty else { return }
            received += Int64(chunk.count)
            try handle.write(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
            if total > 0 {
                let fraction = Double(received) / Double(total)
                if fraction - lastReported >= 0.01 {
                    lastReported = fraction
                    Task { @MainActor in progress(fraction) }
                }
            }
        }

        do {
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= chunkSize { try flush() }
            }
            try flush()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return target
    }

    // MARK: Mount

    nonisolated static func mount(_ dmg: URL) async throws -> URL {
        let point = FileManager.default.temporaryDirectory
            .appendingPathComponent("openly-mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: point, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmg.path, "-readonly", "-nobrowse", "-quiet", "-mountpoint", point.path]
        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: point)
            throw Failure.mountFailed(underlying: error)
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: point)
            throw Failure.mountFailed(underlying: NSError(
                domain: "openly.updates", code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "hdiutil attach failed"]
            ))
        }

        // Find the `.app` in the volume: the release image ships exactly one
        guard let enumerator = FileManager.default.enumerator(at: point, includingPropertiesForKeys: nil),
              let app = enumerator.allObjects.first(where: {
                  ($0 as? URL)?.pathExtension == "app"
              }) as? URL else {
            detach(point)
            throw Failure.noAppInVolume
        }
        return app
    }

    nonisolated private static func detach(_ point: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["detach", point.path, "-quiet"]
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: Install

    /// Every step assembles "in the destination, verify, then swap":
    /// stage → strip quarantine → verify version → move old aside →
    /// rename staging into place. Any thrown error leaves
    /// `/Applications/Openly.app` exactly as it was.
    /// - Parameter retire: how the old copy steps down (to Trash); injectable
    ///   so tests never actually trash anything.
    nonisolated static func install(
        app: URL,
        into locations: Locations,
        expectedVersion: String,
        retire: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws -> URL {
        let manager = FileManager.default
        let destination = locations.applications
            .appendingPathComponent(locations.appName, isDirectory: true)
        let staging = locations.applications
            .appendingPathComponent("openly.app.update-\(UUID().uuidString)", isDirectory: true)

        do {
            try manager.copyItem(at: app, to: staging)
        } catch {
            throw Failure.copyFailed(underlying: error)
        }
        defer { try? manager.removeItem(at: staging) }

        stripQuarantine(staging)

        // Version verification: what was downloaded must be what was promised
        let found = bundleVersion(of: staging)
        guard found == expectedVersion else {
            throw Failure.verifyFailed(expected: expectedVersion, found: found)
        }

        // Old copy steps down: to Trash if possible, renamed aside otherwise —
        // neither path deletes data
        if manager.fileExists(atPath: destination.path) {
            do {
                try retire(destination)
            } catch {
                let aside = locations.applications
                    .appendingPathComponent("openly.app.old-\(UUID().uuidString)", isDirectory: true)
                do {
                    try manager.moveItem(at: destination, to: aside)
                } catch {
                    throw Failure.swapFailed(underlying: error)
                }
            }
        }
        do {
            try manager.moveItem(at: staging, to: destination)
        } catch {
            throw Failure.swapFailed(underlying: error)
        }
        return destination
    }

    /// Strip `com.apple.quarantine`: without it the relaunch is stopped dead
    /// by Gatekeeper (the right-click-open escape hatch is gone on macOS 15+).
    /// A missing or failed xattr never blocks the install — worst case the
    /// user approves once at relaunch.
    nonisolated static func stripQuarantine(_ app: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-cr", app.path]
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// The version reported by the bundle; nil when there is no Info.plist.
    nonisolated static func bundleVersion(of app: URL) -> String? {
        Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Probe the quarantine flag (tests).
    nonisolated static func hasQuarantine(_ path: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-p", "com.apple.quarantine", path.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: Relaunch

    /// Relaunch into the freshly installed copy.
    ///
    /// **Do not simply openApplication**: the new copy now sits at the same
    /// path with an identical bundle id, so LaunchServices only "activates
    /// the exiting self" — the callback returns our own pid and no new
    /// process is ever spawned. The user sees "installed, quit, nothing
    /// reopened" (wtmd #195 proved this on real hardware).
    ///
    /// So "wait until we exit, then open the new copy" is handed to a shell
    /// detached from this process: it is our child, we do not wait, launchd
    /// adopts it after we exit, and it keeps waiting and opens.
    nonisolated static func relaunch(into installed: URL) async throws {
        do {
            try spawnRelauncher(
                waitingFor: ProcessInfo.processInfo.processIdentifier,
                opening: installed
            )
        } catch {
            // Fallback when spawning is denied (sandbox): force a new instance,
            // at least the window comes back. Cost: brief coexistence with our
            // not-yet-dead self — better than nothing.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            try await NSWorkspace.shared.openApplication(at: installed, configuration: configuration)
        }
        await MainActor.run { NSApp.terminate(nil) }
    }

    /// The script handed to `/bin/sh`: wait for `pid` to vanish (max 15 s),
    /// then open the new copy.
    ///
    /// `-n` is the safety net: if the old process truly hangs (a save-conflict
    /// dialog blocking quit, say), force a new instance anyway — an empty
    /// desktop is worse.
    nonisolated static func relaunchScript(waitingFor pid: Int32, opening app: URL) -> String {
        "i=0; while kill -0 \(pid) 2>/dev/null && [ $i -lt 75 ]; do sleep 0.2; i=$((i+1)); done; "
            + "exec /usr/bin/open -n \(shellQuoted(app.path))"
    }

    /// Wrap the path in single quotes: paths with spaces never split into two
    /// arguments. Embedded single quotes escape as `'\''` — the only
    /// shell-safe spelling.
    nonisolated static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Spawn the "reap and relaunch" child; do not wait — it must outlive us.
    nonisolated static func spawnRelauncher(waitingFor pid: Int32, opening app: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", relaunchScript(waitingFor: pid, opening: app)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
    }
}
