import Foundation
import AppKit

public enum LauncherExecutor {
    /// POSIX single-quote shell escaping (zero expansion of $(), backticks, quotes, or spaces).
    public static func shellSingleQuoted(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds the process argument array for a shell script item without string-concatenation injection (S-04).
    public static func buildShellProcessArguments(target: String, extraArgs: [String]) -> [String] {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileManager.default.fileExists(atPath: trimmedTarget) {
            return [trimmedTarget] + extraArgs
        } else {
            if extraArgs.isEmpty {
                return ["-c", trimmedTarget]
            } else {
                // Pass arguments via positional parameters ($1, $2, ...) instead of string interpolation
                let commandBody = trimmedTarget.contains("$") ? trimmedTarget : "\(trimmedTarget) \"$@\""
                return ["-c", commandBody, "--"] + extraArgs
            }
        }
    }

    /// Launches a LauncherItem while honoring its custom executionContext (arguments, workingDirectory, environmentVars, runAsAdmin, terminalMode).
    public static func open(item: LauncherItem, completion: ((Bool) -> Void)? = nil) {
        let wrappedCompletion: (Bool) -> Void = { success in
            if Thread.isMainThread {
                if success {
                    ConfigManager.shared.recordItemLaunch(itemId: item.id)
                }
                completion?(success)
            } else {
                DispatchQueue.main.async {
                    if success {
                        ConfigManager.shared.recordItemLaunch(itemId: item.id)
                    }
                    completion?(success)
                }
            }
        }
        switch item.itemType {
        case .application, .fileOrFolder:
            open(path: item.target, executionContext: item.executionContext, completion: wrappedCompletion)
        case .webURL:
            if let url = URL(string: item.target) {
                let ok = NSWorkspace.shared.open(url)
                wrappedCompletion(ok)
            } else {
                wrappedCompletion(false)
            }
        case .shellScript:
            executeShellScript(target: item.target, executionContext: item.executionContext, completion: wrappedCompletion)
        case .appleScript:
            if let script = NSAppleScript(source: item.target) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                wrappedCompletion(err == nil)
            } else {
                wrappedCompletion(false)
            }
        case .systemAction:
            wrappedCompletion(false)
        }
    }

    private static func executeShellScript(target: String, executionContext: ExecutionContext?, completion: @escaping (Bool) -> Void) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let extraArgs = executionContext?.arguments ?? []
        let wd = executionContext?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validWD = (wd != nil && !wd!.isEmpty && FileManager.default.fileExists(atPath: wd!)) ? wd : nil
        let envVars = executionContext?.environmentVars ?? [:]
        let runAsAdmin = executionContext?.runAsAdmin ?? false
        let terminalMode = executionContext?.terminalMode ?? .integratedBackground

        if runAsAdmin {
            runWithAdminPrivileges(target: target, isFilePath: FileManager.default.fileExists(atPath: target), extraArgs: extraArgs, workingDirectory: validWD, envVars: envVars, completion: completion)
            return
        }

        if terminalMode == .launchTerminal {
            runInTerminalApp(target: target, isFilePath: FileManager.default.fileExists(atPath: target), extraArgs: extraArgs, workingDirectory: validWD, envVars: envVars, completion: completion)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = buildShellProcessArguments(target: target, extraArgs: extraArgs)
        if let validWD = validWD {
            task.currentDirectoryURL = URL(fileURLWithPath: validWD)
        }
        if !envVars.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in envVars { merged[k] = v }
            task.environment = merged
        }
        do {
            try task.run()
            completion(true)
        } catch {
            runtimeLog("[LauncherExecutor] shellScript execution failed: \(error)")
            completion(false)
        }
    }

    private static func buildSafeCommandString(
        target: String,
        isFilePath: Bool,
        extraArgs: [String],
        workingDirectory: String?,
        envVars: [String: String]
    ) -> String {
        var segments: [String] = []
        if let wd = workingDirectory, !wd.isEmpty {
            segments.append("cd \(shellSingleQuoted(wd)) &&")
        }
        for (k, v) in envVars.sorted(by: { $0.key < $1.key }) {
            let safeKey = k.filter { $0.isLetter || $0.isNumber || $0 == "_" }
            if !safeKey.isEmpty {
                segments.append("\(safeKey)=\(shellSingleQuoted(v))")
            }
        }
        if isFilePath {
            segments.append(shellSingleQuoted(target))
        } else {
            segments.append(target)
        }
        for arg in extraArgs {
            segments.append(shellSingleQuoted(arg))
        }
        return segments.joined(separator: " ")
    }

    private static func runWithAdminPrivileges(
        target: String,
        isFilePath: Bool,
        extraArgs: [String],
        workingDirectory: String?,
        envVars: [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        let cmdString = buildSafeCommandString(target: target, isFilePath: isFilePath, extraArgs: extraArgs, workingDirectory: workingDirectory, envVars: envVars)
        let escapedForAppleScript = cmdString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escapedForAppleScript)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&err)
            let ok = (err == nil)
            if let err = err {
                runtimeLog("[LauncherExecutor] Admin execution failed or cancelled: \(err)")
            }
            DispatchQueue.main.async {
                completion(ok)
            }
        }
    }

    private static func runInTerminalApp(
        target: String,
        isFilePath: Bool,
        extraArgs: [String],
        workingDirectory: String?,
        envVars: [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        let cmdString = buildSafeCommandString(target: target, isFilePath: isFilePath, extraArgs: extraArgs, workingDirectory: workingDirectory, envVars: envVars)
        let escapedForAppleScript = cmdString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escapedForAppleScript)"
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&err)
            let ok = (err == nil)
            DispatchQueue.main.async {
                completion(ok)
            }
        }
    }

    /// Launches an application or opens a document file/folder cleanly using macOS modern APIs.
    /// Uses `NSWorkspace.openApplication` for `.app` bundles to avoid triggering false-positive
    /// `kTCCServiceSystemPolicyAppBundles` ("已阻止修改 Mac 上的 App") security alerts.
    public static func open(path: String, executionContext: ExecutionContext? = nil, completion: ((Bool) -> Void)? = nil) {
        let url = URL(fileURLWithPath: path)
        let isApp = url.pathExtension.caseInsensitiveCompare("app") == .orderedSame

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
                    DispatchQueue.main.async {
                        completion?(true)
                    }
                }
            }
        } else {
            // Y-11: Honor runAsAdmin, terminalMode, arguments, workingDirectory, and environmentVars for non-app targets
            if let ctx = executionContext, !ctx.isEmpty {
                let wd = ctx.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
                let validWD = (wd != nil && !wd!.isEmpty && FileManager.default.fileExists(atPath: wd!)) ? wd : nil

                if ctx.runAsAdmin {
                    runWithAdminPrivileges(target: path, isFilePath: true, extraArgs: ctx.arguments, workingDirectory: validWD, envVars: ctx.environmentVars) { ok in
                        completion?(ok)
                    }
                    return
                }
                if ctx.terminalMode == .launchTerminal {
                    runInTerminalApp(target: path, isFilePath: true, extraArgs: ctx.arguments, workingDirectory: validWD, envVars: ctx.environmentVars) { ok in
                        completion?(ok)
                    }
                    return
                }
                let hasProcessContext = !ctx.arguments.isEmpty || validWD != nil || !ctx.environmentVars.isEmpty
                if hasProcessContext && FileManager.default.isExecutableFile(atPath: path) {
                    let task = Process()
                    task.executableURL = url
                    task.arguments = ctx.arguments
                    if let validWD = validWD {
                        task.currentDirectoryURL = URL(fileURLWithPath: validWD)
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
