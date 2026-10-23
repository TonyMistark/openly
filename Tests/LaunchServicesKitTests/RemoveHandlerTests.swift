import XCTest
@testable import LaunchServicesKit

/// 恢复系统默认的核心纯函数：LSHandlers 记录匹配与摘除。
/// 不碰真实偏好域——CFPreferences 那半段没有可注入的测试通道，
/// 真伪由「写回后 CFPreferencesAppSynchronize」保证。
final class RemoveHandlerTests: XCTestCase {

    private func extRecord(_ ext: String, bundleID: String) -> [String: Any] {
        [
            "LSHandlerContentTag": ext,
            "LSHandlerContentTagClass": "public.filename-extension",
            "LSHandlerRoleAll": bundleID,
        ]
    }

    private func utiRecord(_ uti: String, bundleID: String) -> [String: Any] {
        ["LSHandlerContentType": uti, "LSHandlerRoleAll": bundleID]
    }

    private func schemeRecord(_ scheme: String, bundleID: String) -> [String: Any] {
        ["LSHandlerURLScheme": scheme, "LSHandlerRoleAll": bundleID]
    }

    // MARK: recordMatches

    func testMatchesExtensionTagCaseInsensitive() {
        XCTAssertTrue(LSKDatabase.recordMatches(
            extRecord("MD", bundleID: "com.example.a"),
            kind: .fileExtension("md"), resolvedUTI: nil))
    }

    func testMatchesResolvedUTIContentType() {
        // 系统可能把 .md 解析成 UTI 落盘而不是记扩展名 tag
        XCTAssertTrue(LSKDatabase.recordMatches(
            utiRecord("net.daringfireball.markdown", bundleID: "com.example.a"),
            kind: .fileExtension("md"), resolvedUTI: "net.daringfireball.markdown"))
    }

    func testExtensionDoesNotMatchOtherTag() {
        XCTAssertFalse(LSKDatabase.recordMatches(
            extRecord("markdown", bundleID: "com.example.a"),
            kind: .fileExtension("md"), resolvedUTI: nil))
    }

    func testSchemeMatchesCaseInsensitive() {
        XCTAssertTrue(LSKDatabase.recordMatches(
            schemeRecord("MAILTO", bundleID: "com.example.mail"),
            kind: .urlScheme("mailto"), resolvedUTI: nil))
    }

    func testSuperTypeMatchesUTIString() {
        XCTAssertTrue(LSKDatabase.recordMatches(
            utiRecord("public.plain-text", bundleID: "com.example.b"),
            kind: .superType(.plainText), resolvedUTI: nil))
    }

    func testUTIKindMatchesExactContentType() {
        XCTAssertTrue(LSKDatabase.recordMatches(
            utiRecord("com.adobe.pdf", bundleID: "com.example.c"),
            kind: .uti("com.adobe.pdf"), resolvedUTI: nil))
        XCTAssertFalse(LSKDatabase.recordMatches(
            utiRecord("com.adobe.pdf", bundleID: "com.example.c"),
            kind: .uti("public.data"), resolvedUTI: nil))
    }

    // MARK: filteredHandlers

    func testFilterRemovesOnlyMatchingRecords() {
        let handlers = [
            extRecord("md", bundleID: "com.example.a"),
            extRecord("pdf", bundleID: "com.example.b"),
            schemeRecord("mailto", bundleID: "com.example.mail"),
        ]
        let kept = LSKDatabase.filteredHandlers(
            handlers, removing: .fileExtension("md"), resolvedUTI: nil)
        XCTAssertEqual(kept.count, 2)
        XCTAssertFalse(kept.contains { ($0["LSHandlerContentTag"] as? String) == "md" })
    }

    func testFilterRemovesBothTagAndUTIForms() {
        let handlers = [
            extRecord("yml", bundleID: "com.example.a"),
            utiRecord("org.yaml.yaml", bundleID: "com.example.b"),
            extRecord("yaml", bundleID: "com.example.c"),
        ]
        let kept = LSKDatabase.filteredHandlers(
            handlers, removing: .fileExtension("yml"), resolvedUTI: "org.yaml.yaml")
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?["LSHandlerContentTag"] as? String, "yaml")
    }

    func testFilterKeepsEverythingWhenNothingMatches() {
        let handlers = [extRecord("pdf", bundleID: "com.example.b")]
        let kept = LSKDatabase.filteredHandlers(
            handlers, removing: .fileExtension("md"), resolvedUTI: nil)
        XCTAssertEqual(kept.count, 1)
    }
}
