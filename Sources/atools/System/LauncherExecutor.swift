import Foundation
import AppKit

public enum LauncherExecutor {
    /// Launches an application or opens a document file/folder cleanly using macOS modern APIs.
    /// Uses `NSWorkspace.openApplication` for `.app` bundles to avoid triggering false-positive
    /// `kTCCServiceSystemPolicyAppBundles` ("已阻止修改 Mac 上的 App") security alerts.
    public static func open(path: String, completion: ((Bool) -> Void)? = nil) {
        let url = URL(fileURLWithPath: path)
        let isApp = path.hasSuffix(".app")

        if isApp {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.addsToRecentItems = true
            config.promptsUserIfNeeded = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error = error {
                    runtimeLog("[LauncherExecutor] openApplication warning: \(error.localizedDescription), fallback to open(url)")
                    DispatchQueue.main.async {
                        let ok = NSWorkspace.shared.open(url)
                        completion?(ok)
                    }
                } else {
                    completion?(true)
                }
            }
        } else {
            let ok = NSWorkspace.shared.open(url)
            completion?(ok)
        }
    }

    /// Opens the specified Privacy & Security pane in macOS System Settings
    public static func openSystemPrivacySettings(service: String) {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(service)") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
