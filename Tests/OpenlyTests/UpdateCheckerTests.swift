import Foundation
import Testing
@testable import Openly

// MARK: - Version comparison (dual-source groundwork)

@Test func versionComparesNumericallyNotLexically() throws {
    let ten = try #require(AppVersion("0.10.0"))
    let nine = try #require(AppVersion("0.9.9"))
    #expect(ten > nine)
    #expect(nine < ten)
}

/// Regression guard: comparing versions of different segment counts must
/// pad the shorter one with zeros, never index past its end.
@Test func differentSegmentCountsCompareWithoutCrashing() throws {
    let short = try #require(AppVersion("0.4"))
    let long = try #require(AppVersion("0.4.0"))
    #expect(short == long)
    let smaller = try #require(AppVersion("0.4"))
    let bigger = try #require(AppVersion("0.4.1"))
    #expect(smaller < bigger)
}

@Test func malformedVersionsAreRejected() {
    #expect(AppVersion("") == nil)
    #expect(AppVersion("v") == nil)
    #expect(AppVersion("nightly") == nil)
    #expect(AppVersion("1.x.0") == nil)
    #expect(AppVersion("0.4.0-") == nil)
}

// MARK: - Test doubles

/// Deliberately not `@MainActor`: the injected fetch closure is not isolated,
/// and a plain type keeps the stand-in simplest. Replies are keyed by the
/// mirror's configured name — in a dual-source check GitHub and Gitee each
/// get their own answer.
private final class UpdateStub {
    var calls = 0
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    var replies: [String: Result<(Data, URLResponse), Error>] = [:]

    func reply(
        _ source: String = "GitHub", tag: String, draft: Bool = false, prerelease: Bool = false,
        assetName: String? = nil, assetSize: Int? = nil, status: Int = 200
    ) throws {
        var body: [String: Any] = ["tag_name": tag]
        if let url = URL(string: "https://example.invalid/\(source.lowercased())/releases/tag/\(tag)") {
            body["html_url"] = url.absoluteString
        }
        body["draft"] = draft
        body["prerelease"] = prerelease
        if let assetName {
            body["assets"] = [[
                "name": assetName,
                "size": assetSize ?? 0,
                "browser_download_url": "https://example.invalid/\(source.lowercased())/dl/\(assetName)",
            ]]
        }
        try setReply(source, json: body, status: status)
    }

    /// Mimics Gitee's JSON: no `html_url`, no `draft`/`prerelease` fields.
    func replyGiteeLike(tag: String, assetName: String? = nil) throws {
        var body: [String: Any] = ["tag_name": tag]
        if let assetName {
            body["assets"] = [[
                "name": assetName,
                "size": 3_100_000,
                "browser_download_url": "https://example.invalid/gitee/dl/\(assetName)",
            ]]
        }
        try setReply("Gitee", json: body, status: 200)
    }

    private func setReply(_ source: String, json: [String: Any], status: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.invalid/latest")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )
        )
        replies[source] = .success((data, response))
    }

    func replyRaw(_ text: String, status: Int = 200) throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.invalid/latest")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )
        )
        replies["GitHub"] = .success((Data(text.utf8), response))
    }

    /// Default for every unconfigured mirror: connection failure.
    var defaultFailure: Result<(Data, URLResponse), Error> = .failure(URLError(.notConnectedToInternet))

    func answer(_ source: UpdateChecker.Configuration.Source) throws -> (Data, URLResponse) {
        calls += 1
        return try (replies[source.name] ?? defaultFailure).get()
    }
}

@MainActor
private final class UpdateHarness {
    let suite: String
    let defaults: UserDefaults
    let stub = UpdateStub()
    let currentVersion: String

    init(currentVersion: String = "0.2.0") throws {
        self.currentVersion = currentVersion
        suite = "openly.tests.updates.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    func checker(sources: [UpdateChecker.Configuration.Source]? = nil) -> UpdateChecker {
        let stub = stub
        return UpdateChecker(
            configuration: UpdateChecker.Configuration(
                currentVersion: currentVersion,
                sources: sources ?? [UpdateChecker.Configuration.Source(
                    name: "GitHub",
                    endpoint: URL(string: "https://example.invalid/latest")!
                )],
                interval: 24 * 3600,
                retryInterval: 3600
            ),
            defaults: defaults,
            now: { stub.now },
            fetch: { source in try stub.answer(source) }
        )
    }

    /// GitHub primary + Gitee backup, endpoints isomorphic to the real
    /// default configuration (but on the test-double domain).
    func dualChecker() -> UpdateChecker {
        checker(sources: [
            UpdateChecker.Configuration.Source(
                name: "GitHub",
                endpoint: URL(string: "https://example.invalid/github/latest")!,
                pageTemplate: "https://example.invalid/github/releases/tag/{}"
            ),
            UpdateChecker.Configuration.Source(
                name: "Gitee",
                endpoint: URL(string: "https://example.invalid/gitee/latest")!,
                pageTemplate: "https://example.invalid/gitee/releases/tag/{}"
            ),
        ])
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
    }
}

// MARK: - Single-source basics

@Test @MainActor func newerReleaseIsOffered() async throws {
    let harness = try UpdateHarness(currentVersion: "0.2.0")
    defer { harness.cleanup() }
    try harness.stub.reply(tag: "v0.3.0")

    let checker = harness.checker()
    await checker.check(force: true)

    let expectedURL = try #require(URL(string: "https://example.invalid/github/releases/tag/v0.3.0"))
    #expect(checker.status == .available(version: "0.3.0", sources: [
        UpdateSource(name: "GitHub", asset: nil, releaseURL: expectedURL),
    ]))
    #expect(harness.stub.calls == 1)
}

@Test @MainActor func sameVersionReportsUpToDate() async throws {
    let harness = try UpdateHarness(currentVersion: "0.3.0")
    defer { harness.cleanup() }
    try harness.stub.reply(tag: "v0.3.0")

    let checker = harness.checker()
    await checker.check(force: true)

    #expect(checker.status == .upToDate(version: "0.3.0"))
}

@Test @MainActor func prereleaseIsIgnored() async throws {
    let harness = try UpdateHarness(currentVersion: "0.2.0")
    defer { harness.cleanup() }
    try harness.stub.reply(tag: "v0.5.0-beta.1", prerelease: true)

    let checker = harness.checker()
    await checker.check(force: true)

    #expect(checker.status == .upToDate(version: "0.2.0"))
}

@Test @MainActor func networkFailureIsSilent() async throws {
    let harness = try UpdateHarness()
    defer { harness.cleanup() }

    let checker = harness.checker()
    await checker.check(force: true)

    #expect(checker.status == .failed)
}

// MARK: - Dual source

/// GitHub primary + Gitee backup: check concurrently, the higher version
/// wins, one mirror failing falls back to the other. These rules are pinned
/// here so dual-source never quietly becomes "whoever answers fastest wins".
@Suite("Dual-source update checks")
struct UpdateDualSourceTests {

    @Test @MainActor func bothSourcesAtSameVersionOfferBothForDownload() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.reply("GitHub", tag: "v0.3.0", assetName: "Openly-0.3.0.dmg", assetSize: 1_900_000)
        try harness.stub.reply("Gitee", tag: "v0.3.0", assetName: "Openly-0.3.0.dmg", assetSize: 1_900_000)

        let checker = harness.dualChecker()
        await checker.check(force: true)

        guard case .available(let version, let sources) = checker.status else {
            Issue.record("expected available, got \(checker.status)")
            return
        }
        #expect(version == "0.3.0")
        // Configuration order, not TaskGroup completion order
        #expect(sources.map(\.name) == ["GitHub", "Gitee"])
        #expect(sources.allSatisfy { $0.asset?.name == "Openly-0.3.0.dmg" })
    }

    @Test @MainActor func higherVersionWinsEvenIfItComesFromTheBackup() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.reply("GitHub", tag: "v0.3.0")
        try harness.stub.reply("Gitee", tag: "v0.4.0")

        let checker = harness.dualChecker()
        await checker.check(force: true)

        guard case .available(let version, let sources) = checker.status else {
            Issue.record("expected available, got \(checker.status)")
            return
        }
        // Mirrors out of sync (primary behind): listen to the higher one,
        // and only carry the mirrors reporting that version
        #expect(version == "0.4.0")
        #expect(sources.map(\.name) == ["Gitee"])
    }

    @Test @MainActor func failingBackupDoesNotBreakThePrimary() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.reply("GitHub", tag: "v0.3.0")
        // Gitee has no reply configured = connection failure

        let checker = harness.dualChecker()
        await checker.check(force: true)

        let expectedURL = try #require(URL(string: "https://example.invalid/github/releases/tag/v0.3.0"))
        #expect(checker.status == .available(version: "0.3.0", sources: [
            UpdateSource(name: "GitHub", asset: nil, releaseURL: expectedURL),
        ]))
    }

    @Test @MainActor func failingPrimaryFallsBackToTheBackup() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.reply("Gitee", tag: "v0.3.0")

        let checker = harness.dualChecker()
        await checker.check(force: true)

        guard case .available(let version, let sources) = checker.status else {
            Issue.record("expected available, got \(checker.status)")
            return
        }
        #expect(version == "0.3.0")
        #expect(sources.map(\.name) == ["Gitee"])
    }

    @Test @MainActor func allSourcesFailingIsAFailure() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }

        let checker = harness.dualChecker()
        await checker.check(force: true)

        #expect(checker.status == .failed)
    }

    /// Gitee's JSON carries no `html_url` / `draft` / `prerelease`: the page
    /// is assembled from the mirror's template, absent flags read as false.
    @Test @MainActor func giteePayloadWithoutHTMLURLStillGetsAPageFromTheTemplate() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.replyGiteeLike(tag: "v0.3.0")

        let checker = harness.dualChecker()
        await checker.check(force: true)

        let expectedPage = try #require(URL(string: "https://example.invalid/gitee/releases/tag/v0.3.0"))
        #expect(checker.status == .available(version: "0.3.0", sources: [
            UpdateSource(name: "Gitee", asset: nil, releaseURL: expectedPage),
        ]))
    }

    /// Gitee payload with an attached dmg: the asset is picked up and the
    /// release page still comes from the template.
    @Test @MainActor func giteePayloadWithDMGIsInstallable() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.replyGiteeLike(tag: "v0.3.0", assetName: "Openly-0.3.0.dmg")

        let checker = harness.dualChecker()
        await checker.check(force: true)

        guard case .available(_, let sources) = checker.status else {
            Issue.record("expected available, got \(checker.status)")
            return
        }
        #expect(sources.count == 1)
        #expect(sources.first?.name == "Gitee")
        #expect(sources.first?.asset?.url.absoluteString == "https://example.invalid/gitee/dl/Openly-0.3.0.dmg")
    }

    @Test @MainActor func malformedPayloadOnOneMirrorDoesNotMaskTheOther() async throws {
        let harness = try UpdateHarness(currentVersion: "0.2.0")
        defer { harness.cleanup() }
        try harness.stub.replyRaw("not json at all")
        try harness.stub.reply("Gitee", tag: "v0.3.0")

        let checker = harness.dualChecker()
        await checker.check(force: true)

        #expect(checker.status == .available(version: "0.3.0", sources: [
            UpdateSource(name: "Gitee", asset: nil,
                         releaseURL: try #require(URL(string: "https://example.invalid/gitee/releases/tag/v0.3.0"))),
        ]))
    }
}

// MARK: - Source picker assembly

@Suite("Download source picker")
struct UpdateSourcePickerTests {

    @Test func entriesPreserveOrderAndInstallability() {
        let dmg = try! #require(UpdateAsset(
            url: URL(string: "https://example.invalid/dl/Openly-0.3.0.dmg")!,
            name: "Openly-0.3.0.dmg", byteCount: 1_900_000))
        let sources = [
            UpdateSource(name: "GitHub", asset: dmg,
                         releaseURL: URL(string: "https://example.invalid/gh")!),
            UpdateSource(name: "Gitee", asset: nil,
                         releaseURL: URL(string: "https://example.invalid/ge")!),
        ]

        let entries = UpdateSource.pickerEntries(sources)
        #expect(entries.count == 2)
        #expect(entries[0].name == "GitHub" && entries[0].canInstall)
        #expect(entries[1].name == "Gitee" && !entries[1].canInstall)
        #expect(entries[1].releaseURL.absoluteString == "https://example.invalid/ge")
    }

    @Test func emptySourceListYieldsNoEntries() {
        #expect(UpdateSource.pickerEntries([]).isEmpty)
    }
}

// MARK: - Lenient decoding

@Suite("RemoteRelease lenient decoding")
struct RemoteReleaseDecodingTests {

    @Test func missingOptionalFieldsDefaultToFalseAndNil() throws {
        let payload = #"{"tag_name": "v0.3.0"}"#
        let release = try #require(try JSONDecoder().decode(RemoteRelease.self, from: Data(payload.utf8)))
        #expect(release.tagName == "v0.3.0")
        #expect(release.htmlURL == nil)
        #expect(!release.draft)
        #expect(!release.prerelease)
        #expect(release.asset == nil)
    }

    @Test func dmgAssetIsPickedFromFullPayload() throws {
        let payload = """
        {"tag_name": "v0.3.0", "html_url": "https://example.invalid/r",
         "draft": false, "prerelease": false,
         "assets": [
            {"name": "checksums.txt", "size": 64, "browser_download_url": "https://example.invalid/c.txt"},
            {"name": "Openly-0.3.0.dmg", "size": 1900000, "browser_download_url": "https://example.invalid/d.dmg"}
         ]}
        """
        let release = try #require(try JSONDecoder().decode(RemoteRelease.self, from: Data(payload.utf8)))
        let asset = try #require(release.asset)
        #expect(asset.name == "Openly-0.3.0.dmg")
        #expect(asset.byteCount == 1_900_000)
    }

    /// Template wins only when the JSON carries no page; GitHub's own
    /// `html_url` must never be overridden.
    @Test func updateSourcePrefersHTMLURLOverTemplate() throws {
        let release = RemoteRelease(
            tagName: "v0.3.0",
            htmlURL: URL(string: "https://example.invalid/own/page")!
        )
        let source = UpdateChecker.Configuration.Source(
            name: "Gitee",
            endpoint: URL(string: "https://example.invalid/api")!,
            pageTemplate: "https://example.invalid/template/{}"
        )
        let assembled = release.updateSource(on: source)
        #expect(assembled.releaseURL.absoluteString == "https://example.invalid/own/page")
        #expect(assembled.name == "Gitee")
    }

    @Test func updateSourceFallsBackToTemplatePage() throws {
        let release = RemoteRelease(tagName: "v0.3.0")
        let source = UpdateChecker.Configuration.Source(
            name: "Gitee",
            endpoint: URL(string: "https://example.invalid/api")!,
            pageTemplate: "https://example.invalid/template/{}"
        )
        let assembled = release.updateSource(on: source)
        #expect(assembled.releaseURL.absoluteString == "https://example.invalid/template/v0.3.0")
    }
}
