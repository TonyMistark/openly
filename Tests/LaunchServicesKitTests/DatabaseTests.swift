import XCTest
@testable import LaunchServicesKit

/// secure plist 解析 — 用 fixture 验证，不依赖、不触碰用户真实数据库
final class DatabaseTests: XCTestCase {

    private func writeFixture(_ handlers: [[String: Any]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lsk-test-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["LSHandlers": handlers], format: .binary, options: 0)
        try data.write(to: url)
        return url
    }

    func testParseExtensionHandler() throws {
        let url = try writeFixture([[
            "LSHandlerContentTag": "md",
            "LSHandlerContentTagClass": "public.filename-extension",
            "LSHandlerRoleAll": "abnerworks.Typora",
        ]])
        let records = try LSKDatabase.handlers(atURL: url)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].associationKind, .fileExtension("md"))
        XCTAssertEqual(records[0].handlerBundleID, "abnerworks.Typora")
    }

    func testParseSchemeHandler() throws {
        let url = try writeFixture([[
            "LSHandlerURLScheme": "mailto",
            "LSHandlerRoleViewer": "com.apple.mail",
        ]])
        let records = try LSKDatabase.handlers(atURL: url)
        XCTAssertEqual(records[0].associationKind, .urlScheme("mailto"))
        XCTAssertEqual(records[0].handlerBundleID, "com.apple.mail")
    }

    func testParseContentTypeHandler() throws {
        // SuperType UTI → superType；带点但非 SuperType → 原生 UTI
        let url = try writeFixture([
            ["LSHandlerContentType": "public.plain-text", "LSHandlerRoleAll": "com.apple.TextEdit"],
            ["LSHandlerContentType": "com.adobe.pdf", "LSHandlerRoleViewer": "com.apple.Preview"],
        ])
        let records = try LSKDatabase.handlers(atURL: url)
        XCTAssertEqual(records[0].associationKind, .superType(.plainText))
        XCTAssertEqual(records[1].associationKind, .uti("com.adobe.pdf"))
    }

    func testRolePriorityAllOverViewer() throws {
        let url = try writeFixture([[
            "LSHandlerContentTag": "txt",
            "LSHandlerContentTagClass": "public.filename-extension",
            "LSHandlerRoleAll": "app.all",
            "LSHandlerRoleViewer": "app.viewer",
            "LSHandlerRoleEditor": "app.editor",
        ]])
        XCTAssertEqual(try LSKDatabase.handlers(atURL: url)[0].handlerBundleID, "app.all")
    }

    func testUnrecognizableRecordIsSkipped() throws {
        let url = try writeFixture([[
            "LSHandlerContentType": "weird-nodot-type",
            "LSHandlerRoleAll": "some.app",
        ]])
        XCTAssertEqual(try LSKDatabase.handlers(atURL: url).count, 0)
    }

    func testDatabaseNotFoundThrows() {
        let missing = URL(fileURLWithPath: "/nonexistent/lsk-\(UUID().uuidString).plist")
        XCTAssertThrowsError(try LSKDatabase.handlers(atURL: missing)) { error in
            guard case LSKError.databaseNotFound = error else {
                return XCTFail("expected databaseNotFound, got \(error)")
            }
        }
    }
}
