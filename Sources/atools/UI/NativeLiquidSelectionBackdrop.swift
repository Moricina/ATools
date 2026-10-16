import Foundation
import AppKit

/// macOS 原生液态水滴选中态背景容器 (Native Liquid Selection Backdrop)
/// 专用于全局搜索（胶囊栏、搜索结果选中条）与应用抽屉（分类胶囊、应用项 Hover/选中）
/// 呈现 1:1 Apple 原生液态水滴质感：
/// 1. 物理光学透镜折射 (.glassEffect)
/// 2. 水滴表面张力天光漫反射 (Top Sheen Gradient)
/// 3. 双色发丝微切边高光 (Specular Hairline Contour)
/// 4. 柔和物理微环境阴影 (Contact Shadow, 可选)
public final class NativeLiquidSelectionBackdrop: NSView {
    public var cornerRadius: CGFloat = 10 {
        didSet {
            glassContainer.cornerRadius = cornerRadius
            layer?.cornerRadius = cornerRadius
            updatePaths()
        }
    }

    public var isDark: Bool = false {
        didSet { updateStyles() }
    }

    public var isSelected: Bool = false {
        didSet { updateStyles() }
    }

    public var isHovered: Bool = false {
        didSet { updateStyles() }
    }

    public var isPressed: Bool = false {
        didSet { updateStyles() }
    }

    public var contactShadowEnabled: Bool = true {
        didSet { updateStyles() }
    }

    public var customShadowOpacity: Float? = nil {
        didSet { updateStyles() }
    }

    public var customShadowRadius: CGFloat? = nil {
        didSet { updateStyles() }
    }

    private let glassContainer = LiquidGlassContainerView()
    private let topSheenLayer = CAGradientLayer()
    private let specularBorderLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()

    override public var isFlipped: Bool { true }

    public init(cornerRadius: CGFloat = 10) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = false

        // 1. 硬件级光学液态水滴玻璃容器 (Apple .glassEffect)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.isNativeLiquid = true
        glassContainer.usesRegularGlass = true
        glassContainer.cornerRadius = cornerRadius
        addSubview(glassContainer)
        NSLayoutConstraint.activate([
            glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassContainer.topAnchor.constraint(equalTo: topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 2. 顶部天光物理微弧张力微光 (Top Ambient Tension Reflection)
        topSheenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        topSheenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        topSheenLayer.masksToBounds = true
        topSheenLayer.cornerRadius = cornerRadius
        topSheenLayer.locations = [0.0, 0.35, 0.75]
        layer?.addSublayer(topSheenLayer)

        // 3. 双色发丝切边高光 (Specular Hairline Border)
        specularBorderLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        specularBorderLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        borderMaskLayer.fillColor = nil
        borderMaskLayer.strokeColor = NSColor.white.cgColor
        borderMaskLayer.lineWidth = 0.75
        specularBorderLayer.mask = borderMaskLayer
        layer?.addSublayer(specularBorderLayer)

        updateStyles()
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        return nil // 绝对穿透给底层控件
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePaths()
    }

    override public func layout() {
        super.layout()
        updatePaths()
    }

    private func updatePaths() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        layer?.cornerRadius = cornerRadius

        // 让天光漫反射图层 100% 贴合宿主 bounds 并继承完全一致的圆角，根除半高裁切与方角外溢
        topSheenLayer.frame = bounds
        topSheenLayer.cornerRadius = cornerRadius
        topSheenLayer.masksToBounds = true

        specularBorderLayer.frame = bounds
        borderMaskLayer.frame = bounds
        let insetBounds = bounds.insetBy(dx: 0.375, dy: 0.375)
        borderMaskLayer.path = CGPath(
            roundedRect: insetBounds,
            cornerWidth: max(0, cornerRadius - 0.375),
            cornerHeight: max(0, cornerRadius - 0.375),
            transform: nil
        )

        if contactShadowEnabled, let op = layer?.shadowOpacity, op > 0 {
            layer?.shadowPath = CGPath(
                roundedRect: bounds,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        } else {
            layer?.shadowPath = nil
        }
    }

    public func updateStyles() {
        glassContainer.isDark = isDark
        glassContainer.cornerRadius = cornerRadius
        layer?.cornerRadius = cornerRadius

        // 🌟 水滴透镜色温与浓度 (Water Droplet Optical Density)
        // 保持晶莹剔透的水滴质感，适中透光浓度避免遮盖底层磨砂与窗口折射
        if isDark {
            glassContainer.tintColor = NSColor(white: 1.0, alpha: 1.0)
            if isSelected {
                glassContainer.tintOpacity = isPressed ? 0.30 : 0.22
            } else if isHovered {
                glassContainer.tintOpacity = 0.14
            } else {
                glassContainer.tintOpacity = 0.08
            }
        } else {
            // 浅色纯水滴晶体：通透纯白水滴，柔和适中
            glassContainer.tintColor = NSColor(white: 1.0, alpha: 1.0)
            if isSelected {
                glassContainer.tintOpacity = isPressed ? 0.45 : 0.36
            } else if isHovered {
                glassContainer.tintOpacity = 0.22
            } else {
                glassContainer.tintOpacity = 0.10
            }
        }

        // 顶部天光表面张力微弧高光 (Top Sheen)
        let sheenAlpha: CGFloat
        if isPressed {
            sheenAlpha = isDark ? 0.08 : 0.10
        } else if isSelected {
            sheenAlpha = isDark ? 0.16 : 0.20
        } else if isHovered {
            sheenAlpha = isDark ? 0.10 : 0.12
        } else {
            sheenAlpha = 0.0
        }

        topSheenLayer.colors = [
            NSColor.white.withAlphaComponent(sheenAlpha).cgColor,
            NSColor.white.withAlphaComponent(sheenAlpha * 0.3).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]

        // 360° 双色发丝切边高光 (Specular Hairline Contour)
        // 采用细腻优雅的半透明渐变，完全避免生硬惨白刺眼反光与边缘黑化
        if isDark {
            let topAlpha: CGFloat = isSelected ? 0.45 : (isHovered ? 0.32 : 0.18)
            let sideAlpha: CGFloat = isSelected ? 0.18 : (isHovered ? 0.12 : 0.08)
            let bottomAlpha: CGFloat = isSelected ? 0.09 : (isHovered ? 0.06 : 0.04)
            specularBorderLayer.colors = [
                NSColor.white.withAlphaComponent(topAlpha).cgColor,
                NSColor.white.withAlphaComponent(sideAlpha).cgColor,
                NSColor.white.withAlphaComponent(bottomAlpha).cgColor
            ]
        } else {
            let topAlpha: CGFloat = isSelected ? 0.52 : (isHovered ? 0.38 : 0.20)
            let sideAlpha: CGFloat = isSelected ? 0.20 : (isHovered ? 0.15 : 0.10)
            let bottomAlpha: CGFloat = isSelected ? 0.10 : (isHovered ? 0.08 : 0.05)
            specularBorderLayer.colors = [
                NSColor.white.withAlphaComponent(topAlpha).cgColor,
                NSColor.white.withAlphaComponent(sideAlpha).cgColor,
                NSColor.white.withAlphaComponent(bottomAlpha).cgColor
            ]
        }

        // 自然物理微环境投影 (Natural Ambient Shadow)
        // 在 isFlipped 坐标系下，y 偏移设为 +1.5 贴合自然顺光向下投影，绝不向上溢出
        // 配合 6.5pt 宽阔漫射模糊与极低浓度，呈现如丝般柔润的悬浮过渡，根除任何生硬截断
        if !contactShadowEnabled {
            layer?.shadowOpacity = 0.0
            layer?.shadowColor = nil
            layer?.shadowPath = nil
        } else {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOffset = CGSize(width: 0, height: 1.5)
            layer?.shadowRadius = customShadowRadius ?? 6.5
            if let custom = customShadowOpacity {
                layer?.shadowOpacity = (isSelected || isHovered) ? custom : 0.0
            } else if isDark {
                layer?.shadowOpacity = isSelected ? 0.10 : (isHovered ? 0.05 : 0.0)
            } else {
                layer?.shadowOpacity = isSelected ? 0.04 : (isHovered ? 0.02 : 0.0)
            }
            updatePaths()
        }
    }
}
