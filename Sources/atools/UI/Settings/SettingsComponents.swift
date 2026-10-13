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

    // MARK: - 访达文件夹拖拽投放支持 (Finder Drag-and-Drop)

    /// 当设置此闭包时，卡片自动注册并响应来自 Finder 的文件夹拖拽
    public var onDropFolders: (([String]) -> Void)? {
        didSet {
            if onDropFolders != nil {
                registerForDraggedTypes([.fileURL])
            } else {
                unregisterDraggedTypes()
            }
        }
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onDropFolders != nil else { return [] }
        let folders = extractDirectories(from: sender)
        if !folders.isEmpty {
            setDragHighlighted(true)
            return .copy
        }
        return []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onDropFolders != nil else { return [] }
        let folders = extractDirectories(from: sender)
        return folders.isEmpty ? [] : .copy
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        setDragHighlighted(false)
    }

    override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard onDropFolders != nil else { return false }
        return !extractDirectories(from: sender).isEmpty
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlighted(false)
        guard let onDrop = onDropFolders else { return false }
        let folders = extractDirectories(from: sender)
        guard !folders.isEmpty else { return false }
        onDrop(folders)
        return true
    }

    private func setDragHighlighted(_ highlighted: Bool) {
        if highlighted {
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.borderWidth = 0
            layer?.borderColor = NSColor.clear.cgColor
        }
    }

    private func extractDirectories(from sender: NSDraggingInfo) -> [String] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return []
        }
        var directories: [String] = []
        let fm = FileManager.default
        for url in urls {
            let path = url.standardized.path
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                // 排除 .app 软件安装包（通常不应作为普通热目录或排除目录被拖入）
                if path.hasSuffix(".app") { continue }
                directories.append(path)
            }
        }
        return directories
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

/// 内部单项文本视图
private final class LiquidSegmentItemView: NSView {
    let label = NSTextField(labelWithString: "")
    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }
    var isHovered: Bool = false {
        didSet { updateAppearance() }
    }
    var isDark: Bool = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // 穿透给父控件统一处理点击与移动
    }

    func updateAppearance() {
        let font: NSFont = isSelected
            ? NSFont.systemFont(ofSize: 12.5, weight: .bold)
            : NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.font = font

        if isSelected {
            label.textColor = isDark ? NSColor.white : NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1.0)
        } else if isHovered {
            label.textColor = isDark ? NSColor(white: 0.90, alpha: 1.0) : NSColor(white: 0.18, alpha: 1.0)
        } else {
            label.textColor = isDark ? NSColor(white: 0.65, alpha: 1.0) : NSColor(white: 0.40, alpha: 1.0)
        }
    }
}

/// macOS 原生液态水滴次级分段切换胶囊 (Settings Liquid Segmented Control)
/// 呈现 1:1 Apple 原生液态切换胶囊质感（如同图 2）：
/// 1. 外层全圆角跑道形底槽 (Pill Track)，微透光质感与细腻描边
/// 2. 内部悬浮滑动的纯白/黑曜石原生液态水滴胶囊 (Native Liquid Selection Capsule)
/// 3. 水滴表面张力微弧天光反射 + 360° 发丝切边双色高光 + 悬浮立体柔和微投影
/// 4. 丝滑平移动画，多段切换柔畅自如
public final class SettingsLiquidSegmentedControl: NSView {
    public var onSegmentChanged: ((Int) -> Void)?
    public weak var target: AnyObject?
    public var action: Selector?
    public var trackingMode: NSSegmentedControl.SwitchTracking = .selectOne

    private var labels: [String] = []
    private var itemViews: [LiquidSegmentItemView] = []
    private let liquidCapsule = NativeLiquidSelectionBackdrop(cornerRadius: 13.5)
    private var trackingArea: NSTrackingArea?
    private var hoveredIndex: Int = -1

    public var segmentCount: Int {
        get { labels.count }
        set {
            if newValue != labels.count {
                if newValue < labels.count {
                    labels = Array(labels.prefix(newValue))
                } else {
                    while labels.count < newValue {
                        labels.append("")
                    }
                }
                rebuildItems()
            }
        }
    }

    public var isEnabled: Bool = true {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.45
            window?.invalidateCursorRects(for: self)
        }
    }

    public var selectedSegment: Int = 0 {
        didSet {
            if oldValue != selectedSegment {
                updateSelectionState(animated: window != nil)
            }
        }
    }

    public func setSelectedSegment(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < labels.count else { return }
        selectedSegment = index
        updateSelectionState(animated: animated && window != nil)
    }

    public func setLabel(_ label: String, forSegment segment: Int) {
        guard segment >= 0 else { return }
        while labels.count <= segment {
            labels.append("")
        }
        labels[segment] = label
        rebuildItems()
    }

    public func label(forSegment segment: Int) -> String? {
        guard segment >= 0, segment < labels.count else { return nil }
        return labels[segment]
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    public convenience init(labels: [String], trackingMode: NSSegmentedControl.SwitchTracking = .selectOne, target: AnyObject? = nil, action: Selector? = nil) {
        self.init(frame: .zero)
        self.trackingMode = trackingMode
        self.target = target
        self.action = action
        self.labels = labels
        rebuildItems()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        liquidCapsule.contactShadowEnabled = true
        liquidCapsule.customShadowOpacity = 0.14
        liquidCapsule.customShadowRadius = 4.0
        liquidCapsule.isSelected = true
        addSubview(liquidCapsule)
        updateTrackStyles()
    }

    private func rebuildItems() {
        for v in itemViews { v.removeFromSuperview() }
        itemViews.removeAll()

        for (idx, text) in labels.enumerated() {
            let item = LiquidSegmentItemView()
            item.label.stringValue = text
            item.isSelected = (idx == selectedSegment)
            item.isDark = glassIsDark
            item.updateAppearance()
            addSubview(item)
            itemViews.append(item)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override public var intrinsicContentSize: NSSize {
        guard !labels.isEmpty else { return NSSize(width: 120, height: 32) }
        var totalTextWidth: CGFloat = 0
        for label in labels {
            let str = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ])
            totalTextWidth += str.size().width
        }
        let horizontalPaddingPerSegment: CGFloat = 34.0 // 每段文本左右预留 17pt，与图2舒展质感一致
        let neededWidth = totalTextWidth + CGFloat(labels.count) * horizontalPaddingPerSegment + 6.0
        return NSSize(width: max(neededWidth, 220), height: 32)
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackStyles()
        updateSelectionState(animated: false)
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTrackStyles()
        updateSelectionState(animated: false)
    }

    private func updateTrackStyles() {
        let isDark = glassIsDark
        wantsLayer = true
        let r = bounds.height > 0 ? (bounds.height / 2) : 16.0
        layer?.cornerRadius = r
        layer?.masksToBounds = false

        if isDark {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            liquidCapsule.customShadowOpacity = 0.22
        } else {
            layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.045).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(white: 0.0, alpha: 0.08).cgColor
            liquidCapsule.customShadowOpacity = 0.14
        }

        liquidCapsule.isDark = isDark
        liquidCapsule.isSelected = true
        liquidCapsule.updateStyles()

        for item in itemViews {
            item.isDark = isDark
            item.updateAppearance()
        }
    }

    override public func layout() {
        super.layout()
        updateTrackStyles()
        layoutSegments(animated: false)
    }

    private func layoutSegments(animated: Bool) {
        guard !labels.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let insetBounds = bounds.insetBy(dx: 2.5, dy: 2.5)
        let count = CGFloat(labels.count)
        let segWidth = insetBounds.width / count
        let segHeight = insetBounds.height
        let capsuleRadius = segHeight / 2

        liquidCapsule.cornerRadius = capsuleRadius

        for (idx, itemView) in itemViews.enumerated() {
            let itemX = insetBounds.minX + CGFloat(idx) * segWidth
            itemView.frame = CGRect(x: itemX, y: insetBounds.minY, width: segWidth, height: segHeight)
            itemView.isSelected = (idx == selectedSegment)
            itemView.isDark = glassIsDark
            itemView.updateAppearance()
        }

        let targetX = insetBounds.minX + CGFloat(selectedSegment) * segWidth
        let targetRect = CGRect(x: targetX, y: insetBounds.minY, width: segWidth, height: segHeight)

        if animated && window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                liquidCapsule.animator().frame = targetRect
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            liquidCapsule.frame = targetRect
            CATransaction.commit()
        }
    }

    private func updateSelectionState(animated: Bool) {
        layoutSegments(animated: animated)
    }

    // MARK: - Interactions
    override public func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseMoved(with event: NSEvent) {
        guard isEnabled else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let idx = segmentIndex(at: loc)
        if idx != hoveredIndex {
            hoveredIndex = idx
            updateHoverStates()
        }
    }

    override public func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
        updateHoverStates()
    }

    private func updateHoverStates() {
        for (i, item) in itemViews.enumerated() {
            item.isHovered = (i == hoveredIndex && i != selectedSegment)
        }
    }

    override public func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let idx = segmentIndex(at: loc)
        if idx >= 0 && idx < labels.count {
            if idx != selectedSegment {
                selectedSegment = idx
                updateSelectionState(animated: true)
                if let target = target, let action = action {
                    NSApp.sendAction(action, to: target, from: self)
                }
                onSegmentChanged?(selectedSegment)
            }
        }
    }

    private func segmentIndex(at point: CGPoint) -> Int {
        guard !labels.isEmpty, bounds.width > 0 else { return -1 }
        let insetBounds = bounds.insetBy(dx: 2.5, dy: 2.5)
        guard insetBounds.contains(point) else { return -1 }
        let segWidth = insetBounds.width / CGFloat(labels.count)
        let idx = Int((point.x - insetBounds.minX) / segWidth)
        return min(max(0, idx), labels.count - 1)
    }
}

/// 模块大标题与次级分段胶囊 Tab 头部视图
public final class SettingsHeaderView: NSView {
    public let iconView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    public let segmentedControl = SettingsLiquidSegmentedControl()
    public var onSegmentChanged: ((Int) -> Void)? {
        get { segmentedControl.onSegmentChanged }
        set { segmentedControl.onSegmentChanged = newValue }
    }

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
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 50),
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
            addSubview(segmentedControl)

            NSLayoutConstraint.activate([
                segmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
                segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
                segmentedControl.heightAnchor.constraint(equalToConstant: 32),
                segmentedControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
            ])
        } else {
            bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12).isActive = true
        }
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

/// 🌟 原生液态水滴玻璃按钮背景 (Apple Native Liquid Glass Button Backdrop) 🌟
/// 包含：硬件级光学水滴透镜折射 + 顶部天光物理微弧高光 + 双色发丝切边高光 + 微触地立体阴影
public final class NativeLiquidButtonBackdrop: NSView {
    public var cornerRadius: CGFloat = 14 {
        didSet {
            glassContainer.cornerRadius = cornerRadius
            needsLayout = true
        }
    }
    public var isDark: Bool = false {
        didSet { updateStyles() }
    }
    public var isHovered: Bool = false {
        didSet { updateStyles() }
    }
    public var isPressed: Bool = false {
        didSet { updateStyles() }
    }
    public var isPrimary: Bool = false {
        didSet { updateStyles() }
    }
    public var isEnabled: Bool = true {
        didSet { updateStyles() }
    }

    private let glassContainer = LiquidGlassContainerView()
    private let topSheenLayer = CAGradientLayer()
    private let specularBorderLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()

    override public var isFlipped: Bool { true }

    public init(cornerRadius: CGFloat = 14) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = false

        // 1. 微触地立体阴影 (Ambient Contact Shadow) - 默认常态无外溢生硬阴影，Hover/Pressed 时赋予极柔和微浮起
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: 1.0)
        layer?.shadowRadius = 4.0
        layer?.shadowOpacity = 0.0

        // 2. 硬件级光学液态水滴玻璃容器 (Apple .glassEffect)
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

        // 3. 顶部天光物理微弧张力微光 (Top Ambient Tension Reflection)
        topSheenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        topSheenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        topSheenLayer.masksToBounds = true
        topSheenLayer.cornerRadius = cornerRadius
        topSheenLayer.locations = [0.0, 0.35, 0.75]
        layer?.addSublayer(topSheenLayer)

        // 4. 双色发丝切边高光 (Specular Hairline Border)
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
        return nil // 点击穿透给父级按键响应
    }

    override public func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        layer?.cornerRadius = cornerRadius

        // Top Sheen: 100% 覆盖完整 bounds 并继承完全一致的圆角，根除矩形方角外溢
        topSheenLayer.frame = bounds
        topSheenLayer.cornerRadius = cornerRadius
        topSheenLayer.masksToBounds = true

        // Specular Border
        specularBorderLayer.frame = bounds
        borderMaskLayer.frame = bounds
        let insetBounds = bounds.insetBy(dx: 0.375, dy: 0.375)
        borderMaskLayer.path = CGPath(
            roundedRect: insetBounds,
            cornerWidth: max(0, cornerRadius - 0.375),
            cornerHeight: max(0, cornerRadius - 0.375),
            transform: nil
        )

        // Shadow Path: 仅在有投影时提供严格圆角阴影路径
        if let opacity = layer?.shadowOpacity, opacity > 0 {
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

        if isPrimary {
            // 🌟 突出主操作：黑曜石高光水滴晶体（深色下为耀眼晶莹白水滴，浅色下为深邃黑曜石液态玻璃）
            if isDark {
                glassContainer.tintColor = NSColor(white: 0.95, alpha: 1.0)
                glassContainer.tintOpacity = isHovered ? 0.95 : 0.88
            } else {
                glassContainer.tintColor = NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
                glassContainer.tintOpacity = isHovered ? 0.96 : 0.90
            }
        } else {
            // 🌟 常规水滴透镜：晶莹清透，深浅自适应
            if isDark {
                glassContainer.tintColor = NSColor(white: 1.0, alpha: 1.0)
                glassContainer.tintOpacity = isHovered ? 0.22 : 0.14
            } else {
                glassContainer.tintColor = NSColor(white: 0.0, alpha: 1.0)
                glassContainer.tintOpacity = isHovered ? 0.14 : 0.08
            }
        }

        // Top ambient sheen
        let sheenAlpha: CGFloat
        if !isEnabled {
            sheenAlpha = 0.0
        } else if isPressed {
            sheenAlpha = isDark ? 0.08 : 0.12
        } else if isHovered {
            sheenAlpha = isDark ? 0.32 : 0.38
        } else {
            sheenAlpha = isDark ? 0.18 : 0.22
        }
        topSheenLayer.colors = [
            NSColor.white.withAlphaComponent(sheenAlpha).cgColor,
            NSColor.white.withAlphaComponent(sheenAlpha * 0.25).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]

        // Specular Hairline Border
        if !isEnabled {
            let dimAlpha: CGFloat = isDark ? 0.10 : 0.08
            specularBorderLayer.colors = [
                NSColor(white: isDark ? 1.0 : 0.0, alpha: dimAlpha).cgColor,
                NSColor(white: isDark ? 1.0 : 0.0, alpha: dimAlpha * 0.6).cgColor
            ]
            layer?.shadowOpacity = 0.0
        } else if isPrimary {
            let topAlpha: CGFloat = isHovered ? 1.0 : 0.85
            let midAlpha: CGFloat = isHovered ? 0.45 : 0.35
            specularBorderLayer.colors = [
                NSColor.white.withAlphaComponent(topAlpha).cgColor,
                NSColor.white.withAlphaComponent(midAlpha).cgColor,
                NSColor.white.withAlphaComponent(0.20).cgColor
            ]
            layer?.shadowOpacity = isHovered ? 0.16 : 0.08
        } else {
            // Secondary Liquid Glass Border
            if isDark {
                let topAlpha: CGFloat = isHovered ? 0.95 : 0.80
                let sideAlpha: CGFloat = isHovered ? 0.38 : 0.24
                let bottomAlpha: CGFloat = isHovered ? 0.22 : 0.14
                specularBorderLayer.colors = [
                    NSColor.white.withAlphaComponent(topAlpha).cgColor,
                    NSColor.white.withAlphaComponent(sideAlpha).cgColor,
                    NSColor.white.withAlphaComponent(bottomAlpha).cgColor
                ]
            } else {
                let topAlpha: CGFloat = isHovered ? 0.95 : 0.85
                let sideAlpha: CGFloat = isHovered ? 0.22 : 0.14
                let bottomAlpha: CGFloat = isHovered ? 0.14 : 0.08
                specularBorderLayer.colors = [
                    NSColor.white.withAlphaComponent(topAlpha).cgColor,
                    NSColor(white: 0.20, alpha: sideAlpha).cgColor,
                    NSColor(white: 0.10, alpha: bottomAlpha).cgColor
                ]
            }
            // 常态不加突兀生硬黑阴影，Hover/Pressed 时赋予极柔和微浮起
            layer?.shadowOpacity = isHovered ? 0.07 : 0.0
        }

        alphaValue = isEnabled ? 1.0 : 0.45
    }
}

/// 🌟 原生液态水滴胶囊按钮 (Apple Native Liquid Glass Capsule Button) 🌟
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

    private let backdrop = NativeLiquidButtonBackdrop(cornerRadius: SettingsPillButton.height / 2)
    private let titleLabel = NSTextField(labelWithString: "")

    public init(title: String, style: Style = .secondary, target: AnyObject? = nil, action: Selector? = nil) {
        self.style = style
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.momentaryChange)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = SettingsPillButton.height / 2
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: SettingsPillButton.height).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)

        // Mount Native Liquid Backdrop
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Mount Text Label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.refusesFirstResponder = true
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        super.title = ""
        updateAppearanceStyles()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public var title: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override public var intrinsicContentSize: NSSize {
        let textWidth = titleLabel.intrinsicContentSize.width
        return NSSize(width: max(68, ceil(textWidth) + 28), height: SettingsPillButton.height)
    }

    override public var isEnabled: Bool {
        didSet { updateAppearanceStyles() }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateAppearanceStyles()
        }
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override public func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) { if isEnabled { isHovered = true } }
    override public func mouseExited(with event: NSEvent) { isHovered = false }

    override public func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    private func updateAppearanceStyles() {
        let isDark = glassIsDark
        backdrop.isDark = isDark
        backdrop.isPrimary = (style == .primary)
        backdrop.isHovered = isHovered
        backdrop.isPressed = isPressed
        backdrop.isEnabled = isEnabled

        let text: NSColor
        if !isEnabled {
            text = isDark ? NSColor(white: 1.0, alpha: 0.35) : NSColor(white: 0.0, alpha: 0.30)
        } else if style == .primary {
            text = isDark ? NSColor(white: 0.08, alpha: 1.0) : .white
        } else {
            text = GlassPalette.textPrimary(isDark: isDark)
        }
        titleLabel.textColor = text
        alphaValue = isEnabled ? 1.0 : 0.45
    }
}

/// 🌟 原生液态水滴重置按钮 (Apple Native Liquid Glass Reset Button) 🌟
public final class SettingsResetButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { if oldValue != isHovered { updateAppearanceStyles() } }
    }
    private var isPressed = false {
        didSet { if oldValue != isPressed { updateAppearanceStyles() } }
    }

    private let backdrop = NativeLiquidButtonBackdrop(cornerRadius: 11)
    private let titleLabel = NSTextField(labelWithString: "")

    public init(title: String = "恢复默认", target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.momentaryChange)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)

        // Mount Backdrop
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Mount Text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.refusesFirstResponder = true
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        super.title = ""
        updateAppearanceStyles()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public var title: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override public var intrinsicContentSize: NSSize {
        let textWidth = titleLabel.intrinsicContentSize.width
        return NSSize(width: max(64, ceil(textWidth) + 16), height: 22)
    }

    override public var isEnabled: Bool {
        didSet { updateAppearanceStyles() }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateAppearanceStyles()
        }
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override public func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) { if isEnabled { isHovered = true } }
    override public func mouseExited(with event: NSEvent) { isHovered = false }

    override public func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    private func updateAppearanceStyles() {
        let isDark = glassIsDark
        backdrop.isDark = isDark
        backdrop.isHovered = isHovered
        backdrop.isPressed = isPressed
        backdrop.isEnabled = isEnabled

        let textColor: NSColor
        if !isEnabled {
            textColor = isDark ? NSColor.white.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.25)
        } else if isHovered {
            textColor = isDark ? NSColor.white.withAlphaComponent(0.98) : NSColor.black.withAlphaComponent(0.92)
        } else {
            textColor = isDark ? NSColor.white.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.75)
        }
        titleLabel.textColor = textColor
        alphaValue = isEnabled ? 1.0 : 0.45
    }
}

/// 🌟 原生液态水滴圆形图标按钮 (24x24) 🌟
public final class SettingsIconButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { if oldValue != isHovered { updateAppearance() } }
    }
    private var isPressed = false {
        didSet { if oldValue != isPressed { updateAppearance() } }
    }
    public var normalTintColor: NSColor = .secondaryLabelColor {
        didSet { updateAppearance() }
    }
    public var hoverTintColor: NSColor? {
        didSet { updateAppearance() }
    }

    private let backdrop = NativeLiquidButtonBackdrop(cornerRadius: 12)
    private let iconImageView = NSImageView()

    public init(symbolName: String, accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.momentaryChange)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24)
        ])

        // Mount Backdrop
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Mount Icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        addSubview(iconImageView)
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 14),
            iconImageView.heightAnchor.constraint(equalToConstant: 14)
        ])

        super.title = ""
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override public func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) { if isEnabled { isHovered = true } }
    override public func mouseExited(with event: NSEvent) { isHovered = false }

    override public func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override public var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateAppearance()
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = glassIsDark
        backdrop.isDark = isDark
        backdrop.isHovered = isHovered
        backdrop.isPressed = isPressed
        backdrop.isEnabled = isEnabled

        if !isEnabled {
            iconImageView.contentTintColor = normalTintColor.withAlphaComponent(0.35)
        } else if isHovered {
            iconImageView.contentTintColor = hoverTintColor ?? (isDark ? .white : GlassPalette.textPrimary(isDark: false))
        } else {
            iconImageView.contentTintColor = normalTintColor
        }
        alphaValue = isEnabled ? 1.0 : 0.45
    }
}

/// 🌟 原生液态水滴下拉选择按钮 (Apple Native Liquid Glass PopUp Button) 🌟
/// 采用无边框硬件级光学微透镜玻璃胶囊，完美匹配原生液态材质与触控板手势/搜索引擎/自动退出设置
public class SettingsLiquidPopUpButton: NSPopUpButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false {
        didSet { if oldValue != isHovered { updateAppearanceStyles() } }
    }
    private var isPressed: Bool = false {
        didSet { if oldValue != isPressed { updateAppearanceStyles() } }
    }

    public static let height: CGFloat = 28

    private let backdrop = NativeLiquidButtonBackdrop(cornerRadius: SettingsLiquidPopUpButton.height / 2)
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronIconView = NSImageView()

    public override init(frame frameRect: NSRect, pullsDown flag: Bool) {
        super.init(frame: frameRect, pullsDown: flag)
        setupLiquidUI()
    }

    public init() {
        super.init(frame: .zero, pullsDown: false)
        setupLiquidUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLiquidUI()
    }

    private func setupLiquidUI() {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = SettingsLiquidPopUpButton.height / 2
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: SettingsLiquidPopUpButton.height).isActive = true

        if let popupCell = cell as? NSPopUpButtonCell {
            popupCell.arrowPosition = .noArrow
        }

        // Mount Native Liquid Backdrop
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Mount Text Label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.alignment = .left
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.refusesFirstResponder = true
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Mount Chevron Icon
        chevronIconView.translatesAutoresizingMaskIntoConstraints = false
        chevronIconView.imageScaling = .scaleProportionallyDown
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevronIconView.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig)
        addSubview(chevronIconView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronIconView.leadingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevronIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronIconView.widthAnchor.constraint(equalToConstant: 10),
            chevronIconView.heightAnchor.constraint(equalToConstant: 12)
        ])

        syncTitle()
        updateAppearanceStyles()
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, !isHidden else { return nil }
        let pointInView = convert(point, from: superview)
        if bounds.contains(pointInView) {
            return self
        }
        return nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        // 自定义子视图 (backdrop, titleLabel, chevronIconView) 负责全部绘制，完全绕过系统默认 Aqua 粗糙浮雕与双箭头
    }

    public override var title: String {
        get { super.title }
        set {
            super.title = newValue
            syncTitle()
        }
    }

    public override func synchronizeTitleAndSelectedItem() {
        super.synchronizeTitleAndSelectedItem()
        syncTitle()
    }

    public override func selectItem(at index: Int) {
        super.selectItem(at: index)
        syncTitle()
    }

    public override func selectItem(withTitle title: String) {
        super.selectItem(withTitle: title)
        syncTitle()
    }

    public override func selectItem(withTag tag: Int) -> Bool {
        let result = super.selectItem(withTag: tag)
        syncTitle()
        return result
    }

    public override func select(_ item: NSMenuItem?) {
        super.select(item)
        syncTitle()
    }

    public override func addItem(withTitle title: String) {
        super.addItem(withTitle: title)
        syncTitle()
    }

    public override func addItems(withTitles itemTitles: [String]) {
        super.addItems(withTitles: itemTitles)
        syncTitle()
    }

    public override func removeItem(withTitle title: String) {
        super.removeItem(withTitle: title)
        syncTitle()
    }

    public override func removeItem(at index: Int) {
        super.removeItem(at: index)
        syncTitle()
    }

    public override func removeAllItems() {
        super.removeAllItems()
        syncTitle()
    }

    private func syncTitle() {
        let text = titleOfSelectedItem ?? title
        titleLabel.stringValue = text
    }

    public override var intrinsicContentSize: NSSize {
        let textWidth = titleLabel.intrinsicContentSize.width
        return NSSize(width: max(120, ceil(textWidth) + 38), height: SettingsLiquidPopUpButton.height)
    }

    public override var isEnabled: Bool {
        didSet { updateAppearanceStyles() }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateAppearanceStyles()
        }
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    public override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        if isEnabled { isHovered = true }
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
        isHovered = false
        syncTitle()
        updateAppearanceStyles()
    }

    public override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        syncTitle()
        updateAppearanceStyles()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    private func updateAppearanceStyles() {
        let isDark = glassIsDark
        backdrop.isDark = isDark
        backdrop.isHovered = isHovered
        backdrop.isPressed = isPressed
        backdrop.isEnabled = isEnabled

        let text: NSColor
        let chevron: NSColor
        if !isEnabled {
            text = isDark ? NSColor(white: 1.0, alpha: 0.35) : NSColor(white: 0.0, alpha: 0.30)
            chevron = isDark ? NSColor(white: 1.0, alpha: 0.25) : NSColor(white: 0.0, alpha: 0.20)
        } else {
            text = GlassPalette.textPrimary(isDark: isDark)
            chevron = isDark ? NSColor(white: 1.0, alpha: 0.65) : NSColor(white: 0.0, alpha: 0.55)
        }
        titleLabel.textColor = text
        chevronIconView.contentTintColor = chevron
        alphaValue = isEnabled ? 1.0 : 0.45
    }
}

