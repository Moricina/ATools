import Foundation
import AppKit

public struct ReleaseInfo: Equatable {
    public let version: String
    public let name: String
    public let body: String
    public let downloadURL: URL
    public let assetName: String
    public let publishedAt: String

    public init(
        version: String,
        name: String,
        body: String,
        downloadURL: URL,
        assetName: String,
        publishedAt: String
    ) {
        self.version = version
        self.name = name
        self.body = body
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.publishedAt = publishedAt
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

    public private(set) var currentState: UpdateState = .idle {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: UpdateManager.stateDidChangeNotification,
                    object: self
                )
            }
        }
    }

    private var currentDownloadTask: URLSessionDownloadTask?
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 300.0
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var targetRelease: ReleaseInfo?

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
        guard currentState != .checking else { return }
        currentState = .checking

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

            if let error = error {
                let msg = (error as NSError).code == NSURLErrorNotConnectedToInternet
                    ? "未连接互联网，请检查网络设置"
                    : "网络请求失败：\(error.localizedDescription)"
                self.currentState = .error(msg)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.currentState = .error("服务器返回异常响应")
                return
            }

            if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                self.currentState = .error("GitHub API 访问达到限流上限，请稍后再试")
                return
            }

            guard httpResponse.statusCode == 200, let data = data else {
                self.currentState = .error("检测更新失败 (HTTP \(httpResponse.statusCode))")
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.currentState = .error("解析版本发布数据失败")
                    return
                }

                let releaseName = json["name"] as? String ?? tagName
                let body = json["body"] as? String ?? "暂无更新说明"
                let publishedAt = json["published_at"] as? String ?? ""

                // 查找 assets 中的 DMG 或 ZIP
                var assetDownloadURL: URL?
                var assetFileName = ""

                if let assets = json["assets"] as? [[String: Any]] {
                    // 优先选择 ATools.dmg
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                           let urlString = asset["browser_download_url"] as? String,
                           let url = URL(string: urlString) {
                            assetDownloadURL = url
                            assetFileName = name
                            break
                        }
                    }

                    // 备选 ATools.zip
                    if assetDownloadURL == nil {
                        for asset in assets {
                            if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                               let urlString = asset["browser_download_url"] as? String,
                               let url = URL(string: urlString) {
                                assetDownloadURL = url
                                assetFileName = name
                                break
                            }
                        }
                    }
                }

                let currentVer = self.currentAppVersion
                let hasNewVersion = UpdateManager.isVersion(tagName, greaterThan: currentVer)

                if hasNewVersion {
                    guard let downloadURL = assetDownloadURL else {
                        self.currentState = .error("最新版本未提供 macOS 安装镜像包")
                        return
                    }

                    let release = ReleaseInfo(
                        version: tagName,
                        name: releaseName,
                        body: body,
                        downloadURL: downloadURL,
                        assetName: assetFileName,
                        publishedAt: publishedAt
                    )
                    self.targetRelease = release
                    self.currentState = .available(release)
                } else {
                    self.currentState = .upToDate(currentVersion: currentVer)
                }
            } catch {
                self.currentState = .error("解析版本数据异常：\(error.localizedDescription)")
            }
        }
        task.resume()
    }

    // MARK: - Download & Install
    public func startUpdate() {
        guard case .available(let release) = currentState else { return }
        self.targetRelease = release
        self.currentState = .downloading(progress: 0.0)

        // 验证当前路径是否处于 AppTranslocation 只读隔离区
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("AppTranslocation") {
            self.currentState = .error("当前应用运行在临时隔离区中，请先将其移动到「应用程序」文件夹后再执行更新")
            return
        }

        // 验证目标路径写权限
        if !FileManager.default.isWritableFile(atPath: (bundlePath as NSString).deletingLastPathComponent) &&
           !FileManager.default.isWritableFile(atPath: bundlePath) {
            self.currentState = .error("对目标应用程序目录缺少写入权限，无法原地自动更新")
            return
        }

        let downloadTask = downloadSession.downloadTask(with: release.downloadURL)
        self.currentDownloadTask = downloadTask
        downloadTask.resume()
    }

    public func cancelUpdate() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        currentState = .idle
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
        DispatchQueue.main.async { [weak self] in
            self?.currentState = .preparing
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.extractAndRelaunch(downloadedLocation: location)
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
    private func extractAndRelaunch(downloadedLocation: URL) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("atools_update_\(UUID().uuidString)")
        let stagingDir = tempDir.appendingPathComponent("staging")
        let targetAppBundlePath = Bundle.main.bundlePath
        let isDMG = targetRelease?.assetName.hasSuffix(".dmg") ?? true

        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            let localAssetPath: String
            if isDMG {
                localAssetPath = tempDir.appendingPathComponent("download.dmg").path
            } else {
                localAssetPath = tempDir.appendingPathComponent("download.zip").path
            }

            try FileManager.default.copyItem(atPath: downloadedLocation.path, toPath: localAssetPath)

            let stagingAppPath = stagingDir.appendingPathComponent("ATools.app").path

            if isDMG {
                // 挂载 DMG 提取 ATools.app
                let mountPoint = tempDir.appendingPathComponent("mount").path
                try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

                let attachProcess = Process()
                attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attachProcess.arguments = ["attach", localAssetPath, "-nobrowse", "-mountpoint", mountPoint]
                try attachProcess.run()
                attachProcess.waitUntilExit()

                guard attachProcess.terminationStatus == 0 else {
                    throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法挂载更新磁盘镜像"])
                }

                let sourceAppInMount = (mountPoint as NSString).appendingPathComponent("ATools.app")
                if FileManager.default.fileExists(atPath: sourceAppInMount) {
                    try FileManager.default.copyItem(atPath: sourceAppInMount, toPath: stagingAppPath)
                } else {
                    _ = try? self.detachDMG(mountPoint: mountPoint)
                    throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "更新镜像中未找到 ATools.app"])
                }

                _ = try? self.detachDMG(mountPoint: mountPoint)
            } else {
                // 解压 ZIP 提取 ATools.app
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProcess.arguments = ["-xk", localAssetPath, stagingDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: stagingAppPath) else {
                    throw NSError(domain: "UpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "解压更新压缩包失败"])
                }
            }

            // 清除新版本隔离属性
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", stagingAppPath]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            // 写入独立的平滑替换守护脚本
            let scriptPath = tempDir.appendingPathComponent("relaunch.sh").path
            let currentPID = ProcessInfo.processInfo.processIdentifier

            let scriptContent = """
            #!/bin/sh
            OLD_PID="\(currentPID)"
            TARGET_APP="\(targetAppBundlePath)"
            STAGING_APP="\(stagingAppPath)"
            TEMP_DIR="\(tempDir.path)"
            BACKUP_APP="${TARGET_APP}.backup"

            # 1. 等待老进程退出（最长等待 10 秒）
            COUNT=0
            while kill -0 "$OLD_PID" 2>/dev/null; do
                sleep 0.2
                COUNT=$((COUNT+1))
                if [ $COUNT -gt 50 ]; then
                    kill -9 "$OLD_PID" 2>/dev/null
                    break
                fi
            done

            # 2. 原子化覆盖替换
            rm -rf "$BACKUP_APP"
            if mv "$TARGET_APP" "$BACKUP_APP" 2>/dev/null; then
                if cp -R "$STAGING_APP" "$TARGET_APP"; then
                    /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null
                    rm -rf "$BACKUP_APP"
                else
                    # 容灾回滚
                    mv "$BACKUP_APP" "$TARGET_APP"
                fi
            fi

            # 3. 重新拉起应用
            /usr/bin/open "$TARGET_APP"

            # 4. 清理临时更新目录
            rm -rf "$TEMP_DIR"
            """

            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            // 启动守护脚本并退出当前老进程
            let runnerProcess = Process()
            runnerProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            runnerProcess.arguments = [scriptPath]
            try runnerProcess.run()

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.currentState = .error("更新替换失败：\(error.localizedDescription)")
            }
        }
    }

    private func detachDMG(mountPoint: String) throws {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint, "-force"]
        try detach.run()
        detach.waitUntilExit()
    }
}
