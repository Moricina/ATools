import Foundation

/// 🌟 分类名称安全净化与规范化引擎 (Category Name Security Sanitizer) 🌟
/// 负责全面防御控制字符注入、ANSI 逃逸、Unicode BiDi 视觉伪装、Zalgo 渲染瘫痪、路径穿越及超长文本 DoS。
/// 同时严格保障合法多语言文字（中文、英文、日韩等）与复合 Emoji（如 👨‍💻、🏳️‍🌈、🛠️）的 100% 完整性。
public enum CategorySanitizer {
    /// 分类名称最大可视字符长度（按人类字形簇 Grapheme Cluster 计数）
    public static let maxNameLength: Int = 32

    /// 前置防护粗剪裁长度（杜绝超长剪贴板内容引发的内存放大 DoS）
    private static let preSanitizeBudget: Int = 128

    /// 危险的 BiDi 显式重写与隔离字符集 (禁止视觉倒置欺骗)
    private static let dangerousBiDiScalars: Set<UInt32> = [
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // LRE, RLE, PDF, LRO, RLO
        0x2066, 0x2067, 0x2068, 0x2069          // LRI, RLI, FSI, PDI
    ]

    /// 纯粹的零宽隐形与伪造空白字符集 (严格排除 Emoji 必需的 ZWJ 0x200D)
    private static let invisibleScalars: Set<UInt32> = [
        0x200B, // Zero-Width Space
        0xFEFF, // Byte Order Mark / ZWNBSP
        0x00AD  // Soft Hyphen
    ]

    /// 对输入字符串执行工业级清洗与规范化
    /// - Parameter raw: 用户原始输入
    /// - Returns: 清洗后的安全名称；若无有效内容则返回 nil
    public static func sanitize(_ raw: String) -> String? {
        // 0. 防 DoS 前置防护：仅截取前 128 个字符进入管线，杜绝内存放大
        let fastTrimmed = raw.prefix(preSanitizeBudget)

        // 1. 去除首尾空白与换行
        var text = fastTrimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 2. Unicode 标准化 (NFC 预组合规范化，消除畸形分解字符堆叠)
        text = text.precomposedStringWithCanonicalMapping

        // 3. 路径敏感字符过滤：剔除正反斜杠与冒号
        text = text.filter { $0 != "/" && $0 != "\\" && $0 != ":" }

        // 4. 单趟安全扫描 (单次 O(N) 遍历过滤控制字符、危险 BiDi、隐形字符与过量 Zalgo)
        var cleanedScalars = String.UnicodeScalarView()
        var consecutiveCombiningCount = 0

        for scalar in text.unicodeScalars {
            let val = scalar.value

            // 🌟 严格保护复合 Emoji 必需的 ZWJ (0x200D)，防止被 Foundation 的 controlCharacters 误杀
            if val == 0x200D {
                consecutiveCombiningCount = 0
                cleanedScalars.append(scalar)
                continue
            }

            // 拦截 0x00...0x1F, 0x7F...0x9F 控制字符及换行
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                continue
            }

            // 拦截危险 BiDi 重写欺骗
            if dangerousBiDiScalars.contains(val) {
                continue
            }

            // 拦截纯隐形与伪造空白字符
            if invisibleScalars.contains(val) {
                continue
            }

            // 防 Zalgo 攻击：限制连续组合重叠标记不超过 3 个 (U+0300...U+036F 等)
            if CharacterSet.nonBaseCharacters.contains(scalar) {
                consecutiveCombiningCount += 1
                if consecutiveCombiningCount > 3 { continue }
            } else {
                consecutiveCombiningCount = 0
            }

            cleanedScalars.append(scalar)
        }

        var result = String(cleanedScalars)

        // 5. 路径防穿越：彻底拦截纯 "." 或 ".."
        let nonDotContent = result.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespaces))
        guard !nonDotContent.isEmpty else { return nil }

        // 6. 终极安全截断：基于 Swift 字形簇 (Extended Grapheme Cluster)
        // 天然保障 Emoji (如 👨‍💻)、带重音符字符 (如 é) 的 100% 完整性，永不切断代理对！
        if result.count > maxNameLength {
            result = String(result.prefix(maxNameLength))
        }

        let final = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return final.isEmpty ? nil : final
    }
}
