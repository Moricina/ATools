import Foundation
import AppKit
import CoreServices

#if DEBUG || DIAGNOSTIC_MODE
if CommandLine.arguments.contains("--test") {
    do {
        try DiagnosticSuite.run()
        exit(0)
    } catch {
        print("[DiagnosticSuite] Unhandled error: \(error)")
        exit(1)
    }
}
#else
if CommandLine.arguments.contains("--test") {
    fputs("ATools 生产版本未打包诊断套件。请使用开发构建或携带 -DDIAGNOSTIC_MODE 编译以运行诊断。\n", stderr)
    exit(1)
}
#endif

// Maintenance flag (no UI): inspect or flip login-item registration for *this* bundle path.
// The system keys SMAppService.mainApp items by the running app's bundle, so a dev copy
// and the installed copy register separately; running this flag per copy lets us clean up
// stale duplicates: `ATools --login-item [status|register|unregister]`
if CommandLine.arguments.contains("--login-item") {
    let action = CommandLine.arguments.dropFirst().last { $0 != "--login-item" } ?? "status"
    let controller = LaunchAtLoginController.shared
    do {
        switch action {
        case "register":
            try controller.setEnabled(true)
        case "unregister":
            try controller.setEnabled(false)
        case "status":
            break
        default:
            fputs("usage: ATools --login-item [status|register|unregister]\n", stderr)
            exit(2)
        }
        print("[login-item] bundle=\(Bundle.main.bundlePath) state=\(controller.state)")
    } catch {
        fputs("[login-item] \(action) failed: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

// 全局异常与致命信号防御：捕获 Objective-C 未捕获异常与致命信号，输出追踪信息并防范静默闪退
NSSetUncaughtExceptionHandler { exception in
    let callStack = exception.callStackSymbols.joined(separator: "\n")
    let msg = "[CRASH] Uncaught NSException: \(exception.name.rawValue): \(exception.reason ?? "no reason")\n\(callStack)"
    fputs("\(msg)\n", stderr)
    runtimeLog(msg)
}

for sig in [SIGSEGV, SIGBUS, SIGABRT, SIGILL] {
    signal(sig) { signum in
        let msg = "[CRASH] Received fatal signal \(signum)"
        fputs("\(msg)\n", stderr)
        runtimeLog(msg)
        signal(signum, SIG_DFL)
        raise(signum)
    }
}

// 单实例互斥与自愈守护：
// 1. 若检测到卡死/半启动的僵尸 ATools 实例 (isFinishedLaunching == false)，强制清除以释放端口与锁；
// 2. 若已有稳定运行的健康 ATools 实例，绝对不自相残杀！发送广播让已有实例唤起界面，当前重复进程优雅退出。
do {
    let myPid = getpid()
    var healthyInstanceFound = false
    for running in NSWorkspace.shared.runningApplications {
        let pid = running.processIdentifier
        guard pid != myPid, pid > 0 else { continue }
        let bid = running.bundleIdentifier ?? ""
        let name = running.localizedName ?? ""
        let execName = running.executableURL?.lastPathComponent ?? ""
        if bid == "cc.atools.app" || bid == "cc.atools.app.dev" || name == "ATools" || execName == "ATools" {
            if !running.isFinishedLaunching {
                // 僵尸或未完成启动的假死实例：清除以保证后续干净接管
                _ = kill(pid, SIGKILL)
            } else {
                // 已经有健康活跃的主实例在运行：唤醒已有实例并展示 UI，当前进程功成身退
                healthyInstanceFound = true
                running.activate(options: [.activateIgnoringOtherApps])
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("cc.atools.showUI"),
                    object: "\(myPid)",
                    userInfo: nil,
                    deliverImmediately: true
                )
                break
            }
        }
    }
    if healthyInstanceFound {
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
