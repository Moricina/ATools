import Foundation
import AppKit
import SwiftUI

/// Shared visual profile for the search capsule and its expanded result sheet.
/// Keeping the recipe here prevents the collapsed and expanded surfaces from
/// drifting apart while still allowing the configured panel opacity to fade
/// only the glass, never the text or controls above it.
struct SearchGlassSurfaceProfile {
    let tintColor: NSColor
    let tintOpacity: CGFloat
    let surfaceAlpha: CGFloat

    private static let darkBaseTintOpacity: CGFloat = 0.76
    private static let darkEmphasizedTintOpacity: CGFloat = 0.82
    private static let lightBaseTintOpacity: CGFloat = 0.85
    private static let lightEmphasizedTintOpacity: CGFloat = 0.92

    static func resolved(isDark: Bool, isEmphasized: Bool, themeOpacity: Double) -> SearchGlassSurfaceProfile {
        let clampedOpacity = CGFloat(max(0.40, min(1.00, themeOpacity)))
        if isDark {
            return SearchGlassSurfaceProfile(
                tintColor: GlassPalette.darkBaseTop,
                tintOpacity: isEmphasized ? darkEmphasizedTintOpacity : darkBaseTintOpacity,
                surfaceAlpha: clampedOpacity
            )
        }
        return SearchGlassSurfaceProfile(
            tintColor: GlassPalette.lightGlassTint,
            tintOpacity: isEmphasized ? lightEmphasizedTintOpacity : lightBaseTintOpacity,
            surfaceAlpha: clampedOpacity
        )
    }
}

/// A true macOS 26+ liquid-glass surface.
///
/// Unlike `NSVisualEffectView` (a plain frosted blur), the SwiftUI
/// `.glassEffect` modifier renders Apple's actual Liquid Glass with optical
/// refraction, specular highlights and depth. On macOS 12-25 this view falls
/// back to a conventional material so the app keeps its deployment floor.
class LiquidGlassContainerView: NSView {
    private var hostingView: NSView?
    private let fallbackEffect = NSVisualEffectView()
    private var lastFallbackMaskSize: CGSize = .zero
    private var lastFallbackMaskRadius: CGFloat = -1

    // Each setter guards against no-op writes: rebuilding the SwiftUI root view is not free,
    // and callers (e.g. VisualEffectBackdropView.layout) assign these on every layout pass.
    var cornerRadius: CGFloat = 28 {
        didSet { if oldValue != cornerRadius { update() } }
    }

    var tintColor: NSColor = .clear {
        didSet { if oldValue != tintColor { update() } }
    }

    /// How strongly the tint is expressed on the glass. 0 keeps only the
    /// native refraction; values around 0.25-0.45 read as a frosted panel.
    var tintOpacity: CGFloat = 0.35 {
        didSet { if oldValue != tintOpacity { update() } }
    }

    /// Use `.regular` (frosted, refractive) instead of `.clear` (pure
    /// droplet). Regular is what reads as a real macOS liquid-glass surface.
    var usesRegularGlass: Bool = true {
        didSet { if oldValue != usesRegularGlass { update() } }
    }

    /// When true, renders using macOS official system liquid-glass optics:
    /// true background refraction, dual-layer specular hairline highlights, and pure crystal translucency.
    var isNativeLiquid: Bool = false {
        didSet { if oldValue != isNativeLiquid { update() } }
    }

    /// Explicit dark vs light appearance for optics and colorScheme.
    var isDark: Bool = true {
        didSet {
            if oldValue != isDark {
                fallbackEffect.material = isDark ? .hudWindow : .popover
                update()
            }
        }
    }

    private var isLightSurface: Bool {
        guard let rgb = tintColor.usingColorSpace(.deviceRGB) else { return false }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.62
    }

    /// When enabled, the glass fades out softly along its perimeter so it melts
    /// into whatever sits behind it instead of showing a hard 1px seam. This is
    /// what keeps a white search capsule from reading as an opaque sticker on
    /// top of the panel: the surface brightens toward the centre and dissolves
    /// toward the edge, like light bending over a curved droplet.
    var softEdgeEnabled: Bool = false {
        didSet { if oldValue != softEdgeEnabled { updateSoftEdgeMask() } }
    }

    /// How far the feathered transition reaches inward from the edge.
    var softEdgeFeather: CGFloat = 14 {
        didSet { updateSoftEdgeMask() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        if #available(macOS 26.0, *) {
            let root = makeRootView()
            let hosting = NSHostingView(rootView: root)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            hosting.layer?.cornerRadius = cornerRadius
            hosting.layer?.masksToBounds = true
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            hostingView = hosting
            fallbackEffect.isHidden = true
        } else {
            fallbackEffect.material = .hudWindow
            fallbackEffect.blendingMode = .behindWindow
            fallbackEffect.state = .active
            fallbackEffect.translatesAutoresizingMaskIntoConstraints = false
            addSubview(fallbackEffect)
            NSLayoutConstraint.activate([
                fallbackEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
                fallbackEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
                fallbackEffect.topAnchor.constraint(equalTo: topAnchor),
                fallbackEffect.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func update() {
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        hostingView?.layer?.cornerRadius = cornerRadius
        hostingView?.layer?.masksToBounds = true
        updateSoftEdgeMask()
        updateFallbackMask()
        if #available(macOS 26.0, *) {
            if let hosting = hostingView as? NSHostingView<LiquidGlassRoot> {
                hosting.rootView = makeRootView()
            }
        }
    }

    /// `NSVisualEffectView` with `.behindWindow` is not reliably clipped by its
    /// parent layer on macOS 12-25. A generated rounded-rect mask keeps the
    /// fallback material inside the same silhouette as the liquid-glass path.
    private func updateFallbackMask() {
        guard !fallbackEffect.isHidden else { return }
        guard bounds.width > 1, bounds.height > 1 else {
            fallbackEffect.maskImage = nil
            lastFallbackMaskSize = .zero
            lastFallbackMaskRadius = -1
            return
        }
        guard bounds.size != lastFallbackMaskSize || cornerRadius != lastFallbackMaskRadius else { return }

        lastFallbackMaskSize = bounds.size
        lastFallbackMaskRadius = cornerRadius
        let size = bounds.size
        let radius = cornerRadius
        fallbackEffect.maskImage = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.white.setFill()
            path.fill()
            return true
        }
    }

    /// Builds a feathered alpha mask (no image textures) from a solid inset
    /// rounded rect plus four linear gradient bands, one per edge. Where the
    /// bands meet the inset rect, alpha ramps from 0 at the very perimeter to
    /// 1 just inside the feather width, so the silhouette has no hard step.
    private func updateSoftEdgeMask() {
        guard softEdgeEnabled, bounds.width > 4, bounds.height > 4 else {
            layer?.mask = nil
            return
        }
        let feather = min(softEdgeFeather, min(bounds.width, bounds.height) / 2 - 1)
        guard feather > 0.5 else {
            layer?.mask = nil
            return
        }

        let mask = CALayer()
        mask.frame = bounds
        mask.cornerRadius = cornerRadius
        mask.masksToBounds = true

        // Centre: the fully opaque body of the surface.
        let centre = CALayer()
        centre.frame = bounds.insetBy(dx: feather, dy: feather)
        centre.cornerRadius = max(0, cornerRadius - feather)
        centre.backgroundColor = NSColor.white.cgColor
        mask.addSublayer(centre)

        // Edge bands: clear at the perimeter, white as they approach the centre.
        let transparent = NSColor.white.withAlphaComponent(0.0).cgColor
        let opaque = NSColor.white.cgColor
        mask.addSublayer(makeBand(frame: CGRect(x: 0, y: 0, width: bounds.width, height: feather),
                                  start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1),
                                  colors: [transparent, opaque]))
        mask.addSublayer(makeBand(frame: CGRect(x: 0, y: bounds.height - feather, width: bounds.width, height: feather),
                                  start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1),
                                  colors: [opaque, transparent]))
        mask.addSublayer(makeBand(frame: CGRect(x: 0, y: 0, width: feather, height: bounds.height),
                                  start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 1, y: 0.5),
                                  colors: [transparent, opaque]))
        mask.addSublayer(makeBand(frame: CGRect(x: bounds.width - feather, y: 0, width: feather, height: bounds.height),
                                  start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 1, y: 0.5),
                                  colors: [opaque, transparent]))

        layer?.mask = mask
    }

    private func makeBand(frame: CGRect, start: CGPoint, end: CGPoint, colors: [CGColor]) -> CAGradientLayer {
        let band = CAGradientLayer()
        band.frame = frame
        band.startPoint = start
        band.endPoint = end
        band.colors = colors
        return band
    }

    @available(macOS 26.0, *)
    private func makeRootView() -> LiquidGlassRoot {
        LiquidGlassRoot(
            cornerRadius: cornerRadius,
            tintColor: Color(nsColor: tintColor),
            tintOpacity: Double(tintOpacity),
            usesRegularGlass: usesRegularGlass,
            isLight: isLightSurface,
            isNativeLiquid: isNativeLiquid,
            isDark: isDark
        )
    }

    private var lastMaskedSize: CGSize = .zero

    override func layout() {
        super.layout()
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        hostingView?.layer?.cornerRadius = cornerRadius
        hostingView?.layer?.masksToBounds = true
        updateFallbackMask()
        // Rebuilding the mask layers is only needed when the size actually changes.
        if softEdgeEnabled, bounds.size != lastMaskedSize {
            lastMaskedSize = bounds.size
            updateSoftEdgeMask()
        }
    }

    /// The glass surface is purely decorative: it must never swallow mouse
    /// events. Returning `nil` from hit-testing makes every click pass through
    /// to the real controls behind it, which is what keeps the borderless
    /// panels draggable by their background and keeps text fields clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassRoot: View {
    let cornerRadius: CGFloat
    let tintColor: Color
    let tintOpacity: Double
    let usesRegularGlass: Bool
    let isLight: Bool
    let isNativeLiquid: Bool
    let isDark: Bool

    var body: some View {
        let glass = usesRegularGlass ? Glass.regular : Glass.clear
        Group {
            if isNativeLiquid {
                // 🌟 1:1 严格对标 Apple 原生硬件级 Liquid Glass 规范 🌟
                // 浅色模式保持纯水滴透镜 (Glass.clear)；
                // 深色模式：低透明度（40%~55%）动态切入纯水滴透镜 (Glass.clear) 纯净折射底层，且始终保留基准暗色底衬 (underlayAlpha >= 0.24) 塑造纯正深色底蕴；
                // 高透明度（60%~100%）动态切换为 Glass.regular 漫射与强化暗色底衬 (0.58~0.68)，遮蔽背景杂色。
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                let useRegular = (isDark && tintOpacity > 0.36) || (!isDark && tintOpacity > 0.36 && usesRegularGlass)
                ZStack {
                    // 1. 系统硬件级液态水滴玻璃主体
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassEffect(
                            tintOpacity <= 0.001
                                ? Glass.clear
                                : (useRegular ? Glass.regular : Glass.clear).tint(tintColor.opacity(tintOpacity)),
                            in: shape
                        )

                    // 1.5 专属底衬（遮蔽杂色并随透明度动态联动）：
                    // - 深色模式：深邃黑曜石暗色底衬 (underlayAlpha: 0.24 ~ 0.68)
                    // - 浅色模式：纯白水滴微熏透光底衬 (underlayAlpha: 0.08 ~ 0.68)
                    if isDark {
                        let clampedProgress = max(0.0, min(1.0, (tintOpacity - 0.22) / (0.72 - 0.22)))
                        let underlayAlpha = 0.24 + 0.44 * pow(clampedProgress, 1.1)
                        shape
                            .fill(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(underlayAlpha))
                            .allowsHitTesting(false)
                    } else if tintOpacity > 0.001 {
                        let clampedProgress = max(0.0, min(1.0, (tintOpacity - 0.08) / (0.65 - 0.08)))
                        let underlayAlpha = 0.08 + 0.60 * pow(clampedProgress, 1.1)
                        shape
                            .fill(Color.white.opacity(underlayAlpha))
                            .allowsHitTesting(false)
                    }

                    // 2. 顶部物理微弧张力微光 (模拟真实晶体透镜受天光照射的漫反射，还原图一纯净光影)
                    shape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.08), location: 0.0),
                                    .init(color: Color.white.opacity(0.02), location: 0.22),
                                    .init(color: Color.clear, location: 0.45)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)

                    // 3. 内部焦散折射倒角 (产生真实 3-4mm 水滴水晶厚度感，纯净无黑色彩)
                    shape
                        .inset(by: 1.0)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isDark ? 0.35 : 0.22), location: 0.0),
                                    .init(color: Color.clear, location: 0.35),
                                    .init(color: Color.white.opacity(isDark ? 0.12 : 0.08), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )

                    // 4. 双色发丝切边高光 (天光反射 + 侧边微光 + 底部漫射，塑造柔润表面张力)
                    shape
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isDark ? 0.80 : 0.48), location: 0.0),
                                    .init(color: Color.white.opacity(isDark ? 0.30 : 0.18), location: 0.40),
                                    .init(color: Color.white.opacity(isDark ? 0.14 : 0.08), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
            } else {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                if isDark {
                    let rimColor: Color = Color.white.opacity(0.12)
                    ZStack {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .glassEffect(
                                glass.tint(tintColor.opacity(tintOpacity)),
                                in: shape
                            )

                        shape
                            .strokeBorder(rimColor, lineWidth: 0.75)
                    }
                } else {
                    // 🌟 液态玻璃 (浅色) 纯白晶莹磨砂质感 🌟
                    // 结合系统级 Glass.regular 漫射与纯白透光磨砂底衬，
                    // 彻底终结暗灰泥潭底色，呈现如同高级白瓷透光玻璃一样的优雅纯白微熏质感
                    ZStack {
                        // 1. 系统磨砂液态玻璃基底
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .glassEffect(
                                glass.tint(Color.white.opacity(tintOpacity)),
                                in: shape
                            )

                        // 2. 纯白通透磨砂底衬 (伴随 tintOpacity 浓度平滑调节，呈现纯正白瓷透光效果)
                        shape
                            .fill(Color.white.opacity(0.70 + 0.20 * min(1.0, tintOpacity)))
                            .allowsHitTesting(false)

                        // 3. 顶部透亮天光微反射
                        shape
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.45), location: 0.0),
                                        .init(color: Color.white.opacity(0.10), location: 0.25),
                                        .init(color: Color.clear, location: 0.50)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .allowsHitTesting(false)

                        // 4. 精致双层高光边框，塑造高贵质感
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.95), location: 0.0),
                                        .init(color: Color.white.opacity(0.55), location: 0.50),
                                        .init(color: Color(white: 0.88).opacity(0.45), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                    }
                }
            }
        }
        .environment(\.colorScheme, isDark ? .dark : .light)
        .environment(\.controlActiveState, .active)
    }
}
