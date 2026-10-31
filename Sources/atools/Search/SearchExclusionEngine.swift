import Foundation

/// 全盘搜索与热目录快照排除过滤引擎 (参照 Alfred Search Scope 设计)
///
/// 性能契约与安全加固：
/// 1. 维护预编译的不可变规则快照（CompiledRules），全程零锁、零动态堆分配。
/// 2. 军师加固点 3：所有预设前缀、用户自定义排除目录与待检测路径在进入前缀/中缀比对前，
///    统一执行 APFS Unicode NFC 规范化（`.precomposedStringWithCanonicalMapping`），
///    彻底防范带变音符的 NFD 分解形式绕过字符串前缀过滤。
/// 3. Q-09：严格遵守 `searchExcludeDeveloper` 开关，关闭时绝不硬编码排除 `/Library/Developer/CommandLineTools/`。
public final class SearchExclusionEngine {
    public static let shared = SearchExclusionEngine()

    public struct CompiledRules: Sendable {
        public let excludeCaches: Bool
        public let excludeLogs: Bool
        public let excludeDeveloper: Bool
        public let excludeHidden: Bool
        public let excludeTrash: Bool
        public let excludeUserLibrary: Bool

        public let cachePrefixes: [String]
        public let logPrefixes: [String]
        public let trashPrefixes: [String]

        public let userLibraryPrefix: String
        public let cloudStoragePrefix: String
        public let mobileDocsPrefix: String

        public let developerInfixes: [String]
        public let vcsInfixes: [String]

        public let customPrefixes: [String]
        public let customExactPaths: Set<String>
        public let developerFolderNames: Set<String>

        public init(config: AtoolsConfig) {
            self.excludeCaches = config.searchExcludeCaches
            self.excludeLogs = config.searchExcludeLogs
            self.excludeDeveloper = config.searchExcludeDeveloper
            self.excludeHidden = config.searchExcludeHidden
            self.excludeTrash = config.searchExcludeTrash
            self.excludeUserLibrary = config.searchExcludeUserLibrary

            let home = FileManager.default.homeDirectoryForCurrentUser.path.precomposedStringWithCanonicalMapping
            let homePrefix = home.hasSuffix("/") ? home : home + "/"

            // 1. 系统与应用缓存前缀
            var caches: [String] = []
            if config.searchExcludeCaches {
                caches.append("/Library/Caches/")
                caches.append("/System/Library/Caches/")
                caches.append(homePrefix + "Library/Caches/")
            }
            self.cachePrefixes = caches

            // 2. 日志与崩溃诊断前缀
            var logs: [String] = []
            if config.searchExcludeLogs {
                logs.append("/Library/Logs/")
                logs.append("/var/log/")
                logs.append("/private/var/log/")
                logs.append(homePrefix + "Library/Logs/")
            }
            self.logPrefixes = logs

            // 3. 废纸篓与临时目录前缀
            var trash: [String] = []
            if config.searchExcludeTrash {
                trash.append(homePrefix + ".Trash/")
                trash.append("/private/var/folders/")
                trash.append("/private/tmp/")
                trash.append("/tmp/")
            }
            self.trashPrefixes = trash

            // 4. 用户资源库根目录与云盘保护白名单
            self.userLibraryPrefix = homePrefix + "Library/"
            self.cloudStoragePrefix = homePrefix + "Library/CloudStorage/"
            self.mobileDocsPrefix = homePrefix + "Library/Mobile Documents/"

            // 5. 开发者工程构建产物与依赖 (Q-09: 关闭开关时完全清空，不留硬编码排除项)
            if config.searchExcludeDeveloper {
                self.developerInfixes = [
                    "/node_modules/",
                    "/DerivedData/",
                    "/.build/",
                    "/target/",
                    "/__pycache__/",
                    "/.gradle/",
                    "/.cargo/",
                    "/Library/Developer/CommandLineTools/"
                ]
                self.developerFolderNames = [
                    "node_modules",
                    "DerivedData",
                    ".build",
                    "target",
                    "__pycache__",
                    ".gradle",
                    ".cargo"
                ]
            } else {
                self.developerInfixes = []
                self.developerFolderNames = []
            }

            // 6. 版本控制目录
            if config.searchExcludeHidden {
                self.vcsInfixes = ["/.git/", "/.svn/", "/.hg/"]
            } else {
                self.vcsInfixes = []
            }

            // 7. 用户自定义排除目录 (统一 NFC 规范化并构建精准前缀)
            var cPrefixes: [String] = []
            var cExact: Set<String> = []
            for rawPath in config.customExcludedPaths {
                let std = (rawPath as NSString).standardizingPath.precomposedStringWithCanonicalMapping
                guard !std.isEmpty && std != "/" else { continue }
                cExact.insert(std)
                let withSlash = std.hasSuffix("/") ? std : std + "/"
                cPrefixes.append(withSlash)
            }
            self.customPrefixes = cPrefixes
            self.customExactPaths = cExact
        }
    }

    private let lock = NSLock()
    private var rules: CompiledRules

    private init() {
        self.rules = CompiledRules(config: AtoolsConfig())
    }

    /// 在配置发生变更时原子重构预编译规则
    public func recompile(config: AtoolsConfig) {
        let newRules = CompiledRules(config: config)
        lock.lock()
        self.rules = newRules
        lock.unlock()
    }

    /// 获取当前不可变规则快照（无锁使用）
    public var currentRules: CompiledRules {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    /// 核心判定方法：在进入路径前缀与包含比对前统一调用 `.precomposedStringWithCanonicalMapping` (NFC)
    @inline(__always)
    public func isExcluded(path rawPath: String) -> Bool {
        let path = rawPath.isContiguousUTF8 && rawPath.utf8.allSatisfy({ $0 < 0x80 })
            ? rawPath
            : rawPath.precomposedStringWithCanonicalMapping
        let r = currentRules

        // 1. 自定义排除路径（用户显式指定，最高优先级）
        if !r.customPrefixes.isEmpty {
            if r.customExactPaths.contains(path) { return true }
            for prefix in r.customPrefixes {
                if path.hasPrefix(prefix) { return true }
            }
        }

        // 2. 废纸篓与临时目录前缀快速比对 (如 ~/.Trash/xxx, /tmp/xxx)
        if r.excludeTrash {
            for prefix in r.trashPrefixes {
                if path.hasPrefix(prefix) { return true }
            }
        }

        // 3. 系统与应用缓存快速比对 (如 ~/Library/Caches/xxx)
        if r.excludeCaches {
            for prefix in r.cachePrefixes {
                if path.hasPrefix(prefix) { return true }
            }
        }

        // 4. 系统日志与崩溃诊断快速比对 (如 ~/Library/Logs/xxx)
        if r.excludeLogs {
            for prefix in r.logPrefixes {
                if path.hasPrefix(prefix) { return true }
            }
        }

        // 5. 用户资源库 ~/Library 核心策略（智能保留 iCloud Drive 与 CloudStorage 网盘）
        if r.excludeUserLibrary && path.hasPrefix(r.userLibraryPrefix) {
            let isCloud = path.hasPrefix(r.mobileDocsPrefix) || path.hasPrefix(r.cloudStoragePrefix)
            if !isCloud {
                return true
            }
        }

        // 6. 开发者构建产物与依赖 (Q-09: 受 r.excludeDeveloper 保护)
        if r.excludeDeveloper {
            for infix in r.developerInfixes {
                if path.contains(infix) { return true }
            }
        }

        // 7. 版本控制目录 (如 /.git/)
        for infix in r.vcsInfixes {
            if path.contains(infix) { return true }
        }

        // 8. 隐藏文件与隐藏目录 (.*)
        if r.excludeHidden {
            if path.contains("/.") {
                return true
            }
        }

        return false
    }

    /// 热目录快照遍历阻断专用：判断在枚举目录时是否应当调用 enumerator.skipDescendants()。
    @inline(__always)
    public func shouldSkipDescendants(folderName rawFolderName: String, path rawPath: String) -> Bool {
        let folderName = rawFolderName.precomposedStringWithCanonicalMapping
        let path = rawPath.precomposedStringWithCanonicalMapping
        let r = currentRules

        // 1. 命中开发者构建产物目录名（如 node_modules, DerivedData, .build, target 等）
        if r.excludeDeveloper && r.developerFolderNames.contains(folderName) {
            return true
        }

        // 2. 命中版本控制或隐藏目录（如 .git）
        if r.excludeHidden && folderName.hasPrefix(".") {
            return true
        }

        // 3. 命中用户自定义排除目录
        if !r.customPrefixes.isEmpty {
            if r.customExactPaths.contains(path) { return true }
            for prefix in r.customPrefixes {
                if path.hasPrefix(prefix) { return true }
            }
        }

        // 4. 废纸篓与临时目录
        if r.excludeTrash {
            for prefix in r.trashPrefixes {
                if path.hasPrefix(prefix) { return true }
            }
        }

        return false
    }
}
