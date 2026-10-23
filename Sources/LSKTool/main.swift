import Foundation
import LaunchServicesKit

/// lsk — LaunchServicesKit 验证工具。
/// 语义与 infat CLI 对齐，用于 M0 验收：`infat info --ext x` 与 `lsk info --ext x` 输出应一致。
//
// 用法：
//   lsk info --ext <ext> | --scheme <scheme> | --type <type>
//   lsk set  <App> --ext <ext> | --scheme <scheme> | --type <type>
//   lsk dump [--ids]        列出 LS 偏好数据库中的全部 handler
//   lsk supertypes          列出全部支持的回退类型
//   lsk app  <名称或bundleID>

struct Options {
    var ext: String?
    var scheme: String?
    var type: String?
    var showBundleIDs = false

    static func parse(_ args: [String]) -> Options? {
        var opts = Options()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--ext": guard i + 1 < args.count else { return nil }; opts.ext = args[i + 1]; i += 2
            case "--scheme": guard i + 1 < args.count else { return nil }; opts.scheme = args[i + 1]; i += 2
            case "--type": guard i + 1 < args.count else { return nil }; opts.type = args[i + 1]; i += 2
            case "--ids": opts.showBundleIDs = true; i += 1
            default: return nil
            }
        }
        let provided = [opts.ext, opts.scheme, opts.type].compactMap { $0 }.count
        guard provided == 1 else { return nil }
        return opts
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("Error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func usage() -> Never {
    print("""
    lsk — Openly LaunchServicesKit 验证工具（语义对齐 infat CLI）

    USAGE:
      lsk info (--ext <ext> | --scheme <scheme> | --type <type>)
      lsk set  <App> (--ext <ext> | --scheme <scheme> | --type <type>)
      lsk dump [--ids]
      lsk supertypes
      lsk app  <App名称 | bundleID>
    """)
    exit(2)
}

func printInfo(_ info: AssociationInfo, names: (String) -> String) {
    print("Identifier:  \(info.identifier)")
    if let uti = info.uti { print("UTI:         \(uti)" ) }
    print("Default app: \(info.defaultAppBundleID.map(names) ?? "None")")
    let apps = info.allAppBundleIDs.map(names)
    print("All apps (\(apps.count)):")
    for name in apps { print("  • \(name)") }
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { usage() }

    switch command {
    case "info":
        guard let opts = Options.parse(Array(args.dropFirst())) else { usage() }
        if let ext = opts.ext {
            printInfo(try LSKAssociation.info(forExtension: ext)) { LSKAppResolver.appRef(forBundleID: $0).name }
        } else if let scheme = opts.scheme {
            printInfo(try LSKAssociation.info(forURLScheme: scheme)) { LSKAppResolver.appRef(forBundleID: $0).name }
        } else if let type = opts.type {
            printInfo(try LSKAssociation.info(forType: type)) { LSKAppResolver.appRef(forBundleID: $0).name }
        }

    case "set":
        guard args.count >= 3 else { usage() }
        let appName = args[1]
        guard let opts = Options.parse(Array(args.dropFirst(2))) else { usage() }
        if let ext = opts.ext {
            try LSKAssociation.setDefaultApp(appName, forExtension: ext)
            print("✓ Set .\(ext) → \(appName)")
        } else if let scheme = opts.scheme {
            try LSKAssociation.setDefaultApp(appName, forURLScheme: scheme)
            print("✓ Set \(scheme) → \(appName)")
        } else if let type = opts.type {
            try LSKAssociation.setDefaultApp(appName, forType: type)
            print("✓ Set type \(type) → \(appName)")
        }

    case "dump":
        let showIDs = args.contains("--ids")
        let handlers = try LSKDatabase.handlers()
        print("Launch Services database: \(LSKDatabase.defaultURL.path)")
        print("Handlers: \(handlers.count)\n")
        for record in handlers {
            let kind = record.associationKind.map { kind -> String in
                switch kind {
                case .fileExtension(let e): return ".\(e)"
                case .superType(let t): return "type:\(t.rawValue)"
                case .urlScheme(let s): return "\(s):"
                case .uti(let u): return "uti:\(u)"
                }
            } ?? "???"
            let handler = record.handlerBundleID ?? "???"
            let handlerLabel = showIDs ? handler : LSKAppResolver.appRef(forBundleID: handler).name
            print("  \(kind.padding(toLength: 32, withPad: " ", startingAt: 0)) → \(handlerLabel)")
        }

    case "supertypes":
        for supertype in SuperType.allCases {
            print("  \(supertype.rawValue.padding(toLength: 32, withPad: " ", startingAt: 0)) \(supertype.utiString)")
        }

    case "app":
        guard args.count == 2 else { usage() }
        let input = args[1]
        if let url = LSKAppResolver.appURL(forApp: input) {
            print("Path:     \(url.path)")
            print("BundleID: \(try LSKAppResolver.bundleID(forApp: input))")
        } else if let url = LSKAppResolver.appURL(forBundleID: input) {
            let ref = LSKAppResolver.appRef(forBundleID: input)
            print("Name:     \(ref.name)")
            print("Path:     \(url.path)")
        } else {
            fail("app not found: \(input)")
        }

    default:
        usage()
    }
}

do {
    try run()
} catch {
    fail("\(error)")
}
