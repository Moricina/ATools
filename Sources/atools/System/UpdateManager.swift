import Foundation
import AppKit
import CryptoKit

public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let name: String
    public let body: String
    public let downloadURL: URL
    public let assetName: String
    public let publishedAt: String
    public let signatureURL: URL

    public init(
        version: String,
        name: String,
        body: String,
        downloadURL: URL,
        assetName: String,
        publishedAt: String,
        signatureURL: URL
    ) {
        self.version = version
        self.name = name
        self.body = body
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.publishedAt = publishedAt
        self.signatureURL = signatureURL
    }
}

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(ReleaseInfo)
    case downloading(progress: Double)
    case preparing
    case error(String)
}

public final class UpdateManager: NSObject, URLSessionDownloadDelegate {
    public static let shared = UpdateManager()

    public static let stateDidChangeNotification = Notification.Name("UpdateManagerStateDidChangeNotification")
    private static let expectedBundleIdentifier = "cc.atools.app"
    private static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "releases.githubusercontent.com",
        "codeload.github.com"
    ]

    private let stateLock = NSLock()
    private var _currentState: UpdateState = .idle
    private var _targetRelease: ReleaseInfo?
    /// U-01: 全局唯一代次令牌，防止 cancelUpdate() 与下载完成/解压回调发生竞态重入
    private var _currentSessionToken = UUID()
    private var _activeDownloadToken: UUID?
    private var _activeStagingDirectories: Set<URL> = []

    /// All update state is read and written through one lock. Public mutations are forced onto
    /// the main thread so Settings observes a stable state model even from URLSession callbacks.
    public private(set) var currentState: UpdateState {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _currentState
        }
        set {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in self?.currentState = newValue }
                return
            }
            stateLock.lock()
            _currentState = newValue
            stateLock.unlock()
            NotificationCenter.default.post(
                name: UpdateManager.stateDidChangeNotification,
                object: self
            )
        }
    }

    private var currentDownloadTask: URLSessionDownloadTask?

    /// U-04: 专用后台 Delegate Queue，避免下载完成时在主线程同步拷贝数以百兆的 DMG/ZIP 导致 UI 冻结
    private let downloadDelegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "cc.atools.update.delegate"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 300.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: self, delegateQueue: downloadDelegateQueue)
    }()

    private var targetRelease: ReleaseInfo? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _targetRelease
        }
        set {
            stateLock.lock()
            _targetRelease = newValue
            stateLock.unlock()
        }
    }

    public var currentAppVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private override init() {
        super.init()
    }

    // MARK: - U-06: Strict SemVer 2.0.0 Version Comparison

    private struct SemanticVersion: Comparable {
        let numbers: [Int]
        let prerelease: [String]

        init?(_ raw: String) {
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
            guard !cleaned.isEmpty else { return nil }
            // Strip build metadata (+...)
            let withoutBuild = cleaned.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? cleaned
            let dashParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let corePart = String(dashParts[0])
            let rawNums = corePart.split(separator: ".")
            guard !rawNums.isEmpty else { return nil }
            var parsedNums: [Int] = []
            for token in rawNums {
                guard let n = Int(token), n >= 0 else { return nil }
                parsedNums.append(n)
            }
            self.numbers = parsedNums
            if dashParts.count > 1 && !dashParts[1].isEmpty {
                self.prerelease = dashParts[1].split(separator: ".").map(String.init)
            } else {
                self.prerelease = []
            }
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            let maxCount = max(lhs.numbers.count, rhs.numbers.count)
            for i in 0..<maxCount {
                let l = i < lhs.numbers.count ? lhs.numbers[i] : 0
                let r = i < rhs.numbers.count ? rhs.numbers[i] : 0
                if l != r { return l < r }
            }
            // SemVer 2.0.0: normal version has higher precedence than prerelease version (e.g. 1.0.0 > 1.0.0-beta.1)
            if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
            if lhs.prerelease.isEmpty { return false }
            if rhs.prerelease.isEmpty { return true }

            let preCount = max(lhs.prerelease.count, rhs.prerelease.count)
            for i in 0..<preCount {
                if i >= lhs.prerelease.count { return true }
                if i >= rhs.prerelease.count { return false }
                let idL = lhs.prerelease[i]
                let idR = rhs.prerelease[i]
                if idL == idR { continue }
                let numL = Int(idL)
                let numR = Int(idR)
                if let nl = numL, let nr = numR {
                    return nl < nr
                } else if numL != nil {
                    // Numeric identifiers always have lower precedence than non-numeric identifiers
                    return true
                } else if numR != nil {
                    return false
                } else {
                    return idL < idR
                }
            }
            return false
        }
    }

    /// 比较语义化版本号（支持标准 SemVer 预发布后缀如 -beta.1, -rc.2）：若 v1 大于 v2 则返回 true
    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        if let sem1 = SemanticVersion(v1), let sem2 = SemanticVersion(v2) {
            return sem1 > sem2
        }
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }

    private static let lastSilentCheckKey = "atools.lastSilentUpdateCheckTime"
    private static let silentCheckMinInterval: TimeInterval = 14400 // 4 小时间隔节流

    // MARK: - Check for Updates
    public func checkForUpdates(isUserInitiated: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.checkForUpdates(isUserInitiated: isUserInitiated)
            }
            return
        }

        // 静默检查节流控制：避免频繁呼出设置窗口刷爆 GitHub API 限流
        if !isUserInitiated {
            let lastCheck = UserDefaults.standard.double(forKey: UpdateManager.lastSilentCheckKey)
            if lastCheck > 0 && Date().timeIntervalSince1970 - lastCheck < UpdateManager.silentCheckMinInterval {
                return
            }
        }

        guard currentState != .checking else { return }
        let checkToken = UUID()
        stateLock.lock()
        _currentSessionToken = checkToken
        stateLock.unlock()

        currentState = .checking
        targetRelease = nil

        guard let apiURL = URL(string: "https://api.github.com/repos/Moricina/ATools/releases/latest") else {
            if isUserInitiated {
                currentState = .error("无效的更新检测地址")
            } else {
                currentState = .idle
            }
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("ATools-Updater/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.stateLock.lock()
                let isCurrent = (self._currentSessionToken == checkToken)
                self.stateLock.unlock()
                guard isCurrent else { return }
                self.handleUpdateCheck(data: data, response: response, error: error, isUserInitiated: isUserInitiated)
            }
        }
        task.resume()
    }

    private func handleUpdateCheck(data: Data?, response: URLResponse?, error: Error?, isUserInitiated: Bool) {
        if let error = error {
            if !isUserInitiated {
                runtimeLog("[UpdateManager] Silent update check encountered error: \(error.localizedDescription), resetting to idle.")
                currentState = .idle
                return
            }
            let msg = (error as NSError).code == NSURLErrorNotConnectedToInternet
                ? "未连接互联网，请检查网络设置"
                : "网络请求失败：\(error.localizedDescription)"
            currentState = .error(msg)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            if !isUserInitiated {
                currentState = .idle
                return
            }
            currentState = .error("服务器返回异常响应")
            return
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            if !isUserInitiated {
                runtimeLog("[UpdateManager] Silent update check hit GitHub rate limit (\(httpResponse.statusCode)), silently ignored.")
                currentState = .idle
                return
            }
            currentState = .error("GitHub API 访问达到限流上限，请稍后再试")
            return
        }

        guard httpResponse.statusCode == 200, let data = data else {
            if !isUserInitiated {
                currentState = .idle
                return
            }
            currentState = .error("检测更新失败 (HTTP \(httpResponse.statusCode))")
            return
        }

        // 成功获取远端 release 数据，记录静默检查时间戳
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UpdateManager.lastSilentCheckKey)

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if !isUserInitiated {
                    currentState = .idle
                    return
                }
                currentState = .error("解析版本发布数据失败")
                return
            }

            let releaseName = json["name"] as? String ?? tagName
            let body = json["body"] as? String ?? "暂无更新说明"
            let publishedAt = json["published_at"] as? String ?? ""
            let currentVer = currentAppVersion

            if UpdateManager.isVersion(tagName, greaterThan: currentVer) {
                let assets = json["assets"] as? [[String: Any]] ?? []
                guard let preferredAsset = UpdateManager.preferredReleaseAsset(from: assets) else {
                    if !isUserInitiated {
                        currentState = .idle
                        return
                    }
                    currentState = .error("最新版本未提供 macOS 安装镜像包")
                    return
                }
                guard let signatureURL = UpdateManager.signatureURL(
                    for: preferredAsset.name,
                    from: assets
                ) else {
                    if !isUserInitiated {
                        currentState = .idle
                        return
                    }
                    currentState = .error("最新版本缺少 Ed25519 更新签名，已拒绝不安全的安装包")
                    return
                }

                let release = ReleaseInfo(
                    version: tagName,
                    name: releaseName,
                    body: body,
                    downloadURL: preferredAsset.url,
                    assetName: preferredAsset.name,
                    publishedAt: publishedAt,
                    signatureURL: signatureURL
                )
                targetRelease = release
                currentState = .available(release)
            } else {
                currentState = .upToDate(currentVersion: currentVer)
            }
        } catch {
            if !isUserInitiated {
                currentState = .idle
                return
            }
            currentState = .error("解析版本数据异常：\(error.localizedDescription)")
        }
    }

    // MARK: - Download & Install
    public func startUpdate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startUpdate() }
            return
        }

        guard case .available(let release) = currentState else { return }

        // U-05: 校验下载链接与签名链接必须为安全的 HTTPS 协议且在受信任域名白名单内
        guard Self.isTrustedRemoteAssetURL(release.downloadURL),
              Self.isTrustedRemoteAssetURL(release.signatureURL) else {
            self.currentState = .error("更新包下载源地址不受信任，已拒绝下载")
            return
        }

        // 验证当前路径是否处于 AppTranslocation 或只读挂载卷（含软链接解析与 NFC 规范化）
        let bundlePath = Bundle.main.bundlePath
        if UpdateManager.isBlockedUpdateLocation(bundlePath) {
            self.currentState = .error("当前应用运行在临时隔离区或只读磁盘镜像中，请先将其移动到「应用程序」文件夹后再执行更新")
            return
        }

        // 原地替换需要对父目录有写权限；目录本身不可写并不代表替换不可行
        let resolvedBundlePath = URL(fileURLWithPath: bundlePath).standardizedFileURL.resolvingSymlinksInPath().path
        let parentDirectory = (resolvedBundlePath as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: parentDirectory) {
            self.currentState = .error("对目标应用程序目录缺少写入权限，无法原地自动更新")
            return
        }

        let sessionToken = UUID()
        stateLock.lock()
        _currentSessionToken = sessionToken
        _activeDownloadToken = sessionToken
        _targetRelease = release
        stateLock.unlock()

        self.currentState = .downloading(progress: 0.0)

        let downloadTask = downloadSession.downloadTask(with: release.downloadURL)
        stateLock.lock()
        self.currentDownloadTask = downloadTask
        stateLock.unlock()
        downloadTask.resume()
    }

    /// 重试上次失败的安装包；若失败发生在检查阶段，则重新检查更新。
    public func retry() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.retry() }
            return
        }

        if let release = targetRelease {
            currentState = .available(release)
            startUpdate()
        } else {
            checkForUpdates(isUserInitiated: true)
        }
    }

    public func cancelUpdate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.cancelUpdate() }
            return
        }

        stateLock.lock()
        // U-01: 立即轮换代次令牌并清空活跃下载令牌，任何在途或已排队完成的回调都将被硬性拦截
        _currentSessionToken = UUID()
        _activeDownloadToken = nil
        let taskToCancel = currentDownloadTask
        currentDownloadTask = nil
        let dirsToClean = _activeStagingDirectories
        _activeStagingDirectories.removeAll()
        stateLock.unlock()

        taskToCancel?.cancel()
        currentState = .idle

        if !dirsToClean.isEmpty {
            DispatchQueue.global(qos: .utility).async {
                for dir in dirsToClean {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        }
    }

    /// U-05 & 军师加固点 3：同时解析软链接与执行 APFS Unicode NFC 规范化，防止通过符号链接或 NFD 编码绕过位置限制
    static func isBlockedUpdateLocation(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let standardizedPath = url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
        let resolvedPath = url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping

        for candidate in [standardizedPath, resolvedPath] {
            if candidate.contains("/AppTranslocation/")
                || candidate.hasPrefix("/Volumes/")
                || candidate.hasPrefix("/private/var/folders/") {
                return true
            }
        }
        return false
    }

    static func isTrustedRemoteAssetURL(_ url: URL) -> Bool {
        if url.isFileURL { return true }
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        if allowedDownloadHosts.contains(host) { return true }
        return host.hasSuffix(".githubusercontent.com") || host.hasSuffix(".github.com")
    }

    static func isHTTPSOrFileURL(_ url: URL) -> Bool {
        if url.isFileURL { return true }
        return url.scheme?.lowercased() == "https"
    }

    static func normalizedVersion(_ version: String) -> String {
        return version.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
    }

    static func preferredReleaseAsset(from assets: [[String: Any]]) -> (name: String, url: URL)? {
        for preferredExtension in [".dmg", ".zip"] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      name.lowercased().hasSuffix(preferredExtension),
                      let urlString = asset["browser_download_url"] as? String,
                      let url = URL(string: urlString),
                      isHTTPSOrFileURL(url) else {
                    continue
                }
                return (name: name, url: url)
            }
        }
        return nil
    }

    static func signatureURL(for assetName: String, from assets: [[String: Any]]) -> URL? {
        let signatureName = (assetName + ".sig").lowercased()
        for asset in assets {
            guard let candidateName = asset["name"] as? String,
                  candidateName.lowercased() == signatureName,
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString),
                  isHTTPSOrFileURL(url) else {
                continue
            }
            return url
        }
        return nil
    }

    /// Ed25519 更新签名公钥列表
    /// - 移除了历史已废弃旧公钥（HbGQoLgp...），当前保留活跃主公钥（2026-10-06 启用）
    static let updateSigningPublicKeys: [String] = [
        "V+7AgVQr03TBI8wWe9OUB0wrypIj6CrsfLK8xPuNUxU=",  // 2026-10-06 活跃主公钥
    ]

    /// 计算更新包 Canonical 绑定摘要：绑定版本、文件名与文件 SHA-256，防范重放与降级
    static func canonicalPayload(version: String, assetName: String, fileDigest: Data) -> Data {
        let hexDigest = fileDigest.map { String(format: "%02x", $0) }.joined()
        let canonicalString = "ATools-Update:\(version):\(assetName):\(hexDigest)"
        return Data(SHA256.hash(data: Data(canonicalString.utf8)))
    }

    /// U-05: 受限获取签名文件内容（校验 HTTPS 白名单、10秒超时、16KB 体积上限）
    private static func fetchSignatureData(from signatureURL: URL) throws -> Data {
        let maxSignatureBytes = 16 * 1024
        if signatureURL.isFileURL {
            let data = try Data(contentsOf: signatureURL)
            guard data.count <= maxSignatureBytes else {
                throw NSError(domain: "UpdateManager", code: 8, userInfo: [NSLocalizedDescriptionKey: "更新签名文件体积异常超限"])
            }
            return data
        }

        guard isTrustedRemoteAssetURL(signatureURL) else {
            throw NSError(domain: "UpdateManager", code: 8, userInfo: [NSLocalizedDescriptionKey: "更新签名地址协议或域名不受信任"])
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let semaphore = DispatchSemaphore(value: 0)
        var fetchedData: Data?
        var fetchError: Error?

        let task = session.dataTask(with: signatureURL) { data, response, error in
            defer { semaphore.signal() }
            if let error = error {
                fetchError = error
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                fetchError = NSError(domain: "UpdateManager", code: 8, userInfo: [NSLocalizedDescriptionKey: "获取更新签名失败 (HTTP \(http.statusCode))"])
                return
            }
            fetchedData = data
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 12.0) == .timedOut {
            task.cancel()
            throw NSError(domain: "UpdateManager", code: 8, userInfo: [NSLocalizedDescriptionKey: "下载更新签名文件超时"])
        }
        if let err = fetchError {
            throw err
        }
        guard let validData = fetchedData, !validData.isEmpty, validData.count <= maxSignatureBytes else {
            throw NSError(domain: "UpdateManager", code: 8, userInfo: [NSLocalizedDescriptionKey: "更新签名文件为空或体积异常"])
        }
        return validData
    }

    static func verifyUpdateSignature(
        assetURL: URL,
        signatureURL: URL,
        expectedVersion: String? = nil,
        assetName: String? = nil
    ) throws {
        let signatureData = try fetchSignatureData(from: signatureURL)
        guard let signatureText = String(data: signatureData, encoding: .utf8) else {
            throw NSError(
                domain: "UpdateManager",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "更新签名格式无效，已拒绝安装"]
            )
        }

        guard let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(
                domain: "UpdateManager",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "更新签名格式无效，已拒绝安装"]
            )
        }

        let rawDigest = try UpdateManager.sha256(ofFileAt: assetURL)

        // 构造候选验签摘要（双模自适应兼容：先验 Canonical 结构化绑定摘要，再回退验证原始文件 SHA-256 确保老客户端平滑兼容）
        var candidateDigests: [Data] = []
        if let ver = expectedVersion, !ver.isEmpty, let name = assetName, !name.isEmpty {
            candidateDigests.append(canonicalPayload(version: ver, assetName: name, fileDigest: rawDigest))
        }
        candidateDigests.append(rawDigest)

        // 遍历所有公钥与候选摘要，任一通过即为合法
        for publicKeyBase64 in updateSigningPublicKeys {
            guard let rawPublicKey = Data(base64Encoded: publicKeyBase64),
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey) else {
                continue
            }
            for digest in candidateDigests {
                if publicKey.isValidSignature(signature, for: digest) {
                    return  // 签名校验通过
                }
            }
        }

        throw NSError(
            domain: "UpdateManager",
            code: 8,
            userInfo: [NSLocalizedDescriptionKey: "Ed25519 更新签名校验失败，安装包可能已被篡改"]
        )
    }

    private static func sha256(ofFileAt url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            chunk.withUnsafeBytes { buffer in
                hasher.update(bufferPointer: buffer)
            }
        }
        return Data(hasher.finalize())
    }

    private func isTokenStillActive(_ token: UUID) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentSessionToken == token && _activeDownloadToken == token
    }

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        stateLock.lock()
        let isValidTask = (downloadTask === currentDownloadTask && _activeDownloadToken != nil && _currentSessionToken == _activeDownloadToken)
        stateLock.unlock()
        guard isValidTask else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let stillActive = (self._activeDownloadToken != nil && self._currentSessionToken == self._activeDownloadToken)
            self.stateLock.unlock()
            guard stillActive else { return }
            if case .downloading = self.currentState {
                self.currentState = .downloading(progress: min(1.0, max(0.0, progress)))
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // U-01: 强校验当前任务身份与代次令牌，若用户已点击取消，立即删除临时文件并中止
        stateLock.lock()
        guard downloadTask === currentDownloadTask,
              let activeToken = _activeDownloadToken,
              _currentSessionToken == activeToken else {
            stateLock.unlock()
            try? FileManager.default.removeItem(at: location)
            return
        }
        let releaseSnapshot = _targetRelease
        stateLock.unlock()

        guard let httpResponse = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            stateLock.lock()
            currentDownloadTask = nil
            _activeDownloadToken = nil
            stateLock.unlock()
            try? FileManager.default.removeItem(at: location)
            currentState = .error("下载服务器返回异常，请稍后重试")
            return
        }

        currentState = .preparing

        do {
            // U-04: 此代理方法已在后台专用队列 (downloadDelegateQueue) 运行，优先使用 moveItem O(1) 接管临时文件
            let preparedUpdate = try prepareDownloadedAsset(at: location, release: releaseSnapshot, sessionToken: activeToken)
            let expectedVersion = releaseSnapshot?.version ?? ""
            let signatureURL = releaseSnapshot?.signatureURL
            let assetName = releaseSnapshot?.assetName

            stateLock.lock()
            currentDownloadTask = nil
            stateLock.unlock()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.extractAndRelaunch(
                    preparedUpdate: preparedUpdate,
                    expectedVersion: expectedVersion,
                    signatureURL: signatureURL,
                    assetName: assetName,
                    sessionToken: activeToken
                )
            }
        } catch {
            stateLock.lock()
            currentDownloadTask = nil
            _activeDownloadToken = nil
            stateLock.unlock()
            currentState = .error("保存安装包失败：\(error.localizedDescription)")
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as NSError?, error.code != NSURLErrorCancelled else { return }
        stateLock.lock()
        let isValidTask = (task === currentDownloadTask && _activeDownloadToken != nil)
        if isValidTask {
            currentDownloadTask = nil
            _activeDownloadToken = nil
        }
        stateLock.unlock()
        guard isValidTask else { return }

        DispatchQueue.main.async { [weak self] in
            self?.currentState = .error("下载安装包失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Extraction & Same-Volume Atomic Replacement
    private struct PreparedUpdate {
        let tempDirectory: URL
        let assetURL: URL
        let isDMG: Bool
    }

    private func prepareDownloadedAsset(at location: URL, release: ReleaseInfo?, sessionToken: UUID) throws -> PreparedUpdate {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("atools_update_\(UUID().uuidString)")
        // U-06: 统一使用大小写无关扩展名判断
        let isDMG = (release?.assetName.lowercased().hasSuffix(".dmg")) ?? true
        let localAssetPath = tempDir.appendingPathComponent(isDMG ? "download.dmg" : "download.zip")

        stateLock.lock()
        _activeStagingDirectories.insert(tempDir)
        stateLock.unlock()

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            // 优先使用同卷 O(1) moveItem 接管，若跨卷则回退至 copyItem
            do {
                try FileManager.default.moveItem(at: location, to: localAssetPath)
            } catch {
                try FileManager.default.copyItem(at: location, to: localAssetPath)
            }
            guard isTokenStillActive(sessionToken) else {
                try? FileManager.default.removeItem(at: tempDir)
                throw NSError(domain: "UpdateManager", code: 99, userInfo: [NSLocalizedDescriptionKey: "更新已取消"])
            }
            return PreparedUpdate(tempDirectory: tempDir, assetURL: localAssetPath, isDMG: isDMG)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            stateLock.lock()
            _activeStagingDirectories.remove(tempDir)
            stateLock.unlock()
            throw error
        }
    }

    /// 军师加固点 4：优先在目标 App 所在物理卷（如 `/Applications/.atools_staging_<UUID>`）创建隐藏 Staging 目录，
    /// 确保后续 `mv` 底层调用 `rename(2)` 具备绝对的 APFS 同卷原子性，绝不退化为跨卷非原子拷贝。
    static func createSameVolumeStagingDirectory(forTargetAppPath targetAppBundlePath: String, fallbackTempDir: URL) throws -> URL {
        let resolvedTarget = URL(fileURLWithPath: targetAppBundlePath).standardizedFileURL.resolvingSymlinksInPath()
        let parentDir = resolvedTarget.deletingLastPathComponent()
        let sameVolumeCandidate = parentDir.appendingPathComponent(".atools_staging_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sameVolumeCandidate, withIntermediateDirectories: true)
            return sameVolumeCandidate
        } catch {
            let fallback = fallbackTempDir.appendingPathComponent("staging", isDirectory: true)
            try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }

    private func extractAndRelaunch(
        preparedUpdate: PreparedUpdate,
        expectedVersion: String,
        signatureURL: URL?,
        assetName: String?,
        sessionToken: UUID
    ) {
        let tempDir = preparedUpdate.tempDirectory
        let targetAppBundlePath = URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL.resolvingSymlinksInPath().path
        var stagingDir: URL?
        var shouldCleanupDirectories = true
        defer {
            if shouldCleanupDirectories {
                try? FileManager.default.removeItem(at: tempDir)
                if let sDir = stagingDir {
                    try? FileManager.default.removeItem(at: sDir)
                }
                stateLock.lock()
                _activeStagingDirectories.remove(tempDir)
                if let sDir = stagingDir {
                    _activeStagingDirectories.remove(sDir)
                }
                stateLock.unlock()
            }
        }

        do {
            guard isTokenStillActive(sessionToken) else { return }

            guard let signatureURL = signatureURL else {
                throw NSError(
                    domain: "UpdateManager",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "更新包缺少 Ed25519 分离签名，已拒绝安装"]
                )
            }
            try UpdateManager.verifyUpdateSignature(
                assetURL: preparedUpdate.assetURL,
                signatureURL: signatureURL,
                expectedVersion: expectedVersion,
                assetName: assetName
            )

            guard isTokenStillActive(sessionToken) else { return }

            let createdStagingDir = try Self.createSameVolumeStagingDirectory(
                forTargetAppPath: targetAppBundlePath,
                fallbackTempDir: tempDir
            )
            stagingDir = createdStagingDir
            stateLock.lock()
            _activeStagingDirectories.insert(createdStagingDir)
            stateLock.unlock()

            let stagingAppPath = createdStagingDir.appendingPathComponent("ATools.app").path

            if preparedUpdate.isDMG {
                // 挂载 DMG 提取 ATools.app
                let mountPoint = tempDir.appendingPathComponent("mount").path
                try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

                let attachProcess = Process()
                attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attachProcess.arguments = ["attach", preparedUpdate.assetURL.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint]
                try attachProcess.run()
                attachProcess.waitUntilExit()

                guard attachProcess.terminationStatus == 0 else {
                    throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法挂载更新磁盘镜像"])
                }

                defer {
                    _ = try? self.detachDMG(mountPoint: mountPoint)
                }

                let sourceAppInMount = (mountPoint as NSString).appendingPathComponent("ATools.app")
                if FileManager.default.fileExists(atPath: sourceAppInMount) {
                    try FileManager.default.copyItem(atPath: sourceAppInMount, toPath: stagingAppPath)
                } else {
                    throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "更新镜像中未找到 ATools.app"])
                }
            } else {
                // 解压 ZIP 提取 ATools.app
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProcess.arguments = ["-xk", preparedUpdate.assetURL.path, createdStagingDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: stagingAppPath) else {
                    throw NSError(domain: "UpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "解压更新压缩包失败"])
                }
            }

            guard isTokenStillActive(sessionToken) else { return }

            try validateStagedApp(at: stagingAppPath, expectedVersion: expectedVersion)

            // 二次确认取消状态：一旦越过此边界即启动替换守护进程
            guard isTokenStillActive(sessionToken) else { return }

            // 写入独立的平滑替换守护脚本
            let scriptPath = tempDir.appendingPathComponent("relaunch.sh").path
            let currentPID = ProcessInfo.processInfo.processIdentifier

            try UpdateManager.relaunchScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)

            // 启动守护脚本并退出当前老进程 (使用 nohup 隔离父进程退出信号)
            let runnerProcess = Process()
            runnerProcess.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            runnerProcess.arguments = [
                "/bin/sh",
                scriptPath,
                String(currentPID),
                targetAppBundlePath,
                stagingAppPath,
                tempDir.path,
                createdStagingDir.path
            ]
            runnerProcess.standardOutput = FileHandle.nullDevice
            runnerProcess.standardError = FileHandle.nullDevice
            try runnerProcess.run()
            shouldCleanupDirectories = false

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            guard isTokenStillActive(sessionToken) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.currentState = .error("更新替换失败：\(error.localizedDescription)")
            }
        }
    }

    private func validateStagedApp(at stagingAppPath: String, expectedVersion: String) throws {
        let infoPlistPath = (stagingAppPath as NSString).appendingPathComponent("Contents/Info.plist")
        let executablePath = (stagingAppPath as NSString).appendingPathComponent("Contents/MacOS/ATools")

        guard let infoData = FileManager.default.contents(atPath: infoPlistPath),
              let plist = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] else {
            throw NSError(domain: "UpdateManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "更新包缺少有效的 Info.plist"])
        }

        guard plist["CFBundleIdentifier"] as? String == UpdateManager.expectedBundleIdentifier,
              plist["CFBundleExecutable"] as? String == "ATools",
              FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw NSError(domain: "UpdateManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "更新包中的应用标识或可执行文件无效"])
        }

        guard let packagedVersion = plist["CFBundleShortVersionString"] as? String else {
            throw NSError(domain: "UpdateManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "更新包缺少有效的版本号"])
        }

        let currentVer = currentAppVersion

        // 校验：更新包版本必须严格高于当前运行版本（防降级与同版本防重放），且必须与发布目标版本一致
        let isNewerThanCurrent = UpdateManager.isVersion(packagedVersion, greaterThan: currentVer)
        let matchesExpected = !expectedVersion.isEmpty && UpdateManager.normalizedVersion(packagedVersion) == UpdateManager.normalizedVersion(expectedVersion)

        guard isNewerThanCurrent else {
            throw NSError(domain: "UpdateManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "更新包版本 (v\(packagedVersion)) 未高于当前运行版本 (v\(currentVer))，已拦截降级安装"])
        }
        if !expectedVersion.isEmpty {
            guard matchesExpected else {
                throw NSError(domain: "UpdateManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "更新包版本 (v\(packagedVersion)) 与发布目标版本 (v\(expectedVersion)) 不一致"])
            }
        }

        let verifyProcess = Process()
        verifyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verifyProcess.arguments = ["--verify", "--deep", "--strict", "--verbose=2", stagingAppPath]
        try verifyProcess.run()
        verifyProcess.waitUntilExit()

        guard verifyProcess.terminationStatus == 0 else {
            throw NSError(domain: "UpdateManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "更新包代码签名校验失败"])
        }

        try Self.validateCodeSignature(at: stagingAppPath, currentAppPath: Bundle.main.bundlePath)
    }

    /// Validates the Apple designated requirement and signer identity in addition to structural
    /// codesign verification. Ad-hoc builds remain supported, but may only replace ad-hoc builds;
    /// Developer ID builds must retain the same Team ID.
    ///
    /// 静态 + internal：`--test` 诊断套件会拿真实包做回归，防止历史 bug 重现。
    static func validateCodeSignature(at stagingAppPath: String, currentAppPath: String) throws {
        let stagedDescription = UpdateManager.codesign(arguments: ["-dv", "--verbose=4", stagingAppPath])
        let stagedRequirement = UpdateManager.codesign(arguments: ["-dr", "-", stagingAppPath])
        guard stagedDescription.status == 0, stagedRequirement.status == 0 else {
            throw NSError(domain: "UpdateManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "更新包 designated requirement 无效"])
        }

        let requirementMatches = stagedRequirement.output.contains("identifier \"\(UpdateManager.expectedBundleIdentifier)\"")
        let identifierMatches = UpdateManager.identifierValue(in: stagedDescription.output) == UpdateManager.expectedBundleIdentifier
        guard requirementMatches || identifierMatches else {
            throw NSError(domain: "UpdateManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "更新包 designated requirement 无效"])
        }

        let currentDescription = UpdateManager.codesign(arguments: ["-dv", "--verbose=4", currentAppPath])
        let currentTeam = UpdateManager.teamIdentifier(in: currentDescription.output)
        let stagedTeam = UpdateManager.teamIdentifier(in: stagedDescription.output)
        let stagedIsAdhoc = stagedDescription.output.contains("Signature=adhoc")

        if let currentTeam {
            guard !stagedIsAdhoc, stagedTeam == currentTeam else {
                throw NSError(domain: "UpdateManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "更新包签名 Team ID 与当前应用不一致"])
            }
        } else {
            guard Self.acceptsUpdateWithoutTeam(stagedIsAdhoc: stagedIsAdhoc,
                                                stagedTeam: stagedTeam,
                                                stagedRequirement: stagedRequirement.output,
                                                pinnedLeafHashes: Self.expectedSigningLeafHashes) else {
                throw NSError(domain: "UpdateManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "当前 ad-hoc 构建仅接受 ad-hoc 或已固定指纹的证书更新包"])
            }
        }
    }

    // MARK: - 签名指纹 pinning（自签名证书迁移路径）

    static let expectedSigningLeafHashes: [String] = [
        // "ATools Sign" 自签名证书（有效期至 2036-09-26），创建于 2026-09-30
        "e27bee7aa3e27e544d365c8042723d2c6624fbdb"
    ]

    /// 解析 `-dr` 输出中的 `certificate leaf = H"..."` 指纹；无证书（ad-hoc）返回 nil。
    static func certificateLeafHash(in requirementOutput: String) -> String? {
        guard let leafRange = requirementOutput.range(of: "certificate leaf") else { return nil }
        let tail = requirementOutput[leafRange.upperBound...]
        guard let hOpen = tail.range(of: "H\"") else { return nil }
        let after = tail[hOpen.upperBound...]
        guard let close = after.firstIndex(of: "\"") else { return nil }
        let hash = String(after[after.startIndex..<close])
        return hash.isEmpty ? nil : hash
    }

    static func acceptsUpdateWithoutTeam(stagedIsAdhoc: Bool,
                                         stagedTeam: String?,
                                         stagedRequirement: String,
                                         pinnedLeafHashes: [String]) -> Bool {
        if stagedIsAdhoc && stagedTeam == nil { return true }
        guard !pinnedLeafHashes.isEmpty else { return false }
        guard let leaf = certificateLeafHash(in: stagedRequirement) else { return false }
        return pinnedLeafHashes.contains {
            leaf.caseInsensitiveCompare($0) == .orderedSame
        }
    }

    private static func identifierValue(in output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("Identifier=") {
            return String(line.dropFirst("Identifier=".count))
        }
        return nil
    }

    private static func teamIdentifier(in output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count)
            return value == "not set" ? nil : String(value)
        }
        return nil
    }

    private static func codesign(arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func detachDMG(mountPoint: String) throws {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint, "-force"]
        try detach.run()
        detach.waitUntilExit()
    }

    /// U-02, U-03 & 军师加固点 4：
    /// 1. 显式锁定安全 PATH，杜绝环境变量命令劫持；
    /// 2. 校验进程身份必须包含 ATools，严禁裸 PID 暴力 `kill -9`；
    /// 3. 替换前二次校验 `$STAGING_APP` 签名与 `cc.atools.app` 标识符，收敛 TOCTOU 窗口；
    /// 4. 使用目标同卷隐藏目录 `.atools_staging_<UUID>` 执行 `/bin/mv`（底层同卷 `rename(2)` 原子交替），若失败或拉起失败则无损回滚 `$BACKUP_APP`。
    internal static let relaunchScript = """
    #!/bin/sh
    set -u
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

    OLD_PID="$1"
    TARGET_APP="$2"
    STAGING_APP="$3"
    TEMP_DIR="$4"
    STAGING_DIR="${5:-}"
    BACKUP_APP="${TARGET_APP}.atools-update-backup"

    cleanup_all() {
        if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
            /bin/rm -rf "$STAGING_DIR"
        fi
        if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
            /bin/rm -rf "$TEMP_DIR"
        fi
    }

    is_atools_pid() {
        if ! /bin/kill -0 "$OLD_PID" 2>/dev/null; then
            return 1
        fi
        PROC_COMM=$(/bin/ps -p "$OLD_PID" -o comm= 2>/dev/null || true)
        case "$PROC_COMM" in
            *ATools*|*atools*) return 0 ;;
            *) return 1 ;;
        esac
    }

    # 1. 等待旧进程平滑退出（最长等待 10 秒，严禁使用裸 kill -9 强杀防 PID 复用误伤）
    COUNT=0
    while is_atools_pid; do
        /bin/sleep 0.2
        COUNT=$((COUNT+1))
        if [ "$COUNT" -eq 40 ]; then
            /bin/kill -TERM "$OLD_PID" 2>/dev/null || true
        fi
        if [ "$COUNT" -gt 50 ]; then
            cleanup_all
            exit 1
        fi
    done

    # 2. 替换前二次严格验签（防范 TOCTOU 篡改窗口）
    if ! /usr/bin/codesign --verify --deep --strict "$STAGING_APP" >/dev/null 2>&1; then
        cleanup_all
        exit 1
    fi
    STAGED_INFO=$(/usr/bin/codesign -dv --verbose=4 "$STAGING_APP" 2>&1 || true)
    case "$STAGED_INFO" in
        *"Identifier=cc.atools.app"*) ;;
        *)
            cleanup_all
            exit 1
            ;;
    esac

    # 3. 清理陈旧备份并执行同卷 rename(2) 原子交替
    /bin/rm -rf "$BACKUP_APP"

    if /bin/mv "$TARGET_APP" "$BACKUP_APP" 2>/dev/null; then
        if /bin/mv "$STAGING_APP" "$TARGET_APP" 2>/dev/null || /usr/bin/ditto "$STAGING_APP" "$TARGET_APP"; then
            if /usr/bin/codesign --verify --deep --strict "$TARGET_APP" >/dev/null 2>&1; then
                if /usr/bin/open "$TARGET_APP"; then
                    /bin/rm -rf "$BACKUP_APP"
                    cleanup_all
                    exit 0
                else
                    /bin/rm -rf "$TARGET_APP"
                    /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null
                fi
            else
                /bin/rm -rf "$TARGET_APP"
                /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null
            fi
        else
            /bin/rm -rf "$TARGET_APP"
            /bin/mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null
        fi
    fi

    /usr/bin/open "$TARGET_APP" 2>/dev/null || true
    cleanup_all
    exit 1
    """
}
