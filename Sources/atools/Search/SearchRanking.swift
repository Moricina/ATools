import Foundation

/// 文件结果的统一排序（热目录与全盘共用同一套打分，归并后全局降序）。
///
/// 设计要点（方案 A）：
/// - **匹配质量档位间隔 400 > 新鲜度上限 300**：保证"很新的弱匹配"永远不会
///   压过"较旧的精确匹配"，档位内再由新鲜度决定先后。
/// - **新鲜度用连续指数衰减**（最近打开半衰期 7 天 + 最近修改半衰期 14 天），
///   没有"第 N 天突然掉分"的断崖。
/// - 深度惩罚封顶 100，不会逆转档位。
enum SearchRanking {
    // 匹配质量档位（间隔 400）
    static let tierExact = 1600      // 文件名完全相等
    static let tierPrefix = 1200     // 文件名前缀
    static let tierContains = 800    // 文件名包含（含变音符差异的实际命中）
    static let tierPinyinFull = 600  // 拼音全拼（相等/前缀/包含）
    static let tierPinyinAbbr = 400  // 拼音首字母（前缀/包含）

    // 新鲜度上限（合计 300，小于档位间隔 400）
    private static let freshnessLastUsedMax = 180.0   // 最近打开，半衰期 7 天
    private static let freshnessModifiedMax = 120.0   // 最近修改，半衰期 14 天

    // MARK: - 匹配档位

    /// 文件名匹配档位；与查询无文件名级匹配时返回 nil（调用方决定兜底档）。
    /// 比较选项对齐 Spotlight 谓词的 `[cd]`：忽略大小写与变音符。
    static func nameTier(name: String, query: String) -> Int? {
        let opts: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let nsName = name as NSString
        let hit = nsName.range(of: query, options: opts)
        guard hit.location != NSNotFound else { return nil }
        if hit.location == 0 && hit.length == nsName.length { return tierExact }
        if hit.location == 0 { return tierPrefix }
        return tierContains
    }

    /// 拼音匹配档位（仅热目录快照可用；全盘索引里没有拼音）。
    /// 返回 0 = 未命中。查询至少 2 字符，避免单字母打爆首字母表。
    static func pinyinTier(pinyinFull: String, pinyinAbbr: String, query: String) -> Int {
        guard query.count >= 2 else { return 0 }
        let q = query.lowercased().replacingOccurrences(of: " ", with: "")
        guard !q.isEmpty else { return 0 }
        if pinyinFull.hasPrefix(q) || pinyinFull.contains(q) { return tierPinyinFull }
        if pinyinAbbr.hasPrefix(q) || pinyinAbbr.contains(q) { return tierPinyinAbbr }
        return 0
    }

    // MARK: - 新鲜度与深度

    /// 连续衰减的新鲜度分（0~300）：最近打开 + 最近修改。
    static func freshnessScore(modified: Date?, lastUsed: Date?, now: Date = Date()) -> Int {
        var score = 0.0
        if let lastUsed {
            let days = max(0, now.timeIntervalSince(lastUsed) / 86_400)
            score += freshnessLastUsedMax * pow(0.5, days / 7.0)
        }
        if let modified {
            let days = max(0, now.timeIntervalSince(modified) / 86_400)
            score += freshnessModifiedMax * pow(0.5, days / 14.0)
        }
        return Int(score.rounded())
    }

    /// 深度惩罚（0~-100）：家目录根为 0，每深一层 -10。
    static func depthPenalty(path: String) -> Int {
        let components = (path as NSString).pathComponents.count
        return min(100, max(0, components - 4) * 10)
    }

    // MARK: - 最终分

    static func finalScore(baseTier: Int, path: String, modified: Date?, lastUsed: Date?,
                           now: Date = Date()) -> Int {
        baseTier + freshnessScore(modified: modified, lastUsed: lastUsed, now: now) - depthPenalty(path: path)
    }
}
