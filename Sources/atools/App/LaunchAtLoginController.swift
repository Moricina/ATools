import Foundation
import AppKit
import ServiceManagement

/// Reads and mutates the macOS login-item registration for the running app.
public final class LaunchAtLoginController {
    public static let shared = LaunchAtLoginController()

    public enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unsupported
    }

    private init() {}

    public var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    public var state: State {
        guard isSupported else { return .unsupported }
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                return .disabled
            @unknown default:
                return .unsupported
            }
        }
        return .unsupported
    }

    public var isEnabled: Bool {
        return state == .enabled
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) throws -> State {
        guard isSupported else { return .unsupported }
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return state
        }
        return .unsupported
    }

    /// Opens the macOS Login Items pane so the user can approve or inspect registration.
    public func openLoginItemsSettings() {
        if #available(macOS 13.0, *), let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
            return
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
