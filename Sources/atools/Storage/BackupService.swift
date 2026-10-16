import Foundation
import CryptoKit

public struct BackupManifest: Codable, Equatable {
    public var formatVersion: Int
    public var minCompatibleConfigVersion: Int
    public var maxCompatibleConfigVersion: Int
    public var appVersion: String
    public var createdAt: String
    public var sourceUserHomePath: String
    public var configSHA256: String
    public var categoriesCount: Int
    public var totalItemsCount: Int
    public var customIcons: [String: String]

    public init(
        formatVersion: Int = 1,
        minCompatibleConfigVersion: Int = 1,
        maxCompatibleConfigVersion: Int = 10,
        appVersion: String = "1.3.23",
        createdAt: String,
        sourceUserHomePath: String,
        configSHA256: String,
        categoriesCount: Int,
        totalItemsCount: Int,
        customIcons: [String: String]
    ) {
        self.formatVersion = formatVersion
        self.minCompatibleConfigVersion = minCompatibleConfigVersion
        self.maxCompatibleConfigVersion = maxCompatibleConfigVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.sourceUserHomePath = sourceUserHomePath
        self.configSHA256 = configSHA256
        self.categoriesCount = categoriesCount
        self.totalItemsCount = totalItemsCount
        self.customIcons = customIcons
    }
}

public struct BackupValidationResult {
    public let sourceURL: URL
    public let manifest: BackupManifest?
    public let decodedConfig: AtoolsConfig
    public let healedConfig: AtoolsConfig
    public let iconSourceFiles: [String: URL]
    public let categoriesCount: Int
    public let totalItemsCount: Int
    public let customIconsCount: Int
    public let healedIconPathsCount: Int
    public let healedUserPathsCount: Int
    public let createdAtDisplay: String
}

public enum BackupError: LocalizedError, Equatable {
    case backupPathNotFound(String)
    case missingConfigFile
    case invalidJSONFormat(String)
    case missingRequiredConfigFields
    case incompatibleBackupFormat(found: Int, supported: Int)
    case incompatibleConfigVersion(found: Int, maxSupported: Int)
    case corruptedConfigChecksum(expected: String, actual: String)
    case missingCustomIconFile(String)
    case corruptedCustomIconChecksum(fileName: String)
    case exportFailed(String)
    case snapshotFailed(String)
    case noSnapshotAvailable

    public var errorDescription: String? {
        switch self {
        case .backupPathNotFound(let path):
            return "未找到指定的备份路径：\(path)"
        case .missingConfigFile:
            return "备份归档中缺少核心配置文件 config.json。"
        case .invalidJSONFormat(let detail):
            return "配置文件 JSON 格式已损坏或语法错误：\(detail)"
        case .missingRequiredConfigFields:
            return "配置文件缺少必要的 ATools 核心字段（如 categories 或 version），并非有效的 ATools 配置文件。"
        case .incompatibleBackupFormat(let found, let supported):
            return "备份归档格式版本过高（v\(found)），当前版本最高支持 v\(supported)。"
        case .incompatibleConfigVersion(let found, let maxSupported):
            return "配置文件数据结构版本过高（v\(found)），当前版本最高支持 v\(maxSupported)。"
        case .corruptedConfigChecksum(let expected, let actual):
            return "config.json 完整性校验失败（SHA-256 不匹配，期望 \(expected.prefix(10))...，实际 \(actual.prefix(10))...），文件可能已损坏。"
        case .missingCustomIconFile(let name):
            return "备份包中缺失清单声明的自定义图标文件：\(name)"
        case .corruptedCustomIconChecksum(let name):
            return "自定义图标文件校验失败（SHA-256 不匹配）：\(name)"
        case .exportFailed(let reason):
            return "导出备份失败：\(reason)"
        case .snapshotFailed(let reason):
            return "创建恢复前安全快照失败：\(reason)"
        case .noSnapshotAvailable:
            return "当前尚无可用的恢复前安全快照（pre-restore-*）。"
        }
    }
}

/// 对标 GlassDesk BackupService.cs：
/// 提供配置与自定义图标全量打包导出、恢复前内存干跑预校验、自动安全快照（pre-restore-*）与跨机图标/用户目录路径自愈。
public final class BackupService {
    public static let shared = BackupService()
    public static let currentFormatVersion = 1
    public static let maxSupportedConfigVersion = 10
    public static let maxRetainedSnapshots = 10

    private let fileManager = FileManager.default

    private init() {}

    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeTimestampString(for date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: date)
    }

    private static func makeISO8601String(for date: Date = Date()) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }

    public static func defaultBackupFolderName(for date: Date = Date()) -> String {
        return "ATools-Backup-\(makeTimestampString(for: date)).atoolsbackup"
    }

    // MARK: - 1. 导出全量备份 (config.json + icons/ + manifest.json)

    @discardableResult
    public func exportBackup(to destinationURL: URL, sourceHomeOverride: String? = nil) throws -> BackupManifest {
        ConfigManager.shared.flushPendingSave()
        let config = ConfigManager.shared.config

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

            let iconsDestDir = destinationURL.appendingPathComponent("icons", isDirectory: true)
            try fileManager.createDirectory(at: iconsDestDir, withIntermediateDirectories: true)

            // 1. 收集并拷贝所有自定义图标文件（含 icons/ 托管目录及任何有效的自定义图标路径）
            var customIconHashes: [String: String] = [:]
            let exportedConfig = config

            for catIdx in exportedConfig.categories.indices {
                for itemIdx in exportedConfig.categories[catIdx].items.indices {
                    let item = exportedConfig.categories[catIdx].items[itemIdx]
                    guard let customPath = item.customIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !customPath.isEmpty,
                          fileManager.fileExists(atPath: customPath) else { continue }

                    let srcURL = URL(fileURLWithPath: customPath)
                    let ext = srcURL.pathExtension.isEmpty ? "png" : srcURL.pathExtension
                    let canonicalFileName = "\(item.id.uuidString).\(ext)"
                    let dstURL = iconsDestDir.appendingPathComponent(canonicalFileName)

                    if let iconData = try? Data(contentsOf: srcURL) {
                        try iconData.write(to: dstURL, options: .atomic)
                        customIconHashes[canonicalFileName] = Self.sha256Hex(of: iconData)
                        // 保持配置内的路径结构以便 manifest 记录原机器路径与文件名映射
                    }
                }
            }

            // 同时把 iconsDirectoryURL 中现有的托管图标一并归档（防止遗漏）
            let managedIconsDir = ConfigManager.shared.iconsDirectoryURL
            if let existingFiles = try? fileManager.contentsOfDirectory(at: managedIconsDir, includingPropertiesForKeys: nil) {
                for fileURL in existingFiles where !fileURL.lastPathComponent.hasPrefix(".") {
                    let name = fileURL.lastPathComponent
                    let dstURL = iconsDestDir.appendingPathComponent(name)
                    if !fileManager.fileExists(atPath: dstURL.path),
                       let data = try? Data(contentsOf: fileURL) {
                        try data.write(to: dstURL, options: .atomic)
                        customIconHashes[name] = Self.sha256Hex(of: data)
                    }
                }
            }

            // 2. 序列化 config.json 并计算 SHA-256
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let configData = try encoder.encode(exportedConfig)
            let configFileURL = destinationURL.appendingPathComponent("config.json")
            try configData.write(to: configFileURL, options: .atomic)

            let configSHA = Self.sha256Hex(of: configData)
            let totalItems = exportedConfig.categories.reduce(0) { $0 + $1.items.count }
            let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.23"
            let homePath = sourceHomeOverride ?? NSHomeDirectory()

            // 3. 生成并写入 manifest.json
            let manifest = BackupManifest(
                formatVersion: Self.currentFormatVersion,
                minCompatibleConfigVersion: 1,
                maxCompatibleConfigVersion: Self.maxSupportedConfigVersion,
                appVersion: appVer,
                createdAt: Self.makeISO8601String(),
                sourceUserHomePath: homePath,
                configSHA256: configSHA,
                categoriesCount: exportedConfig.categories.count,
                totalItemsCount: totalItems,
                customIcons: customIconHashes
            )

            let manifestData = try encoder.encode(manifest)
            let manifestURL = destinationURL.appendingPathComponent("manifest.json")
            try manifestData.write(to: manifestURL, options: .atomic)

            return manifest
        } catch let err as BackupError {
            throw err
        } catch {
            throw BackupError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - 2. 恢复前内存干跑预校验 (Dry-Run Pre-Validation)

    public func validateBackup(at sourceURL: URL, currentHomeOverride: String? = nil) -> Result<BackupValidationResult, BackupError> {
        let standardizedURL = sourceURL.standardizedFileURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDir) else {
            return .failure(.backupPathNotFound(standardizedURL.path))
        }

        let configFileURL: URL
        let manifestFileURL: URL?
        let iconsDirURL: URL?

        if isDir.boolValue {
            configFileURL = standardizedURL.appendingPathComponent("config.json")
            let mURL = standardizedURL.appendingPathComponent("manifest.json")
            manifestFileURL = fileManager.fileExists(atPath: mURL.path) ? mURL : nil
            let iURL = standardizedURL.appendingPathComponent("icons", isDirectory: true)
            iconsDirURL = fileManager.fileExists(atPath: iURL.path) ? iURL : nil
        } else {
            configFileURL = standardizedURL
            manifestFileURL = nil
            iconsDirURL = nil
        }

        guard fileManager.fileExists(atPath: configFileURL.path),
              let configData = try? Data(contentsOf: configFileURL),
              !configData.isEmpty else {
            return .failure(.missingConfigFile)
        }

        // 1. 先校验原始 JSON 语法及核心顶层字段，拒绝损坏文件或非 ATools 的无关 JSON
        let rawJSONObject: Any
        do {
            rawJSONObject = try JSONSerialization.jsonObject(with: configData, options: [])
        } catch {
            return .failure(.invalidJSONFormat(error.localizedDescription))
        }

        guard let rootDict = rawJSONObject as? [String: Any] else {
            return .failure(.invalidJSONFormat("根节点不是有效的 JSON 对象"))
        }

        let hasRecognizedKeys = rootDict["categories"] != nil || rootDict["version"] != nil || rootDict["shelfHotkey"] != nil
        guard hasRecognizedKeys else {
            return .failure(.missingRequiredConfigFields)
        }

        if let rawVersion = rootDict["version"] as? Int {
            if rawVersion > Self.maxSupportedConfigVersion || rawVersion < 1 {
                return .failure(.incompatibleConfigVersion(found: rawVersion, maxSupported: Self.maxSupportedConfigVersion))
            }
        }

        // 若存在 categories 字段，校验其必须为合法数组且每个分类包含有效的 name 与 items 数组
        if let rawCategories = rootDict["categories"] {
            guard let catArray = rawCategories as? [[String: Any]] else {
                return .failure(.invalidJSONFormat("categories 字段格式非法（非数组结构）"))
            }
            for (idx, catObj) in catArray.enumerated() {
                guard let name = catObj["name"] as? String, !name.isEmpty,
                      let items = catObj["items"] as? [[String: Any]] else {
                    return .failure(.invalidJSONFormat("第 \(idx + 1) 个分类缺少有效的 name 或 items 字段"))
                }
                for (itemIdx, itemObj) in items.enumerated() {
                    guard let itemName = itemObj["name"] as? String, !itemName.isEmpty,
                          let itemTarget = itemObj["target"] as? String, !itemTarget.isEmpty else {
                        return .failure(.invalidJSONFormat("分类「\(name)」第 \(itemIdx + 1) 个启动项缺少有效的 name 或 target"))
                    }
                }
            }
        }

        // 2. 若包含 manifest.json，校验归档版本、config.json 的 SHA-256 以及自定义图标完整性
        var parsedManifest: BackupManifest?
        var verifiedIcons: [String: URL] = [:]

        if let manifestURL = manifestFileURL {
            guard let manifestData = try? Data(contentsOf: manifestURL) else {
                return .failure(.invalidJSONFormat("无法读取 manifest.json"))
            }
            do {
                let m = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
                if m.formatVersion > Self.currentFormatVersion || m.formatVersion < 1 {
                    return .failure(.incompatibleBackupFormat(found: m.formatVersion, supported: Self.currentFormatVersion))
                }
                let actualConfigSHA = Self.sha256Hex(of: configData)
                if actualConfigSHA.lowercased() != m.configSHA256.lowercased() {
                    return .failure(.corruptedConfigChecksum(expected: m.configSHA256, actual: actualConfigSHA))
                }

                // 校验清单中声明的每个自定义图标是否存在且哈希一致
                for (fileName, expectedSHA) in m.customIcons {
                    guard let iconsDir = iconsDirURL else {
                        return .failure(.missingCustomIconFile(fileName))
                    }
                    let iconURL = iconsDir.appendingPathComponent(fileName)
                    guard fileManager.fileExists(atPath: iconURL.path),
                          let iconData = try? Data(contentsOf: iconURL) else {
                        return .failure(.missingCustomIconFile(fileName))
                    }
                    let actualIconSHA = Self.sha256Hex(of: iconData)
                    if actualIconSHA.lowercased() != expectedSHA.lowercased() {
                        return .failure(.corruptedCustomIconChecksum(fileName: fileName))
                    }
                    verifiedIcons[fileName] = iconURL
                }
                parsedManifest = m
            } catch {
                return .failure(.invalidJSONFormat("manifest.json 解析失败：\(error.localizedDescription)"))
            }
        } else if let iconsDir = iconsDirURL,
                  let files = try? fileManager.contentsOfDirectory(at: iconsDir, includingPropertiesForKeys: nil) {
            for f in files where !f.lastPathComponent.hasPrefix(".") {
                verifiedIcons[f.lastPathComponent] = f
            }
        }

        // 3. 在内存中执行 AtoolsConfig 完整反序列化
        let decodedConfig: AtoolsConfig
        do {
            decodedConfig = try JSONDecoder().decode(AtoolsConfig.self, from: configData)
        } catch {
            return .failure(.invalidJSONFormat(error.localizedDescription))
        }

        if decodedConfig.version > Self.maxSupportedConfigVersion || decodedConfig.version < 1 {
            return .failure(.incompatibleConfigVersion(found: decodedConfig.version, maxSupported: Self.maxSupportedConfigVersion))
        }

        // 4. 在内存中干跑跨机图标路径与家目录路径自愈计算
        let currentHome = currentHomeOverride ?? NSHomeDirectory()
        let currentIconsDir = ConfigManager.shared.iconsDirectoryURL
        let (healedConfig, healedIconsCount, healedPathsCount) = Self.healPaths(
            in: decodedConfig,
            sourceHomePath: parsedManifest?.sourceUserHomePath,
            currentHomePath: currentHome,
            currentIconsDir: currentIconsDir,
            availableBackupIcons: Set(verifiedIcons.keys)
        )

        let totalItems = healedConfig.categories.reduce(0) { $0 + $1.items.count }
        let createdDisplay = parsedManifest?.createdAt ?? "单文件配置导入"

        let result = BackupValidationResult(
            sourceURL: standardizedURL,
            manifest: parsedManifest,
            decodedConfig: decodedConfig,
            healedConfig: healedConfig,
            iconSourceFiles: verifiedIcons,
            categoriesCount: healedConfig.categories.count,
            totalItemsCount: totalItems,
            customIconsCount: verifiedIcons.count,
            healedIconPathsCount: healedIconsCount,
            healedUserPathsCount: healedPathsCount,
            createdAtDisplay: createdDisplay
        )
        return .success(result)
    }

    // MARK: - 3. 跨机图标路径与用户目录自愈算法 (Cross-Machine Path Self-Healing)

    public static func healPaths(
        in config: AtoolsConfig,
        sourceHomePath: String?,
        currentHomePath: String = NSHomeDirectory(),
        currentIconsDir: URL = ConfigManager.shared.iconsDirectoryURL,
        availableBackupIcons: Set<String>
    ) -> (healed: AtoolsConfig, healedIconPathsCount: Int, healedUserPathsCount: Int) {
        var cfg = config
        var healedIcons = 0
        var healedUserPaths = 0

        let normalizedSourceHome = sourceHomePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let sourceHomePrefix = (normalizedSourceHome?.isEmpty == false) ? "/\(normalizedSourceHome!)" : nil
        let targetHomePrefix = currentHomePath.hasSuffix("/")
            ? String(currentHomePath.dropLast())
            : currentHomePath

        // 辅助函数：将跨机家目录路径（如 /Users/olduser/Documents/a.sh）映射为当前机器家目录路径
        func remapUserPathIfNeeded(_ rawPath: String) -> (String, Bool) {
            let candidate = rawPath
            if candidate.hasPrefix("~/") {
                let expanded = targetHomePrefix + String(candidate.dropFirst(1))
                return (expanded, expanded != rawPath)
            }
            if let srcPrefix = sourceHomePrefix, srcPrefix != targetHomePrefix, candidate.hasPrefix(srcPrefix + "/") {
                let suffix = String(candidate.dropFirst(srcPrefix.count))
                let remapped = targetHomePrefix + suffix
                // 当原路径在本机不存在，或原路径属于另一台机器的用户目录时，自愈映射至当前机器的用户目录
                if !FileManager.default.fileExists(atPath: candidate) || FileManager.default.fileExists(atPath: remapped) {
                    return (remapped, true)
                }
            }
            // 兜底识别形如 /Users/<otherUser>/... 的路径
            if candidate.hasPrefix("/Users/") && !candidate.hasPrefix(targetHomePrefix + "/") {
                let comps = candidate.components(separatedBy: "/")
                if comps.count >= 4 {
                    let relativeSuffix = "/" + comps.dropFirst(3).joined(separator: "/")
                    let remapped = targetHomePrefix + relativeSuffix
                    if !FileManager.default.fileExists(atPath: candidate) && FileManager.default.fileExists(atPath: remapped) {
                        return (remapped, true)
                    }
                }
            }
            return (candidate, false)
        }

        for catIdx in cfg.categories.indices {
            for itemIdx in cfg.categories[catIdx].items.indices {
                var item = cfg.categories[catIdx].items[itemIdx]

                // A. 自愈自定义图标路径 (customIconPath)
                if let rawCustom = item.customIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !rawCustom.isEmpty {
                    let fileName = (rawCustom as NSString).lastPathComponent
                    let idFileName = "\(item.id.uuidString).png"
                    let targetManagedPath: String?

                    if availableBackupIcons.contains(fileName) {
                        targetManagedPath = currentIconsDir.appendingPathComponent(fileName).path
                    } else if availableBackupIcons.contains(idFileName) {
                        targetManagedPath = currentIconsDir.appendingPathComponent(idFileName).path
                    } else if rawCustom.contains("/ATools/icons/") || rawCustom.contains("/atools/icons/") {
                        targetManagedPath = currentIconsDir.appendingPathComponent(fileName).path
                    } else {
                        let (remappedCustom, changed) = remapUserPathIfNeeded(rawCustom)
                        targetManagedPath = changed ? remappedCustom : nil
                    }

                    if let newCustomPath = targetManagedPath, newCustomPath != rawCustom {
                        item.customIconPath = newCustomPath
                        healedIcons += 1
                    }
                }

                // B. 自愈启动目标路径 (target)
                let (newTarget, targetChanged) = remapUserPathIfNeeded(item.target)
                if targetChanged {
                    item.target = newTarget
                    healedUserPaths += 1
                }

                // C. 自愈工作目录 (executionContext.workingDirectory)
                if let wd = item.executionContext?.workingDirectory, !wd.isEmpty {
                    let (newWD, wdChanged) = remapUserPathIfNeeded(wd)
                    if wdChanged {
                        item.executionContext?.workingDirectory = newWD
                        healedUserPaths += 1
                    }
                }

                cfg.categories[catIdx].items[itemIdx] = item
            }
        }

        // D. 自愈自定义热目录 (extraHotFolders)
        for i in cfg.extraHotFolders.indices {
            let (newFolder, changed) = remapUserPathIfNeeded(cfg.extraHotFolders[i])
            if changed {
                cfg.extraHotFolders[i] = newFolder
                healedUserPaths += 1
            }
        }

        // E. 自愈自定义排除目录 (customExcludedPaths)
        for i in cfg.customExcludedPaths.indices {
            let (newExcluded, changed) = remapUserPathIfNeeded(cfg.customExcludedPaths[i])
            if changed {
                cfg.customExcludedPaths[i] = newExcluded
                healedUserPaths += 1
            }
        }

        return (cfg, healedIcons, healedUserPaths)
    }

    // MARK: - 4. 自动安全快照 (pre-restore-时间戳) 与一键恢复/回滚

    /// 在执行恢复覆盖前，自动将当前配置与托管图标快照至 backups/pre-restore-时间戳/
    @discardableResult
    public func createPreRestoreSnapshot() throws -> URL {
        let backupsDir = ConfigManager.shared.backupsDirectoryURL
        let folderName = "pre-restore-\(Self.makeTimestampString())-\(UUID().uuidString.prefix(4))"
        let snapshotURL = backupsDir.appendingPathComponent(folderName, isDirectory: true)

        do {
            _ = try exportBackup(to: snapshotURL)
            pruneOldSnapshots()
            return snapshotURL
        } catch {
            throw BackupError.snapshotFailed(error.localizedDescription)
        }
    }

    /// 列出所有可用的恢复前自动快照（按创建时间倒序排列，最新在前）
    public func listPreRestoreSnapshots() -> [URL] {
        let backupsDir = ConfigManager.shared.backupsDirectoryURL
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.lastPathComponent.hasPrefix("pre-restore-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func pruneOldSnapshots() {
        let snapshots = listPreRestoreSnapshots()
        guard snapshots.count > Self.maxRetainedSnapshots else { return }
        for oldURL in snapshots.dropFirst(Self.maxRetainedSnapshots) {
            try? fileManager.removeItem(at: oldURL)
        }
    }

    /// 执行全流程安全恢复：干跑预校验 -> 自动创建 pre-restore 快照 -> 还原图标并自愈路径 -> 热重载生效
    @discardableResult
    public func restoreBackup(
        from sourceURL: URL,
        createSnapshot: Bool = true,
        currentHomeOverride: String? = nil
    ) throws -> (validation: BackupValidationResult, snapshotURL: URL?) {
        // 1. 恢复前干跑预校验
        let validation: BackupValidationResult
        switch validateBackup(at: sourceURL, currentHomeOverride: currentHomeOverride) {
        case .success(let valid):
            validation = valid
        case .failure(let error):
            throw error
        }

        // 2. 自动创建 pre-restore 快照
        var snapshotURL: URL?
        if createSnapshot {
            snapshotURL = try createPreRestoreSnapshot()
        }

        // 3. 拷贝托管自定义图标到当前机器的 icons/ 目录
        let targetIconsDir = ConfigManager.shared.iconsDirectoryURL
        for (fileName, srcFileURL) in validation.iconSourceFiles {
            let dstFileURL = targetIconsDir.appendingPathComponent(fileName)
            if srcFileURL.standardizedFileURL != dstFileURL.standardizedFileURL,
               let data = try? Data(contentsOf: srcFileURL) {
                try? data.write(to: dstFileURL, options: .atomic)
            }
        }

        // 4. 应用自愈后的配置并立即通知各子系统热更新
        ConfigManager.shared.applyRestoredConfig(validation.healedConfig)

        return (validation, snapshotURL)
    }

    /// 一键回滚至最近一次恢复前的安全快照（pre-restore-*）
    @discardableResult
    public func rollbackToLatestSnapshot() throws -> BackupValidationResult {
        guard let latestSnapshot = listPreRestoreSnapshots().first else {
            throw BackupError.noSnapshotAvailable
        }
        let (validation, _) = try restoreBackup(from: latestSnapshot, createSnapshot: false)
        return validation
    }
}
