import Foundation
import AppKit

public final class AutoQuitTabView: NSView {
    private var autoQuitSwitch: NSSwitch!
    private var autoQuitModePopUp: SettingsLiquidPopUpButton!
    private var autoQuitDelayPopUp: SettingsLiquidPopUpButton!
    private var autoQuitRulesButton: SettingsPillButton!
    private var autoQuitPermissionLabel: NSTextField!
    private var autoQuitChangeObserver: NSObjectProtocol?
    private var headerView: SettingsHeaderView!

    private let autoQuitDelayOptions: [(title: String, seconds: Int)] = [
        ("立即退出", 0), ("1 秒", 1), ("2 秒 (推荐)", 2), ("3 秒", 3), ("5 秒", 5)
    ]

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()

        autoQuitChangeObserver = NotificationCenter.default.addObserver(
            forName: .atoolsAutoQuitDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let token = autoQuitChangeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        headerView = SettingsHeaderView(title: "关窗退出", iconName: "door.left.hand.open", tabs: [])
        addSubview(headerView)

        let scrollContent = NSView()
        let scrollView = makeTabScrollView(contentView: scrollContent)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Section 1: 行为控制
        let sec1Title = makeSectionHeader(title: "关窗退出总开关与模式")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        autoQuitSwitch = NSSwitch()
        autoQuitSwitch.target = self
        autoQuitSwitch.action = #selector(toggleAutoQuit(_:))
        let rowSwitch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "power"),
            title: "开启关窗自动退出 (AutoQuit)",
            subtitle: "当第三方应用的最后一个可见窗口被关闭时，在后台自动退出该应用进程",
            accessory: autoQuitSwitch
        )
        card1.addRow(rowSwitch)

        autoQuitModePopUp = SettingsLiquidPopUpButton()
        autoQuitModePopUp.target = self
        autoQuitModePopUp.action = #selector(autoQuitModeChanged(_:))
        for mode in AutoQuitMode.allCases {
            autoQuitModePopUp.addItem(withTitle: mode.title)
        }
        let rowMode = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "slider.horizontal.3"),
            title: "生效模式",
            subtitle: "「排除名单」适用于绝大多数应用；「仅退出名单」适合只针对特定应用生效",
            accessory: autoQuitModePopUp
        )
        card1.addRow(rowMode)

        autoQuitDelayPopUp = SettingsLiquidPopUpButton()
        autoQuitDelayPopUp.target = self
        autoQuitDelayPopUp.action = #selector(autoQuitDelayChanged(_:))
        for opt in autoQuitDelayOptions {
            autoQuitDelayPopUp.addItem(withTitle: opt.title)
        }
        autoQuitModePopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
        autoQuitDelayPopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let rowDelay = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "timer"),
            title: "关闭后延迟退出",
            subtitle: "留出短暂时间窗口，避免不小心关闭窗口后立即把应用退出",
            accessory: autoQuitDelayPopUp
        )
        card1.addRow(rowDelay, isLast: true)

        // Section 2: 规则与应用过滤
        let sec2Title = makeSectionHeader(title: "规则与应用过滤")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        autoQuitRulesButton = SettingsPillButton(title: "编辑名单...", target: self, action: #selector(openAutoQuitRulesEditor))
        autoQuitRulesButton.widthAnchor.constraint(equalToConstant: 148).isActive = true
        let rowRules = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "list.bullet.rectangle"),
            title: "应用规则名单",
            subtitle: "添加、移除或查看在此模式下受监控或受豁免的应用",
            accessory: autoQuitRulesButton
        )
        card2.addRow(rowRules)

        let permContainer = NSStackView()
        permContainer.orientation = .horizontal
        permContainer.spacing = 8
        permContainer.alignment = .centerY

        autoQuitPermissionLabel = NSTextField(labelWithString: "检查中...")
        autoQuitPermissionLabel.font = NSFont.systemFont(ofSize: 11)
        autoQuitPermissionLabel.alignment = .right
        permContainer.addArrangedSubview(autoQuitPermissionLabel)

        let openPermBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openAutoQuitAccessibility))
        openPermBtn.widthAnchor.constraint(equalToConstant: 148).isActive = true
        permContainer.addArrangedSubview(openPermBtn)

        let rowPerm = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hand.raised"),
            title: "辅助功能权限状态",
            subtitle: "需要「辅助功能」授权才能安全感知其他软件窗口关闭",
            accessory: permContainer
        )
        card2.addRow(rowPerm, isLast: true)

        let tipLabel = NSTextField(labelWithString: "提示：ATools 采用轻量 Accessibility 观测与 AXUIElement 树差分比对，仅在窗口关闭时进行判定，不常驻轮询 CPU，内存占用极低。")
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont.systemFont(ofSize: 11)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.cell?.wraps = true
        tipLabel.maximumNumberOfLines = 3
        tipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollContent.addSubview(tipLabel)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: scrollContent.topAnchor, constant: 14),
            sec1Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 8),
            card1.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            sec2Title.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 20),
            sec2Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 8),
            card2.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            tipLabel.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 12),
            tipLabel.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 32),
            tipLabel.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),
            tipLabel.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -28)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        autoQuitSwitch.state = cfg.enableAutoQuit ? .on : .off
        autoQuitModePopUp.isEnabled = cfg.enableAutoQuit
        autoQuitDelayPopUp.isEnabled = cfg.enableAutoQuit
        autoQuitRulesButton.isEnabled = true

        if let modeIdx = AutoQuitMode.allCases.firstIndex(of: cfg.autoQuitMode) {
            autoQuitModePopUp.selectItem(at: modeIdx)
        }
        if let delayIdx = autoQuitDelayOptions.firstIndex(where: { $0.seconds == cfg.autoQuitDelaySeconds }) {
            autoQuitDelayPopUp.selectItem(at: delayIdx)
        } else {
            let nearest = autoQuitDelayOptions.enumerated().min {
                abs($0.element.seconds - cfg.autoQuitDelaySeconds) < abs($1.element.seconds - cfg.autoQuitDelaySeconds)
            }?.offset ?? 2
            autoQuitDelayPopUp.selectItem(at: nearest)
        }
        let currentRules = cfg.rules(for: cfg.autoQuitMode)
        switch cfg.autoQuitMode {
        case .allApps:
            autoQuitRulesButton.title = "编辑排除名单 (\(currentRules.count))..."
        case .onlyListed:
            autoQuitRulesButton.title = "编辑退出名单 (\(currentRules.count))..."
        }

        let trusted = HotkeyManager.isAccessibilityTrusted()
        autoQuitPermissionLabel.stringValue = trusted ? "已授权" : "未授权"
        autoQuitPermissionLabel.textColor = trusted ? .systemGreen : .systemOrange
    }

    @objc private func toggleAutoQuit(_ sender: NSSwitch) {
        let desired = (sender.state == .on)
        guard desired else {
            ConfigManager.shared.updateEnableAutoQuit(false)
            return
        }
        if HotkeyManager.isAccessibilityTrusted() {
            ConfigManager.shared.updateEnableAutoQuit(true)
            return
        }
        let alert = NSAlert()
        alert.messageText = "「关窗退出」需要辅助功能授权"
        alert.informativeText = "监听其他应用窗口的关闭事件，需要 macOS「系统设置」->「隐私与安全性」->「辅助功能」中允许 ATools。\n\nATools 仅感知窗口数量变化，绝不读取任何窗口内容或键入信息。是否前往授权？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往系统设置")
        alert.addButton(withTitle: "暂不开启")
        if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
            HotkeyManager.openAccessibilitySettings()
        }
        sender.state = .off
    }

    @objc private func autoQuitModeChanged(_ sender: NSPopUpButton) {
        let modes = AutoQuitMode.allCases
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        ConfigManager.shared.updateAutoQuitMode(modes[sender.indexOfSelectedItem])
        refresh()
    }

    @objc private func autoQuitDelayChanged(_ sender: NSPopUpButton) {
        guard autoQuitDelayOptions.indices.contains(sender.indexOfSelectedItem) else { return }
        ConfigManager.shared.updateAutoQuitDelaySeconds(autoQuitDelayOptions[sender.indexOfSelectedItem].seconds)
    }

    @objc private func openAutoQuitAccessibility() {
        HotkeyManager.openAccessibilitySettings()
    }

    @objc private func openAutoQuitRulesEditor() {
        guard let hostWindow = window else { return }
        guard hostWindow.attachedSheet == nil else {
            return
        }
        let mode = ConfigManager.shared.config.autoQuitMode
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheet.title = (mode == .allApps) ? "AutoQuit 排除名单" : "AutoQuit 退出名单"
        sheet.isReleasedWhenClosed = false
        sheet.contentMinSize = NSSize(width: 470, height: 430)
        sheet.contentMaxSize = NSSize(width: 470, height: 430)
        sheet.setContentSize(NSSize(width: 470, height: 430))
        sheet.contentView = AutoQuitRulesEditorView(frame: NSRect(x: 0, y: 0, width: 470, height: 430), mode: mode)
        hostWindow.beginSheet(sheet) { _ in
            _ = sheet
        }
    }
}
