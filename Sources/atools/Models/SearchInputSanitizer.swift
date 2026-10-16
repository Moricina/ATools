import Foundation
import AppKit

/// 全局搜索输入安全净化器与防护引擎
///
/// 针对全局搜索全链路提供 5 重防御机制：
/// 1. **DoS 长度熔断**：前置字形簇截断（上限 256 字符），杜绝超长文本引发的 CPU/内存过载与 ReDoS；
/// 2. **ANSI 逃逸序列剥离**：消除 `\u{001B}[...`，防止终端日志查看时发生终端模拟器逃逸注入；
/// 3. **控制字符与空字符清除**：清除 `\0`（防底层 C 字符串截断）及 C0/C1 控制字符；
/// 4. **Unicode 规范化与隐形字符过滤**：消除 BiDi 倒排伪装符与零宽字符，并执行 NFC 预组合规范化；
/// 5. **外链协议白名单校验**：严格限制仅允许 `https://`、`http://`、`dict://` 协议，杜绝本地特权 Scheme 伪装跳转。
public enum SearchInputSanitizer {
    /// 允许的最大搜索字符数（按 Unicode 字形簇计），兼顾深层文件路径（>120 字符）与 DoS 防御
    public static let maxQueryLength: Int = 256

    /// 允许的外链协议白名单集合
    public static let allowedSchemes: Set<String> = ["https", "http", "dict"]

    /// ANSI 逃逸码匹配正则（覆盖 ESC[@-Z\\-_] 与 ESC[...[@-~]）
    private static let ansiRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#, options: [])
    }()

    /// 对搜索输入字符串进行全面的安全净化、截断与规范化
    public static func sanitize(_ input: String) -> String {
        guard !input.isEmpty else { return "" }

        // 1. 铁律第一步：快速字形簇前置截断，彻底阻断后续环节的超大内存与 ReDoS
        let bounded = input.count > maxQueryLength ? String(input.prefix(maxQueryLength)) : input

        // 2. 剥除 ANSI 转义序列，防止终端日志逃逸注入
        var text = bounded
        if let regex = ansiRegex, text.contains("\u{001B}") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }

        // 3. 过滤非法 Unicode、控制字符、BiDi 欺骗符与零宽字符
        var sanitizedScalars = String.UnicodeScalarView()
        sanitizedScalars.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            let val = scalar.value
            // 过滤空字符 \0 (防 C 字符串截断漏洞)
            if val == 0 { continue }

            // 过滤 C0 控制字符 (ASCII 0x00...0x1F, 0x7F)；保留换行与制表符后续折叠
            if (val <= 0x1F || val == 0x7F) && val != 0x09 && val != 0x0A && val != 0x0D {
                continue
            }

            // 过滤 C1 控制字符 (0x80...0x9F)
            if val >= 0x80 && val <= 0x9F {
                continue
            }

            // 过滤 BiDi 伪装覆写字符 (U+202A...U+202E, U+2066...U+2069, U+200E, U+200F)
            if (val >= 0x202A && val <= 0x202E) || (val >= 0x2066 && val <= 0x2069) || val == 0x200E || val == 0x200F {
                continue
            }

            // 过滤不可见的零宽字符 (U+200B...U+200D, U+FEFF 字节顺序标记 BOM)
            if (val >= 0x200B && val <= 0x200D) || val == 0xFEFF {
                continue
            }

            sanitizedScalars.append(scalar)
        }

        let filtered = String(sanitizedScalars)

        // 4. 将换行与制表符折叠为单空格，并压缩连续冗余空白
        let collapsed = filtered
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        // 5. Unicode NFC 预组合规范化
        return collapsed.precomposedStringWithCanonicalMapping
    }

    /// 校验 URL Scheme 是否属于受信任的安全协议白名单
    public static func isSafeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    /// 安全打开 URL，自动阻断非白名单协议
    @discardableResult
    public static func openSafeURL(_ url: URL) -> Bool {
        guard isSafeURL(url) else {
            runtimeLog("[Security] Blocked unauthorized URL scheme: \(url.absoluteString)")
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
