import Foundation
import AppKit

public enum LauncherExecutor {
    /// Launches a LauncherItem while honoring its custom executionContext (arguments, workingDirectory, environmentVars).
    public static func open(item: LauncherItem, completion: ((Bool) -> Void)? = nil) {
        switch item.itemType {
        case .application, .fileOrFolder:
            open(path: item.target, executionContext: item.executionContext, completion: completion)
        case .webURL:
            if let url = URL(string: item.target) {
                let ok = NSWorkspace.shared.open(url)
                completion?(ok)
            } else {
                completion?(false)
            }
        case .shellScript:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: shell)
            let extraArgs = item.executionContext?.arguments ?? []
            if FileManager.default.fileExists(atPath: item.target) && !item.target.contains(" ") {
                task.arguments = [item.target] + extraArgs
            } else {
                let joinedArgs = extraArgs.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: " ")
                let cmd = joinedArgs.isEmpty ? item.target : "\(item.target) \(joinedArgs)"
                task.arguments = ["-c", cmd]
            }
            if let wd = item.executionContext?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
               !wd.isEmpty,
               FileManager.default.fileExists(atPath: wd) {
                task.currentDirectoryURL = URL(fileURLWithPath: wd)
            }
            if let env = item.executionContext?.environmentVars, !env.isEmpty {
                var merged = ProcessInfo.processInfo.environment
                for (k, v) in env { merged[k] = v }
                task.environment = merged
            }
            do {
                try task.run()
                completion?(true)
            } catch {
                completion?(false)
            }
        case .appleScript:
            if let script = NSAppleScript(source: item.target) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                completion?(err == nil)
            } else {
                completion?(false)
            }
        case .systemAction:
            completion?(false)
        }
    }

    /// Launches an application or opens a document file/folder cleanly using macOS modern APIs.
    /// Uses `NSWorkspace.openApplication` for `.app` bundles to avoid triggering false-positive
    /// `kTCCServiceSystemPolicyAppBundles` ("已阻止修改 Mac 上的 App") security alerts.
    public static func open(path: String, executionContext: ExecutionContext? = nil, completion: ((Bool) -> Void)? = nil) {
        let url = URL(fileURLWithPath: path)
        let isApp = path.lowercased().hasSuffix(".app")

        if isApp {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.addsToRecentItems = true
            config.promptsUserIfNeeded = true
            if let ctx = executionContext {
                if !ctx.arguments.isEmpty {
                    config.arguments = ctx.arguments
                }
                var env = ctx.environmentVars
                if let wd = ctx.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !wd.isEmpty,
                   FileManager.default.fileExists(atPath: wd) {
                    env["PWD"] = wd
                }
                if !env.isEmpty {
                    config.environment = env
                }
            }
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
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
            // Non-app file or script: if arguments or workingDirectory are specified and file is executable, run via Process
            if let ctx = executionContext,
               (!ctx.arguments.isEmpty || !(ctx.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)),
               FileManager.default.isExecutableFile(atPath: path) {
                let task = Process()
                task.executableURL = url
                task.arguments = ctx.arguments
                if let wd = ctx.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !wd.isEmpty,
                   FileManager.default.fileExists(atPath: wd) {
                    task.currentDirectoryURL = URL(fileURLWithPath: wd)
                }
                if !ctx.environmentVars.isEmpty {
                    var merged = ProcessInfo.processInfo.environment
                    for (k, v) in ctx.environmentVars { merged[k] = v }
                    task.environment = merged
                }
                do {
                    try task.run()
                    completion?(true)
                    return
                } catch {
                    runtimeLog("[LauncherExecutor] executable launch fallback to NSWorkspace.open: \(error)")
                }
            }
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
