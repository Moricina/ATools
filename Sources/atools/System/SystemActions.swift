import Foundation
import AppKit

public struct SystemActionItem {
    public let id: String
    public let name: String
    public let keywords: [String]
    public let iconSymbol: String
    /// Destructive / disruptive actions ask for confirmation before running.
    public let confirmationMessage: String?
    public let run: () -> Void

    public init(id: String, name: String, keywords: [String], iconSymbol: String, confirmationMessage: String? = nil, run: @escaping () -> Void) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.iconSymbol = iconSymbol
        self.confirmationMessage = confirmationMessage
        self.run = run
    }

    public var execute: () -> Void {
        let message = confirmationMessage
        let name = self.name
        let run = self.run
        return {
            guard let message = message else {
                run()
                return
            }
            let alert = NSAlert()
            alert.messageText = name
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
                run()
            }
        }
    }
}

public final class SystemActions {
    public static let shared = SystemActions()

    public private(set) var actions: [SystemActionItem] = []

    private init() {
        setupActions()
    }

    /// Runs a helper tool off the main thread so Apple Events / TCC prompts never freeze the UI.
    private static func runTool(_ path: String, _ arguments: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = arguments
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    runtimeLog("[SystemActions] \(path) \(arguments) exited with \(task.terminationStatus)")
                }
            } catch {
                runtimeLog("[SystemActions] Failed to run \(path): \(error)")
            }
        }
    }

    private static func runAppleScript(_ source: String) {
        runTool("/usr/bin/osascript", ["-e", source])
    }

    /// `CGSession -suspend` was removed in macOS 11, so lock via login.framework instead.
    private static func lockScreen() {
        typealias LockFunction = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            let lock = unsafeBitCast(symbol, to: LockFunction.self)
            lock()
            return
        }
        // Fallback: sleep the display; locks when "require password immediately" is set.
        runTool("/usr/bin/pmset", ["displaysleepnow"])
    }

    private func setupActions() {
        actions = [
            SystemActionItem(
                id: "lock_screen",
                name: "锁定屏幕 (Lock Screen)",
                keywords: ["lock", "suoping", "锁屏", "锁定屏幕", "锁定"],
                iconSymbol: "lock.fill",
                run: { SystemActions.lockScreen() }
            ),
            SystemActionItem(
                id: "sleep",
                name: "进入睡眠 (Sleep)",
                keywords: ["sleep", "shuimian", "xiumian", "睡眠", "休眠"],
                iconSymbol: "moon.fill",
                run: { SystemActions.runTool("/usr/bin/pmset", ["sleepnow"]) }
            ),
            SystemActionItem(
                id: "empty_trash",
                name: "清空废纸篓 (Empty Trash)",
                keywords: ["emptytrash", "empty trash", "trash", "feizhilou", "清空废纸篓", "清空垃圾桶", "废纸篓", "垃圾桶"],
                iconSymbol: "trash.fill",
                confirmationMessage: "废纸篓中的所有项目将被永久删除，此操作无法撤销。",
                run: { SystemActions.runAppleScript("tell application \"Finder\" to empty trash") }
            ),
            SystemActionItem(
                id: "restart",
                name: "重新启动 (Restart)",
                keywords: ["restart", "reboot", "chongqi", "重启", "重新启动"],
                iconSymbol: "arrow.clockwise",
                confirmationMessage: "确定要立即重新启动这台 Mac 吗？未保存的内容可能会丢失。",
                run: { SystemActions.runAppleScript("tell application \"System Events\" to restart") }
            ),
            SystemActionItem(
                id: "screensaver",
                name: "启动屏幕保护程序 (Screen Saver)",
                keywords: ["screensaver", "pingbao", "屏保", "屏幕保护程序"],
                iconSymbol: "display",
                run: { SystemActions.runTool("/usr/bin/open", ["-a", "ScreenSaverEngine"]) }
            ),
            SystemActionItem(
                id: "activity_monitor",
                name: "活动监视器 (Activity Monitor)",
                keywords: ["activity monitor", "huodongjianshiqi", "任务管理器", "活动监视器"],
                iconSymbol: "chart.bar.xaxis",
                run: { LauncherExecutor.open(path: "/System/Applications/Utilities/Activity Monitor.app") }
            )
        ]
    }

    /// Matches only when the query is a prefix of a keyword (min. 2 characters, or 1 CJK
    /// character). The previous bidirectional `contains` check surfaced "Lock Screen" for a
    /// single "s" and "Empty Trash" for any file name containing "empty".
    public func match(_ query: String) -> [SystemActionItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let isCJK = q.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        guard q.count >= 2 || isCJK else { return [] }

        return actions.filter { action in
            action.keywords.contains { $0.hasPrefix(q) }
        }
    }
}
