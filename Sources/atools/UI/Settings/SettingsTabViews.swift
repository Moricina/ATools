import Foundation
import AppKit

private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

/// 辅助创建滚动的设置容器
func makeTabScrollView(contentView: NSView) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let flipped = FlippedContainerView()
    flipped.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = flipped

    flipped.addSubview(contentView)
    contentView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        flipped.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        flipped.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        flipped.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        flipped.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

        contentView.topAnchor.constraint(equalTo: flipped.topAnchor),
        contentView.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
        contentView.bottomAnchor.constraint(equalTo: flipped.bottomAnchor)
    ])

    return scrollView
}

func makeSectionHeader(title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
    label.textColor = .labelColor
    return label
}

// MARK: - 1. General Tab View
public final class GeneralTabView: NSView {
    private var shelfSwitch: NSSwitch!
    private var searchSwitch: NSSwitch!
    private var mutualExclusionHint: NSTextField!
    private var launchOnLoginSwitch: NSSwitch!
    private var pinSwitch: NSSwitch!
    private var pageContainer: NSView!
    private var pages: [NSView] = []
    private var headerView: SettingsHeaderView!
    private var sec1TitleTopConstraint: NSLayoutConstraint?

    // 「窗口退出」页控件
    private var autoQuitSwitch: NSSwitch!
    private var autoQuitModePopUp: NSPopUpButton!
    private var autoQuitDelayPopUp: NSPopUpButton!
    private var autoQuitRulesButton: SettingsPillButton!
    private var autoQuitPermissionLabel: NSTextField!
    private var autoQuitChangeObserver: NSObjectProtocol?
    private let autoQuitDelayOptions: [(title: String, seconds: Int)] = [
        ("立即退出", 0), ("1 秒", 1), ("2 秒 (推荐)", 2), ("3 秒", 3), ("5 秒", 5)
    ]

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
        // 状态栏菜单或名单 sheet 改配置时同步本页控件（页内分段切换不触发 refresh，
        // 所以必须自己监听配置变更）。
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

        headerView = SettingsHeaderView(title: "常规", iconName: "gearshape", tabs: ["通用与启动", "面板开关", "系统权限", "窗口退出"])
        addSubview(headerView)

        pageContainer = NSView()
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageContainer)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            pageContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Page 0: 通用与启动
        let launchPage = NSView()
        let launchScrollContent = NSView()
        let launchScroll = makeTabScrollView(contentView: launchScrollContent)
        launchPage.addSubview(launchScroll)
        NSLayoutConstraint.activate([
            launchScroll.topAnchor.constraint(equalTo: launchPage.topAnchor),
            launchScroll.leadingAnchor.constraint(equalTo: launchPage.leadingAnchor),
            launchScroll.trailingAnchor.constraint(equalTo: launchPage.trailingAnchor),
            launchScroll.bottomAnchor.constraint(equalTo: launchPage.bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "基础与系统")
        launchScrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        launchScrollContent.addSubview(card1)

        let welcomeBanner: WelcomeGuideBannerView?
        if !WelcomeGuideBannerView.hasDismissed {
            let banner = WelcomeGuideBannerView()
            banner.translatesAutoresizingMaskIntoConstraints = false
            launchScrollContent.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: launchScrollContent.topAnchor, constant: 14),
                banner.leadingAnchor.constraint(equalTo: launchScrollContent.leadingAnchor, constant: 28),
                banner.trailingAnchor.constraint(equalTo: launchScrollContent.trailingAnchor, constant: -28)
            ])
            welcomeBanner = banner
        } else {
            welcomeBanner = nil
        }

        launchOnLoginSwitch = NSSwitch()
        launchOnLoginSwitch.target = self
        launchOnLoginSwitch.action = #selector(toggleLaunchOnLogin(_:))
        let rowLaunch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "power"),
            title: "开机自启",
            subtitle: "登录 macOS 后自动启动 ATools 并驻留在右上角菜单栏",
            accessory: launchOnLoginSwitch
        )
        card1.addRow(rowLaunch)

        let autoCloseLaunchSwitch = NSSwitch()
        autoCloseLaunchSwitch.target = self
        autoCloseLaunchSwitch.action = #selector(toggleAutoCloseLaunch(_:))
        autoCloseLaunchSwitch.state = ConfigManager.shared.config.autoCloseOnLaunch ? .on : .off
        let rowCloseLaunch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.down.right.and.arrow.up.left"),
            title: "点击应用后自动关闭面板",
            subtitle: "在应用分类抽屉中点击启动后，立即自动隐藏窗口",
            accessory: autoCloseLaunchSwitch
        )
        card1.addRow(rowCloseLaunch)

        let autoCloseMouseExitSwitch = NSSwitch()
        autoCloseMouseExitSwitch.target = self
        autoCloseMouseExitSwitch.action = #selector(toggleAutoCloseMouseExit(_:))
        autoCloseMouseExitSwitch.state = ConfigManager.shared.config.autoCloseOnMouseExit ? .on : .off
        let rowCloseMouse = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "cursorarrow.motionlines"),
            title: "鼠标移出面板后自动关闭",
            subtitle: "含 0.35s 智能防抖延迟与右键菜单弹出保护",
            accessory: autoCloseMouseExitSwitch
        )
        card1.addRow(rowCloseMouse)

        let autoCloseDeactivateSwitch = NSSwitch()
        autoCloseDeactivateSwitch.target = self
        autoCloseDeactivateSwitch.action = #selector(toggleAutoCloseDeactivate(_:))
        autoCloseDeactivateSwitch.state = ConfigManager.shared.config.autoCloseOnDeactivate ? .on : .off
        let rowCloseDeactivate = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "macwindow.badge.plus"),
            title: "失焦时自动关闭",
            subtitle: "点击面板外部任意工作区或切换应用时自动收起窗口",
            accessory: autoCloseDeactivateSwitch,
            minHeight: 46
        )
        card1.addRow(rowCloseDeactivate, isLast: true)

        let sec1Top: NSLayoutConstraint
        if let banner = welcomeBanner {
            sec1Top = sec1Title.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 18)
            banner.onNavigateToSpotlightGuide = { [weak self] in
                self?.headerView.segmentedControl.selectedSegment = 2
                self?.showPage(2)
            }
            banner.onDismiss = { [weak self, weak banner, weak launchScrollContent] in
                guard let banner = banner, let content = launchScrollContent else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    banner.animator().alphaValue = 0
                }, completionHandler: {
                    banner.removeFromSuperview()
                    self?.sec1TitleTopConstraint?.isActive = false
                    let newTop = sec1Title.topAnchor.constraint(equalTo: content.topAnchor, constant: 14)
                    self?.sec1TitleTopConstraint = newTop
                    newTop.isActive = true
                })
            }
        } else {
            sec1Top = sec1Title.topAnchor.constraint(equalTo: launchScrollContent.topAnchor, constant: 14)
        }
        self.sec1TitleTopConstraint = sec1Top

        NSLayoutConstraint.activate([
            sec1Top,
            sec1Title.leadingAnchor.constraint(equalTo: launchScrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 8),
            card1.leadingAnchor.constraint(equalTo: launchScrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: launchScrollContent.trailingAnchor, constant: -28),
            card1.bottomAnchor.constraint(equalTo: launchScrollContent.bottomAnchor, constant: -28)
        ])

        // Page 1: 面板开关
        let panelPage = NSView()
        let panelScrollContent = NSView()
        let panelScroll = makeTabScrollView(contentView: panelScrollContent)
        panelPage.addSubview(panelScroll)
        NSLayoutConstraint.activate([
            panelScroll.topAnchor.constraint(equalTo: panelPage.topAnchor),
            panelScroll.leadingAnchor.constraint(equalTo: panelPage.leadingAnchor),
            panelScroll.trailingAnchor.constraint(equalTo: panelPage.trailingAnchor),
            panelScroll.bottomAnchor.constraint(equalTo: panelPage.bottomAnchor)
        ])

        let sec2Title = makeSectionHeader(title: "功能面板启用控制")
        panelScrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        panelScrollContent.addSubview(card2)

        shelfSwitch = NSSwitch()
        shelfSwitch.target = self
        shelfSwitch.action = #selector(toggleShelfPanel(_:))
        let rowShelf = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "square.grid.2x2"),
            title: "启用应用分类工作台",
            subtitle: "支持自定义分类、拖拽整理与快速启停",
            accessory: shelfSwitch
        )
        card2.addRow(rowShelf)

        searchSwitch = NSSwitch()
        searchSwitch.target = self
        searchSwitch.action = #selector(toggleSearchPanel(_:))
        let rowSearch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass"),
            title: "启用全盘搜索中枢",
            subtitle: "毫秒级全盘文件秒搜、公式即时计算与系统词典",
            accessory: searchSwitch
        )
        card2.addRow(rowSearch, isLast: true)

        let secPinTitle = makeSectionHeader(title: "面板驻留行为")
        panelScrollContent.addSubview(secPinTitle)

        let cardPin = SettingsCardView()
        cardPin.translatesAutoresizingMaskIntoConstraints = false
        panelScrollContent.addSubview(cardPin)

        pinSwitch = NSSwitch()
        pinSwitch.target = self
        pinSwitch.action = #selector(togglePin(_:))
        let rowPin = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "pin.fill"),
            title: "固定应用抽屉在桌面",
            subtitle: "开启后抽屉忽略失焦与鼠标移出关闭；跨 App 拖拽保护始终独立生效",
            accessory: pinSwitch
        )
        cardPin.addRow(rowPin, isLast: true)

        mutualExclusionHint = NSTextField(labelWithString: "💡 提示：为了保证随时有可用的生产力入口，不能同时禁用两个面板。")
        mutualExclusionHint.translatesAutoresizingMaskIntoConstraints = false
        mutualExclusionHint.font = NSFont.systemFont(ofSize: 11)
        mutualExclusionHint.textColor = .secondaryLabelColor
        mutualExclusionHint.cell?.wraps = true
        mutualExclusionHint.maximumNumberOfLines = 2
        mutualExclusionHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        panelScrollContent.addSubview(mutualExclusionHint)

        NSLayoutConstraint.activate([
            sec2Title.topAnchor.constraint(equalTo: panelScrollContent.topAnchor, constant: 14),
            sec2Title.leadingAnchor.constraint(equalTo: panelScrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 8),
            card2.leadingAnchor.constraint(equalTo: panelScrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: panelScrollContent.trailingAnchor, constant: -28),

            secPinTitle.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 20),
            secPinTitle.leadingAnchor.constraint(equalTo: panelScrollContent.leadingAnchor, constant: 28),

            cardPin.topAnchor.constraint(equalTo: secPinTitle.bottomAnchor, constant: 8),
            cardPin.leadingAnchor.constraint(equalTo: panelScrollContent.leadingAnchor, constant: 28),
            cardPin.trailingAnchor.constraint(equalTo: panelScrollContent.trailingAnchor, constant: -28),

            mutualExclusionHint.topAnchor.constraint(equalTo: cardPin.bottomAnchor, constant: 8),
            mutualExclusionHint.leadingAnchor.constraint(equalTo: panelScrollContent.leadingAnchor, constant: 32),
            mutualExclusionHint.trailingAnchor.constraint(equalTo: panelScrollContent.trailingAnchor, constant: -28),
            mutualExclusionHint.bottomAnchor.constraint(equalTo: panelScrollContent.bottomAnchor, constant: -28)
        ])

        // Page 2: 系统权限与环境引导
        let permPage = NSView()
        let permScrollContent = NSView()
        let permScroll = makeTabScrollView(contentView: permScrollContent)
        permPage.addSubview(permScroll)
        NSLayoutConstraint.activate([
            permScroll.topAnchor.constraint(equalTo: permPage.topAnchor),
            permScroll.leadingAnchor.constraint(equalTo: permPage.leadingAnchor),
            permScroll.trailingAnchor.constraint(equalTo: permPage.trailingAnchor),
            permScroll.bottomAnchor.constraint(equalTo: permPage.bottomAnchor)
        ])

        let sec3Title = makeSectionHeader(title: "系统安全与隐私权限")
        permScrollContent.addSubview(sec3Title)

        let card3 = SettingsCardView()
        card3.translatesAutoresizingMaskIntoConstraints = false
        permScrollContent.addSubview(card3)

        let fdaBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openFDA))
        let rowFDA = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "lock.shield"),
            title: "完全磁盘访问权限 (Full Disk Access)",
            subtitle: "若搜不到“下载”或“文稿”等受 TCC 保护的目录文件，请前往系统设置授权",
            accessory: fdaBtn
        )
        card3.addRow(rowFDA, isLast: true)

        let secSpotlightTitle = makeSectionHeader(title: "系统聚焦 (Spotlight) 完整平替指南")
        permScrollContent.addSubview(secSpotlightTitle)

        let cardSpotlight = SettingsCardView()
        cardSpotlight.translatesAutoresizingMaskIntoConstraints = false
        permScrollContent.addSubview(cardSpotlight)

        let kbBtn = SettingsPillButton(title: "前往键盘设置...", target: self, action: #selector(openKeyboardSettings))
        let rowKB = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "command"),
            title: "步骤 1：禁用系统 Spotlight 快捷键",
            subtitle: "在 macOS「键盘」->「快捷键」取消聚焦勾选，释放 ⌘Space 由 ATools 接管",
            accessory: kbBtn
        )
        cardSpotlight.addRow(rowKB)

        let ccBtn = SettingsPillButton(title: "前往控制中心...", target: self, action: #selector(openControlCenterSettings))
        let rowCC = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "menubar.arrow.up.rectangle"),
            title: "步骤 2：隐藏系统菜单栏聚焦图标",
            subtitle: "在 macOS「控制中心」将聚焦设为「不在菜单栏中显示」，只保留 ATools 图标",
            accessory: ccBtn
        )
        cardSpotlight.addRow(rowCC, isLast: true)

        let spotlightTip = NSTextField(labelWithString: "💡 技术保障：ATools 直接复用 macOS 原生 CoreServices 索引，无需额外后台扫描进程，请勿在终端强行停用系统 mds 索引。")
        spotlightTip.translatesAutoresizingMaskIntoConstraints = false
        spotlightTip.font = NSFont.systemFont(ofSize: 11)
        spotlightTip.textColor = .secondaryLabelColor
        spotlightTip.cell?.wraps = true
        spotlightTip.maximumNumberOfLines = 3
        spotlightTip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permScrollContent.addSubview(spotlightTip)

        NSLayoutConstraint.activate([
            sec3Title.topAnchor.constraint(equalTo: permScrollContent.topAnchor, constant: 14),
            sec3Title.leadingAnchor.constraint(equalTo: permScrollContent.leadingAnchor, constant: 28),

            card3.topAnchor.constraint(equalTo: sec3Title.bottomAnchor, constant: 8),
            card3.leadingAnchor.constraint(equalTo: permScrollContent.leadingAnchor, constant: 28),
            card3.trailingAnchor.constraint(equalTo: permScrollContent.trailingAnchor, constant: -28),

            secSpotlightTitle.topAnchor.constraint(equalTo: card3.bottomAnchor, constant: 20),
            secSpotlightTitle.leadingAnchor.constraint(equalTo: permScrollContent.leadingAnchor, constant: 28),

            cardSpotlight.topAnchor.constraint(equalTo: secSpotlightTitle.bottomAnchor, constant: 8),
            cardSpotlight.leadingAnchor.constraint(equalTo: permScrollContent.leadingAnchor, constant: 28),
            cardSpotlight.trailingAnchor.constraint(equalTo: permScrollContent.trailingAnchor, constant: -28),

            spotlightTip.topAnchor.constraint(equalTo: cardSpotlight.bottomAnchor, constant: 10),
            spotlightTip.leadingAnchor.constraint(equalTo: permScrollContent.leadingAnchor, constant: 32),
            spotlightTip.trailingAnchor.constraint(equalTo: permScrollContent.trailingAnchor, constant: -28),
            spotlightTip.bottomAnchor.constraint(equalTo: permScrollContent.bottomAnchor, constant: -28)
        ])

        // Page 3: 窗口退出 (AutoQuit) —— 必须追加在 pages 末尾，欢迎横幅硬编码跳转 showPage(2)
        let autoQuitPage = NSView()
        let autoQuitScrollContent = NSView()
        let autoQuitScroll = makeTabScrollView(contentView: autoQuitScrollContent)
        autoQuitPage.addSubview(autoQuitScroll)
        NSLayoutConstraint.activate([
            autoQuitScroll.topAnchor.constraint(equalTo: autoQuitPage.topAnchor),
            autoQuitScroll.leadingAnchor.constraint(equalTo: autoQuitPage.leadingAnchor),
            autoQuitScroll.trailingAnchor.constraint(equalTo: autoQuitPage.trailingAnchor),
            autoQuitScroll.bottomAnchor.constraint(equalTo: autoQuitPage.bottomAnchor)
        ])

        let sec4Title = makeSectionHeader(title: "关闭窗口即退出应用")
        autoQuitScrollContent.addSubview(sec4Title)

        let card4 = SettingsCardView()
        card4.translatesAutoresizingMaskIntoConstraints = false
        autoQuitScrollContent.addSubview(card4)

        autoQuitSwitch = NSSwitch()
        autoQuitSwitch.target = self
        autoQuitSwitch.action = #selector(toggleAutoQuit(_:))
        let rowAutoQuit = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "xmark.circle"),
            title: "最后一个窗口关闭后退出应用",
            subtitle: "点击窗口红色关闭按钮且应用再无其他窗口时，延迟自动退出该应用（对标 SwiftQuit）",
            accessory: autoQuitSwitch
        )
        card4.addRow(rowAutoQuit)

        autoQuitPermissionLabel = NSTextField(labelWithString: "")
        autoQuitPermissionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let autoQuitPermissionBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openAutoQuitAccessibility))
        let permissionStack = NSStackView(views: [autoQuitPermissionLabel, autoQuitPermissionBtn])
        permissionStack.orientation = .horizontal
        permissionStack.spacing = 8
        permissionStack.alignment = .centerY
        let rowAutoQuitPermission = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "accessibility"),
            title: "辅助功能授权状态",
            subtitle: "监听窗口关闭事件需在系统设置中允许「辅助功能」；ATools 仅感知窗口数量变化，不读取任何窗口内容",
            accessory: permissionStack
        )
        card4.addRow(rowAutoQuitPermission)

        autoQuitModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in AutoQuitMode.allCases {
            autoQuitModePopUp.addItem(withTitle: mode.title)
        }
        autoQuitModePopUp.target = self
        autoQuitModePopUp.action = #selector(autoQuitModeChanged(_:))
        autoQuitModePopUp.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let rowAutoQuitMode = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "scope"),
            title: "作用范围",
            subtitle: "「全部应用」开箱即用；追求可控可选「仅名单内」，只自动退出勾选的应用",
            accessory: autoQuitModePopUp
        )
        card4.addRow(rowAutoQuitMode)

        autoQuitDelayPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in autoQuitDelayOptions {
            autoQuitDelayPopUp.addItem(withTitle: option.title)
        }
        autoQuitDelayPopUp.target = self
        autoQuitDelayPopUp.action = #selector(autoQuitDelayChanged(_:))
        autoQuitDelayPopUp.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let rowAutoQuitDelay = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "timer"),
            title: "退出延迟",
            subtitle: "确认窗口关闭后的等待时间；延迟内重开窗口会自动取消退出",
            accessory: autoQuitDelayPopUp
        )
        card4.addRow(rowAutoQuitDelay)

        autoQuitRulesButton = SettingsPillButton(title: "编辑名单...", target: self, action: #selector(openAutoQuitRulesEditor))
        let rowAutoQuitRules = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "list.bullet.rectangle"),
            title: "应用名单",
            subtitle: "勾选的应用构成名单：随上方「作用范围」作为排除项或退出项生效",
            accessory: autoQuitRulesButton
        )
        card4.addRow(rowAutoQuitRules, isLast: true)

        let autoQuitTip = NSTextField(labelWithString: "💡 边界保护：未保存文档会先弹保存框（窗口未真正关闭不退出）；最小化、⌘H 隐藏或位于其他空间的窗口不误判；访达等系统应用与应用本身永远排除。")
        autoQuitTip.translatesAutoresizingMaskIntoConstraints = false
        autoQuitTip.font = NSFont.systemFont(ofSize: 11)
        autoQuitTip.textColor = .secondaryLabelColor
        autoQuitTip.cell?.wraps = true
        autoQuitTip.maximumNumberOfLines = 3
        autoQuitTip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        autoQuitScrollContent.addSubview(autoQuitTip)

        NSLayoutConstraint.activate([
            sec4Title.topAnchor.constraint(equalTo: autoQuitScrollContent.topAnchor, constant: 14),
            sec4Title.leadingAnchor.constraint(equalTo: autoQuitScrollContent.leadingAnchor, constant: 28),

            card4.topAnchor.constraint(equalTo: sec4Title.bottomAnchor, constant: 8),
            card4.leadingAnchor.constraint(equalTo: autoQuitScrollContent.leadingAnchor, constant: 28),
            card4.trailingAnchor.constraint(equalTo: autoQuitScrollContent.trailingAnchor, constant: -28),

            autoQuitTip.topAnchor.constraint(equalTo: card4.bottomAnchor, constant: 10),
            autoQuitTip.leadingAnchor.constraint(equalTo: autoQuitScrollContent.leadingAnchor, constant: 32),
            autoQuitTip.trailingAnchor.constraint(equalTo: autoQuitScrollContent.trailingAnchor, constant: -28),
            autoQuitTip.bottomAnchor.constraint(equalTo: autoQuitScrollContent.bottomAnchor, constant: -28)
        ])

        pages = [launchPage, panelPage, permPage, autoQuitPage]
        for (idx, page) in pages.enumerated() {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
            ])
            page.isHidden = (idx != 0)
        }

        headerView.onSegmentChanged = { [weak self] index in
            self?.showPage(index)
        }
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        shelfSwitch.state = cfg.enableShelfPanel ? .on : .off
        searchSwitch.state = cfg.enableSearchPanel ? .on : .off
        shelfSwitch.isEnabled = cfg.enableSearchPanel
        searchSwitch.isEnabled = cfg.enableShelfPanel
        pinSwitch.state = cfg.isShelfPinned ? .on : .off
        refreshLaunchOnLogin()
        refreshAutoQuitPage()
    }

    private func refreshAutoQuitPage() {
        guard autoQuitSwitch != nil else { return }
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
            // 手改配置出现的非预设值：选最接近的预设，避免显示过期选项
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
        // 授权引导只在用户显式点击开关时出现；refresh() 绝不触发系统弹窗（--test 环境安全）
        let alert = NSAlert()
        alert.messageText = "「窗口退出」需要辅助功能授权"
        alert.informativeText = "监听其他应用窗口的关闭事件，需要 macOS「系统设置」->「隐私与安全性」->「辅助功能」中允许 ATools。\n\nATools 仅感知窗口数量变化，绝不读取任何窗口内容或键入信息。是否前往授权？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往系统设置")
        alert.addButton(withTitle: "暂不开启")
        if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
            HotkeyManager.openAccessibilitySettings()
            // 保存开关；在授权完成前 AutoQuitManager 保持空闲，授权后切回应用即热启动
            ConfigManager.shared.updateEnableAutoQuit(true)
        } else {
            sender.state = .off
        }
    }

    @objc private func autoQuitModeChanged(_ sender: NSPopUpButton) {
        let modes = AutoQuitMode.allCases
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        ConfigManager.shared.updateAutoQuitMode(modes[sender.indexOfSelectedItem])
        refreshAutoQuitPage()
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
        // 防重入：连点两次会让第二个 beginSheet 排队，叠加上一次的呈现耗时
        // 造成可感知的卡顿（见 CHANGELOG 十-修复记录）。
        guard hostWindow.attachedSheet == nil else {
            runtimeLog("[AutoQuit] rules sheet already attached; ignoring re-entrant open")
            return
        }
        let t0 = Date()
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
        let constructDone = Date()
        // 在 completion 闭包里强持有 sheet，endSheet 关闭后由 ARC 安全释放（不泄漏不悬垂）
        hostWindow.beginSheet(sheet) { _ in
            _ = sheet
        }
        runtimeLog("[AutoQuit] rules sheet: construct=\(String(format: "%.0f", constructDone.timeIntervalSince(t0) * 1000))ms present=\(String(format: "%.0f", Date().timeIntervalSince(constructDone) * 1000))ms")
    }

    @objc private func toggleLaunchOnLogin(_ sender: NSSwitch) {
        let desired = (sender.state == .on)
        do {
            let newState = try LaunchAtLoginController.shared.setEnabled(desired)
            if newState == .requiresApproval {
                NSSound.beep()
                let alert = NSAlert()
                alert.messageText = "需要系统授权"
                alert.informativeText = "请在「系统设置」->「通用」->「登录项」中允许 ATools 开机自启。"
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "好")
                if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
                    LaunchAtLoginController.shared.openLoginItemsSettings()
                }
            }
        } catch {
            NSSound.beep()
        }
        refreshLaunchOnLogin()
    }

    private func refreshLaunchOnLogin() {
        guard let launchOnLoginSwitch = launchOnLoginSwitch else { return }
        let supported = LaunchAtLoginController.shared.isSupported
        launchOnLoginSwitch.isEnabled = supported
        launchOnLoginSwitch.state = LaunchAtLoginController.shared.isEnabled ? .on : .off
    }

    @objc private func togglePin(_ sender: NSSwitch) {
        ConfigManager.shared.updateIsShelfPinned(sender.state == .on)
        PanelCoordinator.shared.refreshShelfPinState()
    }

    private func showPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        for (idx, page) in pages.enumerated() {
            page.isHidden = (idx != index)
        }
    }

    @objc private func toggleAutoCloseLaunch(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoCloseOnLaunch(sender.state == .on)
    }

    @objc private func toggleAutoCloseMouseExit(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoCloseOnMouseExit(sender.state == .on)
    }

    @objc private func toggleAutoCloseDeactivate(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoCloseOnDeactivate(sender.state == .on)
    }

    @objc private func toggleShelfPanel(_ sender: NSSwitch) {
        let desired = (sender.state == .on)
        if !ConfigManager.shared.updateEnableShelfPanel(desired) {
            NSSound.beep()
            sender.state = .on
        } else {
            if desired {
                HotkeyManager.shared.register(id: .shelf, binding: ConfigManager.shared.config.shelfHotkey)
            } else {
                HotkeyManager.shared.unregister(id: .shelf)
                PanelCoordinator.shared.shelfPanel.orderOut(nil)
            }
            NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
            refresh()
        }
    }

    @objc private func toggleSearchPanel(_ sender: NSSwitch) {
        let desired = (sender.state == .on)
        if !ConfigManager.shared.updateEnableSearchPanel(desired) {
            NSSound.beep()
            sender.state = .on
        } else {
            if desired {
                HotkeyManager.shared.register(id: .search, binding: ConfigManager.shared.config.searchHotkey)
            } else {
                HotkeyManager.shared.unregister(id: .search)
                PanelCoordinator.shared.searchPanel.orderOut(nil)
            }
            NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
            refresh()
        }
    }

    @objc private func openFDA() {
        if #available(macOS 13.0, *), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
            return
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc private func openKeyboardSettings() {
        HotkeyManager.shared.openSystemKeyboardSettings()
    }

    @objc private func openControlCenterSettings() {
        if #available(macOS 13.0, *), let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            if NSWorkspace.shared.open(url) { return }
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - 2. Shelf Tab View
public final class ShelfTabView: NSView {
    private var orientationControl: NSSegmentedControl!
    private var iconSizeSlider: NSSlider!
    private var iconSizeBadge: NSTextField!
    private var trackpadGesturePopUp: NSPopUpButton!
    private var favoritesSwitch: NSSwitch!
    private var pageContainer: NSView!
    private var pages: [NSView] = []
    private var headerView: SettingsHeaderView!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        headerView = SettingsHeaderView(title: "应用抽屉", iconName: "square.grid.2x2", tabs: ["布局与排版", "分类管理"])
        addSubview(headerView)

        pageContainer = NSView()
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageContainer)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            pageContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Page 0: 布局与排版
        let layoutPage = NSView()
        let layoutScrollContent = NSView()
        let layoutScroll = makeTabScrollView(contentView: layoutScrollContent)
        layoutPage.addSubview(layoutScroll)
        NSLayoutConstraint.activate([
            layoutScroll.topAnchor.constraint(equalTo: layoutPage.topAnchor),
            layoutScroll.leadingAnchor.constraint(equalTo: layoutPage.leadingAnchor),
            layoutScroll.trailingAnchor.constraint(equalTo: layoutPage.trailingAnchor),
            layoutScroll.bottomAnchor.constraint(equalTo: layoutPage.bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "排版与尺寸")
        layoutScrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        layoutScrollContent.addSubview(card1)

        orientationControl = NSSegmentedControl(labels: ["横向排版 (顶部标签)", "纵向排版 (左侧侧边栏)"], trackingMode: .selectOne, target: self, action: #selector(orientationChanged(_:)))
        let rowOrient = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "rectangle.split.2x1"),
            title: "抽屉排版方向",
            subtitle: "支持横向顶部胶囊标签或纵向侧边导航",
            accessory: orientationControl
        )
        card1.addRow(rowOrient)

        let scaleContainer = NSView()
        scaleContainer.translatesAutoresizingMaskIntoConstraints = false

        iconSizeSlider = NSSlider(value: 100, minValue: 70, maxValue: 130, target: self, action: #selector(scaleSliderChanged(_:)))
        iconSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        iconSizeSlider.numberOfTickMarks = 5
        iconSizeSlider.allowsTickMarkValuesOnly = true
        iconSizeSlider.isContinuous = true
        scaleContainer.addSubview(iconSizeSlider)

        let badgeContainer = NSView()
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 10
        badgeContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        scaleContainer.addSubview(badgeContainer)

        iconSizeBadge = NSTextField(labelWithString: "100%（默认）")
        iconSizeBadge.translatesAutoresizingMaskIntoConstraints = false
        iconSizeBadge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        iconSizeBadge.textColor = .labelColor
        badgeContainer.addSubview(iconSizeBadge)

        NSLayoutConstraint.activate([
            scaleContainer.widthAnchor.constraint(equalToConstant: 260),
            scaleContainer.heightAnchor.constraint(equalToConstant: 28),

            iconSizeSlider.leadingAnchor.constraint(equalTo: scaleContainer.leadingAnchor),
            iconSizeSlider.centerYAnchor.constraint(equalTo: scaleContainer.centerYAnchor),
            iconSizeSlider.trailingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: -10),

            badgeContainer.trailingAnchor.constraint(equalTo: scaleContainer.trailingAnchor),
            badgeContainer.centerYAnchor.constraint(equalTo: scaleContainer.centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 20),

            iconSizeBadge.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            iconSizeBadge.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            iconSizeBadge.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
        ])

        let rowScale = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "app.dashed"),
            title: "图标缩放比例",
            subtitle: "支持 70% ~ 130% 五档缩放",
            accessory: scaleContainer
        )
        card1.addRow(rowScale, isLast: true)

        let secGestureTitle = makeSectionHeader(title: "唤出与触控手势")
        layoutScrollContent.addSubview(secGestureTitle)

        let cardGesture = SettingsCardView()
        cardGesture.translatesAutoresizingMaskIntoConstraints = false
        layoutScrollContent.addSubview(cardGesture)

        trackpadGesturePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        trackpadGesturePopUp.translatesAutoresizingMaskIntoConstraints = false
        trackpadGesturePopUp.widthAnchor.constraint(equalToConstant: 220).isActive = true
        for gesture in ShelfTrackpadGesture.allCases {
            trackpadGesturePopUp.addItem(withTitle: gesture.title)
        }
        trackpadGesturePopUp.target = self
        trackpadGesturePopUp.action = #selector(trackpadGestureChanged(_:))

        let rowGesture = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hand.point.up.left"),
            title: "触控板手势唤出",
            subtitle: "在触控板上触发手势即可直接呼出或收回抽屉面板",
            accessory: trackpadGesturePopUp
        )
        cardGesture.addRow(rowGesture, isLast: true)

        let gestureTipLabel = NSTextField(labelWithString: "💡 提示：四指轻点与系统快捷手势完全不冲突（推荐首选）；若选用三指轻点，请确保系统「三指轻点查询」已调整或关闭。")
        gestureTipLabel.translatesAutoresizingMaskIntoConstraints = false
        gestureTipLabel.font = NSFont.systemFont(ofSize: 11)
        gestureTipLabel.textColor = .secondaryLabelColor
        gestureTipLabel.cell?.wraps = true
        gestureTipLabel.maximumNumberOfLines = 2
        gestureTipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        layoutScrollContent.addSubview(gestureTipLabel)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: layoutScrollContent.topAnchor, constant: 14),
            sec1Title.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 8),
            card1.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: layoutScrollContent.trailingAnchor, constant: -28),

            secGestureTitle.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 18),
            secGestureTitle.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 28),

            cardGesture.topAnchor.constraint(equalTo: secGestureTitle.bottomAnchor, constant: 8),
            cardGesture.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 28),
            cardGesture.trailingAnchor.constraint(equalTo: layoutScrollContent.trailingAnchor, constant: -28),

            gestureTipLabel.topAnchor.constraint(equalTo: cardGesture.bottomAnchor, constant: 6),
            gestureTipLabel.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 32),
            gestureTipLabel.trailingAnchor.constraint(equalTo: layoutScrollContent.trailingAnchor, constant: -28),
            gestureTipLabel.bottomAnchor.constraint(equalTo: layoutScrollContent.bottomAnchor, constant: -28)
        ])

        // Page 1: 分类管理
        let categoryPage = NSView()
        let categoryScrollContent = NSView()
        let categoryScroll = makeTabScrollView(contentView: categoryScrollContent)
        categoryPage.addSubview(categoryScroll)
        NSLayoutConstraint.activate([
            categoryScroll.topAnchor.constraint(equalTo: categoryPage.topAnchor),
            categoryScroll.leadingAnchor.constraint(equalTo: categoryPage.leadingAnchor),
            categoryScroll.trailingAnchor.constraint(equalTo: categoryPage.trailingAnchor),
            categoryScroll.bottomAnchor.constraint(equalTo: categoryPage.bottomAnchor)
        ])

        let sec2Title = makeSectionHeader(title: "分类与标签")
        categoryScrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        categoryScrollContent.addSubview(card2)

        favoritesSwitch = NSSwitch()
        favoritesSwitch.target = self
        favoritesSwitch.action = #selector(toggleFavorites(_:))
        let rowFav = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "star.fill"),
            title: "启用「常用」应用标签分类",
            subtitle: "开启后自动智能扫描系统装机常用 App 并置顶展示；关闭时自动清空",
            accessory: favoritesSwitch
        )
        card2.addRow(rowFav, isLast: true)

        let tipLabel = NSTextField(labelWithString: "💡 提示：在抽屉面板任意标签或空白处右键，可快速新建、重命名或安全删除分类。")
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont.systemFont(ofSize: 11)
        tipLabel.textColor = .secondaryLabelColor
        categoryScrollContent.addSubview(tipLabel)

        NSLayoutConstraint.activate([
            sec2Title.topAnchor.constraint(equalTo: categoryScrollContent.topAnchor, constant: 14),
            sec2Title.leadingAnchor.constraint(equalTo: categoryScrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 8),
            card2.leadingAnchor.constraint(equalTo: categoryScrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: categoryScrollContent.trailingAnchor, constant: -28),

            tipLabel.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 8),
            tipLabel.leadingAnchor.constraint(equalTo: categoryScrollContent.leadingAnchor, constant: 32),
            tipLabel.bottomAnchor.constraint(equalTo: categoryScrollContent.bottomAnchor, constant: -28)
        ])

        pages = [layoutPage, categoryPage]
        for (idx, page) in pages.enumerated() {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
            ])
            page.isHidden = (idx != 0)
        }

        headerView.onSegmentChanged = { [weak self] index in
            self?.showPage(index)
        }
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        orientationControl.selectedSegment = (cfg.categoryOrientation == .vertical) ? 1 : 0
        iconSizeSlider.doubleValue = cfg.shelfIconScale * 100.0
        let pct = Int(round(cfg.shelfIconScale * 100.0))
        iconSizeBadge.stringValue = (pct == 100) ? "100%（默认）" : "\(pct)%"
        favoritesSwitch.state = cfg.enableFavoritesCategory ? .on : .off
        if let idx = ShelfTrackpadGesture.allCases.firstIndex(of: cfg.shelfTrackpadGesture) {
            trackpadGesturePopUp.selectItem(at: idx)
        }
        trackpadGesturePopUp.isEnabled = cfg.enableShelfPanel
    }

    @objc private func trackpadGestureChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        let all = ShelfTrackpadGesture.allCases
        guard all.indices.contains(index) else { return }
        let selected = all[index]
        ConfigManager.shared.updateShelfTrackpadGesture(selected)
    }

    private func showPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        for (idx, page) in pages.enumerated() {
            page.isHidden = (idx != index)
        }
    }

    @objc private func orientationChanged(_ sender: NSSegmentedControl) {
        let newOrientation: CategoryOrientation = (sender.selectedSegment == 1) ? .vertical : .horizontal
        ConfigManager.shared.updateCategoryOrientation(newOrientation)
        NotificationCenter.default.post(name: .atoolsCategoryOrientationDidChange, object: nil)
    }

    @objc private func scaleSliderChanged(_ sender: NSSlider) {
        let val = round(sender.doubleValue)
        let scale = val / 100.0
        let pct = Int(val)
        iconSizeBadge.stringValue = (pct == 100) ? "100%（默认）" : "\(pct)%"
        // A continuous slider fires for every drag event; only react to real value changes
        // (each change rebuilds the grid and re-snaps the shelf window).
        guard abs(scale - ConfigManager.shared.config.shelfIconScale) > 0.001 else { return }
        ConfigManager.shared.updateShelfIconScale(scale)
        NotificationCenter.default.post(name: .atoolsShelfIconSizeDidChange, object: nil)
    }

    @objc private func toggleFavorites(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableFavoritesCategory(sender.state == .on)
        NotificationCenter.default.post(name: .atoolsFavoritesToggleDidChange, object: nil)
    }
}

// MARK: - 3. Search Tab View
public final class SearchTabView: NSView, NSTextFieldDelegate {
    private var diskSearchSwitch: NSSwitch!
    private var autoPasteSwitch: NSSwitch!
    private var dictSwitch: NSSwitch!
    private var calcSwitch: NSSwitch!
    private var limitControl: NSSegmentedControl!
    private var webSearchSwitch: NSSwitch!
    private var enginePopUp: NSPopUpButton!
    private var customURLField: NSTextField!
    private var pageContainer: NSView!
    private var pages: [NSView] = []
    private var headerView: SettingsHeaderView!
    private var hotFolderStack: NSStackView!

    // 排除范围页控件
    private var excludeCachesSwitch: NSSwitch!
    private var excludeLogsSwitch: NSSwitch!
    private var excludeDevSwitch: NSSwitch!
    private var excludeUserLibSwitch: NSSwitch!
    private var excludeTrashSwitch: NSSwitch!
    private var excludeHiddenSwitch: NSSwitch!
    private var customExclusionStack: NSStackView!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        headerView = SettingsHeaderView(title: "全盘搜索", iconName: "magnifyingglass", tabs: ["搜索选项", "排除范围", "扩展功能", "网络搜索"])
        addSubview(headerView)

        pageContainer = NSView()
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageContainer)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            pageContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Page 0: 搜索选项
        let optionsPage = NSView()
        let optionsScrollContent = NSView()
        let optionsScroll = makeTabScrollView(contentView: optionsScrollContent)
        optionsPage.addSubview(optionsScroll)
        NSLayoutConstraint.activate([
            optionsScroll.topAnchor.constraint(equalTo: optionsPage.topAnchor),
            optionsScroll.leadingAnchor.constraint(equalTo: optionsPage.leadingAnchor),
            optionsScroll.trailingAnchor.constraint(equalTo: optionsPage.trailingAnchor),
            optionsScroll.bottomAnchor.constraint(equalTo: optionsPage.bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "搜索选项与结果数量")
        optionsScrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        optionsScrollContent.addSubview(card1)

        diskSearchSwitch = NSSwitch()
        diskSearchSwitch.target = self
        diskSearchSwitch.action = #selector(toggleDiskSearch(_:))
        let rowDisk = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "opticaldiscdrive"),
            title: "全盘深度文件搜索 (基于 Spotlight 索引)",
            subtitle: "直连系统 CoreServices 索引，复用已有索引数据，毫秒级流式返回文件结果",
            accessory: diskSearchSwitch
        )
        card1.addRow(rowDisk)

        limitControl = NSSegmentedControl(labels: ["30 条", "50 条", "80 条 (推荐)", "120 条"], trackingMode: .selectOne, target: self, action: #selector(limitChanged(_:)))
        let rowLimit = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "list.number"),
            title: "搜索结果条数上限",
            subtitle: "控制全盘搜索中枢最大展示条目，避免过多项目占用视觉与内存",
            accessory: limitControl
        )
        card1.addRow(rowLimit)

        autoPasteSwitch = NSSwitch()
        autoPasteSwitch.target = self
        autoPasteSwitch.action = #selector(toggleAutoPaste(_:))
        let rowAutoPaste = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "doc.on.clipboard"),
            title: "复制后立即呼出时自动粘贴",
            subtitle: "在外部复制文本后短时间（3 秒）内唤出全盘搜索，自动填入复制内容并开始检索",
            accessory: autoPasteSwitch
        )
        card1.addRow(rowAutoPaste, isLast: true)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: optionsScrollContent.topAnchor, constant: 14),
            sec1Title.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 8),
            card1.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28)
        ])

        // 自定义热目录：内存快照白名单（只进快照，不影响全盘检索范围）
        let secHotTitle = makeSectionHeader(title: "自定义热目录")
        optionsScrollContent.addSubview(secHotTitle)

        let cardHot = SettingsCardView()
        cardHot.translatesAutoresizingMaskIntoConstraints = false
        cardHot.onDropFolders = { [weak self] droppedPaths in
            var addedCount = 0
            for path in droppedPaths {
                if ConfigManager.shared.addHotFolder(path) {
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                self?.reloadHotFolderRows()
            } else {
                NSSound.beep()
            }
        }
        optionsScrollContent.addSubview(cardHot)

        let hotFolderContainer = NSView()
        hotFolderContainer.translatesAutoresizingMaskIntoConstraints = false
        cardHot.addRow(hotFolderContainer, isLast: true)

        hotFolderStack = NSStackView()
        hotFolderStack.orientation = .vertical
        hotFolderStack.spacing = 0
        hotFolderStack.distribution = .fill
        hotFolderStack.alignment = .leading
        hotFolderStack.translatesAutoresizingMaskIntoConstraints = false
        hotFolderContainer.addSubview(hotFolderStack)
        NSLayoutConstraint.activate([
            hotFolderStack.topAnchor.constraint(equalTo: hotFolderContainer.topAnchor),
            hotFolderStack.bottomAnchor.constraint(equalTo: hotFolderContainer.bottomAnchor),
            hotFolderStack.leadingAnchor.constraint(equalTo: hotFolderContainer.leadingAnchor),
            hotFolderStack.trailingAnchor.constraint(equalTo: hotFolderContainer.trailingAnchor),
            hotFolderStack.widthAnchor.constraint(equalTo: hotFolderContainer.widthAnchor)
        ])

        NSLayoutConstraint.activate([
            secHotTitle.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 20),
            secHotTitle.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            cardHot.topAnchor.constraint(equalTo: secHotTitle.bottomAnchor, constant: 8),
            cardHot.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            cardHot.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28),
            cardHot.bottomAnchor.constraint(equalTo: optionsScrollContent.bottomAnchor, constant: -28)
        ])
        reloadHotFolderRows()

        // Page 1: 排除范围 (对齐 Alfred Search Scope 设计)
        let exclusionPage = NSView()
        let exclusionScrollContent = NSView()
        let exclusionScroll = makeTabScrollView(contentView: exclusionScrollContent)
        exclusionPage.addSubview(exclusionScroll)
        NSLayoutConstraint.activate([
            exclusionScroll.topAnchor.constraint(equalTo: exclusionPage.topAnchor),
            exclusionScroll.leadingAnchor.constraint(equalTo: exclusionPage.leadingAnchor),
            exclusionScroll.trailingAnchor.constraint(equalTo: exclusionPage.trailingAnchor),
            exclusionScroll.bottomAnchor.constraint(equalTo: exclusionPage.bottomAnchor)
        ])

        let secPresetTitle = makeSectionHeader(title: "常用排除预设 (快捷过滤)")
        exclusionScrollContent.addSubview(secPresetTitle)

        let cardPreset = SettingsCardView()
        cardPreset.translatesAutoresizingMaskIntoConstraints = false
        exclusionScrollContent.addSubview(cardPreset)

        excludeCachesSwitch = NSSwitch()
        excludeCachesSwitch.target = self
        excludeCachesSwitch.action = #selector(toggleExcludeCaches(_:))
        let rowCaches = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "archivebox"),
            title: "排除系统与应用缓存",
            subtitle: "自动过滤 ~/Library/Caches, /Library/Caches 及各类 WebKit 临时缓存数据",
            accessory: excludeCachesSwitch
        )
        cardPreset.addRow(rowCaches)

        excludeLogsSwitch = NSSwitch()
        excludeLogsSwitch.target = self
        excludeLogsSwitch.action = #selector(toggleExcludeLogs(_:))
        let rowLogs = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "doc.text.magnifyingglass"),
            title: "排除系统日志与崩溃报告",
            subtitle: "自动过滤 ~/Library/Logs, /var/log, DiagnosticReports 及系统崩溃堆栈文件",
            accessory: excludeLogsSwitch
        )
        cardPreset.addRow(rowLogs)

        excludeDevSwitch = NSSwitch()
        excludeDevSwitch.target = self
        excludeDevSwitch.action = #selector(toggleExcludeDev(_:))
        let rowDev = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hammer"),
            title: "排除常见开发依赖与构建产物",
            subtitle: "自动过滤 node_modules, DerivedData, .build, target, __pycache__, .gradle 等工程副产物",
            accessory: excludeDevSwitch
        )
        cardPreset.addRow(rowDev)

        excludeUserLibSwitch = NSSwitch()
        excludeUserLibSwitch.target = self
        excludeUserLibSwitch.action = #selector(toggleExcludeUserLib(_:))
        let rowUserLib = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "folder.badge.gearshape"),
            title: "排除用户资源库 (~/Library)",
            subtitle: "参照 Alfred 核心规则过滤系统配置杂项；智能保留 iCloud 云盘与各类第三方网盘文档",
            accessory: excludeUserLibSwitch
        )
        cardPreset.addRow(rowUserLib)

        excludeTrashSwitch = NSSwitch()
        excludeTrashSwitch.target = self
        excludeTrashSwitch.action = #selector(toggleExcludeTrash(_:))
        let rowTrash = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "trash"),
            title: "排除废纸篓与临时目录",
            subtitle: "自动过滤 ~/.Trash, /private/var/folders, /tmp 等已丢弃与临时文件夹",
            accessory: excludeTrashSwitch
        )
        cardPreset.addRow(rowTrash)

        excludeHiddenSwitch = NSSwitch()
        excludeHiddenSwitch.target = self
        excludeHiddenSwitch.action = #selector(toggleExcludeHidden(_:))
        let rowHidden = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "eye.slash"),
            title: "排除版本控制与隐藏文件",
            subtitle: "自动过滤 .git, .svn 及以 \".\" 开头的系统级隐藏文件与隐藏文件夹",
            accessory: excludeHiddenSwitch
        )
        cardPreset.addRow(rowHidden, isLast: true)

        NSLayoutConstraint.activate([
            secPresetTitle.topAnchor.constraint(equalTo: exclusionScrollContent.topAnchor, constant: 14),
            secPresetTitle.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),

            cardPreset.topAnchor.constraint(equalTo: secPresetTitle.bottomAnchor, constant: 8),
            cardPreset.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            cardPreset.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28)
        ])

        // 自定义排除目录 (黑名单)
        let secCustomTitle = makeSectionHeader(title: "自定义排除目录 (黑名单)")
        exclusionScrollContent.addSubview(secCustomTitle)

        let cardCustom = SettingsCardView()
        cardCustom.translatesAutoresizingMaskIntoConstraints = false
        cardCustom.onDropFolders = { [weak self] droppedPaths in
            var addedCount = 0
            for path in droppedPaths {
                if ConfigManager.shared.addCustomExcludedPath(path) {
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                self?.reloadCustomExclusionRows()
            } else {
                NSSound.beep()
            }
        }
        exclusionScrollContent.addSubview(cardCustom)

        let customContainer = NSView()
        customContainer.translatesAutoresizingMaskIntoConstraints = false
        cardCustom.addRow(customContainer, isLast: true)

        customExclusionStack = NSStackView()
        customExclusionStack.orientation = .vertical
        customExclusionStack.spacing = 0
        customExclusionStack.distribution = .fill
        customExclusionStack.alignment = .leading
        customExclusionStack.translatesAutoresizingMaskIntoConstraints = false
        customContainer.addSubview(customExclusionStack)
        NSLayoutConstraint.activate([
            customExclusionStack.topAnchor.constraint(equalTo: customContainer.topAnchor),
            customExclusionStack.bottomAnchor.constraint(equalTo: customContainer.bottomAnchor),
            customExclusionStack.leadingAnchor.constraint(equalTo: customContainer.leadingAnchor),
            customExclusionStack.trailingAnchor.constraint(equalTo: customContainer.trailingAnchor),
            customExclusionStack.widthAnchor.constraint(equalTo: customContainer.widthAnchor)
        ])

        let exclusionTipLabel = NSTextField(labelWithString: "💡 提示：排除范围在全盘检索与内存快照中同时生效；设置排除目录可有效净化搜索结果并大幅提升检索性能。")
        exclusionTipLabel.translatesAutoresizingMaskIntoConstraints = false
        exclusionTipLabel.font = NSFont.systemFont(ofSize: 11)
        exclusionTipLabel.textColor = .secondaryLabelColor
        exclusionTipLabel.cell?.wraps = true
        exclusionTipLabel.maximumNumberOfLines = 2
        exclusionTipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        exclusionScrollContent.addSubview(exclusionTipLabel)

        NSLayoutConstraint.activate([
            secCustomTitle.topAnchor.constraint(equalTo: cardPreset.bottomAnchor, constant: 20),
            secCustomTitle.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),

            cardCustom.topAnchor.constraint(equalTo: secCustomTitle.bottomAnchor, constant: 8),
            cardCustom.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            cardCustom.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28),

            exclusionTipLabel.topAnchor.constraint(equalTo: cardCustom.bottomAnchor, constant: 12),
            exclusionTipLabel.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            exclusionTipLabel.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28),
            exclusionTipLabel.bottomAnchor.constraint(equalTo: exclusionScrollContent.bottomAnchor, constant: -28)
        ])
        reloadCustomExclusionRows()

        // Page 2: 扩展功能
        let extPage = NSView()
        let extScrollContent = NSView()
        let extScroll = makeTabScrollView(contentView: extScrollContent)
        extPage.addSubview(extScroll)
        NSLayoutConstraint.activate([
            extScroll.topAnchor.constraint(equalTo: extPage.topAnchor),
            extScroll.leadingAnchor.constraint(equalTo: extPage.leadingAnchor),
            extScroll.trailingAnchor.constraint(equalTo: extPage.trailingAnchor),
            extScroll.bottomAnchor.constraint(equalTo: extPage.bottomAnchor)
        ])

        let sec2Title = makeSectionHeader(title: "即时计算与本地词典")
        extScrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        extScrollContent.addSubview(card2)

        calcSwitch = NSSwitch()
        calcSwitch.target = self
        calcSwitch.action = #selector(toggleCalc(_:))
        let rowCalc = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "number.square"),
            title: "数学公式实时计算",
            subtitle: "输入 (1024 * 768) / 2 或十六进制 0x10+16 即时求解，回车自动复制结果",
            accessory: calcSwitch
        )
        card2.addRow(rowCalc)

        dictSwitch = NSSwitch()
        dictSwitch.target = self
        dictSwitch.action = #selector(toggleDict(_:))
        let rowDict = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "character.book.closed"),
            title: "离线本地词典释义查询",
            subtitle: "调用 macOS 系统底层词典库，输入单词即时显示权威释义，按下回车打开词典 App",
            accessory: dictSwitch
        )
        card2.addRow(rowDict, isLast: true)

        NSLayoutConstraint.activate([
            sec2Title.topAnchor.constraint(equalTo: extScrollContent.topAnchor, constant: 14),
            sec2Title.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 8),
            card2.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),
            card2.bottomAnchor.constraint(equalTo: extScrollContent.bottomAnchor, constant: -28)
        ])

        // Page 2: 网络搜索
        let webPage = NSView()
        let webScrollContent = NSView()
        let webScroll = makeTabScrollView(contentView: webScrollContent)
        webPage.addSubview(webScroll)
        NSLayoutConstraint.activate([
            webScroll.topAnchor.constraint(equalTo: webPage.topAnchor),
            webScroll.leadingAnchor.constraint(equalTo: webPage.leadingAnchor),
            webScroll.trailingAnchor.constraint(equalTo: webPage.trailingAnchor),
            webScroll.bottomAnchor.constraint(equalTo: webPage.bottomAnchor)
        ])

        let sec3Title = makeSectionHeader(title: "网络搜索回退设置")
        webScrollContent.addSubview(sec3Title)

        let card3 = SettingsCardView()
        card3.translatesAutoresizingMaskIntoConstraints = false
        webScrollContent.addSubview(card3)

        webSearchSwitch = NSSwitch()
        webSearchSwitch.target = self
        webSearchSwitch.action = #selector(toggleWebSearch(_:))
        let rowWebSearch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "network"),
            title: "启用网页搜索回退",
            subtitle: "开启后，若全盘未找到匹配结果或需要在线查询，可在搜索结果底部快速跳转至浏览器",
            accessory: webSearchSwitch
        )
        card3.addRow(rowWebSearch)

        enginePopUp = NSPopUpButton()
        enginePopUp.target = self
        enginePopUp.action = #selector(engineChanged(_:))
        for engine in WebSearchEngine.allCases {
            enginePopUp.addItem(withTitle: engine.title)
        }
        let rowEngine = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "globe"),
            title: "未命中时的网页搜索引擎",
            subtitle: "选择触发网页搜索时使用的默认搜索引擎或自定义搜索地址",
            accessory: enginePopUp
        )
        card3.addRow(rowEngine)

        customURLField = NSTextField()
        customURLField.placeholderString = "https://www.google.com/search?q={query}"
        customURLField.isEditable = true
        customURLField.isSelectable = true
        customURLField.bezelStyle = .roundedBezel
        customURLField.font = NSFont.systemFont(ofSize: 12)
        customURLField.delegate = self
        customURLField.target = self
        customURLField.action = #selector(customURLSubmitted(_:))
        customURLField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        customURLField.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let rowCustomURL = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "link"),
            title: "自定义搜索 URL 模板",
            subtitle: "仅当引擎选择「自定义」时生效。支持使用 {query} 或 %s 占位符",
            accessory: customURLField
        )
        card3.addRow(rowCustomURL, isLast: true)

        let tipLabel = NSTextField(labelWithString: "💡 提示：自定义搜索示例：https://www.google.com/search?q={query} 或 https://duckduckgo.com/?q=%s，回车或失焦即可自动保存。")
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont.systemFont(ofSize: 11)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.cell?.wraps = true
        tipLabel.maximumNumberOfLines = 2
        tipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        webScrollContent.addSubview(tipLabel)

        NSLayoutConstraint.activate([
            sec3Title.topAnchor.constraint(equalTo: webScrollContent.topAnchor, constant: 14),
            sec3Title.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),

            card3.topAnchor.constraint(equalTo: sec3Title.bottomAnchor, constant: 8),
            card3.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),
            card3.trailingAnchor.constraint(equalTo: webScrollContent.trailingAnchor, constant: -28),

            tipLabel.topAnchor.constraint(equalTo: card3.bottomAnchor, constant: 12),
            tipLabel.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),
            tipLabel.trailingAnchor.constraint(equalTo: webScrollContent.trailingAnchor, constant: -28),
            tipLabel.bottomAnchor.constraint(equalTo: webScrollContent.bottomAnchor, constant: -28)
        ])

        pages = [optionsPage, exclusionPage, extPage, webPage]
        for (idx, page) in pages.enumerated() {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
            ])
            page.isHidden = (idx != 0)
        }

        headerView.onSegmentChanged = { [weak self] index in
            self?.showPage(index)
        }
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        reloadHotFolderRows()
        reloadCustomExclusionRows()
        diskSearchSwitch.state = cfg.enableFullDiskSearch ? .on : .off
        autoPasteSwitch.state = cfg.autoPasteOnSummonAfterCopy ? .on : .off
        calcSwitch.state = cfg.enableCalculator ? .on : .off
        dictSwitch.state = cfg.enableDictionary ? .on : .off

        excludeCachesSwitch.state = cfg.searchExcludeCaches ? .on : .off
        excludeLogsSwitch.state = cfg.searchExcludeLogs ? .on : .off
        excludeDevSwitch.state = cfg.searchExcludeDeveloper ? .on : .off
        excludeUserLibSwitch.state = cfg.searchExcludeUserLibrary ? .on : .off
        excludeTrashSwitch.state = cfg.searchExcludeTrash ? .on : .off
        excludeHiddenSwitch.state = cfg.searchExcludeHidden ? .on : .off

        switch cfg.searchResultLimit {
        case ..<40: limitControl.selectedSegment = 0
        case ..<65: limitControl.selectedSegment = 1
        case ..<100: limitControl.selectedSegment = 2
        default: limitControl.selectedSegment = 3
        }

        webSearchSwitch.state = cfg.enableWebSearch ? .on : .off
        if let idx = WebSearchEngine.allCases.firstIndex(of: cfg.webSearchEngine) {
            enginePopUp.selectItem(at: idx)
        }
        customURLField.stringValue = cfg.customWebSearchURL
        updateWebSearchUIState()
    }

    private func updateWebSearchUIState() {
        let isWebEnabled = (webSearchSwitch.state == .on)
        enginePopUp.isEnabled = isWebEnabled
        let isCustom = (enginePopUp.indexOfSelectedItem == WebSearchEngine.allCases.firstIndex(of: .custom))
        customURLField.isEnabled = isWebEnabled && isCustom
        customURLField.alphaValue = (isWebEnabled && isCustom) ? 1.0 : 0.5
    }

    private func showPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        for (idx, page) in pages.enumerated() {
            page.isHidden = (idx != index)
        }
    }

    @objc private func toggleDiskSearch(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableFullDiskSearch(sender.state == .on)
    }

    @objc private func toggleAutoPaste(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoPasteOnSummonAfterCopy(sender.state == .on)
    }

    // MARK: - 自定义热目录列表

    private func reloadHotFolderRows() {
        guard hotFolderStack != nil else { return }
        for view in hotFolderStack.arrangedSubviews {
            hotFolderStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        func addRow(_ view: NSView) {
            // 必须先入栈再激活宽度约束：激活时两视图需在同一层级
            //（否则 “no common ancestor” 直接抛 NSGenericException）。
            hotFolderStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: hotFolderStack.widthAnchor).isActive = true
        }

        let folders = ConfigManager.shared.config.extraHotFolders
        if folders.isEmpty {
            addRow(makeHotFolderInfoRow(
                subtitle: "默认热目录：下载 / 桌面 / 文档（深度 3 层）。可点击添加或从访达直接拖拽文件夹至此，搜索毫秒级命中；未覆盖目录由全盘检索兜底。"))
        } else {
            for (index, path) in folders.enumerated() {
                if index > 0 { addRow(makeSeparator()) }
                addRow(makeHotFolderRow(path: path))
            }
            addRow(makeSeparator())
        }
        addRow(makeAddHotFolderRow(count: folders.count))
    }

    private func makeHotFolderRow(path: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = ThumbnailPipeline.shared.symbolIcon(name: "folder")
        icon.contentTintColor = .secondaryLabelColor
        row.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(titleLabel)

        let pathLabel = NSTextField(labelWithString: path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(pathLabel)

        let removeBtn = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill",
                                                accessibilityDescription: "移除") ?? NSImage(),
                                 target: self, action: #selector(removeHotFolderClicked(_:)))
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        removeBtn.isBordered = false
        removeBtn.identifier = NSUserInterfaceItemIdentifier(path)
        removeBtn.toolTip = "从热目录移除"
        removeBtn.contentTintColor = .secondaryLabelColor
        row.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 46),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -7)
        ])
        return row
    }

    private func makeAddHotFolderRow(count: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "添加目录…")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .controlAccentColor
        row.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "已添加 \(count)/\(ConfigManager.maxExtraHotFolders) · 可点击添加，或直接从访达将文件夹拖拽至此")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        row.addSubview(subtitle)

        let addBtn = NSButton(image: NSImage(systemSymbolName: "plus.circle.fill",
                                             accessibilityDescription: "添加") ?? NSImage(),
                              target: self, action: #selector(addHotFolderClicked(_:)))
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.isBordered = false
        addBtn.toolTip = "添加热目录"
        addBtn.isEnabled = count < ConfigManager.maxExtraHotFolders
        addBtn.contentTintColor = .controlAccentColor
        row.addSubview(addBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 46),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -7),

            addBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeHotFolderInfoRow(subtitle: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: subtitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])
        return row
    }

    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        ])
        return container
    }

    @objc private func removeHotFolderClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        ConfigManager.shared.removeHotFolder(path)
        reloadHotFolderRows()
    }

    @objc private func addHotFolderClicked(_ sender: Any?) {
        guard ConfigManager.shared.config.extraHotFolders.count < ConfigManager.maxExtraHotFolders else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "添加"
        panel.message = "选择加入热目录快照的文件夹（深度 3 层，每目录上限 25,000 条）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if ConfigManager.shared.addHotFolder(url.path) {
            reloadHotFolderRows()
        } else {
            let alert = NSAlert()
            alert.messageText = "无法添加该目录"
            alert.informativeText = "目录不存在、与已有热目录重复或互相包含、或已达到上限（\(ConfigManager.maxExtraHotFolders) 个）。"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - 自定义排除目录列表与事件

    private func reloadCustomExclusionRows() {
        guard customExclusionStack != nil else { return }
        for view in customExclusionStack.arrangedSubviews {
            customExclusionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        func addRow(_ view: NSView) {
            customExclusionStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: customExclusionStack.widthAnchor).isActive = true
        }

        let paths = ConfigManager.shared.config.customExcludedPaths
        if paths.isEmpty {
            addRow(makeCustomExclusionInfoRow(subtitle: "暂无自定义排除目录。可点击下方按钮添加，或直接从访达将文件夹拖拽至此。"))
        } else {
            for (index, path) in paths.enumerated() {
                if index > 0 { addRow(makeSeparator()) }
                addRow(makeCustomExclusionRow(path: path))
            }
            addRow(makeSeparator())
        }
        addRow(makeAddCustomExclusionRow(count: paths.count))
    }

    private func makeCustomExclusionRow(path: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = ThumbnailPipeline.shared.symbolIcon(name: "folder.badge.minus")
        icon.contentTintColor = .secondaryLabelColor
        row.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(titleLabel)

        let pathLabel = NSTextField(labelWithString: path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(pathLabel)

        let removeBtn = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill",
                                                accessibilityDescription: "移除") ?? NSImage(),
                                 target: self, action: #selector(removeCustomExclusionClicked(_:)))
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        removeBtn.isBordered = false
        removeBtn.identifier = NSUserInterfaceItemIdentifier(path)
        removeBtn.toolTip = "从排除目录中移除"
        removeBtn.contentTintColor = .secondaryLabelColor
        row.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 46),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -7)
        ])
        return row
    }

    private func makeAddCustomExclusionRow(count: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "添加排除目录…")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .controlAccentColor
        row.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "已添加 \(count)/\(ConfigManager.maxCustomExcludedPaths) · 可点击添加，或直接从访达将文件夹拖拽至此")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        row.addSubview(subtitle)

        let addBtn = NSButton(image: NSImage(systemSymbolName: "plus.circle.fill",
                                             accessibilityDescription: "添加") ?? NSImage(),
                              target: self, action: #selector(addCustomExclusionClicked(_:)))
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.isBordered = false
        addBtn.toolTip = "选择文件夹添加至排除黑名单"
        addBtn.isEnabled = count < ConfigManager.maxCustomExcludedPaths
        addBtn.contentTintColor = .controlAccentColor
        row.addSubview(addBtn)

        let resetBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetCustomExclusionClicked(_:)))
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.bezelStyle = .inline
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.toolTip = "清空自定义排除目录"
        row.addSubview(resetBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 46),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: resetBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -7),

            resetBtn.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -8),
            resetBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            addBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeCustomExclusionInfoRow(subtitle: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: subtitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])
        return row
    }

    @objc private func addCustomExclusionClicked(_ sender: Any?) {
        guard ConfigManager.shared.config.customExcludedPaths.count < ConfigManager.maxCustomExcludedPaths else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "排除"
        panel.message = "选择要从全盘搜索中排除的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if ConfigManager.shared.addCustomExcludedPath(url.path) {
            reloadCustomExclusionRows()
        } else {
            let alert = NSAlert()
            alert.messageText = "无法排除该目录"
            alert.informativeText = "该目录不存在、已被包含在已有排除项中、或是系统根/用户家目录，或已达到最大排除数量（\(ConfigManager.maxCustomExcludedPaths) 个）。"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func removeCustomExclusionClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        ConfigManager.shared.removeCustomExcludedPath(path)
        reloadCustomExclusionRows()
    }

    @objc private func resetCustomExclusionClicked(_ sender: Any?) {
        ConfigManager.shared.resetCustomExcludedPathsToDefault()
        reloadCustomExclusionRows()
    }

    @objc private func toggleExcludeCaches(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeCaches(sender.state == .on)
    }

    @objc private func toggleExcludeLogs(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeLogs(sender.state == .on)
    }

    @objc private func toggleExcludeDev(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeDeveloper(sender.state == .on)
    }

    @objc private func toggleExcludeUserLib(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeUserLibrary(sender.state == .on)
    }

    @objc private func toggleExcludeTrash(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeTrash(sender.state == .on)
    }

    @objc private func toggleExcludeHidden(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeHidden(sender.state == .on)
    }

    @objc private func toggleCalc(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableCalculator(sender.state == .on)
    }

    @objc private func toggleDict(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableDictionary(sender.state == .on)
    }

    @objc private func limitChanged(_ sender: NSSegmentedControl) {
        let limits = [30, 50, 80, 120]
        let selected = limits[max(0, min(limits.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateSearchResultLimit(selected)
    }

    @objc private func toggleWebSearch(_ sender: NSSwitch) {
        let isEnabled = (sender.state == .on)
        ConfigManager.shared.updateEnableWebSearch(isEnabled)
        updateWebSearchUIState()
    }

    @objc private func engineChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < WebSearchEngine.allCases.count {
            ConfigManager.shared.updateWebSearchEngine(WebSearchEngine.allCases[idx])
        }
        updateWebSearchUIState()
    }

    @objc private func customURLSubmitted(_ sender: NSTextField) {
        ConfigManager.shared.updateCustomWebSearchURL(sender.stringValue)
        window?.makeFirstResponder(nil)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf == customURLField {
            ConfigManager.shared.updateCustomWebSearchURL(tf.stringValue)
        }
    }
}

// MARK: - 4. Hotkeys Tab View
public final class HotkeysTabView: NSView {
    public private(set) var shelfRecorder: HotkeyRecorderControl!
    public private(set) var searchRecorder: HotkeyRecorderControl!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "全局快捷键", iconName: "keyboard")
        addSubview(header)

        let scrollContent = NSView()
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeTabScrollView(contentView: scrollContent)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "核心面板快捷键录制")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        shelfRecorder = HotkeyRecorderControl(binding: ConfigManager.shared.config.shelfHotkey)
        shelfRecorder.translatesAutoresizingMaskIntoConstraints = false
        shelfRecorder.widthAnchor.constraint(equalToConstant: 210).isActive = true
        shelfRecorder.onChange = { [weak self] newBinding in
            self?.handleShelfRecorded(newBinding)
        }
        shelfRecorder.onClear = { [weak self] in
            self?.handleShelfCleared()
        }
        let rowShelf = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "square.grid.2x2"),
            title: "分类工作台快捷键",
            subtitle: "默认 ⌥A，支持按下键盘任意组合键或双击修饰键 (如 2× ⌥)",
            accessory: shelfRecorder
        )
        card1.addRow(rowShelf)

        searchRecorder = HotkeyRecorderControl(binding: ConfigManager.shared.config.searchHotkey)
        searchRecorder.translatesAutoresizingMaskIntoConstraints = false
        searchRecorder.widthAnchor.constraint(equalToConstant: 210).isActive = true
        searchRecorder.onChange = { [weak self] newBinding in
            self?.handleSearchRecorded(newBinding)
        }
        searchRecorder.onClear = { [weak self] in
            self?.handleSearchCleared()
        }
        let rowSearch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass"),
            title: "全盘搜索中枢快捷键",
            subtitle: "默认 ⌥Space，释放系统聚焦后可无缝绑定为 ⌘Space",
            accessory: searchRecorder
        )
        card1.addRow(rowSearch, isLast: true)

        let conflictHint = NSTextField(labelWithString: "💡 提示：若将搜索快捷键设为与抽屉相同，ATools 将自动将两者对调，保证绝不冲突。")
        conflictHint.translatesAutoresizingMaskIntoConstraints = false
        conflictHint.font = NSFont.systemFont(ofSize: 11)
        conflictHint.textColor = .secondaryLabelColor
        conflictHint.cell?.wraps = true
        conflictHint.maximumNumberOfLines = 2
        conflictHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollContent.addSubview(conflictHint)

        let sec2Title = makeSectionHeader(title: "系统聚焦 (Spotlight) 冲突排查与平替")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let sysBtn = SettingsPillButton(title: "前往系统键盘设置...", target: self, action: #selector(openKeyboardSettings))
        let rowSys = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "command"),
            title: "释放 Spotlight 快捷键 (⌘Space)",
            subtitle: "macOS 默认占用了该键。前往「系统设置」->「键盘」->「键盘快捷键」取消聚焦勾选即可释放",
            accessory: sysBtn
        )
        card2.addRow(rowSys)

        let ccBtn = SettingsPillButton(title: "前往控制中心...", target: self, action: #selector(openControlCenterSettings))
        let rowCC = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "menubar.arrow.up.rectangle"),
            title: "隐藏系统菜单栏 Spotlight 放大镜",
            subtitle: "在 macOS「控制中心」将聚焦设为「不在菜单栏中显示」，让菜单栏只保留 ATools 搜索入口",
            accessory: ccBtn
        )
        card2.addRow(rowCC, isLast: true)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: scrollContent.topAnchor, constant: 14),
            sec1Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 8),
            card1.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            conflictHint.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 6),
            conflictHint.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 32),
            conflictHint.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            sec2Title.topAnchor.constraint(equalTo: conflictHint.bottomAnchor, constant: 18),
            sec2Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 8),
            card2.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -28)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        shelfRecorder.currentBinding = cfg.shelfHotkey
        searchRecorder.currentBinding = cfg.searchHotkey
        shelfRecorder.isEnabled = cfg.enableShelfPanel
        searchRecorder.isEnabled = cfg.enableSearchPanel
    }

    private func handleShelfRecorded(_ binding: HotkeyBinding) {
        applyRecordedBinding(binding, for: .shelf)
    }

    /// Applies a freshly recorded binding. When it collides with the other panel's binding the
    /// two are swapped. Both registrations are released first because Carbon refuses to
    /// register a key combination that is still held — even by this same process.
    private func applyRecordedBinding(_ binding: HotkeyBinding, for id: HotKeyID) {
        let cfg = ConfigManager.shared.config
        let otherId: HotKeyID = (id == .shelf) ? .search : .shelf
        let previous = (id == .shelf) ? cfg.shelfHotkey : cfg.searchHotkey
        let other = (id == .shelf) ? cfg.searchHotkey : cfg.shelfHotkey
        let isEnabled = (id == .shelf) ? cfg.enableShelfPanel : cfg.enableSearchPanel
        let isOtherEnabled = (id == .shelf) ? cfg.enableSearchPanel : cfg.enableShelfPanel
        let recorder: HotkeyRecorderControl = (id == .shelf) ? shelfRecorder : searchRecorder
        let otherRecorder: HotkeyRecorderControl = (id == .shelf) ? searchRecorder : shelfRecorder

        let collides = !other.isUnassigned
            && binding.keyCode == other.keyCode
            && binding.carbonModifiers == other.carbonModifiers
            && binding.specialTrigger == other.specialTrigger

        if collides {
            HotkeyManager.shared.unregister(id: .shelf)
            HotkeyManager.shared.unregister(id: .search)
        }

        let success = isEnabled ? HotkeyManager.shared.register(id: id, binding: binding) : true
        guard success else {
            if collides {
                HotkeyManager.shared.registerDefaultHotkeys()
            }
            showConflictAlert(binding: binding, name: id == .shelf ? "应用分类工作台" : "全盘搜索中枢")
            recorder.currentBinding = previous
            return
        }

        if id == .shelf {
            ConfigManager.shared.updateShelfHotkey(binding)
        } else {
            ConfigManager.shared.updateSearchHotkey(binding)
        }
        recorder.currentBinding = binding

        if collides {
            if otherId == .shelf {
                ConfigManager.shared.updateShelfHotkey(previous)
            } else {
                ConfigManager.shared.updateSearchHotkey(previous)
            }
            otherRecorder.currentBinding = previous
            if isOtherEnabled {
                HotkeyManager.shared.register(id: otherId, binding: previous)
            }
        }

        NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
        checkAccessibilityIfNeeded(for: binding)
    }

    private func handleShelfCleared() {
        HotkeyManager.shared.unregister(id: .shelf)
        ConfigManager.shared.updateShelfHotkey(HotkeyBinding(keyCode: 0, carbonModifiers: 0, displayString: ""))
        NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
    }

    private func handleSearchRecorded(_ binding: HotkeyBinding) {
        applyRecordedBinding(binding, for: .search)
    }

    private func checkAccessibilityIfNeeded(for binding: HotkeyBinding) {
        guard binding.specialTrigger != .none else { return }
        if !HotkeyManager.isAccessibilityTrusted() {
            let alert = NSAlert()
            alert.messageText = "双击修饰键需要「辅助功能」授权"
            alert.informativeText = "您已设置「\(binding.displayString)」快捷键。\n\nmacOS 安全机制要求：全局感知修饰键轻击需在系统设置中允许 ATools 使用「辅助功能」。\n\nATools 仅监听单键轻敲，绝不记录任何键入内容。是否前往系统设置开启授权？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "前往系统设置")
            alert.addButton(withTitle: "稍后手动开启")
            if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
                HotkeyManager.openAccessibilitySettings()
            }
        }
    }

    private func handleSearchCleared() {
        HotkeyManager.shared.unregister(id: .search)
        ConfigManager.shared.updateSearchHotkey(HotkeyBinding(keyCode: 0, carbonModifiers: 0, displayString: ""))
        NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
    }

    private func showConflictAlert(binding: HotkeyBinding, name: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = "快捷键注册失败"
        alert.informativeText = "快捷键「\(binding.displayString)」未能注册为【\(name)】的热键。\n该快捷键可能已被系统聚焦或其他软件占用。"
        alert.addButton(withTitle: "前往系统设置...")
        alert.addButton(withTitle: "好")
        if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
            HotkeyManager.shared.openSystemKeyboardSettings()
        }
    }

    @objc private func openKeyboardSettings() {
        HotkeyManager.shared.openSystemKeyboardSettings()
    }

    @objc private func openControlCenterSettings() {
        if #available(macOS 13.0, *), let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            if NSWorkspace.shared.open(url) { return }
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - 5. Theme Tab View
public final class ThemeTabView: NSView {
    private var themeCards: [ThemeCardView] = []
    private var opacitySlider: NSSlider!
    private var opacityBadge: NSTextField!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "外观与主题", iconName: "paintbrush")
        addSubview(header)

        let scrollContent = NSView()
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeTabScrollView(contentView: scrollContent)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "精选视觉风格")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        let themesStack = NSStackView()
        themesStack.translatesAutoresizingMaskIntoConstraints = false
        themesStack.orientation = .horizontal
        themesStack.distribution = .fillEqually
        themesStack.spacing = 14
        themesStack.alignment = .centerY

        themeCards.removeAll()
        for theme in AppTheme.allCases {
            let card = ThemeCardView(theme: theme, isSelected: ConfigManager.shared.config.theme == theme)
            card.onClick = { [weak self] sel in
                self?.handleThemeSelected(sel)
            }
            themeCards.append(card)
            themesStack.addArrangedSubview(card)
        }

        let themeRow = NSView()
        themeRow.translatesAutoresizingMaskIntoConstraints = false
        themeRow.addSubview(themesStack)
        NSLayoutConstraint.activate([
            themeRow.heightAnchor.constraint(equalToConstant: 108),
            themesStack.topAnchor.constraint(equalTo: themeRow.topAnchor, constant: 10),
            themesStack.bottomAnchor.constraint(equalTo: themeRow.bottomAnchor, constant: -10),
            themesStack.leadingAnchor.constraint(equalTo: themeRow.leadingAnchor, constant: 16),
            themesStack.trailingAnchor.constraint(equalTo: themeRow.trailingAnchor, constant: -16)
        ])
        card1.addRow(themeRow, isLast: true)

        let sec2Title = makeSectionHeader(title: "背景阻尼与透明度")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let opacityContainer = NSView()
        opacityContainer.translatesAutoresizingMaskIntoConstraints = false

        opacitySlider = NSSlider(value: 90, minValue: 40, maxValue: 100, target: self, action: #selector(opacitySliderChanged(_:)))
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.numberOfTickMarks = 7
        opacitySlider.allowsTickMarkValuesOnly = false
        opacitySlider.isContinuous = true
        opacityContainer.addSubview(opacitySlider)

        let badgeContainer = NSView()
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 10
        badgeContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        opacityContainer.addSubview(badgeContainer)

        opacityBadge = NSTextField(labelWithString: "90%（默认）")
        opacityBadge.translatesAutoresizingMaskIntoConstraints = false
        opacityBadge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        opacityBadge.textColor = .labelColor
        badgeContainer.addSubview(opacityBadge)

        NSLayoutConstraint.activate([
            opacityContainer.widthAnchor.constraint(equalToConstant: 260),
            opacityContainer.heightAnchor.constraint(equalToConstant: 28),

            opacitySlider.leadingAnchor.constraint(equalTo: opacityContainer.leadingAnchor),
            opacitySlider.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            opacitySlider.trailingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: -10),

            badgeContainer.trailingAnchor.constraint(equalTo: opacityContainer.trailingAnchor),
            badgeContainer.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 20),

            opacityBadge.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            opacityBadge.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            opacityBadge.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
        ])

        let rowOpacity = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "slider.horizontal.below.rectangle"),
            title: "面板背景透明度",
            subtitle: "40% 轻透玻璃，数值越高玻璃越模糊、遮光越强",
            accessory: opacityContainer
        )
        card2.addRow(rowOpacity, isLast: true)

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
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -28)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        for card in themeCards {
            card.isSelected = (card.theme == cfg.theme)
        }
        opacitySlider.doubleValue = cfg.themeOpacity * 100.0
        let pct = Int(round(cfg.themeOpacity * 100.0))
        opacityBadge.stringValue = (pct == 90) ? "90%（默认）" : "\(pct)%"
    }

    private func handleThemeSelected(_ theme: AppTheme) {
        ConfigManager.shared.updateTheme(theme)
        for card in themeCards {
            card.isSelected = (card.theme == theme)
        }
        // Theme change notification is now posted by ConfigManager
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        let val = round(sender.doubleValue)
        let opacity = val / 100.0
        let pct = Int(val)
        opacityBadge.stringValue = (pct == 90) ? "90%（默认）" : "\(pct)%"
        guard abs(opacity - ConfigManager.shared.config.themeOpacity) > 0.001 else { return }
        ConfigManager.shared.updateThemeOpacity(opacity)
        // Theme change notification is now posted by ConfigManager
    }
}

// MARK: - 6. Performance Tab View
public final class PerformanceTabView: NSView {
    private var memLabel = NSTextField(labelWithString: "正在测量...")
    private var purgeStatusLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var annealControl: NSSegmentedControl!
    private var debounceControl: NSSegmentedControl!
    private var cacheControl: NSSegmentedControl!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public func startMonitor() {
        stopMonitor()
        updateMemoryMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemoryMetrics()
        }
    }

    public func stopMonitor() {
        timer?.invalidate()
        timer = nil
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "运行与性能", iconName: "gauge.with.dots.needle.bottom.50percent")
        addSubview(header)

        let scrollContent = NSView()
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeTabScrollView(contentView: scrollContent)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "物理内存监测与一键回收")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        memLabel.translatesAutoresizingMaskIntoConstraints = false
        memLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        memLabel.textColor = .labelColor

        let purgeBtn = SettingsPillButton(title: "一键深度释放", target: self, action: #selector(handlePurge))

        let memRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "memorychip"),
            title: "当前物理内存占用 (Footprint)",
            subtitle: "与「活动监视器」内存列一致的真实物理足迹；RSS 口径会把共享的系统框架页计入，虚高 2–3 倍",
            accessory: memLabel
        )
        card1.addRow(memRow)

        let actionRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "sparkles"),
            title: "立即回收缓存与堆脏页",
            subtitle: "清空当前图标缓存并主动向系统内核归还堆内存",
            accessory: purgeBtn
        )
        card1.addRow(actionRow)

        purgeStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        purgeStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        purgeStatusLabel.textColor = .secondaryLabelColor
        purgeStatusLabel.stringValue = "上次释放：尚未执行"

        let statusRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.triangle.2.circlepath"),
            title: "释放结果",
            subtitle: "显示本次释放前后物理内存占用的差值",
            accessory: purgeStatusLabel
        )
        card1.addRow(statusRow, isLast: true)

        let sec2Title = makeSectionHeader(title: "退火策略与响应延迟")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        annealControl = NSSegmentedControl(labels: ["1.5s (激进省电)", "3.0s (推荐平衡)", "10.0s (宽松缓存)"], trackingMode: .selectOne, target: self, action: #selector(annealChanged(_:)))
        let rowAnneal = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "timer"),
            title: "面板隐藏退火延迟",
            subtitle: "面板关闭后经过此延迟自动触发内存脏页回收",
            accessory: annealControl
        )
        card2.addRow(rowAnneal)

        debounceControl = NSSegmentedControl(labels: ["50ms (极速)", "150ms (均衡)", "300ms (节能)"], trackingMode: .selectOne, target: self, action: #selector(debounceChanged(_:)))
        let rowDebounce = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "waveform.path"),
            title: "全盘搜索防抖延迟",
            subtitle: "控制打字时的 Spotlight 检索流式触发间隔",
            accessory: debounceControl
        )
        card2.addRow(rowDebounce)

        cacheControl = NSSegmentedControl(labels: ["4 MB", "6 MB (默认)", "12 MB"], trackingMode: .selectOne, target: self, action: #selector(cacheLimitChanged(_:)))
        let rowCache = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "photo.stack"),
            title: "缩略图缓存池上限",
            subtitle: "限制 QuickLook 文件与 App 图标的最大驻留容量",
            accessory: cacheControl
        )
        card2.addRow(rowCache, isLast: true)

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
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -28)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        switch cfg.memoryAnnealDelay {
        case ..<2.0: annealControl.selectedSegment = 0
        case ..<6.0: annealControl.selectedSegment = 1
        default: annealControl.selectedSegment = 2
        }

        switch cfg.searchDebounceMs {
        case ..<100: debounceControl.selectedSegment = 0
        case ..<250: debounceControl.selectedSegment = 1
        default: debounceControl.selectedSegment = 2
        }

        switch cfg.thumbnailCacheLimitMB {
        case ..<5: cacheControl.selectedSegment = 0
        case ..<10: cacheControl.selectedSegment = 1
        default: cacheControl.selectedSegment = 2
        }

        updateMemoryMetrics()
    }

    private func updateMemoryMetrics() {
        memLabel.stringValue = String(format: "%.1f MB (真实物理占用)", currentFootprintMB())
    }

    /// Apple 官方的物理内存口径（task_vm_info.phys_footprint），与「活动监视器」
    /// 的内存列一致。此前使用 MACH_TASK_BASIC_INFO.resident_size（RSS），它把与
    /// 其他进程共享的 dyld 共享缓存和框架文本页也计入本进程，读数可达真实物理
    /// 占用的 2–3 倍（实测 RSS ≈128MB vs 真实足迹 ≈47MB）。
    private func currentFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.phys_footprint) / (1024.0 * 1024.0)
        }
        return 0
    }

    @objc private func handlePurge() {
        let before = currentFootprintMB()
        MemoryGuardian.shared.performImmediatePurge()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            let after = currentFootprintMB()
            self.updateMemoryMetrics()
            let delta = before - after
            if delta > 0.05 {
                self.purgeStatusLabel.textColor = .secondaryLabelColor
                self.purgeStatusLabel.stringValue = String(format: "已释放 %.1f MB", delta)
            } else {
                self.purgeStatusLabel.textColor = .secondaryLabelColor
                self.purgeStatusLabel.stringValue = "缓存已清空，物理内存无显著变化"
            }
        }
    }

    @objc private func annealChanged(_ sender: NSSegmentedControl) {
        let delays = [1.5, 3.0, 10.0]
        let sel = delays[max(0, min(delays.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateMemoryAnnealDelay(sel)
    }

    @objc private func debounceChanged(_ sender: NSSegmentedControl) {
        let ms = [50, 150, 300]
        let sel = ms[max(0, min(ms.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateSearchDebounceMs(sel)
    }

    @objc private func cacheLimitChanged(_ sender: NSSegmentedControl) {
        let mbs = [4, 6, 12]
        let sel = mbs[max(0, min(mbs.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateThumbnailCacheLimitMB(sel)
    }
}

// MARK: - 7. About Tab View
public final class AboutTabView: NSView {
    private let statusLabel = NSTextField(labelWithString: "点击右侧按钮连接 GitHub 检查最新发布版本")
    private let actionButton = SettingsPillButton(title: "", style: .primary)
    private let progressIndicator = NSProgressIndicator()
    private let releaseNotesBox = NSView()
    private let releaseNotesText = NSTextView()
    private var releaseNotesHeightConstraint: NSLayoutConstraint?

    public init() {
        super.init(frame: .zero)
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateStateChanged),
            name: UpdateManager.stateDidChangeNotification,
            object: nil
        )
        updateUIState()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "关于 ATools", iconName: "info.circle")
        addSubview(header)

        let scrollContent = NSView()
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeTabScrollView(contentView: scrollContent)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Section 1: 软件更新与版本
        let sec1Title = makeSectionHeader(title: "软件版本与更新")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        let currentVer = UpdateManager.shared.currentAppVersion
        let verLabel = NSTextField(labelWithString: "v\(currentVer)")
        verLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        verLabel.textColor = .secondaryLabelColor
        let rowVer = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "sparkles"),
            title: "ATools for macOS",
            subtitle: "极简启动抽屉与全盘秒搜中枢",
            accessory: verLabel
        )
        card1.addRow(rowVer)

        // Action Container
        let actionContainer = NSView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionContainer.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            actionButton.leadingAnchor.constraint(greaterThanOrEqualTo: actionContainer.leadingAnchor),
            actionContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            actionContainer.heightAnchor.constraint(equalToConstant: 32)
        ])

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.cell?.wraps = true
        statusLabel.cell?.isScrollable = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowUpdate = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.triangle.2.circlepath"),
            title: "检查与安装更新",
            subtitle: "直连官方 GitHub Releases，支持一键无感下载与平滑原地热更新",
            accessory: actionContainer
        )
        card1.addRow(rowUpdate, isLast: false)

        // Download Progress & Status Row (Clean arranged subview inside card1)
        let updateDetailView = NSView()
        updateDetailView.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0.0
        progressIndicator.maxValue = 1.0
        progressIndicator.doubleValue = 0.0
        progressIndicator.isHidden = true
        updateDetailView.addSubview(progressIndicator)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        updateDetailView.addSubview(statusLabel)

        // Release Notes Box (folded by default)
        releaseNotesBox.translatesAutoresizingMaskIntoConstraints = false
        releaseNotesBox.wantsLayer = true
        releaseNotesBox.layer?.cornerRadius = 8
        releaseNotesBox.layer?.backgroundColor = NSColor.clear.cgColor
        let notesBackground = NSVisualEffectView()
        notesBackground.translatesAutoresizingMaskIntoConstraints = false
        notesBackground.material = .contentBackground
        notesBackground.blendingMode = .withinWindow
        notesBackground.state = .active
        releaseNotesBox.addSubview(notesBackground)
        NSLayoutConstraint.activate([
            notesBackground.leadingAnchor.constraint(equalTo: releaseNotesBox.leadingAnchor),
            notesBackground.trailingAnchor.constraint(equalTo: releaseNotesBox.trailingAnchor),
            notesBackground.topAnchor.constraint(equalTo: releaseNotesBox.topAnchor),
            notesBackground.bottomAnchor.constraint(equalTo: releaseNotesBox.bottomAnchor)
        ])
        releaseNotesBox.isHidden = true
        updateDetailView.addSubview(releaseNotesBox)

        let scrollNotes = NSScrollView()
        scrollNotes.translatesAutoresizingMaskIntoConstraints = false
        scrollNotes.hasVerticalScroller = true
        scrollNotes.drawsBackground = false

        releaseNotesText.isEditable = false
        releaseNotesText.isSelectable = true
        releaseNotesText.font = NSFont.systemFont(ofSize: 11)
        releaseNotesText.textColor = .labelColor
        releaseNotesText.backgroundColor = .clear
        releaseNotesText.textContainerInset = NSSize(width: 8, height: 8)
        releaseNotesText.isVerticallyResizable = true
        releaseNotesText.isHorizontallyResizable = false
        releaseNotesText.autoresizingMask = [.width]
        releaseNotesText.textContainer?.widthTracksTextView = true
        scrollNotes.documentView = releaseNotesText
        releaseNotesBox.addSubview(scrollNotes)

        let notesHeight = releaseNotesBox.heightAnchor.constraint(equalToConstant: 0)
        releaseNotesHeightConstraint = notesHeight

        card1.addRow(updateDetailView, isLast: true)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: updateDetailView.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: updateDetailView.leadingAnchor, constant: 48),
            statusLabel.trailingAnchor.constraint(equalTo: updateDetailView.trailingAnchor, constant: -16),

            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            progressIndicator.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 6),

            releaseNotesBox.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 6),
            releaseNotesBox.leadingAnchor.constraint(equalTo: updateDetailView.leadingAnchor, constant: 16),
            releaseNotesBox.trailingAnchor.constraint(equalTo: updateDetailView.trailingAnchor, constant: -16),
            notesHeight,
            releaseNotesBox.bottomAnchor.constraint(equalTo: updateDetailView.bottomAnchor, constant: -12),

            scrollNotes.topAnchor.constraint(equalTo: releaseNotesBox.topAnchor),
            scrollNotes.leadingAnchor.constraint(equalTo: releaseNotesBox.leadingAnchor),
            scrollNotes.trailingAnchor.constraint(equalTo: releaseNotesBox.trailingAnchor),
            scrollNotes.bottomAnchor.constraint(equalTo: releaseNotesBox.bottomAnchor)
        ])

        // Section 2: 系统兼容性与架构
        let sec2Title = makeSectionHeader(title: "系统兼容与技术规格")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let archLabel = NSTextField(labelWithString: AboutTabView.currentArchitectureLabel)
        archLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        archLabel.textColor = .secondaryLabelColor
        let rowArch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "cpu"),
            title: "原生架构支持",
            subtitle: "基于当前安装包的原生架构构建，适配 macOS 12 及以上系统",
            accessory: archLabel
        )
        card2.addRow(rowArch)

        let rowStack = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "curlybraces"),
            title: "精纯 Swift + 原生 AppKit 架构",
            subtitle: "零 Electron/Web 视图臃肿，零第三方二进制框架依赖",
            accessory: nil
        )
        card2.addRow(rowStack, isLast: true)

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
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -28)
        ])
    }

    private static var currentArchitectureLabel: String {
        // Read the Mach-O header via NSBundle instead of spawning /usr/bin/lipo synchronously
        // on the main thread when the About tab is built.
        let architectures = Bundle.main.executableArchitectures?.map { $0.intValue } ?? []
        let hasArm = architectures.contains(NSBundleExecutableArchitectureARM64)
        let hasIntel = architectures.contains(NSBundleExecutableArchitectureX86_64)
        if hasArm && hasIntel {
            return "Universal (Apple Silicon + Intel)"
        }
        if hasArm {
            return "Apple Silicon (arm64)"
        }
        if hasIntel {
            return "Intel (x86_64)"
        }
        return "当前 Mac 原生架构"
    }

    @objc private func handleUpdateStateChanged() {
        updateUIState()
    }

    @objc private func actionButtonClicked() {
        switch UpdateManager.shared.currentState {
        case .idle, .upToDate:
            UpdateManager.shared.checkForUpdates(isUserInitiated: true)
        case .error:
            UpdateManager.shared.retry()
        case .available:
            UpdateManager.shared.startUpdate()
        case .downloading:
            UpdateManager.shared.cancelUpdate()
        case .checking, .preparing:
            break
        }
    }

    private func updateUIState() {
        let state = UpdateManager.shared.currentState
        switch state {
        case .idle:
            statusLabel.stringValue = "点击「检查更新」连接 GitHub 获取最新版本。"
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "检查更新"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            hideReleaseNotes()

        case .checking:
            statusLabel.stringValue = "正在连接 GitHub 检查版本发布..."
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "检查中..."
            actionButton.isEnabled = false
            progressIndicator.isHidden = true
            hideReleaseNotes()

        case .upToDate(let ver):
            statusLabel.stringValue = "当前版本已是最新 (v\(ver))。"
            statusLabel.textColor = .labelColor
            actionButton.title = "重新检查"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            hideReleaseNotes()

        case .available(let release):
            statusLabel.stringValue = "发现新版本 \(release.version)（\(release.name)）。"
            statusLabel.textColor = .labelColor
            actionButton.title = "一键更新"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            showReleaseNotes(release.body)

        case .downloading(let progress):
            let percent = Int(progress * 100)
            statusLabel.stringValue = "正在下载更新安装包 (\(percent)%)..."
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "取消"
            actionButton.isEnabled = true
            progressIndicator.isHidden = false
            progressIndicator.doubleValue = progress

        case .preparing:
            statusLabel.stringValue = "正在解包校验并准备原地平滑替换与重启..."
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "更新中..."
            actionButton.isEnabled = false
            progressIndicator.isHidden = false
            progressIndicator.doubleValue = 1.0

        case .error(let msg):
            statusLabel.stringValue = msg
            statusLabel.textColor = .labelColor
            actionButton.title = "重试"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            hideReleaseNotes()
        }
    }

    private func showReleaseNotes(_ text: String) {
        // GitHub release body 是 Markdown；直接塞纯文本会把 `**`、`-` 原样露出来。
        releaseNotesText.textStorage?.setAttributedString(MarkdownText.render(text))
        releaseNotesBox.isHidden = false
        releaseNotesHeightConstraint?.constant = 110
        layoutSubtreeIfNeeded()
    }

    private func hideReleaseNotes() {
        releaseNotesBox.isHidden = true
        releaseNotesHeightConstraint?.constant = 0
        layoutSubtreeIfNeeded()
    }
}
