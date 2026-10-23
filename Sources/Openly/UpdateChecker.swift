import Foundation
import SwiftUI

// MARK: - Version

/// Lenient semver: `v0.4.0`, `0.4`, `0.4.0-beta.2` all parse.
///
/// Minimal semver-faithful comparison: numeric segments compared positionally
/// (missing = 0), prerelease ranks **below** the same-numbered release
/// (`0.4.0-beta` < `0.4.0`), numeric prerelease identifiers rank below
/// alphanumeric ones (`beta.2` < `beta.x`).
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let core: [Int]
    let prerelease: [String]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        // Build metadata (+build.5) never participates in comparison
        if let plus = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plus])
        }
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".").map { Int($0) }
        // Any non-integer numeric segment invalidates the whole string —
        // a missed notice beats a false "update available"
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        core = numbers.compactMap { $0 }
        if parts.count > 1 {
            let identifiers = parts[1].split(separator: ".").map(String.init)
            guard !identifiers.isEmpty else { return nil }
            prerelease = identifiers
        } else {
            prerelease = []
        }
    }

    var description: String {
        let base = core.map(String.init).joined(separator: ".")
        return prerelease.isEmpty ? base : "\(base)-\(prerelease.joined(separator: "."))"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.core.count, rhs.core.count)
        for index in 0..<count {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right { return left < right }
        }
        // Equal numeric segments: the one with a prerelease tag is smaller
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (_?, nil):
                return true      // numeric identifier < alphanumeric identifier
            case (nil, _?):
                return false
            default:
                return left < right
            }
        }
        // Same prefix, fewer identifiers is smaller (0.4.0-beta < 0.4.0-beta.1)
        return lhs.prerelease.count < rhs.prerelease.count
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

// MARK: - Check result

/// State consumed directly by the UI. `upToDate` and `failed` are one-shot
/// feedback that flashes back to `idle`; `available` stays until the user
/// upgrades.
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    /// `asset` is the dmg download (URL + size); nil when the release has no
    /// dmg attached and the UI falls back to opening the release page.
    case available(version: String, releaseURL: URL, asset: UpdateAsset?)
    case failed
}

/// The dmg asset picked out of a release — what one-click update downloads.
struct UpdateAsset: Equatable {
    let url: URL
    let name: String
    let byteCount: Int

    var megabytes: String {
        byteCount >= 0 ? String(format: "%.1f MB", Double(byteCount) / 1_000_000) : ""
    }

    /// Pick the installable dmg from a set of assets: matches
    /// `openly-<version>.dmg` (case-insensitive); with several candidates
    /// prefer the one containing the version, else the first.
    static func dmg(named names: [(name: String, url: URL, size: Int)], version: String?) -> UpdateAsset? {
        let candidates = names.compactMap { piece -> UpdateAsset? in
            guard piece.name.lowercased().hasSuffix(".dmg") else { return nil }
            return UpdateAsset(url: piece.url, name: piece.name, byteCount: piece.size)
        }
        guard candidates.count > 1, let version else { return candidates.first }
        return candidates.first {
            $0.name.localizedCaseInsensitiveContains(version)
        } ?? candidates.first
    }
}

// MARK: - Checker

/// Queries the GitHub release at most once a day; surfaces new versions in
/// Settings and the app menu.
///
/// Three deliberate restraints:
/// 1. **Throttled** — no re-check within 24 h after success, 1 h after failure;
/// 2. **Silent failure** — a settings/association tool must not nag offline;
/// 3. **Injectable** — network, current version, clock and UserDefaults are
///    all injected; tests never touch the real network.
@MainActor
final class UpdateChecker: ObservableObject {
    typealias Fetch = () async throws -> (Data, URLResponse)

    struct Configuration {
        var currentVersion: String
        var endpoint: URL
        /// Quiet period after a successful check.
        var interval: TimeInterval
        /// Retry interval after failure (shorter, but long enough to avoid
        /// hammering a wall on every launch).
        var retryInterval: TimeInterval

        static let `default` = Configuration(
            currentVersion: UpdateChecker.bundleVersion(),
            endpoint: URL(string: "https://api.github.com/repos/TonyMistark/openly/releases/latest")!,
            interval: 24 * 60 * 60,
            retryInterval: 60 * 60
        )
    }

    /// UserDefaults switch for the launch-time automatic check.
    static let autoCheckKey = "openly.updates.autoCheck"

    @Published private(set) var status: UpdateStatus = .idle

    /// How long one-shot feedback stays visible.
    private static let flashDuration: TimeInterval = 4

    private let configuration: Configuration
    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: Fetch
    private var resetTask: Task<Void, Never>?

    private enum Key {
        static let lastCheck = "openly.updates.lastCheck"
        static let lastCheckSucceeded = "openly.updates.lastCheckOK"
    }

    init(
        configuration: Configuration = .default,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping Fetch = UpdateChecker.fetchLatestRelease
    ) {
        self.configuration = configuration
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
    }

    var isChecking: Bool { status == .checking }

    var currentVersion: String { configuration.currentVersion }

    /// Whether the launch-time check is enabled (default on).
    static func autoCheckEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: autoCheckKey) as? Bool ?? true
    }

    /// Called at launch: actually fires only when due and the auto switch is on.
    func checkIfDue() async {
        guard Self.autoCheckEnabled(defaults: defaults) else { return }
        await check(force: false)
    }

    /// Manual "Check Now" — ignores throttling.
    func check(force: Bool) async {
        guard status != .checking else { return }
        guard force || isDue else { return }

        resetTask?.cancel()
        status = .checking

        do {
            let (data, response) = try await fetch()
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw UpdateError.badResponse
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            recordAttempt(succeeded: true)
            evaluate(release)
        } catch {
            recordAttempt(succeeded: false)
            flash(.failed)
        }
    }

    // MARK: Evaluation

    private func evaluate(_ release: GitHubRelease) {
        guard !release.draft, !release.prerelease,
              let latest = AppVersion(release.tagName) else {
            // Prerelease or unparseable tag: treat as "no stable release",
            // never bother the user with it
            flash(.upToDate(version: configuration.currentVersion))
            return
        }
        guard let current = AppVersion(configuration.currentVersion) else {
            flash(.failed)
            return
        }
        if latest > current {
            status = .available(version: latest.description, releaseURL: release.htmlURL, asset: release.asset)
        } else {
            flash(.upToDate(version: current.description))
        }
    }

    // MARK: Throttling

    private var isDue: Bool {
        guard let last = defaults.object(forKey: Key.lastCheck) as? Double else { return true }
        let succeeded = defaults.bool(forKey: Key.lastCheckSucceeded)
        let interval = succeeded ? configuration.interval : configuration.retryInterval
        return now().timeIntervalSince1970 - last >= interval
    }

    private func recordAttempt(succeeded: Bool) {
        defaults.set(now().timeIntervalSince1970, forKey: Key.lastCheck)
        defaults.set(succeeded, forKey: Key.lastCheckSucceeded)
    }

    // MARK: One-shot feedback

    private func flash(_ value: UpdateStatus) {
        status = value
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.flashDuration * 1_000_000_000))
            guard !Task.isCancelled, let self, self.status == value else { return }
            self.status = .idle
        }
    }

    // MARK: Default network implementation

    nonisolated private static func fetchLatestRelease() async throws -> (Data, URLResponse) {
        var request = URLRequest(url: Configuration.default.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub requires a User-Agent, otherwise straight 403
        request.setValue("Openly/\(Configuration.default.currentVersion)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    nonisolated private static func bundleVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}

// MARK: - Network payload

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    var asset: UpdateAsset? {
        UpdateAsset.dmg(
            named: (assets ?? []).compactMap { piece in
                guard let url = piece.downloadURL, let name = piece.name, !name.isEmpty else { return nil }
                return (name, url, piece.size ?? -1)
            },
            version: AppVersion(tagName)?.description
        )
    }

    private var assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    private struct GitHubAsset: Decodable {
        // Missing asset fields are not an error: GitHub sometimes attaches
        // non-dmg files, we just skip them
        let name: String?
        let size: Int?
        let downloadURL: URL?

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case downloadURL = "browser_download_url"
        }
    }
}

private enum UpdateError: Error {
    case badResponse
}

// MARK: - Status copy

extension UpdateStatus {
    /// The sentence the settings page shows. Silent when idle — no news is
    /// good news.
    var summary: String? {
        switch self {
        case .idle: return nil
        case .checking: return t("Checking…")
        case .upToDate(let version): return t("v{} is up to date", version)
        case .available(let version, _, _): return t("v{} available", version)
        case .failed: return t("Last check failed")
        }
    }
}
