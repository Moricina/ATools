import Foundation
import AppKit
import SwiftUI

/// A true macOS 26+ liquid-glass surface.
///
/// Unlike `NSVisualEffectView` (a plain frosted blur), the SwiftUI
/// `.glassEffect` modifier renders Apple's actual Liquid Glass with optical
/// refraction, specular highlights and depth. On macOS 12-25 this view falls
/// back to a conventional material so the app keeps its deployment floor.
class LiquidGlassContainerView: NSView {
    private var hostingView: NSView?
    private let fallbackEffect = NSVisualEffectView()

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
        updateSoftEdgeMask()
        if #available(macOS 26.0, *) {
            if let hosting = hostingView as? NSHostingView<LiquidGlassRoot> {
                hosting.rootView = makeRootView()
            }
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
                                  start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
                                  colors: [transparent, opaque]))
        mask.addSublayer(makeBand(frame: CGRect(x: bounds.width - feather, y: 0, width: feather, height: bounds.height),
                                  start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
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
            isLight: isLightSurface
        )
    }

    private var lastMaskedSize: CGSize = .zero

    override func layout() {
        super.layout()
        layer?.cornerRadius = cornerRadius
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

    var body: some View {
        let glass = usesRegularGlass ? Glass.regular : Glass.clear
        let rimColor: Color = isLight
            ? Color.black.opacity(0.10)
            : Color.white.opacity(0.12)
        ZStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(
                    glass.tint(tintColor.opacity(tintOpacity)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(rimColor, lineWidth: 0.75)
        }
    }
}
