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
    /// A new version is out. `sources` lists every mirror reporting this
    /// version (GitHub / Gitee), first one being the default one-click
    /// download; a mirror whose release carries no dmg has `asset == nil`
    /// and the UI falls back to opening its release page.
    case available(version: String, sources: [UpdateSource])
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

/// One place an update can be downloaded from: `name` is for humans
/// (GitHub / Gitee), `asset` feeds the one-click installer and the release
/// page is the exit when installation refuses to work. The same version may
/// exist on several mirrors — which one to use is the user's call.
struct UpdateSource: Equatable {
    let name: String
    let asset: UpdateAsset?
    let releaseURL: URL

    /// Entries for the "switch download source" picker, in the order given
    /// (which the checker already sorted into configuration order). Each
    /// entry says whether direct install is possible or only the release
    /// page can be offered.
    static func pickerEntries(_ sources: [UpdateSource]) -> [(name: String, canInstall: Bool, releaseURL: URL)] {
        sources.map { ($0.name, $0.asset != nil, $0.releaseURL) }
    }
}

// MARK: - Checker

/// Queries every release mirror concurrently, at most once a day; surfaces
/// new versions in Settings and the app menu.
///
/// Mirrors: GitHub is primary, Gitee is the China-friendly backup. Checks
/// run **concurrently** and all results are awaited before comparing —
/// the higher version wins, whatever mirror it came from. One mirror being
/// down falls back to the other; only when every mirror fails does the check
/// itself count as failed.
///
/// Three deliberate restraints:
/// 1. **Throttled** — no re-check within 24 h after success, 1 h after failure;
/// 2. **Silent failure** — a settings/association tool must not nag offline;
/// 3. **Injectable** — network, current version, clock and UserDefaults are
///    all injected; tests never touch the real network.
@MainActor
final class UpdateChecker: ObservableObject {
    typealias Fetch = @Sendable (Configuration.Source) async throws -> (Data, URLResponse)

    struct Configuration {
        struct Source {
            /// Human-facing name: the picker in Settings picks a download
            /// mirror by it.
            let name: String
            /// "latest release" query address (GitHub API and Gitee API v5
            /// share the same JSON shape).
            let endpoint: URL
            /// Fallback template for the release page (`{}` becomes the
            /// tag). Gitee's JSON carries no `html_url`, so its page is
            /// assembled from here; GitHub's own `html_url` wins when present.
            var pageTemplate: String = ""

            /// The release page for a given tag on this mirror.
            func page(forTag tag: String) -> URL? {
                guard !pageTemplate.isEmpty else { return nil }
                return URL(string: pageTemplate.replacingOccurrences(of: "{}", with: tag))
            }
        }

        var currentVersion: String
        /// All mirrors. Checked concurrently; the higher version wins.
        var sources: [Source]
        /// Quiet period after a successful check.
        var interval: TimeInterval
        /// Retry interval after failure (shorter, but long enough to avoid
        /// hammering a wall on every launch).
        var retryInterval: TimeInterval

        static let `default` = Configuration(
            currentVersion: UpdateChecker.bundleVersion(),
            sources: [
                Source(
                    name: "GitHub",
                    endpoint: URL(string: "https://api.github.com/repos/TonyMistark/openly/releases/latest")!
                ),
                Source(
                    name: "Gitee",
                    endpoint: URL(string: "https://gitee.com/api/v5/repos/Micestark/openly/releases/latest")!,
                    pageTemplate: "https://gitee.com/Micestark/openly/releases/tag/{}"
                ),
            ],
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

        // Query all mirrors concurrently: one mirror failing must neither
        // drag down nor mask the other's answer. Only when every mirror
        // fails does the check count as failed; any survivor feeds the
        // "higher version wins" comparison.
        var found: [(source: Configuration.Source, release: RemoteRelease)] = []
        await withTaskGroup(of: (Configuration.Source, Result<RemoteRelease, Error>).self) { group in
            for source in configuration.sources {
                group.addTask { [fetch] in
                    do {
                        let (data, response) = try await fetch(source)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode) else {
                            throw UpdateError.badResponse
                        }
                        return (source, .success(try JSONDecoder().decode(RemoteRelease.self, from: data)))
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }
            for await (source, result) in group {
                if let release = try? result.get() { found.append((source, release)) }
            }
        }

        guard !found.isEmpty else {
            recordAttempt(succeeded: false)
            flash(.failed)
            return
        }
        recordAttempt(succeeded: true)
        evaluate(found)
    }

    // MARK: Evaluation

    /// Position of a mirror in the configuration; unknown mirrors sort last
    /// (cannot happen, kept as a safety net).
    private func index(of source: Configuration.Source) -> Int {
        configuration.sources.firstIndex { $0.endpoint == source.endpoint } ?? .max
    }

    private func evaluate(_ releases: [(source: Configuration.Source, release: RemoteRelease)]) {
        guard let current = AppVersion(configuration.currentVersion) else {
            flash(.failed)
            return
        }

        // Mirrors can drift out of sync (a forgotten Gitee upload, or Gitee
        // briefly ahead): the higher version wins, and every mirror reporting
        // that version is carried so the user can pick a download. The result
        // order follows configuration order — TaskGroup completion order is
        // arbitrary and must never decide which mirror is "primary".
        var bestVersion: AppVersion?
        var sources: [UpdateSource] = []
        for piece in releases.sorted(by: {
            index(of: $0.source) < index(of: $1.source)
        }) {
            guard !piece.release.draft, !piece.release.prerelease,
                  let version = AppVersion(piece.release.tagName) else { continue }
            if let best = bestVersion {
                if version > best {
                    bestVersion = version
                    sources = [piece.release.updateSource(on: piece.source)]
                } else if version == best {
                    sources.append(piece.release.updateSource(on: piece.source))
                }
            } else {
                bestVersion = version
                sources = [piece.release.updateSource(on: piece.source)]
            }
        }
        // Prerelease / unparseable tag: treated as "no stable release",
        // never bother the user with it
        guard let latest = bestVersion else {
            flash(.upToDate(version: configuration.currentVersion))
            return
        }
        if latest > current {
            status = .available(version: latest.description, sources: sources)
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

    nonisolated private static func fetchLatestRelease(from source: Configuration.Source) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: source.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub requires a User-Agent, otherwise straight 403; Gitee is
        // indifferent but a named client never hurts
        request.setValue("Openly/\(Configuration.default.currentVersion)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    nonisolated private static func bundleVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}

// MARK: - Network payload

/// GitHub and Gitee release JSON share a shape but are both incomplete:
/// Gitee omits `html_url`/`draft`/`prerelease`. Absence is always read
/// leniently — a missing field is not bad news.
struct RemoteRelease: Decodable {
    let tagName: String
    let htmlURL: URL?
    let draft: Bool
    let prerelease: Bool
    private let assets: [Asset]?

    init(tagName: String, htmlURL: URL? = nil, draft: Bool = false, prerelease: Bool = false, assets: [Asset]? = nil) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try? container.decode(URL.self, forKey: .htmlURL)
        draft = (try? container.decode(Bool.self, forKey: .draft)) ?? false
        prerelease = (try? container.decode(Bool.self, forKey: .prerelease)) ?? false
        assets = try? container.decode([Asset].self, forKey: .assets)
    }

    /// The download entry for this release on a given mirror.
    func updateSource(on source: UpdateChecker.Configuration.Source) -> UpdateSource {
        UpdateSource(
            name: source.name,
            asset: asset,
            releaseURL: htmlURL ?? source.page(forTag: tagName) ?? htmlFallback
        )
    }

    /// No template configured and no `html_url` either: drop the user at
    /// the repository's releases index, better than nothing.
    private var htmlFallback: URL {
        URL(string: "https://github.com/TonyMistark/openly/releases")!
    }

    var asset: UpdateAsset? {
        UpdateAsset.dmg(
            named: (assets ?? []).compactMap { piece in
                guard let url = piece.downloadURL, let name = piece.name, !name.isEmpty else { return nil }
                return (name, url, piece.size ?? -1)
            },
            version: AppVersion(tagName)?.description
        )
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    struct Asset: Decodable, Equatable {
        // Missing asset fields are not an error: both platforms sometimes
        // attach non-dmg files, we just skip them
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
        case .available(let version, _): return t("v{} available", version)
        case .failed: return t("Last check failed")
        }
    }
}
