import Foundation
import AppKit

/// The primary glass backdrop for both panels.
///
/// This leans on the system's own liquid-glass stack (`NSVisualEffectView`)
/// instead of hand-rolled layers. The semantic materials drive the blur,
/// saturation and translucency exactly like macOS panels, while a thin tint
/// overlay only adds the dreamy rose-purple wash on top.
public final class VisualEffectBackdropView: NSView {
    override public var isFlipped: Bool { true }

    private let effectView = LiquidGlassContainerView()
    private let tintOverlayView = NSView()

    /// Match the standalone search capsule exactly when this backdrop hosts
    /// expanded search results. Other panels keep their theme-opacity profile.
    public var matchesSearchCapsuleAppearance: Bool = false {
        didSet {
            guard oldValue != matchesSearchCapsuleAppearance else { return }
            updateAppearanceColors()
        }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupHierarchy() {
        wantsLayer = true

        // Clip every child (system glass, tint, content) to the same rounded
        // silhouette so no square corners can peek out behind the glass.
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        // The true liquid-glass surface is the visual anchor.
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        // A very thin tint sits above the system material to tint the glass
        // toward the dreamy deep-purple palette without hiding the blur.
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
        let opacity = CGFloat(ConfigManager.shared.config.themeOpacity)
        let isDark = theme.isDark

        self.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // Corner radius: larger, glassier panel for the liquid look.
        let radius: CGFloat = matchesSearchCapsuleAppearance ? 20 : 24
        layer?.cornerRadius = radius
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        effectView.cornerRadius = radius
        effectView.usesRegularGlass = true

        effectView.isHidden = false

        if matchesSearchCapsuleAppearance {
            // The search capsule uses this exact glass tint at full surface
            // opacity. Keeping the expanded sheet on the same profile prevents
            // its dark base from being lifted toward gray by the backdrop.
            effectView.alphaValue = 1.0
            if isDark {
                effectView.tintColor = GlassPalette.darkBaseTop
                effectView.tintOpacity = 0.82
            } else {
                effectView.tintColor = GlassPalette.lightGlassTint
                effectView.tintOpacity = 0.66
            }
            tintOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
            window?.invalidateShadow()
            return
        }

        effectView.alphaValue = opacity

        if isDark {
            effectView.tintColor = GlassPalette.darkBaseTop
            effectView.tintOpacity = 0.76
            tintOverlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08 * opacity).cgColor
        } else {
            effectView.tintColor = GlassPalette.lightGlassTint
            effectView.tintOpacity = 0.58
            tintOverlayView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06 * opacity).cgColor
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
