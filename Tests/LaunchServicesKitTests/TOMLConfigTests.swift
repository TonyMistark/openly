import XCTest
@testable import LaunchServicesKit

final class TOMLConfigTests: XCTestCase {

    func testRoundTrip() throws {
        let original = TOMLConfig.Config(
            extensions: ["md": "Typora", "json": "VS Code", "yml": "VS Code"],
            types: ["plain-text": "TextEdit"],
            schemes: ["mailto": "Mail", "http": "Safari"]
        )
        let text = TOMLConfig.encode(original)
        let decoded = try TOMLConfig.decode(text)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeInfatStyleConfig() throws {
        // infat README 中的配置样式（含注释）
        let toml = """
        # my associations
        [extensions]
        md = "TextEdit"     # markdown
        json = "VS Code"

        [types]
        plain-text = "TextEdit"

        [schemes]
        mailto = "Mail"
        """
        let config = try TOMLConfig.decode(toml)
        XCTAssertEqual(config.extensions, ["md": "TextEdit", "json": "VS Code"])
        XCTAssertEqual(config.types, ["plain-text": "TextEdit"])
        XCTAssertEqual(config.schemes, ["mailto": "Mail"])
    }

    func testEmptySectionsSkipped() {
        let text = TOMLConfig.encode(TOMLConfig.Config(extensions: ["txt": "TextEdit"]))
        XCTAssertFalse(text.contains("[types]"))
        XCTAssertFalse(text.contains("[schemes]"))
        XCTAssertTrue(text.contains("[extensions]"))
    }

    func testValueEscapingRoundTrip() throws {
        // 含引号和反斜杠的路径值
        let original = TOMLConfig.Config(extensions: [
            "dmg": "/Applications/My \"Tools\"/App.app",
            "iso": "/Volumes/backup\\disk/App.app",
        ])
        let decoded = try TOMLConfig.decode(TOMLConfig.encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testDecodeErrors() {
        XCTAssertThrowsError(try TOMLConfig.decode("md = \"Typora\""))  // 表头前出现条目
        XCTAssertThrowsError(try TOMLConfig.decode("[unknown]\nmd = \"X\""))  // 不支持的表
        XCTAssertThrowsError(try TOMLConfig.decode("[extensions]\nmd"))  // 缺 =
        XCTAssertThrowsError(try TOMLConfig.decode("[extensions]\nmd = X"))  // 值非字符串
    }

    func testDecodeEmptyString() throws {
        let config = try TOMLConfig.decode("")
        XCTAssertTrue(config.isEmpty)
    }
}
