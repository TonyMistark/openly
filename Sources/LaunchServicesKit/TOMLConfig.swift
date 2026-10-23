import Foundation

/// infat 兼容的 TOML 配置编解码。
///
/// 目标格式（与 infat `config.toml` 逐字段兼容）：
/// ```toml
/// [extensions]
/// md = "Typora"
///
/// [types]
/// plain-text = "TextEdit"
///
/// [schemes]
/// mailto = "Mail"
/// ```
/// 值为 infat 语义的应用标识：名称 / ~/ 相对路径 / 绝对路径。
/// 只支持这一子集（标量字符串 + 三张表），不实现通用 TOML。
public enum TOMLConfig {

    public struct Config: Equatable, Sendable {
        public var extensions: [String: String]
        public var types: [String: String]
        public var schemes: [String: String]

        public init(extensions: [String: String] = [:], types: [String: String] = [:], schemes: [String: String] = [:]) {
            self.extensions = extensions
            self.types = types
            self.schemes = schemes
        }

        public var isEmpty: Bool { extensions.isEmpty && types.isEmpty && schemes.isEmpty }

        public var total: Int { extensions.count + types.count + schemes.count }
    }

    // MARK: - 编码

    public static func encode(_ config: Config) -> String {
        var lines: [String] = [
            "# Openly 导出 · 兼容 infat CLI",
            "# 应用方法：infat --config <此文件路径>",
            "",
        ]
        if !config.extensions.isEmpty {
            lines.append("[extensions]")
            lines.append(contentsOf: sortedPairs(config.extensions))
            lines.append("")
        }
        if !config.types.isEmpty {
            lines.append("[types]")
            lines.append(contentsOf: sortedPairs(config.types))
            lines.append("")
        }
        if !config.schemes.isEmpty {
            lines.append("[schemes]")
            lines.append(contentsOf: sortedPairs(config.schemes))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func sortedPairs(_ dict: [String: String]) -> [String] {
        dict.keys.sorted().map { key in
            // 转义反斜杠和引号（TOML basic string）
            let escaped = dict[key]!
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\(escapeKey(key)) = \"\(escaped)\""
        }
    }

    private static func escapeKey(_ key: String) -> String {
        // key 均为扩展名/类型名/scheme（bare key 安全字符），保险起见仍校验
        let safe = key.allSatisfy { c in
            c.isLetter || c.isNumber || c == "-" || c == "_" || c == "."
        }
        return safe ? key : "\"\(key)\""
    }

    // MARK: - 解码

    public static func decode(_ string: String) throws -> Config {
        var config = Config()
        var currentTable: String?

        for (lineNumber, rawLine) in string.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("#") { continue }

            // 表头
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                switch name {
                case "extensions", "types", "schemes":
                    currentTable = name
                default:
                    throw TOMLError.unsupportedTable(name, lineNumber: lineNumber + 1)
                }
                continue
            }

            // key = "value"
            guard let current = currentTable else {
                throw TOMLError.entryBeforeTable(lineNumber: lineNumber + 1)
            }
            guard let eqIndex = line.firstIndex(of: "=") else {
                throw TOMLError.invalidLine(line, lineNumber: lineNumber + 1)
            }
            let key = unquoteKey(String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces))
            var value = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
            // 行内注释
            if let commentIndex = findCommentStart(value) {
                value = String(value[..<commentIndex]).trimmingCharacters(in: .whitespaces)
            }
            guard value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 else {
                throw TOMLError.invalidValue(value, lineNumber: lineNumber + 1)
            }
            let unescaped = String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            guard !key.isEmpty, !unescaped.isEmpty else {
                throw TOMLError.invalidLine(line, lineNumber: lineNumber + 1)
            }

            switch current {
            case "extensions": config.extensions[key] = unescaped
            case "types": config.types[key] = unescaped
            case "schemes": config.schemes[key] = unescaped
            default: break
            }
        }
        return config
    }

    private static func unquoteKey(_ key: String) -> String {
        if key.hasPrefix("\"") && key.hasSuffix("\"") && key.count >= 2 {
            return String(key.dropFirst().dropLast())
        }
        return key
    }

    /// 找到不在字符串内的 # 注释起点（简化实现：值以 " 开头时找闭合引号后的 #）
    private static func findCommentStart(_ value: String) -> String.Index? {
        guard value.hasPrefix("\"") else { return value.firstIndex(of: "#") }
        var index = value.index(after: value.startIndex)
        var inEscape = false
        while index < value.endIndex {
            let c = value[index]
            if inEscape { inEscape = false }
            else if c == "\\" { inEscape = true }
            else if c == "\"" {
                let after = value.index(after: index)
                if after < value.endIndex {
                    let rest = value[after...].trimmingCharacters(in: .whitespaces)
                    if rest.hasPrefix("#") { return after }
                }
                return nil
            }
            index = value.index(after: index)
        }
        return nil
    }
}

public enum TOMLError: Error, Equatable {
    case unsupportedTable(String, lineNumber: Int)
    case entryBeforeTable(lineNumber: Int)
    case invalidLine(String, lineNumber: Int)
    case invalidValue(String, lineNumber: Int)
}
