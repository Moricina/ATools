import Foundation
import AppKit
import Carbon

public final class HotkeyRecorderControl: NSControl {
    public var currentBinding: HotkeyBinding? {
        didSet {
            updateDisplay()
        }
    }

    public var onChange: ((HotkeyBinding) -> Void)?
    public var onClear: (() -> Void)?

    private var isRecording: Bool = false {
        didSet {
            needsDisplay = true
            updateDisplay()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private var localMonitor: Any?

    // Double modifier recording state machine
    private var lastCandidateTrigger: HotkeySpecialTrigger = .none
    private var lastCandidateReleaseTime: TimeInterval = 0
    private var lastActiveModifierMask: NSEvent.ModifierFlags = []

    override public var acceptsFirstResponder: Bool { true }
    override public var canBecomeKeyView: Bool { true }

    public init(binding: HotkeyBinding? = nil, frame frameRect: NSRect = .zero) {
        self.currentBinding = binding
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1.0

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.isSelectable = false
        titleLabel.isEditable = false
        titleLabel.refusesFirstResponder = true
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26)
        ])

        updateDisplay()
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        if super.hitTest(point) != nil {
            return self
        }
        return nil
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    private func updateDisplay() {
        if isRecording {
            titleLabel.stringValue = "请按下快捷键或连按两下Command"
            titleLabel.textColor = .controlAccentColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        } else {
            if let binding = currentBinding, !binding.displayString.isEmpty {
                titleLabel.stringValue = binding.displayString
                titleLabel.textColor = .labelColor
            } else {
                titleLabel.stringValue = "点击录制快捷键"
                titleLabel.textColor = .tertiaryLabelColor
            }
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.08).cgColor
        }
    }

    override public func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }

    public func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        lastCandidateTrigger = .none
        lastCandidateReleaseTime = 0
        lastActiveModifierMask = []
        window?.makeFirstResponder(self)

        // Temporarily pause global hotkey registration so keys are received by local monitors
        HotkeyManager.shared.pauseHotkeys()

        // Install local monitor to capture both keyDown and flagsChanged events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            if event.type == .flagsChanged {
                if self.handleFlagsChanged(event) {
                    return nil
                }
            } else if event.type == .keyDown {
                if self.handleKeyEvent(event) {
                    return nil
                }
            }
            return event
        }
    }

    public func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        lastCandidateTrigger = .none
        lastCandidateReleaseTime = 0
        lastActiveModifierMask = []
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        // Restore global hotkeys
        HotkeyManager.shared.resumeHotkeys()
    }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording {
            return handleKeyEvent(event)
        }
        return super.performKeyEquivalent(with: event)
    }

    override public func keyDown(with event: NSEvent) {
        if isRecording {
            _ = handleKeyEvent(event)
            return
        }
        super.keyDown(with: event)
    }

    override public func flagsChanged(with event: NSEvent) {
        if isRecording {
            _ = handleFlagsChanged(event)
            return
        }
        super.flagsChanged(with: event)
    }

    override public func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let currentFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let now = Date().timeIntervalSince1970

        // Determine if a single modifier is pressed down
        if !currentFlags.isEmpty && lastActiveModifierMask.isEmpty {
            // Key Down transition for a modifier
            var trigger: HotkeySpecialTrigger = .none
            if currentFlags == .command { trigger = .doubleCommand }
            else if currentFlags == .option { trigger = .doubleOption }
            else if currentFlags == .control { trigger = .doubleControl }
            else if currentFlags == .shift { trigger = .doubleShift }

            if trigger != .none && trigger == lastCandidateTrigger && (now - lastCandidateReleaseTime) < 0.38 {
                // Detected double-tap!
                let binding = HotkeyBinding(
                    keyCode: 0,
                    carbonModifiers: 0,
                    displayString: trigger.displayPrefix,
                    specialTrigger: trigger
                )
                currentBinding = binding
                stopRecording()
                onChange?(binding)
                return true
            }
            lastActiveModifierMask = currentFlags
        } else if currentFlags.isEmpty && !lastActiveModifierMask.isEmpty {
            // Key Up transition for a modifier
            if lastActiveModifierMask == .command { lastCandidateTrigger = .doubleCommand }
            else if lastActiveModifierMask == .option { lastCandidateTrigger = .doubleOption }
            else if lastActiveModifierMask == .control { lastCandidateTrigger = .doubleControl }
            else if lastActiveModifierMask == .shift { lastCandidateTrigger = .doubleShift }
            else { lastCandidateTrigger = .none }

            lastCandidateReleaseTime = now
            lastActiveModifierMask = []
        } else {
            lastActiveModifierMask = currentFlags
        }

        return false
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Any real key cancels double-modifier candidate
        lastCandidateTrigger = .none
        lastCandidateReleaseTime = 0
        lastActiveModifierMask = []
        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // 1. Esc with no modifiers cancels recording
        if keyCode == 53 && flags.isEmpty {
            stopRecording()
            return true
        }

        // 2. Delete / Backspace with no modifiers clears shortcut
        if (keyCode == 51 || keyCode == 117) && flags.isEmpty {
            currentBinding = nil
            stopRecording()
            onClear?()
            return true
        }

        // 3. Safety Guard: Is it an F-key (F1-F12)?
        let isFunctionKey = (keyCode >= 96 && keyCode <= 101) ||
                            (keyCode == 103) || (keyCode == 109) ||
                            (keyCode == 111) || (keyCode == 118) ||
                            (keyCode == 120) || (keyCode == 122)

        // Ordinary keys MUST have at least Command, Option, or Control
        let hasPrimaryModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        if !isFunctionKey && !hasPrimaryModifier {
            NSSound.beep()
            return true
        }

        // 4. Convert modifiers to Carbon modifiers
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbonMods |= UInt32(shiftKey) }

        // 5. Build human-readable display string
        var display = ""
        if flags.contains(.control) { display += "⌃" }
        if flags.contains(.option)  { display += "⌥" }
        if flags.contains(.shift)   { display += "⇧" }
        if flags.contains(.command) { display += "⌘" }
        display += keyString(for: keyCode, characters: event.charactersIgnoringModifiers)

        let newBinding = HotkeyBinding(keyCode: keyCode, carbonModifiers: carbonMods, displayString: display)
        currentBinding = newBinding
        stopRecording()
        onChange?(newBinding)
        return true
    }

    private func keyString(for keyCode: UInt32, characters: String?) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let chars = characters?.uppercased(), !chars.isEmpty {
                return chars
            }
            return "Key(\(keyCode))"
        }
    }

    deinit {
        stopRecording()
    }
}
