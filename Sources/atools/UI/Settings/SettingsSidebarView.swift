import Foundation
import AppKit

public enum SettingsSidebarItem: Int, CaseIterable {
    case general = 0
    case shelf = 1
    case search = 2
    case hotkeys = 3
    case theme = 4
    case performance = 5
    case about = 6

    public var title: String {
        switch self {
        case .general: return "常规"
        case .shelf: return "应用抽屉"
        case .search: return "全盘搜索"
        case .hotkeys: return "全局快捷键"
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
        case .hotkeys: return "keyboard"
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
        self.layer?.cornerRadius = 8
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    private func setupContent() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true

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

    func updateAppearance() {
        if isCurrentSelected {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.78).cgColor
            titleLabel.textColor = .labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            iconView.contentTintColor = .labelColor
        } else {
            layer?.backgroundColor = isHovered
                ? NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor
                : NSColor.clear.cgColor
            titleLabel.textColor = .labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            iconView.contentTintColor = .secondaryLabelColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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

        let rightBorder = NSBox()
        rightBorder.translatesAutoresizingMaskIntoConstraints = false
        rightBorder.boxType = .separator
        addSubview(rightBorder)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            rightBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightBorder.topAnchor.constraint(equalTo: topAnchor),
            rightBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightBorder.widthAnchor.constraint(equalToConstant: 0.5)
        ])

        // 1. Top App Brand Row
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
        appTitle.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        appTitle.textColor = .labelColor
        addSubview(appTitle)

        NSLayoutConstraint.activate([
            appIcon.topAnchor.constraint(equalTo: topAnchor, constant: 20),
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
        navStack.spacing = 4
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

        // 3. Bottom Status Bar (对标参考图 "✓ Pro 已激活")
        let bottomContainer = NSView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.wantsLayer = true
        bottomContainer.layer?.cornerRadius = 6
        addSubview(bottomContainer)

        let statusIcon = NSImageView()
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.image = ThumbnailPipeline.shared.symbolIcon(name: "checkmark.seal.fill", pointSize: 13, weight: .semibold)
        statusIcon.contentTintColor = .secondaryLabelColor
        bottomContainer.addSubview(statusIcon)

        let statusLabel = NSTextField(labelWithString: "常驻极简就绪")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .labelColor
        bottomContainer.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            bottomContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bottomContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
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
