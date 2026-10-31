import Foundation
import AppKit

public extension Notification.Name {
    static let atoolsDesktopIconsVisibilityDidChange = Notification.Name("atoolsDesktopIconsVisibilityDidChange")
}

public final class DesktopIconManager {
    public static let shared = DesktopIconManager()

    private let finderDomain = "com.apple.finder" as CFString
    private let key = "CreateDesktop" as CFString
    /// Y-10: 专用串行队列，保证快速双击切换桌面图标时 defaults 写入与 Finder 重启严格按顺序串行执行，杜绝并发竞态
    private let executionQueue = DispatchQueue(label: "cc.atools.desktopicon.serial", qos: .userInitiated)

    private init() {}

    /// Returns `true` if macOS desktop icons are currently hidden, `false` if they are shown (default).
    public var isDesktopIconsHidden: Bool {
        CFPreferencesSynchronize(finderDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if let val = CFPreferencesCopyAppValue(key, finderDomain) as? Bool {
            return !val
        } else if let num = CFPreferencesCopyAppValue(key, finderDomain) as? Int {
            return num == 0
        } else if let str = CFPreferencesCopyAppValue(key, finderDomain) as? String {
            let lower = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "false" || lower == "0"
        }
        return false
    }

    /// Toggles desktop icon visibility and restarts Finder in the background.
    /// Returns the new `isDesktopIconsHidden` state.
    @discardableResult
    public func toggleDesktopIcons() -> Bool {
        let newHidden = !isDesktopIconsHidden
        setDesktopIconsHidden(newHidden)
        return newHidden
    }

    /// Explicitly sets desktop icon visibility on a serial queue and verifies exit codes (Y-10).
    public func setDesktopIconsHidden(_ hidden: Bool) {
        let targetBool = !hidden // CreateDesktop == true means icons are visible
        CFPreferencesSetAppValue(key, targetBool ? kCFBooleanTrue : kCFBooleanFalse, finderDomain)
        CFPreferencesAppSynchronize(finderDomain)

        executionQueue.async { [targetBool] in
            let defaultsTask = Process()
            defaultsTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            defaultsTask.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", targetBool ? "true" : "false"]
            do {
                try defaultsTask.run()
                defaultsTask.waitUntilExit()
                guard defaultsTask.terminationStatus == 0 else {
                    runtimeLog("[DesktopIconManager] defaults write exited with status \(defaultsTask.terminationStatus)")
                    return
                }
            } catch {
                runtimeLog("[DesktopIconManager] Failed to run defaults: \(error)")
                return
            }

            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killTask.arguments = ["Finder"]
            do {
                try killTask.run()
                killTask.waitUntilExit()
            } catch {
                runtimeLog("[DesktopIconManager] Failed to restart Finder: \(error)")
                return
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .atoolsDesktopIconsVisibilityDidChange, object: nil)
            }
        }
    }
}
