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
        layer?.masksToBounds = true
        effectView.cornerRadius = radius
        effectView.usesRegularGlass = true
        effectView.isDark = isDark
        effectView.isNativeLiquid = theme.isNativeLiquid
        effectView.isHidden = false

        if theme.isNativeLiquid {
            // 🌟 原生液态模式（应用抽屉与搜索大面板均采用此 100% 水滴透镜）🌟
            effectView.alphaValue = 1.0
            tintOverlayView.layer?.backgroundColor = NSColor.clear.cgColor

            if isDark {
                // 原生液态 (深色)：深邃黑曜石微熏透镜，联动 themeOpacity 滑块 (40% ~ 100%)
                // 40% 时保留 0.22 基础微熏黑曜石浓度与暗色底衬，配合纯水滴透镜 (Glass.clear)，既能晶莹透出底层桌面，又具备纯正深色底蕴
                // 100% 时浓度平滑升至 0.72，暗色底衬同步增至 0.68，有效遮蔽背景杂色，确保文字清晰聚焦
                let progress = max(0.0, min(1.0, (ConfigManager.shared.config.themeOpacity - 0.40) / 0.60))
                let dynamicTintOpacity = CGFloat(0.22 + 0.50 * pow(progress, 1.20))
                effectView.tintColor = NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)
                effectView.tintOpacity = dynamicTintOpacity
            } else {
                // 原生液态 (浅色)：纯白水滴透光透镜，联动 themeOpacity 滑块 (40% ~ 100%)
                // 40% 时保留 0.08 基础纯白水滴通透折射 (Glass.clear)，白底晶莹通透，透出底层桌面与应用窗口；
                // 100% 时浓度平滑升至 0.65，配合 Glass.regular 漫射与纯白底衬，有效遮蔽杂乱背景，确保文字高对比度与清晰度
                let progress = max(0.0, min(1.0, (ConfigManager.shared.config.themeOpacity - 0.40) / 0.60))
                let dynamicTintOpacity = CGFloat(0.08 + 0.57 * pow(progress, 1.15))
                effectView.tintColor = NSColor.white
                effectView.tintOpacity = dynamicTintOpacity
            }
            window?.invalidateShadow()
            return
        }

        if matchesSearchCapsuleAppearance {
            // The expanded sheet uses the emphasized search-capsule profile.
            // Opacity is applied only to the decorative glass layer, leaving
            // result text at full contrast.
            let profile = SearchGlassSurfaceProfile.resolved(
                isDark: isDark,
                isEmphasized: true,
                themeOpacity: ConfigManager.shared.config.themeOpacity
            )
            effectView.alphaValue = profile.surfaceAlpha
            effectView.tintColor = profile.tintColor
            effectView.tintOpacity = profile.tintOpacity
            if !isDark {
                // 🌟 液态玻璃 (浅色) 纯白通透磨砂：配合白底微光底衬，消除暗沉杂色，纯净明亮 🌟
                tintOverlayView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.20 * opacity).cgColor
            } else {
                tintOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
            }
            window?.invalidateShadow()
            return
        }

        effectView.alphaValue = opacity

        if isDark {
            // 恢复液态玻璃（深色）先前的磨砂质感
            effectView.tintColor = GlassPalette.darkBaseTop
            effectView.tintOpacity = 0.76
            tintOverlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08 * opacity).cgColor
        } else {
            // 🌟 液态玻璃 (浅色) 纯白通透磨砂质感 🌟
            effectView.tintColor = GlassPalette.lightGlassTint
            effectView.tintOpacity = 0.85
            tintOverlayView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.20 * opacity).cgColor
        }

        window?.invalidateShadow()
    }

    override public func layout() {
        super.layout()
        let radius: CGFloat = matchesSearchCapsuleAppearance ? 20 : 24
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        effectView.cornerRadius = radius
        effectView.layer?.cornerRadius = radius
        effectView.layer?.masksToBounds = true
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
