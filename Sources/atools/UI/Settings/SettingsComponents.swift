import Foundation
import AppKit

/// 现代 macOS 卡片式容器视图 (自适应浅/深色背景与微高光圆角描边)
public final class SettingsCardView: NSView {
    private let stackView = NSStackView()
    private let backgroundView = NSVisualEffectView()

    public init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.material = .contentBackground
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        addSubview(backgroundView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.distribution = .fill
        stackView.alignment = .leading
        addSubview(stackView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    /// 添加一行设置项，并在需要时在行间插入标准 Inset 分割线
    public func addRow(_ rowView: NSView, isLast: Bool = false) {
        rowView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
        ])

        if !isLast {
            let separatorContainer = NSView()
            separatorContainer.translatesAutoresizingMaskIntoConstraints = false
            separatorContainer.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

            let line = NSBox()
            line.translatesAutoresizingMaskIntoConstraints = false
            line.boxType = .separator
            separatorContainer.addSubview(line)

            NSLayoutConstraint.activate([
                line.topAnchor.constraint(equalTo: separatorContainer.topAnchor),
                line.bottomAnchor.constraint(equalTo: separatorContainer.bottomAnchor),
                line.leadingAnchor.constraint(equalTo: separatorContainer.leadingAnchor, constant: 16),
                line.trailingAnchor.constraint(equalTo: separatorContainer.trailingAnchor, constant: -16)
            ])

            stackView.addArrangedSubview(separatorContainer)
            NSLayoutConstraint.activate([
                separatorContainer.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                separatorContainer.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
            ])
        }
    }
}

/// 标准设置行视图：左侧图标 + 主标题 + 详细副标题说明，右侧控件
public final class SettingsRowView: NSView {
    public let titleLabel = NSTextField(labelWithString: "")
    public let subtitleLabel = NSTextField(labelWithString: "")
    public let iconImageView = NSImageView()
    public let accessoryContainer = NSView()

    public init(
        icon: NSImage? = nil,
        title: String,
        subtitle: String? = nil,
        accessory: NSView? = nil,
        minHeight: CGFloat = 46
    ) {
        super.init(frame: .zero)
        setupUI(icon: icon, title: title, subtitle: subtitle, accessory: accessory, minHeight: minHeight)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupUI(icon: NSImage?, title: String, subtitle: String?, accessory: NSView?, minHeight: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textStack.addArrangedSubview(titleLabel)

        if let sub = subtitle, !sub.isEmpty {
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel.stringValue = sub
            subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.cell?.wraps = true
            subtitleLabel.maximumNumberOfLines = 2
            subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textStack.addArrangedSubview(subtitleLabel)
        }

        addSubview(textStack)

        var leftAnchorConstraint = textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        if let icon = icon {
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            iconImageView.image = icon
            iconImageView.contentTintColor = .secondaryLabelColor
            addSubview(iconImageView)

            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: 18),
                iconImageView.heightAnchor.constraint(equalToConstant: 18)
            ])
            leftAnchorConstraint = textStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12)
        }
        leftAnchorConstraint.isActive = true

        accessoryContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessoryContainer)

        if let accessory = accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessoryContainer.addSubview(accessory)
            NSLayoutConstraint.activate([
                accessory.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
                accessory.bottomAnchor.constraint(equalTo: accessoryContainer.bottomAnchor),
                accessory.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
                accessory.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            textStack.trailingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor, constant: -12),

            accessoryContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            accessoryContainer.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// 模块大标题与次级分段胶囊 Tab 头部视图
public final class SettingsHeaderView: NSView {
    public let iconView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    public let segmentedControl = NSSegmentedControl()
    public var onSegmentChanged: ((Int) -> Void)?

    public init(title: String, iconName: String, tabs: [String] = []) {
        super.init(frame: .zero)
        setupUI(title: title, iconName: iconName, tabs: tabs)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupUI(title: String, iconName: String, tabs: [String]) {
        translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = ThumbnailPipeline.shared.symbolIcon(name: iconName, pointSize: 20, weight: .semibold)
        iconView.contentTintColor = .labelColor
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor)
        ])

        if !tabs.isEmpty {
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false
            segmentedControl.segmentCount = tabs.count
            for (idx, tabTitle) in tabs.enumerated() {
                segmentedControl.setLabel(tabTitle, forSegment: idx)
            }
            segmentedControl.selectedSegment = 0
            segmentedControl.target = self
            segmentedControl.action = #selector(segmentChanged(_:))
            if #available(macOS 11.0, *) {
                segmentedControl.trackingMode = .selectOne
            }
            addSubview(segmentedControl)

            NSLayoutConstraint.activate([
                segmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
                segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
                segmentedControl.heightAnchor.constraint(equalToConstant: 26),
                segmentedControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
            ])
        } else {
            bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12).isActive = true
        }
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        onSegmentChanged?(sender.selectedSegment)
    }
}

/// 首次启动新手引导与快速概览横幅 (精致轻量，直达配置)
public final class WelcomeGuideBannerView: NSView {
    public static let dismissedKey = "atools.hasDismissedWelcomeBanner"
    public static var hasDismissed: Bool {
        return UserDefaults.standard.bool(forKey: dismissedKey)
    }

    public var onDismiss: (() -> Void)?
    public var onNavigateToSpotlightGuide: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let guideButton = SettingsPillButton(title: "查看 Spotlight 设置指南")
    private let dismissButton = SettingsPillButton(title: "我知道了，开始体验", style: .primary)
    private let backgroundView = NSVisualEffectView()

    public init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.material = .contentBackground
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        addSubview(backgroundView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = "欢迎使用 ATools"
        addSubview(titleLabel)

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.stringValue = """
        分类工作台：按 Option + A (⌥A) 呼出分类面板，支持拖拽文件与应用加入
        全盘搜索：按 Option + Space (⌥Space) 居中呼出，搜索应用与全盘文件
        状态栏：菜单栏图标常驻，可快速打开面板、设置或退出应用
        Spotlight 设置：建议关闭系统搜索快捷键并隐藏其菜单栏图标
        """
        addSubview(bodyLabel)

        guideButton.target = self
        guideButton.action = #selector(handleGuideClicked)
        addSubview(guideButton)

        dismissButton.target = self
        dismissButton.action = #selector(handleDismiss)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            guideButton.centerYAnchor.constraint(equalTo: dismissButton.centerYAnchor),
            guideButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            dismissButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 10),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    @objc private func handleGuideClicked() {
        onNavigateToSpotlightGuide?()
    }

    @objc private func handleDismiss() {
        UserDefaults.standard.set(true, forKey: WelcomeGuideBannerView.dismissedKey)
        onDismiss?()
    }

}

/// Borderless capsule button used throughout Settings.
///
/// The stock `.rounded` bezel renders an almost-white fill on macOS 26, which disappears
/// on the white settings cards and leaves only floating text. This draws its own fill
/// (no outline) with hover / pressed / disabled states and follows the light/dark appearance.
public final class SettingsPillButton: NSButton {
    public enum Style {
        case primary
        case secondary
    }

    public var style: Style {
        didSet { updateAppearanceStyles() }
    }

    private var isHovered = false {
        didSet { if oldValue != isHovered { updateAppearanceStyles() } }
    }
    private var isPressed = false {
        didSet { if oldValue != isPressed { updateAppearanceStyles() } }
    }
    private var trackingArea: NSTrackingArea?

    public static let height: CGFloat = 28

    public init(title: String, style: Style = .secondary, target: AnyObject? = nil, action: Selector? = nil) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setButtonType(.momentaryChange)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = SettingsPillButton.height / 2
        layer?.borderWidth = 0
        font = NSFont.systemFont(ofSize: 12, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: SettingsPillButton.height).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        updateAppearanceStyles()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: ceil(base.width) + 28, height: SettingsPillButton.height)
    }

    override public var isEnabled: Bool {
        didSet { updateAppearanceStyles() }
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) { isHovered = true }
    override public func mouseExited(with event: NSEvent) { isHovered = false }

    override public func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event) // runs the tracking loop until mouse up
        isPressed = false
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    private func updateAppearanceStyles() {
        let isDark = glassIsDark
        let fill: NSColor
        let text: NSColor
        switch style {
        case .primary:
            let base = GlassPalette.textPrimary(isDark: isDark)
            fill = isPressed ? base.withAlphaComponent(0.72) : (isHovered ? base.withAlphaComponent(0.86) : base)
            text = isDark ? NSColor(white: 0.08, alpha: 1.0) : .white
        case .secondary:
            let alpha: CGFloat = isPressed ? (isDark ? 0.24 : 0.14) : (isHovered ? (isDark ? 0.18 : 0.10) : (isDark ? 0.12 : 0.06))
            fill = isDark ? NSColor(white: 1.0, alpha: alpha) : NSColor(white: 0.0, alpha: alpha)
            text = GlassPalette.textPrimary(isDark: isDark)
        }
        layer?.backgroundColor = fill.cgColor
        contentTintColor = text
        alphaValue = isEnabled ? 1.0 : 0.45
    }
}
