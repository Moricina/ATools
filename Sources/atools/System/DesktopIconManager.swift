import Foundation
import AppKit

public extension Notification.Name {
    static let atoolsDesktopIconsVisibilityDidChange = Notification.Name("atoolsDesktopIconsVisibilityDidChange")
}

public final class DesktopIconManager {
    public static let shared = DesktopIconManager()

    private let finderDomain = "com.apple.finder" as CFString
    private let key = "CreateDesktop" as CFString

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

    /// Explicitly sets desktop icon visibility.
    public func setDesktopIconsHidden(_ hidden: Bool) {
        let targetBool = !hidden // CreateDesktop == true means icons are visible
        CFPreferencesSetAppValue(key, targetBool ? kCFBooleanTrue : kCFBooleanFalse, finderDomain)
        CFPreferencesAppSynchronize(finderDomain)

        DispatchQueue.global(qos: .userInitiated).async { [targetBool] in
            // Use defaults write + killall Finder for guaranteed multi-version macOS consistency
            let defaultsTask = Process()
            defaultsTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            defaultsTask.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", targetBool ? "true" : "false"]
            try? defaultsTask.run()
            defaultsTask.waitUntilExit()

            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killTask.arguments = ["Finder"]
            try? killTask.run()
            killTask.waitUntilExit()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .atoolsDesktopIconsVisibilityDidChange, object: nil)
            }
        }
    }
}
