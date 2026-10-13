import Foundation
import AppKit

/// Monochrome visual tokens for the product UI.
enum GlassPalette {
    static let darkBaseTop = NSColor(white: 0.12, alpha: 1.0)
    static let darkBaseBottom = NSColor(white: 0.075, alpha: 1.0)
    static let lightGlassTint = NSColor(white: 1.0, alpha: 1.0)
    static let lightGlassTintBright = NSColor(white: 1.0, alpha: 1.0)
    static let lightHoverFill = NSColor(white: 0.0, alpha: 0.045)
    static let lightSelectedFill = NSColor(white: 0.0, alpha: 0.075)
    static let lightPressedFill = NSColor(white: 0.0, alpha: 0.11)

    static func textPrimary(isDark: Bool) -> NSColor {
        return isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1.0) // #1D1D1F
    }

    static func textSecondary(isDark: Bool) -> NSColor {
        return isDark ? NSColor(white: 1.0, alpha: 0.78) : NSColor(white: 0.0, alpha: 0.55)
    }

    static func textTertiary(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 1.0, alpha: 0.60) : NSColor(white: 0.0, alpha: 0.38)
    }

    static func panelBorder(isDark: Bool) -> NSColor {
        if ConfigManager.shared.config.theme.isNativeLiquid {
            return isDark ? NSColor(white: 1.0, alpha: 0.22) : NSColor(white: 0.0, alpha: 0.15)
        }
        return isDark ? NSColor(white: 1.0, alpha: 0.12) : NSColor(white: 0.0, alpha: 0.10)
    }

    static func controlFill(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 1.0, alpha: 0.075) : NSColor(white: 0.0, alpha: 0.045)
    }

    static func controlHoverFill(isDark: Bool) -> NSColor {
        if ConfigManager.shared.config.theme.isNativeLiquid {
            return isDark ? NSColor(white: 1.0, alpha: 0.10) : NSColor(white: 0.0, alpha: 0.06)
        }
        return isDark ? NSColor(white: 1.0, alpha: 0.06) : lightHoverFill
    }

    static func selectedFill(isDark: Bool) -> NSColor {
        if ConfigManager.shared.config.theme.isNativeLiquid {
            return isDark ? NSColor(white: 1.0, alpha: 0.18) : NSColor(white: 0.0, alpha: 0.10)
        }
        return isDark ? NSColor(white: 1.0, alpha: 0.12) : lightSelectedFill
    }

    static func pressedFill(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 1.0, alpha: 0.18) : lightPressedFill
    }

    static func dropTargetFill(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 1.0, alpha: 0.14) : NSColor(white: 0.0, alpha: 0.09)
    }

    static func shadowColor(isDark: Bool) -> NSColor {
        isDark ? NSColor.black.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.12)
    }

    static func accentFill(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 1.0, alpha: 0.16) : NSColor(white: 0.0, alpha: 0.10)
    }

    static func accentText(isDark: Bool) -> NSColor {
        textPrimary(isDark: isDark)
    }
}

extension NSView {
    /// Convenience check used across all glass-styled controls.
    var glassIsDark: Bool {
        if let win = window {
            let app = win.appearance ?? win.effectiveAppearance
            return app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let app = NSApp?.effectiveAppearance ?? effectiveAppearance
        if let match = app.bestMatch(from: [.darkAqua, .aqua]) {
            return match == .darkAqua
        }
        return ConfigManager.shared.config.theme.isDark
    }

    var isNativeLiquidTheme: Bool {
        ConfigManager.shared.config.theme.isNativeLiquid
    }
}
