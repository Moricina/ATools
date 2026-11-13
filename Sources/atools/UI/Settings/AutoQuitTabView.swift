import Foundation
import AppKit

public final class AutoQuitTabView: NSView {
    private var autoQuitSwitch: NSSwitch!
    private var autoQuitModePopUp: SettingsLiquidPopUpButton!
    private var autoQuitDelayPopUp: SettingsLiquidPopUpButton!
    private var autoQuitUndoHUDSwitch: NSSwitch!
    private var autoQuitRulesButton: SettingsPillButton!
    private var autoQuitPermissionLabel: NSTextField!
    private var autoQuitInspectorButton: SettingsPillButton!
    private var autoQuitChangeObserver: NSObjectProtocol?
    private var headerView: SettingsHeaderView!

    private let autoQuitDelayOptions: [(title: String, seconds: Int)] = [
        ("立即退出", 0), ("1 秒", 1), ("2 秒", 2), ("3 秒", 3), ("5 秒", 5)
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
        let sec1Title = makeSectionHeader(title: "关窗退出设置")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        autoQuitSwitch = NSSwitch()
        autoQuitSwitch.target = self
        autoQuitSwitch.action = #selector(toggleAutoQuit(_:))
        let rowSwitch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "power"),
            title: "开启关窗自动退出",
            subtitle: "关闭应用的最后一个窗口时，自动退出该应用",
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
            subtitle: "选择对所有应用生效或仅对指定应用生效",
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
            subtitle: "关闭窗口后等待设定的时间再退出应用",
            accessory: autoQuitDelayPopUp
        )
        card1.addRow(rowDelay)

        autoQuitUndoHUDSwitch = NSSwitch()
        autoQuitUndoHUDSwitch.target = self
        autoQuitUndoHUDSwitch.action = #selector(toggleAutoQuitUndoHUD(_:))
        let rowHUD = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "bell.badge"),
            title: "退出前显示倒计时浮层",
            subtitle: "显示退出倒计时，期间可点击取消退出",
            accessory: autoQuitUndoHUDSwitch
        )
        card1.addRow(rowHUD, isLast: true)

        // Section 2: 规则与应用过滤
        let sec2Title = makeSectionHeader(title: "规则与权限")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        autoQuitRulesButton = SettingsPillButton(title: "编辑名单...", target: self, action: #selector(openAutoQuitRulesEditor))
        autoQuitRulesButton.widthAnchor.constraint(equalToConstant: 148).isActive = true
        let rowRules = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "list.bullet.rectangle"),
            title: "应用规则名单",
            subtitle: "管理生效或排除的应用名单",
            accessory: autoQuitRulesButton
        )
        card2.addRow(rowRules)

        let permContainer = NSView()
        permContainer.translatesAutoresizingMaskIntoConstraints = false

        autoQuitPermissionLabel = NSTextField(labelWithString: "检查中...")
        autoQuitPermissionLabel.translatesAutoresizingMaskIntoConstraints = false
        autoQuitPermissionLabel.font = NSFont.systemFont(ofSize: 11)
        autoQuitPermissionLabel.alignment = .right
        permContainer.addSubview(autoQuitPermissionLabel)

        let openPermBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openAutoQuitAccessibility))
        openPermBtn.translatesAutoresizingMaskIntoConstraints = false
        openPermBtn.widthAnchor.constraint(equalToConstant: 148).isActive = true
        permContainer.addSubview(openPermBtn)

        NSLayoutConstraint.activate([
            openPermBtn.trailingAnchor.constraint(equalTo: permContainer.trailingAnchor),
            openPermBtn.centerYAnchor.constraint(equalTo: permContainer.centerYAnchor),
            openPermBtn.topAnchor.constraint(greaterThanOrEqualTo: permContainer.topAnchor),
            openPermBtn.bottomAnchor.constraint(lessThanOrEqualTo: permContainer.bottomAnchor),

            autoQuitPermissionLabel.trailingAnchor.constraint(equalTo: openPermBtn.leadingAnchor, constant: -8),
            autoQuitPermissionLabel.leadingAnchor.constraint(equalTo: permContainer.leadingAnchor),
            autoQuitPermissionLabel.centerYAnchor.constraint(equalTo: permContainer.centerYAnchor)
        ])

        let rowPerm = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hand.raised"),
            title: "辅助功能权限状态",
            subtitle: "用于检测应用窗口的关闭状态",
            accessory: permContainer
        )
        card2.addRow(rowPerm)

        autoQuitInspectorButton = SettingsPillButton(title: "查看记录...", target: self, action: #selector(openAutoQuitInspector))
        autoQuitInspectorButton.widthAnchor.constraint(equalToConstant: 148).isActive = true
        let rowInspector = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "stethoscope"),
            title: "运行记录与诊断",
            subtitle: "查看应用窗口状态与退出记录，或导出诊断日志",
            accessory: autoQuitInspectorButton
        )
        card2.addRow(rowInspector, isLast: true)

        let tipLabel = NSTextField(labelWithString: "提示：访达等系统常驻服务与虚拟机应用默认受保护，不会自动退出。")
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont.systemFont(ofSize: 11)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.cell?.wraps = true
        tipLabel.maximumNumberOfLines = 3
        tipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollContent.addSubview(tipLabel)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: scrollContent.topAnchor, constant: 8),
            sec1Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 7),
            card1.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            sec2Title.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 16),
            sec2Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 7),
            card2.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            tipLabel.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 10),
            tipLabel.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 32),
            tipLabel.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),
            tipLabel.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -16)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        autoQuitSwitch.state = cfg.enableAutoQuit ? .on : .off
        autoQuitModePopUp.isEnabled = cfg.enableAutoQuit
        autoQuitDelayPopUp.isEnabled = cfg.enableAutoQuit
        autoQuitUndoHUDSwitch.state = cfg.enableAutoQuitUndoHUD ? .on : .off
        autoQuitUndoHUDSwitch.isEnabled = cfg.enableAutoQuit
        autoQuitRulesButton.isEnabled = true
        autoQuitInspectorButton.isEnabled = true

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
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "检测应用窗口关闭状态需要辅助功能权限。请在「系统设置」>「隐私与安全性」>「辅助功能」中允许 ATools。是否前往设置？"
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

    @objc private func toggleAutoQuitUndoHUD(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableAutoQuitUndoHUD(sender.state == .on)
    }

    @objc private func openAutoQuitInspector() {
        guard let hostWindow = window else { return }
        guard hostWindow.attachedSheet == nil else { return }
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "AutoQuit 决策审查与应用诊断"
        sheet.isReleasedWhenClosed = false
        sheet.contentMinSize = NSSize(width: 580, height: 400)
        sheet.setContentSize(NSSize(width: 660, height: 480))
        sheet.contentView = AutoQuitInspectorSheet(frame: NSRect(x: 0, y: 0, width: 660, height: 480))
        hostWindow.beginSheet(sheet) { _ in
            _ = sheet
        }
    }
}
