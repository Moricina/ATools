import Foundation
import Carbon
import AppKit
import ApplicationServices

public enum HotKeyID: UInt32 {
    case shelf = 1
    case search = 2
}

public final class HotkeyManager {
    public static let shared = HotkeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotkeys: [UInt32: EventHotKeyRef] = [:]
    private var specialBindings: [HotKeyID: HotkeySpecialTrigger] = [:]
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var lastModifierReleaseTime: [HotkeySpecialTrigger: TimeInterval] = [:]
    private var lastObservedModifierMask: NSEvent.ModifierFlags = []

    public var onHotKeyTriggered: ((HotKeyID) -> Void)?

    private init() {
        installCarbonEventHandler()
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.signature == OSType(0x41544F4C) {
                if let identified = HotKeyID(rawValue: hotKeyID.id) {
                    DispatchQueue.main.async {
                        HotkeyManager.shared.onHotKeyTriggered?(identified)
                    }
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    public func registerDefaultHotkeys() {
        let config = ConfigManager.shared.config
        if config.enableShelfPanel {
            register(id: .shelf, binding: config.shelfHotkey)
        } else {
            unregister(id: .shelf)
        }
        if config.enableSearchPanel {
            register(id: .search, binding: config.searchHotkey)
        } else {
            unregister(id: .search)
        }
    }

    @discardableResult
    public func register(id: HotKeyID, binding: HotkeyBinding) -> Bool {
        // Clear any old Carbon or special binding for this id
        unregister(id: id)

        if binding.specialTrigger != .none {
            specialBindings[id] = binding.specialTrigger
            setupFlagsMonitorsIfNeeded()
            return true
        }

        var gHotKeyID = EventHotKeyID()
        gHotKeyID.signature = OSType(0x41544F4C) // "ATOL"
        gHotKeyID.id = id.rawValue

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            gHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            registeredHotkeys[id.rawValue] = ref
            return true
        } else {
            print("[HotkeyManager] Error registering HotKey \(id): \(status)")
            return false
        }
    }

    public func unregister(id: HotKeyID) {
        if let ref = registeredHotkeys.removeValue(forKey: id.rawValue) {
            UnregisterEventHotKey(ref)
        }
        specialBindings.removeValue(forKey: id)
        if specialBindings.isEmpty {
            teardownFlagsMonitors()
        }
    }

    public func unregisterAll() {
        for (_, ref) in registeredHotkeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotkeys.removeAll()
        specialBindings.removeAll()
        teardownFlagsMonitors()
    }

    private func setupFlagsMonitorsIfNeeded() {
        if globalFlagsMonitor == nil {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleGlobalFlagsChanged(event: event)
            }
        }
        if localFlagsMonitor == nil {
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleGlobalFlagsChanged(event: event)
                return event
            }
        }
    }

    private func teardownFlagsMonitors() {
        if let m = globalFlagsMonitor {
            NSEvent.removeMonitor(m)
            globalFlagsMonitor = nil
        }
        if let m = localFlagsMonitor {
            NSEvent.removeMonitor(m)
            localFlagsMonitor = nil
        }
        lastModifierPressTime.removeAll()
        lastModifierReleaseTime.removeAll()
        lastObservedModifierMask = []
    }

    private var lastModifierPressTime: [HotkeySpecialTrigger: TimeInterval] = [:]

    private func handleGlobalFlagsChanged(event: NSEvent) {
        guard !specialBindings.isEmpty else { return }
        let currentFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let now = Date().timeIntervalSince1970

        if !currentFlags.isEmpty && lastObservedModifierMask.isEmpty {
            // Key Down transition for a modifier
            var trigger: HotkeySpecialTrigger = .none
            if currentFlags == .command { trigger = .doubleCommand }
            else if currentFlags == .option { trigger = .doubleOption }
            else if currentFlags == .control { trigger = .doubleControl }
            else if currentFlags == .shift { trigger = .doubleShift }

            if trigger != .none {
                lastModifierPressTime[trigger] = now
                if let releaseTime = lastModifierReleaseTime[trigger], (now - releaseTime) < 0.38 {
                    // Double tap matched!
                    for (id, spec) in specialBindings where spec == trigger {
                        DispatchQueue.main.async { [weak self] in
                            self?.onHotKeyTriggered?(id)
                        }
                    }
                    lastModifierReleaseTime.removeValue(forKey: trigger)
                    lastModifierPressTime.removeValue(forKey: trigger)
                }
            }
            lastObservedModifierMask = currentFlags
        } else if currentFlags.isEmpty && !lastObservedModifierMask.isEmpty {
            // Key Up transition
            var trigger: HotkeySpecialTrigger = .none
            if lastObservedModifierMask == .command { trigger = .doubleCommand }
            else if lastObservedModifierMask == .option { trigger = .doubleOption }
            else if lastObservedModifierMask == .control { trigger = .doubleControl }
            else if lastObservedModifierMask == .shift { trigger = .doubleShift }

            if trigger != .none {
                let pressTime = lastModifierPressTime[trigger] ?? 0
                let pressDuration = now - pressTime
                // Only register as candidate tap if it was a quick light tap (< 220ms)
                // This cleanly filters out Cmd+C, Cmd+V, Cmd+Tab where Command is held
                if pressDuration < 0.22 {
                    lastModifierReleaseTime[trigger] = now
                } else {
                    lastModifierReleaseTime.removeValue(forKey: trigger)
                }
            }
            lastObservedModifierMask = []
        } else {
            // Multiple modifiers pressed simultaneously (e.g. Cmd+Shift) - cancel candidate
            lastModifierReleaseTime.removeAll()
            lastModifierPressTime.removeAll()
            lastObservedModifierMask = currentFlags
        }
    }

    public func pauseHotkeys() {
        unregisterAll()
    }

    public func resumeHotkeys() {
        registerDefaultHotkeys()
    }

    /// Checks whether macOS native Spotlight shortcut (Cmd+Space) is currently enabled in system preferences
    public func isSpotlightShortcutEnabled() -> Bool {
        let plistPath = ("~/Library/Preferences/com.apple.symbolichotkeys.plist" as NSString).expandingTildeInPath
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
              let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }

        // 64 is Spotlight search bar, 65 is Spotlight finder search
        if let key64 = hotkeys["64"] as? [String: Any],
           let enabled = key64["enabled"] as? Bool, enabled {
            return true
        }
        return false
    }

    /// Opens macOS System Settings -> Keyboard -> Keyboard Shortcuts
    public func openSystemKeyboardSettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        let script = "tell application \"System Preferences\"\nactivate\nset current pane to pane id \"com.apple.preference.keyboard\"\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// 检查 macOS 辅助功能 (Accessibility) 权限状态
    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 打开系统偏好设置 -> 隐私与安全性 -> 辅助功能
    public static func openAccessibilitySettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        let script = "tell application \"System Preferences\"\nactivate\nset current pane to pane id \"com.apple.preference.security\"\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// 触发系统底层的辅助功能授权引导弹窗
    public static func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 在应用重新激活时，刷新全局修饰键监视器
    public func reloadFlagsMonitorsIfTrusted() {
        guard !specialBindings.isEmpty else { return }
        teardownFlagsMonitors()
        setupFlagsMonitorsIfNeeded()
    }

    deinit {
        unregisterAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
