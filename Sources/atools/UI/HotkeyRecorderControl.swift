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
        layer?.cornerRadius = 8
        layer?.borderWidth = 0

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
            heightAnchor.constraint(equalToConstant: SettingsPillButton.height)
        ])

        setAccessibilityRole(.button)
        setAccessibilityLabel("快捷键录制控件")
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

    /// Filled field, no outline (the old 0.75pt separator border read as a hard black line).
    /// Colours are resolved explicitly per appearance: `cgColor` of a dynamic system colour is
    /// frozen at the moment it's read and doesn't follow light/dark changes.
    private func updateDisplay() {
        let isDark = glassIsDark
        if isRecording {
            titleLabel.stringValue = "请按下快捷键，或连按两下修饰键"
            titleLabel.textColor = .controlAccentColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.28 : 0.16).cgColor
        } else {
            if let binding = currentBinding, !binding.displayString.isEmpty {
                titleLabel.stringValue = binding.displayString
                titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
            } else {
                titleLabel.stringValue = "点击录制快捷键"
                titleLabel.textColor = GlassPalette.textTertiary(isDark: isDark)
            }
            let alpha: CGFloat = isHovered ? (isDark ? 0.18 : 0.10) : (isDark ? 0.12 : 0.06)
            layer?.backgroundColor = (isDark ? NSColor(white: 1.0, alpha: alpha) : NSColor(white: 0.0, alpha: alpha)).cgColor
        }
        alphaValue = isEnabled ? 1.0 : 0.45
    }

    private var isHovered = false {
        didSet { if oldValue != isHovered { updateDisplay() } }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) { isHovered = true }
    override public func mouseExited(with event: NSEvent) { isHovered = false }

    override public var isEnabled: Bool {
        didSet { updateDisplay() }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDisplay()
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

        let display = HotkeyDisplayFormatter.displayString(
            keyCode: keyCode,
            carbonModifiers: carbonMods,
            characters: event.charactersIgnoringModifiers
        )

        let newBinding = HotkeyBinding(keyCode: keyCode, carbonModifiers: carbonMods, displayString: display)
        currentBinding = newBinding
        stopRecording()
        onChange?(newBinding)
        return true
    }

    deinit {
        stopRecording()
    }
}
