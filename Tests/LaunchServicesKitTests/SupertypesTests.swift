import XCTest
@testable import LaunchServicesKit

/// SuperType 表移植正确性 — 与 infat uti.rs 逐一对照
final class SupertypesTests: XCTestCase {

    func testKnownUTIMappings() {
        // 抽查 infat uti_string() 的关键映射（含特殊值）
        XCTAssertEqual(SuperType.plainText.utiString, "public.plain-text")
        XCTAssertEqual(SuperType.markdown.utiString, "net.daringfireball.markdown")
        XCTAssertEqual(SuperType.html.utiString, "public.html")
        XCTAssertEqual(SuperType.mp4Movie.utiString, "public.mpeg-4")
        XCTAssertEqual(SuperType.quicktimeMovie.utiString, "com.apple.quicktime-movie")
        XCTAssertEqual(SuperType.zip.utiString, "public.zip-archive")
        XCTAssertEqual(SuperType.sourcecode.utiString, "public.source-code")
        XCTAssertEqual(SuperType.typeScript.utiString, "com.microsoft.typescript")
        XCTAssertEqual(SuperType.appBundle.utiString, "com.apple.application-bundle")
        XCTAssertEqual(SuperType.defaultAppWebBrowser.utiString, "com.apple.default-app.web-browser")
        // infat 源码里就是无前缀的原样字符串，保持一致
        XCTAssertEqual(SuperType.mpeg2TransportStream.utiString, "mpeg2-transport-stream")
    }

    func testParseKebabCase() {
        XCTAssertEqual(SuperType.parse("plain-text"), .plainText)
        XCTAssertEqual(SuperType.parse("sourcecode"), .sourcecode)
        XCTAssertEqual(SuperType.parse("app-bundle"), .appBundle)
        XCTAssertEqual(SuperType.parse("x509-certificate"), .x509Certificate)
    }

    func testParseNormalization() {
        // 大小写不敏感 + 下划线归一（对应 Rust 的 to_lowercase + replace('_', "-")）
        XCTAssertEqual(SuperType.parse("Plain-Text"), .plainText)
        XCTAssertEqual(SuperType.parse("plain_text"), .plainText)
    }

    func testParseAliases() {
        XCTAssertEqual(SuperType.parse("md"), .markdown)
        XCTAssertEqual(SuperType.parse("ts"), .typeScript)
        XCTAssertEqual(SuperType.parse("mp4"), .mp4Movie)
        XCTAssertEqual(SuperType.parse("mpeg4-movie"), .mp4Movie)
        XCTAssertEqual(SuperType.parse("m3u"), .m3uPlaylist)
        XCTAssertEqual(SuperType.parse("comma-separated-text"), .csv)
    }

    func testParseUnknownReturnsNil() {
        XCTAssertNil(SuperType.parse("definitely-not-a-type"))
        XCTAssertNil(SuperType.parse(""))
    }

    func testFromUTIString() {
        XCTAssertEqual(SuperType.from(utiString: "public.plain-text"), .plainText)
        XCTAssertEqual(SuperType.from(utiString: "com.adobe.pdf"), nil)
    }

    func testRawValuesAreUnique() {
        let rawValues = SuperType.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "rawValue 冲突会破坏 parse")
        let utis = SuperType.allCases.map(\.utiString)
        XCTAssertEqual(utis.count, Set(utis).count, "utiString 冲突会破坏 from(utiString:)")
        XCTAssertGreaterThanOrEqual(SuperType.allCases.count, 100, "infat 约 110 种，移植不应大量缺失")
    }
}
