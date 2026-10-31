import Foundation

public enum LauncherItemType: String, Codable, Equatable, Sendable {
    case application
    case fileOrFolder
    case webURL
    case shellScript
    case appleScript
    case systemAction
}

public enum TerminalMode: String, Codable, Equatable, Sendable {
    case integratedBackground
    case launchTerminal
    case openWith
}

public struct ExecutionContext: Codable, Equatable, Sendable {
    public var arguments: [String]
    public var workingDirectory: String?
    public var environmentVars: [String: String]
    public var runAsAdmin: Bool
    public var terminalMode: TerminalMode

    public init(
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environmentVars: [String: String] = [:],
        runAsAdmin: Bool = false,
        terminalMode: TerminalMode = .integratedBackground
    ) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentVars = environmentVars
        self.runAsAdmin = runAsAdmin
        self.terminalMode = terminalMode
    }

    public var isEmpty: Bool {
        let wdEmpty = (workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return arguments.isEmpty && wdEmpty && environmentVars.isEmpty && !runAsAdmin && terminalMode == .integratedBackground
    }

    /// 将参数数组格式化为人类可读的命令行字符串（含空格的参数自动加双引号）
    public var formattedArgumentsString: String {
        return arguments.map { arg in
            if arg.contains(" ") || arg.contains("\"") {
                let escaped = arg.replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            return arg
        }.joined(separator: " ")
    }

    /// 解析命令行参数字符串（支持空格分隔、单双引号包裹及反斜杠转义）
    public static func parseArguments(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for ch in trimmed {
            if isEscaping {
                current.append(ch)
                isEscaping = false
                continue
            }
            if ch == "\\" && !inSingleQuote {
                isEscaping = true
                continue
            }
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if ch.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

public struct LauncherItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var parentId: UUID?
    public var name: String
    public var itemType: LauncherItemType
    public var target: String
    public var bundleIdentifier: String?
    public var executionContext: ExecutionContext?
    public var customIconPath: String?
    public var hotkey: String?
    public var tags: [String]
    public var sortWeight: Int
    public var isVirtualGroup: Bool
    public var launchCount: Int
    public var lastLaunchedAt: Double?
    public var addedAt: Double?

    public init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        name: String,
        itemType: LauncherItemType,
        target: String,
        bundleIdentifier: String? = nil,
        executionContext: ExecutionContext? = nil,
        customIconPath: String? = nil,
        hotkey: String? = nil,
        tags: [String] = [],
        sortWeight: Int = 0,
        isVirtualGroup: Bool = false,
        launchCount: Int = 0,
        lastLaunchedAt: Double? = nil,
        addedAt: Double? = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.itemType = itemType
        self.target = target
        if let explicitBid = bundleIdentifier, !explicitBid.isEmpty {
            self.bundleIdentifier = explicitBid
        } else if itemType == .application && target.lowercased().hasSuffix(".app") {
            self.bundleIdentifier = Bundle(path: target)?.bundleIdentifier
        } else {
            self.bundleIdentifier = nil
        }
        self.executionContext = executionContext
        self.customIconPath = customIconPath
        self.hotkey = hotkey
        self.tags = tags
        self.sortWeight = sortWeight
        self.isVirtualGroup = isVirtualGroup
        self.launchCount = launchCount
        self.lastLaunchedAt = lastLaunchedAt
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, parentId, name, itemType, target, bundleIdentifier, executionContext, customIconPath, hotkey, tags, sortWeight, isVirtualGroup
        case launchCount, lastLaunchedAt, addedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.parentId = try? container.decode(UUID.self, forKey: .parentId)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.itemType = (try? container.decode(LauncherItemType.self, forKey: .itemType)) ?? .application
        self.target = (try? container.decode(String.self, forKey: .target)) ?? ""
        if let decodedBid = try? container.decode(String.self, forKey: .bundleIdentifier), !decodedBid.isEmpty {
            self.bundleIdentifier = decodedBid
        } else if self.itemType == .application && self.target.lowercased().hasSuffix(".app") {
            self.bundleIdentifier = Bundle(path: self.target)?.bundleIdentifier
        } else {
            self.bundleIdentifier = nil
        }
        self.executionContext = try? container.decode(ExecutionContext.self, forKey: .executionContext)
        self.customIconPath = try? container.decode(String.self, forKey: .customIconPath)
        self.hotkey = try? container.decode(String.self, forKey: .hotkey)
        self.tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        self.sortWeight = (try? container.decode(Int.self, forKey: .sortWeight)) ?? 0
        self.isVirtualGroup = (try? container.decode(Bool.self, forKey: .isVirtualGroup)) ?? false
        self.launchCount = (try? container.decode(Int.self, forKey: .launchCount)) ?? 0
        self.lastLaunchedAt = try? container.decode(Double.self, forKey: .lastLaunchedAt)
        self.addedAt = try? container.decode(Double.self, forKey: .addedAt)
    }

    /// S-04：判断 shellScript 的 target 是否为磁盘路径（支持含空格的脚本文件路径）
    public static func isLikelyFileSystemScriptPath(_ rawTarget: String) -> Bool {
        let trimmed = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        if FileManager.default.fileExists(atPath: trimmed) {
            return true
        }
        let shellOperators = CharacterSet(charactersIn: "|&;$><`!(){}[]*?")
        if trimmed.rangeOfCharacter(from: shellOperators) != nil {
            return false
        }
        if !trimmed.contains(" ") {
            return true
        }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        let scriptExtensions: Set<String> = ["sh", "zsh", "bash", "command", "py", "rb", "pl", "js", "swift"]
        return scriptExtensions.contains(ext)
    }

    /// 检测目标路径是否已失效（对标 GlassDesk IsTargetMissing）
    public func checkTargetMissing() -> Bool {
        if isVirtualGroup { return false }
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        switch itemType {
        case .application, .fileOrFolder:
            return !FileManager.default.fileExists(atPath: trimmed)
        case .shellScript:
            if Self.isLikelyFileSystemScriptPath(trimmed) {
                return !FileManager.default.fileExists(atPath: trimmed)
            }
            return false
        case .webURL, .appleScript, .systemAction:
            return false
        }
    }

    /// 解析以逗号、中文逗号、分号或空格分隔的搜索别名标签字符串
    public static func parseTags(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，;； \n\t")
        let parts = raw.components(separatedBy: separators)
        var cleaned: [String] = []
        var seen = Set<String>()
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if seen.insert(lower).inserted {
                cleaned.append(trimmed)
            }
        }
        return cleaned
    }

    /// 格式化别名标签用于输入框展示
    public var formattedTagsString: String {
        return tags.joined(separator: ", ")
    }

    /// 拼音与首字母转换（用于抽屉内过滤及全局别名检索）
    public static func pinyinAndAbbr(for text: String) -> (full: String, abbr: String) {
        let mutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        let spaced = mutableString as String
        let words = spaced.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        var abbr = ""
        for w in words where !w.isEmpty {
            if let first = w.first {
                abbr.append(first)
            }
        }
        let full = spaced.replacingOccurrences(of: " ", with: "")
        return (full.lowercased(), abbr.lowercased())
    }

    /// 判断当前启动项是否匹配过滤词（支持名称、路径、tags 别名以及中文拼音/首字母）
    public func matchesFilter(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }

        if name.lowercased().contains(q) || target.lowercased().contains(q) {
            return true
        }
        for tag in tags where tag.lowercased().contains(q) {
            return true
        }

        let (namePy, nameAbbr) = Self.pinyinAndAbbr(for: name)
        if namePy.contains(q) || nameAbbr.contains(q) {
            return true
        }

        for tag in tags {
            let (tagPy, tagAbbr) = Self.pinyinAndAbbr(for: tag)
            if tagPy.contains(q) || tagAbbr.contains(q) {
                return true
            }
        }
        return false
    }

    /// 计算全盘搜索中对启动项自定义名称与搜索别名标签（tags）的匹配分值
    public func searchMatchScore(for query: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        let candidates = [name] + tags
        var bestScore: Int?

        for candidate in candidates {
            let lower = candidate.lowercased()
            if lower == q {
                return 860
            } else if lower.hasPrefix(q) {
                bestScore = max(bestScore ?? 0, 800)
            } else if lower.contains(q) {
                bestScore = max(bestScore ?? 0, 730)
            } else {
                let (py, abbr) = Self.pinyinAndAbbr(for: candidate)
                if py == q || abbr == q {
                    bestScore = max(bestScore ?? 0, 790)
                } else if py.hasPrefix(q) || abbr.hasPrefix(q) {
                    bestScore = max(bestScore ?? 0, 760)
                }
            }
        }
        return bestScore
    }
}

/// Stable identity used to prevent dragging the same file or application into a category twice.
/// File system paths are standardized, symlinks are resolved, and Unicode NFC normalization
/// (.precomposedStringWithCanonicalMapping) is applied so APFS NFD/NFC variants never create duplicates.
public struct LauncherItemIdentity: Hashable, Sendable {
    public let itemType: LauncherItemType
    public let canonicalTarget: String

    public init(itemType: LauncherItemType, target: String) {
        self.itemType = itemType
        if itemType == .application || itemType == .fileOrFolder {
            self.canonicalTarget = URL(fileURLWithPath: target)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
                .precomposedStringWithCanonicalMapping
        } else {
            self.canonicalTarget = target.precomposedStringWithCanonicalMapping
        }
    }
}

public extension LauncherItem {
    var identity: LauncherItemIdentity {
        LauncherItemIdentity(itemType: itemType, target: target)
    }

    /// 解析该项存储的全局单项快捷键绑定
    var parsedHotkeyBinding: HotkeyBinding? {
        guard let raw = hotkey, !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            return binding
        }
        return nil
    }

    mutating func setHotkeyBinding(_ binding: HotkeyBinding?) {
        if let b = binding, !b.isUnassigned {
            if let data = try? JSONEncoder().encode(b),
               let str = String(data: data, encoding: .utf8) {
                self.hotkey = str
            } else {
                self.hotkey = b.displayString
            }
        } else {
            self.hotkey = nil
        }
    }

    /// 人类可读的单项快捷键显示文本
    var hotkeyDisplayString: String {
        if let b = parsedHotkeyBinding {
            return b.displayString
        }
        return hotkey ?? ""
    }
}

public struct Category: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var iconSymbol: String
    public var sortWeight: Int
    public var items: [LauncherItem]

    public init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String = "folder",
        sortWeight: Int = 0,
        items: [LauncherItem] = []
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.sortWeight = sortWeight
        self.items = items
    }
}

extension Category {
    public static let favoritesName = "常用"
    public static let favoritesIcon = "star.fill"

    /// The auto-generated favourites category. Requires *both* name and icon: user categories
    /// are created with "folder.fill" and renaming never changes the icon, so a user category
    /// that happens to be called "常用" is never mistaken for it (and silently deleted).
    public var isFavorites: Bool {
        return name == Category.favoritesName && iconSymbol == Category.favoritesIcon
    }
}
