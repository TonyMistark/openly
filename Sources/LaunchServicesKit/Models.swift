import Foundation

/// 关联的类别 — 对应 infat 的 extensions / types / schemes 三张配置表
public enum AssociationKind: Equatable, Hashable, Sendable {
    case fileExtension(String)
    case superType(SuperType)
    case urlScheme(String)
    /// 不属于任何已知 SuperType 的原生 UTI（如 com.adobe.pdf）
    case uti(String)

    /// 稳定去重键（用于选择集、最近修改记录等）
    public func kindKey() -> String {
        switch self {
        case .fileExtension(let e): return "ext:\(e)"
        case .urlScheme(let s): return "scheme:\(s)"
        case .superType(let t): return "type:\(t.rawValue)"
        case .uti(let u): return "uti:\(u)"
        }
    }
}

/// 某一扩展名 / 类型 / URL scheme 的关联信息（只含 bundle ID，名称由 LSKAppResolver 解析）
public struct AssociationInfo: Equatable, Sendable {
    /// 展示用标识，如 ".txt"、"plain-text"、"mailto:"
    public let identifier: String
    /// 底层 UTI（URL scheme 为 nil）
    public let uti: String?
    /// 默认应用 bundle ID，nil 表示无默认
    public let defaultAppBundleID: String?
    /// 所有注册应用 bundle ID（含默认）
    public let allAppBundleIDs: [String]

    public init(identifier: String, uti: String?, defaultAppBundleID: String?, allAppBundleIDs: [String]) {
        self.identifier = identifier
        self.uti = uti
        self.defaultAppBundleID = defaultAppBundleID
        self.allAppBundleIDs = allAppBundleIDs
    }
}

/// 应用引用 — GUI 渲染所需的最小信息
public struct AppRef: Equatable, Hashable, Sendable {
    public let bundleID: String
    public let name: String
    public let path: String?

    public init(bundleID: String, name: String, path: String?) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}
