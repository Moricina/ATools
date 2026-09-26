import Foundation
import AppKit

public struct SystemActionItem {
    public let id: String
    public let name: String
    public let keywords: [String]
    public let iconSymbol: String
    public let execute: () -> Void
}

public final class SystemActions {
    public static let shared = SystemActions()

    public private(set) var actions: [SystemActionItem] = []

    private init() {
        setupActions()
    }

    private func setupActions() {
        actions = [
            SystemActionItem(
                id: "lock_screen",
                name: "锁定屏幕 (Lock Screen)",
                keywords: ["lock", "suo", "suoping", "锁屏", "锁定屏幕", "锁定"],
                iconSymbol: "lock.fill",
                execute: {
                    let task = Process()
                    task.launchPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
                    task.arguments = ["-suspend"]
                    try? task.run()
                }
            ),
            SystemActionItem(
                id: "sleep",
                name: "进入睡眠 (Sleep)",
                keywords: ["sleep", "shuimian", "xiu", "xiubing", "睡眠", "休眠"],
                iconSymbol: "moon.fill",
                execute: {
                    let source = "tell application \"System Events\" to sleep"
                    if let script = NSAppleScript(source: source) {
                        var error: NSDictionary?
                        script.executeAndReturnError(&error)
                    }
                }
            ),
            SystemActionItem(
                id: "empty_trash",
                name: "清空废纸篓 (Empty Trash)",
                keywords: ["trash", "empty", "feizhilou", "垃圾桶", "清空", "清空废纸篓", "清空垃圾桶"],
                iconSymbol: "trash.fill",
                execute: {
                    let source = "tell application \"Finder\" to empty trash"
                    if let script = NSAppleScript(source: source) {
                        var error: NSDictionary?
                        script.executeAndReturnError(&error)
                    }
                }
            ),
            SystemActionItem(
                id: "restart",
                name: "重新启动 (Restart)",
                keywords: ["restart", "reboot", "chongqi", "重启", "重新启动"],
                iconSymbol: "arrow.clockwise",
                execute: {
                    let source = "tell application \"System Events\" to restart"
                    if let script = NSAppleScript(source: source) {
                        var error: NSDictionary?
                        script.executeAndReturnError(&error)
                    }
                }
            ),
            SystemActionItem(
                id: "screensaver",
                name: "启动屏幕保护程序 (Screen Saver)",
                keywords: ["screensaver", "saver", "pingbao", "屏保", "屏幕保护程序"],
                iconSymbol: "display",
                execute: {
                    let source = "tell application \"System Events\" to start current screen saver"
                    if let script = NSAppleScript(source: source) {
                        var error: NSDictionary?
                        script.executeAndReturnError(&error)
                    }
                }
            ),
            SystemActionItem(
                id: "activity_monitor",
                name: "活动监视器 (Activity Monitor)",
                keywords: ["activity", "monitor", "top", "huodong", "jianshiqi", "任务管理器", "活动监视器"],
                iconSymbol: "chart.bar.xaxis",
                execute: {
                    let path = "/System/Applications/Utilities/Activity Monitor.app"
                    LauncherExecutor.open(path: path)
                }
            )
        ]
    }

    public func match(_ query: String) -> [SystemActionItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return actions.filter { action in
            action.keywords.contains { kw in
                kw.contains(q) || q.contains(kw)
            }
        }
    }
}
