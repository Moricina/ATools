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
    private var registeredBindings: [HotKeyID: HotkeyBinding] = [:]
    private var specialBindings: [HotKeyID: HotkeySpecialTrigger] = [:]
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var lastModifierReleaseTime: [HotkeySpecialTrigger: TimeInterval] = [:]
    private var lastObservedModifierMask: NSEvent.ModifierFlags = []

    // Native CGEventTap for resilient modifier interception across recording sessions
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isModifierTainted: Bool = false
    private var lastCGModifierPressTime: [HotkeySpecialTrigger: TimeInterval] = [:]
    private var lastCGModifierReleaseTime: [HotkeySpecialTrigger: TimeInterval] = [:]
    private var lastObservedCGModifiers: CGEventFlags = []

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
        if binding.isUnassigned {
            unregister(id: id)
            return true
        }

        if registeredBindings[id] == binding {
            return true
        }

        let oldHotKeyRef = registeredHotkeys[id.rawValue]
        let oldSpecialBinding = specialBindings[id]

        if binding.specialTrigger != .none {
            if let ref = oldHotKeyRef {
                UnregisterEventHotKey(ref)
                registeredHotkeys.removeValue(forKey: id.rawValue)
            }
            specialBindings[id] = binding.specialTrigger
            registeredBindings[id] = binding
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
            if let oldHotKeyRef = oldHotKeyRef {
                UnregisterEventHotKey(oldHotKeyRef)
            }
            if oldSpecialBinding != nil {
                specialBindings.removeValue(forKey: id)
                if specialBindings.isEmpty {
                    teardownFlagsMonitors()
                }
            }
            registeredBindings[id] = binding
            return true
        } else {
            print("[HotkeyManager] Error registering HotKey \(id): \(status)")
            // RegisterEventHotKey failed, so the previous binding remains active.
            return false
        }
    }

    public func unregister(id: HotKeyID) {
        if let ref = registeredHotkeys.removeValue(forKey: id.rawValue) {
            UnregisterEventHotKey(ref)
        }
        specialBindings.removeValue(forKey: id)
        registeredBindings.removeValue(forKey: id)
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
        registeredBindings.removeAll()
        teardownFlagsMonitors()
    }

    private func setupFlagsMonitorsIfNeeded() {
        let trusted = HotkeyManager.isAccessibilityTrusted()
        if eventTap == nil && trusted {
            setupNativeEventTap()
        }
        // If eventTap could not be installed (e.g. accessibility permission not yet granted), fall back to AppKit monitors
        guard eventTap == nil else {
            runtimeLog("[HotkeyManager] special triggers: CGEventTap active (axTrusted=\(trusted))")
            if let m = globalFlagsMonitor {
                NSEvent.removeMonitor(m)
                globalFlagsMonitor = nil
            }
            if let m = localFlagsMonitor {
                NSEvent.removeMonitor(m)
                localFlagsMonitor = nil
            }
            return
        }

        // 兜底路径更敏感（阈值/状态机不同），失灵时优先怀疑权限而不是用户手速。
        runtimeLog("[HotkeyManager] special triggers: FALLBACK NSEvent monitors (axTrusted=\(trusted), eventTap=\(eventTap != nil))")

        if globalFlagsMonitor == nil {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleGlobalFlagsChanged(event: event)
            }
        }
        if localFlagsMonitor == nil {
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                if event.type == .keyDown {
                    self?.handleLocalKeyDown(event: event)
                } else if event.type == .flagsChanged {
                    self?.handleGlobalFlagsChanged(event: event)
                }
                return event
            }
        }
    }

    private func teardownFlagsMonitors() {
        teardownNativeEventTap()
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
        lastCGModifierPressTime.removeAll()
        lastCGModifierReleaseTime.removeAll()
        lastSpecialFireTime.removeAll()
    }

    private func setupNativeEventTap() {
        guard eventTap == nil else { return }
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            runtimeLog("[HotkeyManager] Failed to create CGEventTap, falling back to NSEvent monitors")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runtimeLog("[HotkeyManager] Successfully installed headInsert CGEventTap for special triggers")
    }

    private func teardownNativeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
                runLoopSource = nil
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        lastCGModifierPressTime.removeAll()
        lastCGModifierReleaseTime.removeAll()
        lastObservedCGModifiers = []
        isModifierTainted = false
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                runtimeLog("[HotkeyManager] Re-enabled CGEventTap after timeout/disable")
            }
            return Unmanaged.passUnretained(event)
        }

        guard !specialBindings.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        // 1. Any normal key press invalidates the candidate modifier double-tap sequence (e.g. Cmd+C, Cmd+Tab)
        if type == .keyDown {
            isModifierTainted = true
            lastCGModifierPressTime.removeAll()
            lastCGModifierReleaseTime.removeAll()
            runtimeLog("[Hotkey] candidate state: CLEARED by keyDown (another key pressed between taps)")
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let flags = event.flags
            let now = Date().timeIntervalSince1970
            let relevantFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
            let prevFlags = lastObservedCGModifiers.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])

            if !relevantFlags.isEmpty && prevFlags.isEmpty {
                // Key down transition for modifier
                var trigger: HotkeySpecialTrigger = .none
                if relevantFlags == .maskCommand { trigger = .doubleCommand }
                else if relevantFlags == .maskAlternate { trigger = .doubleOption }
                else if relevantFlags == .maskControl { trigger = .doubleControl }
                else if relevantFlags == .maskShift { trigger = .doubleShift }

                if trigger != .none {
                    isModifierTainted = false
                    lastCGModifierPressTime[trigger] = now
                    if let releaseTime = lastCGModifierReleaseTime[trigger], (now - releaseTime) < Self.doubleTapGap {
                        // Double tap matched!
                        fireSpecialTrigger(trigger, source: "cgTap")
                        lastCGModifierReleaseTime.removeValue(forKey: trigger)
                        lastCGModifierPressTime.removeValue(forKey: trigger)
                    } else if let releaseTime = lastCGModifierReleaseTime[trigger] {
                        runtimeLog("[Hotkey] \(trigger) NOT matched: gap \(Int((now - releaseTime) * 1000))ms > \(Int(Self.doubleTapGap * 1000))ms limit")
                        lastCGModifierReleaseTime.removeValue(forKey: trigger)
                        lastCGModifierPressTime.removeValue(forKey: trigger)
                    } else {
                        runtimeLog("[Hotkey] \(trigger) press #1 (candidate start)")
                    }
                }
            } else if relevantFlags.isEmpty && !prevFlags.isEmpty {
                // Key up transition
                var trigger: HotkeySpecialTrigger = .none
                if prevFlags == .maskCommand { trigger = .doubleCommand }
                else if prevFlags == .maskAlternate { trigger = .doubleOption }
                else if prevFlags == .maskControl { trigger = .doubleControl }
                else if prevFlags == .maskShift { trigger = .doubleShift }

                if trigger != .none {
                    if !isModifierTainted {
                        let pressTime = lastCGModifierPressTime[trigger] ?? 0
                        if pressTime > 0 {
                            let pressDuration = now - pressTime
                            if pressDuration < Self.doubleTapPress {
                                lastCGModifierReleaseTime[trigger] = now
                                runtimeLog("[Hotkey] \(trigger) release: candidate OK (press \(Int(pressDuration * 1000))ms)")
                            } else {
                                lastCGModifierReleaseTime.removeValue(forKey: trigger)
                                runtimeLog("[Hotkey] \(trigger) release: candidate DROPPED, held \(Int(pressDuration * 1000))ms ≥ \(Int(Self.doubleTapPress * 1000))ms limit")
                            }
                        } else {
                            // 触发成功后状态已清空：这是双击后半段的松开，忽略即可
                            //（否则会算出 now-0 的天文数字时长）。
                            runtimeLog("[Hotkey] \(trigger) release after fire, state already reset")
                        }
                    } else {
                        lastCGModifierReleaseTime.removeValue(forKey: trigger)
                        runtimeLog("[Hotkey] \(trigger) release: candidate DROPPED (tainted by intervening key)")
                    }
                }
                isModifierTainted = false
            } else if relevantFlags.isEmpty {
                isModifierTainted = false
            } else {
                // Multiple modifiers pressed simultaneously (e.g. Cmd+Shift) - cancel candidate
                isModifierTainted = true
                lastCGModifierReleaseTime.removeAll()
                lastCGModifierPressTime.removeAll()
            }
            lastObservedCGModifiers = relevantFlags
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleLocalKeyDown(event: NSEvent) {
        lastModifierReleaseTime.removeAll()
        lastModifierPressTime.removeAll()
        // CG 兑底检测器的状态也必须一并清理，否则两条路径的候选状态会不同步。
        lastCGModifierReleaseTime.removeAll()
        lastCGModifierPressTime.removeAll()
        isModifierTainted = true
    }

    // MARK: - 双击修饰键触发（统一出口）

    /// 双击判定参数（两套检测器统一，避免一条路径松一条紧）。
    /// press: 单次按住时长上限；gap: 两次松开-按下间隔上限。
    private static let doubleTapPress: TimeInterval = 0.30
    private static let doubleTapGap: TimeInterval = 0.50
    /// 同一次物理双击可能被两套检测器各报一次（监视器切换瞬间/事件重复投递）：
    /// 250ms 内的重复触发直接吞掉，否则会出现“开了一下又立刻自己关了”。
    private static let duplicateFireWindow: TimeInterval = 0.25

    private var lastSpecialFireTime: [HotkeySpecialTrigger: TimeInterval] = [:]

    private func fireSpecialTrigger(_ trigger: HotkeySpecialTrigger, source: String) {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastSpecialFireTime[trigger], now - last < Self.duplicateFireWindow {
            runtimeLog("[HotkeyManager] duplicate \(trigger) from \(source) suppressed (\(Int((now - last) * 1000))ms after previous)")
            return
        }
        lastSpecialFireTime[trigger] = now
        runtimeLog("[HotkeyManager] fireSpecial \(trigger) source=\(source) t=\(String(format: "%.3f", now))")
        for (id, spec) in specialBindings where spec == trigger {
            DispatchQueue.main.async { [weak self] in
                self?.onHotKeyTriggered?(id)
            }
        }
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
                if let releaseTime = lastModifierReleaseTime[trigger], (now - releaseTime) < Self.doubleTapGap {
                    // Double tap matched!
                    fireSpecialTrigger(trigger, source: "nsevent")
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
                // Only register as candidate tap if it was a quick light tap
                // This cleanly filters out Cmd+C, Cmd+V, Cmd+Tab where Command is held
                if pressDuration < Self.doubleTapPress {
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

    /// 清空修饰键候选态与临时时序，防止外部手势或点击造成双击修饰键判定残留半态
    public func resetCandidateState() {
        lastCGModifierPressTime.removeAll()
        lastCGModifierReleaseTime.removeAll()
        lastModifierPressTime.removeAll()
        lastModifierReleaseTime.removeAll()
        isModifierTainted = false
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
        // Called on every app activation (i.e. every panel show). Only rebuild when the
        // CGEventTap is missing but permission has since been granted.
        guard eventTap == nil, HotkeyManager.isAccessibilityTrusted() else { return }
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
