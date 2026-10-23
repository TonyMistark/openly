import XCTest
@testable import LaunchServicesKit

/// 只读查询测试 — 不包含 set 操作（会真实修改系统默认应用，由 lsk CLI 手动验收）
final class AssociationQueryTests: XCTestCase {

    func testUTIDerivationForCommonExtensions() throws {
        XCTAssertEqual(try LSKAssociation.uti(forExtension: "txt"), "public.plain-text")
        XCTAssertEqual(try LSKAssociation.uti(forExtension: "md"), "net.daringfireball.markdown")
        XCTAssertEqual(try LSKAssociation.uti(forExtension: "png"), "public.png")
        XCTAssertEqual(try LSKAssociation.uti(forExtension: "zip"), "public.zip-archive")
    }

    func testUTIDerivationSupertypeShortcircuit() throws {
        // infat 行为：SuperType 能解析的扩展名直接用其 UTI，不走 UTType 推导
        XCTAssertEqual(try LSKAssociation.uti(forExtension: "html"), "public.html")
    }

    func testUnknownExtensionYieldsDynamicUTI() throws {
        // 与 infat 实际行为一致：未知扩展名由系统生成 dyn.* 动态 UTI，而非报错
        let uti = try LSKAssociation.uti(forExtension: "zzqqxx")
        XCTAssertTrue(uti.hasPrefix("dyn."), "expected dynamic UTI, got \(uti)")
    }

    func testInfoForExtensionShape() throws {
        let info = try LSKAssociation.info(forExtension: "txt")
        XCTAssertEqual(info.identifier, ".txt")
        XCTAssertEqual(info.uti, "public.plain-text")
        // 默认应用机器相关：只约束结构，不断言具体值
        XCTAssertTrue(info.defaultAppBundleID == nil || !info.defaultAppBundleID!.isEmpty)
    }

    func testInfoForURLSchemeShape() throws {
        let info = try LSKAssociation.info(forURLScheme: "http")
        XCTAssertEqual(info.identifier, "http:")
        XCTAssertNil(info.uti)
        // 绝大多数 macOS 都注册了 http handler
        XCTAssertNotNil(info.defaultAppBundleID)
        XCTAssertFalse(info.allAppBundleIDs.isEmpty)
    }

    func testInfoForType() throws {
        let info = try LSKAssociation.info(forType: "plain-text")
        XCTAssertEqual(info.uti, "public.plain-text")
    }

    func testAppResolverSystemApps() throws {
        // 系统自带应用必然存在，作为解析器的冒烟测试
        XCTAssertEqual(try LSKAppResolver.bundleID(forApp: "Finder"), "com.apple.finder")
        XCTAssertNotNil(LSKAppResolver.appURL(forApp: "Finder"))
        XCTAssertNotNil(LSKAppResolver.appURL(forBundleID: "com.apple.finder"))
        XCTAssertEqual(LSKAppResolver.appRef(forBundleID: "com.apple.finder").bundleID, "com.apple.finder")
    }

    func testAppResolverPathForms() throws {
        // 绝对路径（带 .app 后缀）
        XCTAssertNotNil(LSKAppResolver.appURL(forApp: "/System/Library/CoreServices/Finder.app"))
        // 不存在的绝对路径
        XCTAssertNil(LSKAppResolver.appURL(forApp: "/Applications/Definitely Not An App.app"))
        // 默认位置中不存在的名称
        XCTAssertNil(LSKAppResolver.appURL(forApp: "Definitely Not An App 12345"))
        XCTAssertThrowsError(try LSKAppResolver.bundleID(forApp: "Definitely Not An App 12345"))
    }
}
