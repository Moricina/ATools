import Foundation
import AppKit

public final class VisualEffectBackdropView: NSView {
    private let effectView = NSVisualEffectView()
    private let tintOverlayView = NSView()

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupHierarchy() {
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        // 1. Core popover material with behindWindow blending for frosted glass effect
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        // 2. Adaptive opacity tint overlay
        tintOverlayView.wantsLayer = true
        tintOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tintOverlayView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tintOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintOverlayView.topAnchor.constraint(equalTo: topAnchor),
            tintOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 3. Rim highlight border (delicate physical boundary)
        layer?.borderWidth = 0.5
        updateAppearanceColors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: .atoolsThemeDidChange,
            object: nil
        )
    }

    @objc private func handleThemeChanged() {
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        let theme = ConfigManager.shared.config.theme
        let opacity = ConfigManager.shared.config.themeOpacity
        let isDark = theme.isDark

        // Propagate appearance to self and window so subviews adapt
        self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        layer?.borderWidth = 0.5

        if theme.isLiquid {
            effectView.isHidden = false
            effectView.material = .popover
            effectView.state = .active
            effectView.alphaValue = 1.0 // Keep physical Gaussian blur fully active

            // Regulate translucency through the tint overlay layer with themeOpacity
            let tintAlpha = CGFloat(opacity * (isDark ? 0.70 : 0.80))
            if isDark {
                tintOverlayView.layer?.backgroundColor = NSColor(white: 0.10, alpha: tintAlpha).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.15 * CGFloat(opacity)).cgColor
            } else {
                tintOverlayView.layer?.backgroundColor = NSColor(white: 0.98, alpha: tintAlpha).cgColor
                layer?.borderColor = NSColor(white: 0.0, alpha: 0.09 * CGFloat(opacity)).cgColor
            }
        } else {
            // Solid theme (sleek acrylic): 0.5pt delicate physical stroke
            effectView.isHidden = true
            let solidAlpha = CGFloat(opacity)
            if isDark {
                tintOverlayView.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: solidAlpha).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            } else {
                tintOverlayView.layer?.backgroundColor = NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: solidAlpha).cgColor
                layer?.borderColor = NSColor(white: 0.0, alpha: 0.09).cgColor
            }
        }

        window?.invalidateShadow()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceColors()
        window?.invalidateShadow()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
        window?.invalidateShadow()
    }
}
