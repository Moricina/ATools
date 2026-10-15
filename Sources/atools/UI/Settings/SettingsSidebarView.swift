import Foundation
import AppKit

public enum SettingsSidebarItem: Int, CaseIterable {
    case general = 0
    case shelf = 1
    case search = 2
    case autoQuit = 3
    case theme = 4
    case performance = 5
    case about = 6

    public var title: String {
        switch self {
        case .general: return "常规"
        case .shelf: return "应用抽屉"
        case .search: return "全盘搜索"
        case .autoQuit: return "关窗退出"
        case .theme: return "外观与主题"
        case .performance: return "运行与性能"
        case .about: return "关于"
        }
    }

    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .shelf: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .autoQuit: return "door.left.hand.open"
        case .theme: return "paintbrush"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        case .about: return "info.circle"
        }
    }
}

/// 侧边栏单个导航项按钮（现代 macOS 胶囊高亮风格）
private final class SidebarRowButton: NSButton {
    let item: SettingsSidebarItem
    var isCurrentSelected: Bool = false {
        didSet { updateAppearance() }
    }
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?

    init(item: SettingsSidebarItem, target: AnyObject?, action: Selector) {
        self.item = item
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = ""
        self.setButtonType(.momentaryPushIn)
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 9
        setupContent()
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "NEW")

    var showsUpdateBadge: Bool = false {
        didSet {
            guard showsUpdateBadge != oldValue else { return }
            updateBadgeVisibility(animated: window != nil)
        }
    }

    private func setupContent() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = ThumbnailPipeline.shared.symbolIcon(name: item.iconName, pointSize: 14, weight: .medium)
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = item.title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        addSubview(titleLabel)

        if item == .about {
            badgeContainer.translatesAutoresizingMaskIntoConstraints = false
            badgeContainer.wantsLayer = true
            badgeContainer.layer?.cornerRadius = 8
            badgeContainer.layer?.masksToBounds = true
            badgeContainer.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.88).cgColor
            badgeContainer.isHidden = true
            badgeContainer.alphaValue = 0.0
            addSubview(badgeContainer)

            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeLabel.stringValue = "NEW"
            badgeLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.alignment = .center
            badgeContainer.addSubview(badgeLabel)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 18),
                iconView.heightAnchor.constraint(equalToConstant: 18),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeContainer.leadingAnchor, constant: -6),

                badgeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                badgeContainer.heightAnchor.constraint(equalToConstant: 16),

                badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
                badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
                badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 18),
                iconView.heightAnchor.constraint(equalToConstant: 18),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
            ])
        }

        updateAppearance()
    }

    private func updateBadgeVisibility(animated: Bool) {
        guard item == .about else { return }
        if showsUpdateBadge {
            badgeContainer.isHidden = false
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                badgeContainer.alphaValue = 0.0
                badgeContainer.layer?.transform = CATransform3DMakeScale(0.1, 0.1, 1.0)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.35
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    badgeContainer.animator().alphaValue = 1.0
                }
                let spring = CAKeyframeAnimation(keyPath: "transform.scale")
                spring.values = [0.1, 1.15, 0.95, 1.0]
                spring.keyTimes = [0.0, 0.5, 0.8, 1.0]
                spring.duration = 0.35
                spring.fillMode = .forwards
                spring.isRemovedOnCompletion = false
                badgeContainer.layer?.add(spring, forKey: "badgeScale")
            } else {
                badgeContainer.alphaValue = 1.0
                badgeContainer.layer?.transform = CATransform3DIdentity
                badgeContainer.layer?.removeAnimation(forKey: "badgeScale")
            }
        } else {
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2
                    badgeContainer.animator().alphaValue = 0.0
                }, completionHandler: { [weak self] in
                    guard let self = self, !self.showsUpdateBadge else { return }
                    self.badgeContainer.isHidden = true
                    self.badgeContainer.layer?.removeAnimation(forKey: "badgeScale")
                })
            } else {
                badgeContainer.isHidden = true
                badgeContainer.alphaValue = 0.0
                badgeContainer.layer?.removeAnimation(forKey: "badgeScale")
            }
        }
    }

    private var isDarkAppearance: Bool {
        if let win = window {
            let app = win.appearance ?? win.effectiveAppearance
            if let match = app.bestMatch(from: [.darkAqua, .aqua]) {
                return match == .darkAqua
            }
        }
        return ConfigManager.shared.config.theme.isDark
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        if isCurrentSelected, let op = layer?.shadowOpacity, op > 0 {
            layer?.shadowPath = CGPath(
                roundedRect: bounds,
                cornerWidth: layer?.cornerRadius ?? 9,
                cornerHeight: layer?.cornerRadius ?? 9,
                transform: nil
            )
        } else {
            layer?.shadowPath = nil
        }
    }

    func updateAppearance() {
        let isDark = isDarkAppearance
        if isCurrentSelected {
            // 🌟 纯白液态水滴质感选中高亮 + 活力蓝调图标 (1:1 完美对标图 2 AuraSnap 精致一体化风格) 🌟
            if isDark {
                layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.18).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
                layer?.shadowColor = NSColor.black.cgColor
                layer?.shadowOffset = CGSize(width: 0, height: 1.0)
                layer?.shadowRadius = 4.0
                layer?.shadowOpacity = 0.20
                titleLabel.textColor = .white
                iconView.contentTintColor = NSColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
            } else {
                layer?.backgroundColor = NSColor.white.cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = NSColor.black.withAlphaComponent(0.04).cgColor
                layer?.shadowColor = NSColor.black.cgColor
                layer?.shadowOffset = CGSize(width: 0, height: 1.0)
                layer?.shadowRadius = 3.5
                layer?.shadowOpacity = 0.07
                titleLabel.textColor = NSColor(white: 0.10, alpha: 1.0)
                iconView.contentTintColor = NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
            }
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        } else {
            layer?.shadowOpacity = 0.0
            layer?.shadowColor = nil
            layer?.shadowPath = nil
            if isHovered {
                if isDark {
                    layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
                    layer?.borderWidth = 0.5
                    layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
                    titleLabel.textColor = NSColor(white: 1.0, alpha: 0.95)
                    iconView.contentTintColor = NSColor(white: 1.0, alpha: 0.88)
                } else {
                    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
                    layer?.borderWidth = 0.5
                    layer?.borderColor = NSColor.black.withAlphaComponent(0.02).cgColor
                    titleLabel.textColor = NSColor(white: 0.10, alpha: 1.0)
                    iconView.contentTintColor = NSColor(white: 0.20, alpha: 1.0)
                }
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                layer?.borderColor = nil
                if isDark {
                    titleLabel.textColor = NSColor(white: 1.0, alpha: 0.75)
                    iconView.contentTintColor = NSColor(white: 1.0, alpha: 0.65)
                } else {
                    titleLabel.textColor = NSColor(white: 0.20, alpha: 0.90)
                    iconView.contentTintColor = NSColor(white: 0.35, alpha: 0.85)
                }
            }
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}

/// 具有可点击交互态与无障碍支持的应用图标视图
private final class ClickableAppIconView: NSImageView {
    var isUpdateAvailable: Bool = false {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isUpdateAvailable {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

/// 极简精致的更新红点徽标（带 1.5pt 毛玻璃背景描边隔离环，防粘连 + 一次性入场微动效）
private final class NotificationBadgeView: NSView {
    private let dotLayer = CALayer()
    private let dotSize: CGFloat

    init(size: CGFloat = 8.0) {
        self.dotSize = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        alphaValue = 0.0
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        guard let rootLayer = layer else { return }
        rootLayer.masksToBounds = false

        // 柔和自然微阴影
        rootLayer.shadowColor = NSColor.black.cgColor
        rootLayer.shadowOpacity = 0.22
        rootLayer.shadowOffset = CGSize(width: 0, height: -0.5)
        rootLayer.shadowRadius = 1.5

        dotLayer.frame = NSRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dotLayer.cornerRadius = dotSize / 2.0
        dotLayer.backgroundColor = NSColor.systemRed.cgColor
        dotLayer.borderWidth = 1.5
        rootLayer.addSublayer(dotLayer)
    }

    override func layout() {
        super.layout()
        dotLayer.frame = bounds
        dotLayer.cornerRadius = bounds.width / 2.0
    }

    func updateBorderColor(isDark: Bool) {
        // 毛玻璃背景同色描边：浅色模式下为柔白，深色模式下为深灰，形成 1.5pt 隔离发丝
        let color = isDark
            ? NSColor(white: 0.18, alpha: 0.95).cgColor
            : NSColor(white: 0.95, alpha: 0.95).cgColor
        dotLayer.borderColor = color
    }

    var showsBadge: Bool = false {
        didSet {
            guard showsBadge != oldValue else { return }
            if showsBadge {
                isHidden = false
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    alphaValue = 1.0
                    layer?.transform = CATransform3DIdentity
                    layer?.removeAnimation(forKey: "dotSpring")
                } else {
                    alphaValue = 0.0
                    layer?.transform = CATransform3DMakeScale(0.1, 0.1, 1.0)
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.35
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        animator().alphaValue = 1.0
                    }
                    let spring = CAKeyframeAnimation(keyPath: "transform.scale")
                    spring.values = [0.1, 1.15, 0.95, 1.0]
                    spring.keyTimes = [0.0, 0.5, 0.8, 1.0]
                    spring.duration = 0.35
                    spring.fillMode = .forwards
                    spring.isRemovedOnCompletion = false
                    layer?.add(spring, forKey: "dotSpring")
                }
            } else {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    isHidden = true
                    alphaValue = 0.0
                    layer?.removeAnimation(forKey: "dotSpring")
                } else {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.2
                        animator().alphaValue = 0.0
                    }, completionHandler: { [weak self] in
                        guard let self = self, !self.showsBadge else { return }
                        self.isHidden = true
                        self.layer?.removeAnimation(forKey: "dotSpring")
                    })
                }
            }
        }
    }
}

/// 侧边栏主视图 (宽 200pt, 磨砂半透明背景 + 顶部 App 标志 + 菜单列表 + 底部就绪状态)
public final class SettingsSidebarView: NSView {
    public var onItemSelected: ((SettingsSidebarItem) -> Void)?
    private var buttons: [SidebarRowButton] = []
    public private(set) var selectedItem: SettingsSidebarItem = .general
    private let rightDivider = NSView()
    private let statusIcon = NSImageView()
    private let appIcon = ClickableAppIconView()
    private let appIconBadge = NotificationBadgeView(size: 8.0)

    public init() {
        super.init(frame: .zero)
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateStateChanged),
            name: UpdateManager.stateDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 200).isActive = true

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        addSubview(effectView)

        // 🌟 0.5pt 极细微环境发丝分割线（彻底替换生硬的 NSBox 粗黑线，实现一体化自然消融）🌟
        rightDivider.translatesAutoresizingMaskIntoConstraints = false
        rightDivider.wantsLayer = true
        addSubview(rightDivider)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            rightDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightDivider.topAnchor.constraint(equalTo: topAnchor),
            rightDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: 0.5)
        ])

        // 1. Top App Brand Row（在红绿灯下方约 22pt 处优雅展开，1:1 对标图 2 AuraSnap 顶底间距）
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        if let icon = NSApp.applicationIconImage {
            appIcon.image = icon
        } else {
            appIcon.image = ThumbnailPipeline.shared.symbolIcon(name: "sparkles", pointSize: 22, weight: .bold)
        }
        let appIconClick = NSClickGestureRecognizer(target: self, action: #selector(handleAppIconClicked))
        appIcon.addGestureRecognizer(appIconClick)
        addSubview(appIcon)
        addSubview(appIconBadge)

        let appTitle = NSTextField(labelWithString: "ATools")
        appTitle.translatesAutoresizingMaskIntoConstraints = false
        appTitle.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        appTitle.textColor = .labelColor
        addSubview(appTitle)

        NSLayoutConstraint.activate([
            appIcon.topAnchor.constraint(equalTo: topAnchor, constant: 52),
            appIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            appIcon.widthAnchor.constraint(equalToConstant: 26),
            appIcon.heightAnchor.constraint(equalToConstant: 26),

            appIconBadge.widthAnchor.constraint(equalToConstant: 8),
            appIconBadge.heightAnchor.constraint(equalToConstant: 8),
            appIconBadge.centerXAnchor.constraint(equalTo: appIcon.trailingAnchor, constant: -1),
            appIconBadge.centerYAnchor.constraint(equalTo: appIcon.topAnchor, constant: 1),

            appTitle.leadingAnchor.constraint(equalTo: appIcon.trailingAnchor, constant: 8),
            appTitle.centerYAnchor.constraint(equalTo: appIcon.centerYAnchor)
        ])

        // 2. Navigation Items Stack
        let navStack = NSStackView()
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navStack.orientation = .vertical
        navStack.alignment = .leading
        navStack.spacing = 3
        addSubview(navStack)

        NSLayoutConstraint.activate([
            navStack.topAnchor.constraint(equalTo: appIcon.bottomAnchor, constant: 18),
            navStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            navStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])

        for item in SettingsSidebarItem.allCases {
            let btn = SidebarRowButton(item: item, target: self, action: #selector(handleButtonClicked(_:)))
            btn.isCurrentSelected = (item == .general)
            buttons.append(btn)
            navStack.addArrangedSubview(btn)
            NSLayoutConstraint.activate([
                btn.leadingAnchor.constraint(equalTo: navStack.leadingAnchor),
                btn.trailingAnchor.constraint(equalTo: navStack.trailingAnchor)
            ])
        }

        // 3. Bottom Status Bar (1:1 完美复刻参考图 2 "✓ Pro 已激活" 蓝调微标与高级质感)
        let bottomContainer = NSView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.wantsLayer = true
        addSubview(bottomContainer)

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.image = ThumbnailPipeline.shared.symbolIcon(name: "checkmark.seal.fill", pointSize: 13, weight: .semibold)
        statusIcon.contentTintColor = NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        bottomContainer.addSubview(statusIcon)

        let statusLabel = NSTextField(labelWithString: "常驻极简就绪")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .labelColor
        bottomContainer.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            bottomContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            bottomContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            bottomContainer.heightAnchor.constraint(equalToConstant: 24),

            statusIcon.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            statusIcon.centerYAnchor.constraint(equalTo: bottomContainer.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalToConstant: 14),

            statusLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: bottomContainer.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor)
        ])

        updateColors()
    }

    private func updateColors() {
        let isDark: Bool
        if let win = window {
            let app = win.appearance ?? win.effectiveAppearance
            isDark = (app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        } else {
            isDark = ConfigManager.shared.config.theme.isDark
        }
        rightDivider.layer?.backgroundColor = isDark
            ? NSColor(white: 1.0, alpha: 0.10).cgColor
            : NSColor(white: 0.0, alpha: 0.06).cgColor
        statusIcon.contentTintColor = isDark
            ? NSColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
            : NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        appIconBadge.updateBorderColor(isDark: isDark)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
        if window != nil {
            refreshUpdateBadges()
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    @objc private func handleAppIconClicked() {
        if case .available = UpdateManager.shared.currentState {
            selectItem(.about)
        }
    }

    @objc private func handleUpdateStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshUpdateBadges()
        }
    }

    private func refreshUpdateBadges() {
        let hasUpdate: Bool
        if case .available = UpdateManager.shared.currentState {
            hasUpdate = true
        } else {
            hasUpdate = false
        }
        appIcon.isUpdateAvailable = hasUpdate
        appIcon.toolTip = hasUpdate ? "发现 ATools 新版本，点击查看更新详情" : nil
        appIconBadge.showsBadge = hasUpdate
        if let aboutBtn = buttons.first(where: { $0.item == .about }) {
            aboutBtn.showsUpdateBadge = hasUpdate
        }
    }

    @objc private func handleButtonClicked(_ sender: SidebarRowButton) {
        selectItem(sender.item)
    }

    public func selectItem(_ item: SettingsSidebarItem) {
        selectedItem = item
        for btn in buttons {
            btn.isCurrentSelected = (btn.item == item)
        }
        onItemSelected?(item)
    }
}
