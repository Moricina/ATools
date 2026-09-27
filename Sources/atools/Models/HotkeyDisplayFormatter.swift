import Carbon
import Foundation

/// Resolves shortcut key names against the active keyboard layout. Physical key codes are
/// intentionally not mapped to American QWERTY letters in application code.
public enum HotkeyDisplayFormatter {
    public static func displayString(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        specialTrigger: HotkeySpecialTrigger = .none,
        characters: String? = nil
    ) -> String {
        guard specialTrigger == .none else { return specialTrigger.displayPrefix }

        var display = ""
        if carbonModifiers & UInt32(controlKey) != 0 { display += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { display += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { display += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { display += "⌘" }
        return display + keyName(keyCode: keyCode, characters: characters)
    }

    public static func keyName(keyCode: UInt32, characters: String? = nil) -> String {
        if let translated = translate(keyCode: keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        if let chars = characters?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return chars.uppercased()
        }

        // Named keys are hardware/layout independent; printable keys use the active layout above.
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51, 117: return "Delete"
        case 53: return "Esc"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key(\(keyCode))"
        }
    }

    private static func translate(keyCode: UInt32) -> String? {
        guard keyCode <= UInt32(UInt16.max),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { bytes -> String? in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var unicode = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                unicode.count,
                &actualLength,
                &unicode
            )
            guard status == noErr, actualLength > 0 else { return nil }
            return String(utf16CodeUnits: unicode, count: actualLength)
        }
    }
}
