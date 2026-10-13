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

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])

        updateAppearance()
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

/// 侧边栏主视图 (宽 200pt, 磨砂半透明背景 + 顶部 App 标志 + 菜单列表 + 底部就绪状态)
public final class SettingsSidebarView: NSView {
    public var onItemSelected: ((SettingsSidebarItem) -> Void)?
    private var buttons: [SidebarRowButton] = []
    public private(set) var selectedItem: SettingsSidebarItem = .general
    private let rightDivider = NSView()
    private let statusIcon = NSImageView()

    public init() {
        super.init(frame: .zero)
        setupUI()
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
        let appIcon = NSImageView()
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        if let icon = NSApp.applicationIconImage {
            appIcon.image = icon
        } else {
            appIcon.image = ThumbnailPipeline.shared.symbolIcon(name: "sparkles", pointSize: 22, weight: .bold)
        }
        addSubview(appIcon)

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
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
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
