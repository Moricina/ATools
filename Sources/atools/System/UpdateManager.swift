import Foundation
import AppKit
import CryptoKit

public struct ReleaseInfo: Equatable {
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

public enum UpdateState: Equatable {
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

    private let stateLock = NSLock()
    private var _currentState: UpdateState = .idle
    private var _targetRelease: ReleaseInfo?

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
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 300.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
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

    // MARK: - Version Comparison
    /// 比较语义化版本号：若 v1 大于 v2 则返回 true
    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
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

    // MARK: - Check for Updates
    public func checkForUpdates(isUserInitiated: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.checkForUpdates(isUserInitiated: isUserInitiated)
            }
            return
        }

        guard currentState != .checking else { return }
        currentState = .checking
        targetRelease = nil

        guard let apiURL = URL(string: "https://api.github.com/repos/Moricina/ATools/releases/latest") else {
            currentState = .error("无效的更新检测地址")
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
                self?.handleUpdateCheck(data: data, response: response, error: error)
            }
        }
        task.resume()
    }

    private func handleUpdateCheck(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            let msg = (error as NSError).code == NSURLErrorNotConnectedToInternet
                ? "未连接互联网，请检查网络设置"
                : "网络请求失败：\(error.localizedDescription)"
            currentState = .error(msg)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            currentState = .error("服务器返回异常响应")
            return
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            currentState = .error("GitHub API 访问达到限流上限，请稍后再试")
            return
        }

        guard httpResponse.statusCode == 200, let data = data else {
            currentState = .error("检测更新失败 (HTTP \(httpResponse.statusCode))")
            return
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
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
                    currentState = .error("最新版本未提供 macOS 安装镜像包")
                    return
                }
                guard let signatureURL = UpdateManager.signatureURL(
                    for: preferredAsset.name,
                    from: assets
                ) else {
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
        self.targetRelease = release
        self.currentState = .downloading(progress: 0.0)

        // 验证当前路径是否处于 AppTranslocation 或只读挂载卷
        let bundlePath = Bundle.main.bundlePath
        if UpdateManager.isBlockedUpdateLocation(bundlePath) {
            self.currentState = .error("当前应用运行在临时隔离区或只读磁盘镜像中，请先将其移动到「应用程序」文件夹后再执行更新")
            return
        }

        // 原地替换需要对父目录有写权限；目录本身不可写并不代表替换不可行
        let parentDirectory = (bundlePath as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: parentDirectory) {
            self.currentState = .error("对目标应用程序目录缺少写入权限，无法原地自动更新")
            return
        }

        let downloadTask = downloadSession.downloadTask(with: release.downloadURL)
        self.currentDownloadTask = downloadTask
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

        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        currentState = .idle
    }

    static func isBlockedUpdateLocation(_ path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardizedPath.contains("/AppTranslocation/")
            || standardizedPath.hasPrefix("/Volumes/")
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
                      let url = URL(string: urlString) else {
                    continue
                }
                return (name: name, url: url)
            }
        }
        return nil
    }

    static func signatureURL(for assetName: String, from assets: [[String: Any]]) -> URL? {
        let signatureName = assetName + ".sig"
        for asset in assets {
            guard asset["name"] as? String == signatureName,
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else {
                continue
            }
            return url
        }
        return nil
    }

    static let updateSigningPublicKeyBase64 = "HbGQoLgpZ8MVghAQOJIR79JC7YvkRQmzimfO2OuFE34="

    static func verifyUpdateSignature(assetURL: URL, signatureURL: URL) throws {
        let signatureData = try Data(contentsOf: signatureURL)
        guard let signatureText = String(data: signatureData, encoding: .utf8) else {
            throw NSError(
                domain: "UpdateManager",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "更新签名格式无效，已拒绝安装"]
            )
        }

        guard let rawPublicKey = Data(base64Encoded: updateSigningPublicKeyBase64),
              let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey) else {
            throw NSError(
                domain: "UpdateManager",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "更新签名格式无效，已拒绝安装"]
            )
        }

        let digest = try UpdateManager.sha256(ofFileAt: assetURL)
        guard publicKey.isValidSignature(signature, for: digest) else {
            throw NSError(
                domain: "UpdateManager",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Ed25519 更新签名校验失败，安装包可能已被篡改"]
            )
        }
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

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
        currentState = .preparing

        guard let httpResponse = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            currentDownloadTask = nil
            currentState = .error("下载服务器返回异常，请稍后重试")
            return
        }

        do {
            // URLSession 会在本代理方法返回后删除 location，必须先同步接管临时文件。
            let preparedUpdate = try prepareDownloadedAsset(at: location)
            let expectedVersion = targetRelease?.version ?? ""
            let signatureURL = targetRelease?.signatureURL
            currentDownloadTask = nil
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.extractAndRelaunch(
                    preparedUpdate: preparedUpdate,
                    expectedVersion: expectedVersion,
                    signatureURL: signatureURL
                )
            }
        } catch {
            currentDownloadTask = nil
            currentState = .error("保存安装包失败：\(error.localizedDescription)")
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            DispatchQueue.main.async { [weak self] in
                self?.currentState = .error("下载安装包失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Extraction & In-Place Replacement
    private struct PreparedUpdate {
        let tempDirectory: URL
        let assetURL: URL
        let isDMG: Bool
    }

    private func prepareDownloadedAsset(at location: URL) throws -> PreparedUpdate {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("atools_update_\(UUID().uuidString)")
        let isDMG = targetRelease?.assetName.hasSuffix(".dmg") ?? true
        let localAssetPath = tempDir.appendingPathComponent(isDMG ? "download.dmg" : "download.zip")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: location, to: localAssetPath)
            return PreparedUpdate(tempDirectory: tempDir, assetURL: localAssetPath, isDMG: isDMG)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    private func extractAndRelaunch(
        preparedUpdate: PreparedUpdate,
        expectedVersion: String,
        signatureURL: URL?
    ) {
        let tempDir = preparedUpdate.tempDirectory
        let stagingDir = tempDir.appendingPathComponent("staging")
        let targetAppBundlePath = Bundle.main.bundlePath
        var shouldCleanupTempDirectory = true
        defer {
            if shouldCleanupTempDirectory {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        do {
            guard let signatureURL = signatureURL else {
                throw NSError(
                    domain: "UpdateManager",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "更新包缺少 Ed25519 分离签名，已拒绝安装"]
                )
            }
            try UpdateManager.verifyUpdateSignature(
                assetURL: preparedUpdate.assetURL,
                signatureURL: signatureURL
            )

            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let stagingAppPath = stagingDir.appendingPathComponent("ATools.app").path

            if preparedUpdate.isDMG {
                // 挂载 DMG 提取 ATools.app
                let mountPoint = tempDir.appendingPathComponent("mount").path
                try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

                let attachProcess = Process()
                attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attachProcess.arguments = ["attach", preparedUpdate.assetURL.path, "-nobrowse", "-mountpoint", mountPoint]
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
                unzipProcess.arguments = ["-xk", preparedUpdate.assetURL.path, stagingDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: stagingAppPath) else {
                    throw NSError(domain: "UpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "解压更新压缩包失败"])
                }
            }

            try validateStagedApp(at: stagingAppPath, expectedVersion: expectedVersion)

            // 写入独立的平滑替换守护脚本
            let scriptPath = tempDir.appendingPathComponent("relaunch.sh").path
            let currentPID = ProcessInfo.processInfo.processIdentifier

            try UpdateManager.relaunchScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            // 启动守护脚本并退出当前老进程 (使用 nohup 隔离父进程退出信号)
            let runnerProcess = Process()
            runnerProcess.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            runnerProcess.arguments = [
                "/bin/sh",
                scriptPath,
                String(currentPID),
                targetAppBundlePath,
                stagingAppPath,
                tempDir.path
            ]
            runnerProcess.standardOutput = FileHandle.nullDevice
            runnerProcess.standardError = FileHandle.nullDevice
            try runnerProcess.run()
            shouldCleanupTempDirectory = false

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
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

        // 校验：更新包版本只要高于当前运行版本，或者与目标发布版本一致，即为合法有效更新
        let isNewerThanCurrent = UpdateManager.isVersion(packagedVersion, greaterThan: currentVer)
        let matchesExpected = !expectedVersion.isEmpty && UpdateManager.normalizedVersion(packagedVersion) == UpdateManager.normalizedVersion(expectedVersion)

        guard isNewerThanCurrent || matchesExpected else {
            throw NSError(domain: "UpdateManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "更新包版本 (v\(packagedVersion)) 未高于当前运行版本 (v\(currentVer))"])
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

        // 证书签名（Developer ID 等）的 DR 形如：
        //   designated => identifier "cc.atools.app" and certificate leaf=H"..."
        // ad-hoc 签名没有证书，DR 只会是 cdhash（`# designated => cdhash H"..."`），
        // 根本不含 identifier——只查 DR 的话所有 ad-hoc 正式包都会被误拒，
        // 所以退回用 -dv 输出的 Identifier= 校验（历史上就是这里导致更新报错）。
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
            guard stagedIsAdhoc, stagedTeam == nil else {
                throw NSError(domain: "UpdateManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "当前 ad-hoc 构建仅接受 ad-hoc 更新包"])
            }
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

    private static let relaunchScript = """
    #!/bin/sh
    set -u

    OLD_PID="$1"
    TARGET_APP="$2"
    STAGING_APP="$3"
    TEMP_DIR="$4"
    BACKUP_APP="${TARGET_APP}.atools-update-backup"

    # 1. 等待老进程退出（最长等待 10 秒）
    COUNT=0
    while kill -0 "$OLD_PID" 2>/dev/null; do
        sleep 0.2
        COUNT=$((COUNT+1))
        if [ "$COUNT" -gt 50 ]; then
            kill -9 "$OLD_PID" 2>/dev/null
            break
        fi
    done

    # 2. 替换前清理陈旧备份
    rm -rf "$BACKUP_APP"

    # 3. 先移动旧包，再使用 ditto 保留资源、权限与隔离属性
    if mv "$TARGET_APP" "$BACKUP_APP" 2>/dev/null; then
        if /usr/bin/ditto "$STAGING_APP" "$TARGET_APP"; then
            if /usr/bin/codesign --verify --deep --strict "$TARGET_APP" >/dev/null 2>&1; then
                rm -rf "$BACKUP_APP"
            else
                rm -rf "$TARGET_APP"
                mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null
            fi
        else
            rm -rf "$TARGET_APP"
            mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null
        fi
    fi

    # 4. 重新拉起应用
    /usr/bin/open "$TARGET_APP"

    # 5. 清理临时更新目录
    rm -rf "$TEMP_DIR"
    """
}
