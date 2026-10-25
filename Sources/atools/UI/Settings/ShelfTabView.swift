import Foundation
import AppKit

// MARK: - 2. Shelf Tab View
public final class ShelfTabView: NSView {
    public private(set) var shelfRecorder: HotkeyRecorderControl?
    private var shelfSwitch: NSSwitch!
    private var trackpadGesturePopUp: SettingsLiquidPopUpButton!
    private var pinSwitch: NSSwitch!
    private var autoCloseLaunchSwitch: NSSwitch!
    private var autoCloseMouseExitSwitch: NSSwitch!
    private var orientationControl: SettingsLiquidSegmentedControl!
    private var iconSizeSlider: NSSlider!
    private var iconSizeBadge: NSTextField!
    private var resetScaleButton: SettingsResetButton!
    private var itemSpacingSlider: NSSlider!
    private var itemSpacingBadge: NSTextField!
    private var resetSpacingButton: SettingsResetButton!
    private var favoritesSwitch: NSSwitch!
    private var shelfMissingItemsRow: SettingsRowView!
    private var shelfCleanMissingBtn: SettingsPillButton!
    public var headerView: SettingsHeaderView!
    private var pageContainer: NSView!
    private var pages: [NSView] = []

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShelfDataChanged),
            name: .atoolsShelfDataDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    @objc private func handleShelfDataChanged() {
        refresh()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        headerView = SettingsHeaderView(title: "应用抽屉", iconName: "square.grid.2x2", tabs: ["启用与唤出触发", "驻留形态与关闭行为", "分类与视觉排版"])
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

        // Page 0: 启用与唤出触发
        let triggerPage = NSView()
        let triggerScrollContent = NSView()
        let triggerScroll = makeTabScrollView(contentView: triggerScrollContent)
        triggerPage.addSubview(triggerScroll)
        NSLayoutConstraint.activate([
            triggerScroll.topAnchor.constraint(equalTo: triggerPage.topAnchor),
            triggerScroll.leadingAnchor.constraint(equalTo: triggerPage.leadingAnchor),
            triggerScroll.trailingAnchor.constraint(equalTo: triggerPage.trailingAnchor),
            triggerScroll.bottomAnchor.constraint(equalTo: triggerPage.bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "启用与唤出触发")
        triggerScrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        triggerScrollContent.addSubview(card1)

        shelfSwitch = NSSwitch()
        shelfSwitch.target = self
        shelfSwitch.action = #selector(toggleShelfPanel(_:))
        let rowShelf = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "square.grid.2x2"),
            title: "启用应用分类工作台",
            subtitle: "开启后支持自定义分类、拖拽整理与快速启停",
            accessory: shelfSwitch
        )
        card1.addRow(rowShelf)

        let recorder = HotkeyRecorderControl(binding: ConfigManager.shared.config.shelfHotkey)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 210).isActive = true
        recorder.onChange = { [weak self] newBinding in
            self?.handleShelfRecorded(newBinding)
        }
        recorder.onClear = { [weak self] in
            self?.handleShelfCleared()
        }
        self.shelfRecorder = recorder
        let rowRecorder = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "keyboard"),
            title: "专属全局快捷键",
            subtitle: "默认 ⌥A，支持按下键盘任意组合键或双击修饰键 (如 2× ⌥)",
            accessory: recorder
        )
        card1.addRow(rowRecorder)

        trackpadGesturePopUp = SettingsLiquidPopUpButton(frame: .zero, pullsDown: false)
        trackpadGesturePopUp.translatesAutoresizingMaskIntoConstraints = false
        trackpadGesturePopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
        for gesture in ShelfTrackpadGesture.allCases {
            trackpadGesturePopUp.addItem(withTitle: gesture.title)
        }
        trackpadGesturePopUp.target = self
        trackpadGesturePopUp.action = #selector(trackpadGestureChanged(_:))
        let rowGesture = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hand.point.up.left"),
            title: "触控板手势唤出",
            subtitle: "在触控板上轻点手势随时呼出工作台（推荐四指轻点）",
            accessory: trackpadGesturePopUp
        )
        card1.addRow(rowGesture, isLast: true)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: triggerScrollContent.topAnchor, constant: 6),
            sec1Title.leadingAnchor.constraint(equalTo: triggerScrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 7),
            card1.leadingAnchor.constraint(equalTo: triggerScrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: triggerScrollContent.trailingAnchor, constant: -28),
            card1.bottomAnchor.constraint(equalTo: triggerScrollContent.bottomAnchor, constant: -16)
        ])

        // Page 1: 驻留形态与关闭行为
        let behaviorPage = NSView()
        let behaviorScrollContent = NSView()
        let behaviorScroll = makeTabScrollView(contentView: behaviorScrollContent)
        behaviorPage.addSubview(behaviorScroll)
        NSLayoutConstraint.activate([
            behaviorScroll.topAnchor.constraint(equalTo: behaviorPage.topAnchor),
            behaviorScroll.leadingAnchor.constraint(equalTo: behaviorPage.leadingAnchor),
            behaviorScroll.trailingAnchor.constraint(equalTo: behaviorPage.trailingAnchor),
            behaviorScroll.bottomAnchor.constraint(equalTo: behaviorPage.bottomAnchor)
        ])

        let sec2Title = makeSectionHeader(title: "驻留形态与关闭行为")
        behaviorScrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        behaviorScrollContent.addSubview(card2)

        pinSwitch = NSSwitch()
        pinSwitch.target = self
        pinSwitch.action = #selector(togglePin(_:))
        let rowPin = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "pin"),
            title: "抽屉面板固定在桌面",
            subtitle: "开启后抽屉始终停留在桌面壁纸上方，不受失焦关闭影响",
            accessory: pinSwitch
        )
        card2.addRow(rowPin)

        autoCloseLaunchSwitch = NSSwitch()
        autoCloseLaunchSwitch.target = self
        autoCloseLaunchSwitch.action = #selector(toggleAutoCloseLaunch(_:))
        let rowCloseLaunch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.down.right.and.arrow.up.left"),
            title: "点击启动应用后自动关闭",
            subtitle: "在抽屉中点击启动应用后，立即自动收起抽屉窗口",
            accessory: autoCloseLaunchSwitch
        )
        card2.addRow(rowCloseLaunch)

        autoCloseMouseExitSwitch = NSSwitch()
        autoCloseMouseExitSwitch.target = self
        autoCloseMouseExitSwitch.action = #selector(toggleAutoCloseMouseExit(_:))
        let rowCloseMouse = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "cursorarrow.motionlines"),
            title: "鼠标移出面板后自动关闭",
            subtitle: "含 0.35s 防抖延迟与右键菜单弹出保护",
            accessory: autoCloseMouseExitSwitch
        )
        card2.addRow(rowCloseMouse, isLast: true)

        NSLayoutConstraint.activate([
            sec2Title.topAnchor.constraint(equalTo: behaviorScrollContent.topAnchor, constant: 6),
            sec2Title.leadingAnchor.constraint(equalTo: behaviorScrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 7),
            card2.leadingAnchor.constraint(equalTo: behaviorScrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: behaviorScrollContent.trailingAnchor, constant: -28),
            card2.bottomAnchor.constraint(equalTo: behaviorScrollContent.bottomAnchor, constant: -16)
        ])

        // Page 2: 分类与视觉排版
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

        let sec3Title = makeSectionHeader(title: "分类与视觉排版")
        layoutScrollContent.addSubview(sec3Title)

        let card3 = SettingsCardView()
        card3.translatesAutoresizingMaskIntoConstraints = false
        layoutScrollContent.addSubview(card3)

        orientationControl = SettingsLiquidSegmentedControl(labels: ["水平顶部", "垂直左侧"], target: self, action: #selector(orientationChanged(_:)))
        orientationControl.translatesAutoresizingMaskIntoConstraints = false
        orientationControl.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let rowOrient = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "rectangle.split.2x1"),
            title: "分类栏布局方向",
            subtitle: "切换分类胶囊栏在应用抽屉的展示方位（顶部或左侧）",
            accessory: orientationControl
        )
        card3.addRow(rowOrient)

        let sliderContainer = NSView()
        sliderContainer.translatesAutoresizingMaskIntoConstraints = false

        iconSizeSlider = NSSlider(value: 100, minValue: 70, maxValue: 110, target: self, action: #selector(scaleSliderChanged(_:)))
        iconSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        iconSizeSlider.numberOfTickMarks = 5
        iconSizeSlider.allowsTickMarkValuesOnly = false
        iconSizeSlider.isContinuous = true
        sliderContainer.addSubview(iconSizeSlider)

        iconSizeBadge = NSTextField(labelWithString: "100%")
        iconSizeBadge.translatesAutoresizingMaskIntoConstraints = false
        iconSizeBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        iconSizeBadge.textColor = .secondaryLabelColor
        iconSizeBadge.alignment = .left
        sliderContainer.addSubview(iconSizeBadge)

        resetScaleButton = SettingsResetButton(title: "恢复默认", target: self, action: #selector(resetScaleToDefault))
        sliderContainer.addSubview(resetScaleButton)

        NSLayoutConstraint.activate([
            sliderContainer.widthAnchor.constraint(equalToConstant: 240),
            sliderContainer.heightAnchor.constraint(equalToConstant: 24),

            iconSizeSlider.leadingAnchor.constraint(equalTo: sliderContainer.leadingAnchor),
            iconSizeSlider.centerYAnchor.constraint(equalTo: sliderContainer.centerYAnchor),
            iconSizeSlider.widthAnchor.constraint(equalToConstant: 120),

            iconSizeBadge.leadingAnchor.constraint(equalTo: iconSizeSlider.trailingAnchor, constant: 6),
            iconSizeBadge.centerYAnchor.constraint(equalTo: sliderContainer.centerYAnchor),
            iconSizeBadge.widthAnchor.constraint(equalToConstant: 38),

            resetScaleButton.leadingAnchor.constraint(equalTo: iconSizeBadge.trailingAnchor, constant: 8),
            resetScaleButton.centerYAnchor.constraint(equalTo: sliderContainer.centerYAnchor),
            resetScaleButton.trailingAnchor.constraint(equalTo: sliderContainer.trailingAnchor),
            resetScaleButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        let rowScale = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "slider.horizontal.below.rectangle"),
            title: "应用图标大小比例",
            subtitle: "自由缩放应用抽屉网格内图标和文字尺寸 (70% ~ 110%，默认 100%)",
            accessory: sliderContainer
        )
        card3.addRow(rowScale)

        let spacingContainer = NSView()
        spacingContainer.translatesAutoresizingMaskIntoConstraints = false

        itemSpacingSlider = NSSlider(value: 6, minValue: 2, maxValue: 24, target: self, action: #selector(spacingSliderChanged(_:)))
        itemSpacingSlider.translatesAutoresizingMaskIntoConstraints = false
        itemSpacingSlider.numberOfTickMarks = 0
        itemSpacingSlider.allowsTickMarkValuesOnly = false
        itemSpacingSlider.isContinuous = true
        spacingContainer.addSubview(itemSpacingSlider)

        itemSpacingBadge = NSTextField(labelWithString: "6 pt")
        itemSpacingBadge.translatesAutoresizingMaskIntoConstraints = false
        itemSpacingBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        itemSpacingBadge.textColor = .secondaryLabelColor
        itemSpacingBadge.alignment = .left
        spacingContainer.addSubview(itemSpacingBadge)

        resetSpacingButton = SettingsResetButton(title: "恢复默认", target: self, action: #selector(resetSpacingToDefault))
        spacingContainer.addSubview(resetSpacingButton)

        NSLayoutConstraint.activate([
            spacingContainer.widthAnchor.constraint(equalToConstant: 240),
            spacingContainer.heightAnchor.constraint(equalToConstant: 24),

            itemSpacingSlider.leadingAnchor.constraint(equalTo: spacingContainer.leadingAnchor),
            itemSpacingSlider.centerYAnchor.constraint(equalTo: spacingContainer.centerYAnchor),
            itemSpacingSlider.widthAnchor.constraint(equalToConstant: 120),

            itemSpacingBadge.leadingAnchor.constraint(equalTo: itemSpacingSlider.trailingAnchor, constant: 6),
            itemSpacingBadge.centerYAnchor.constraint(equalTo: spacingContainer.centerYAnchor),
            itemSpacingBadge.widthAnchor.constraint(equalToConstant: 38),

            resetSpacingButton.leadingAnchor.constraint(equalTo: itemSpacingBadge.trailingAnchor, constant: 8),
            resetSpacingButton.centerYAnchor.constraint(equalTo: spacingContainer.centerYAnchor),
            resetSpacingButton.trailingAnchor.constraint(equalTo: spacingContainer.trailingAnchor),
            resetSpacingButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        let rowSpacing = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.left.and.right.square"),
            title: "应用图标间距",
            subtitle: "自由调节应用抽屉网格内图标选中底衬之间的间隙 (2 ~ 24 pt，默认 6 pt)",
            accessory: spacingContainer
        )
        card3.addRow(rowSpacing)

        favoritesSwitch = NSSwitch()
        favoritesSwitch.target = self
        favoritesSwitch.action = #selector(toggleFavorites(_:))
        let rowFav = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "star.fill"),
            title: "启用「常用」分类",
            subtitle: "在分类栏首位展示常用应用，并随使用频率自动排序",
            accessory: favoritesSwitch
        )
        card3.addRow(rowFav)

        shelfCleanMissingBtn = SettingsPillButton(title: "一键清理失效项", target: self, action: #selector(cleanShelfMissingItemsClicked))
        shelfMissingItemsRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "exclamationmark.triangle"),
            title: "清理失效启动项",
            subtitle: "对已卸载或移动的项目渲染灰阶与感叹号角标，支持右键重定位或一键清理",
            accessory: shelfCleanMissingBtn
        )
        card3.addRow(shelfMissingItemsRow, isLast: true)

        NSLayoutConstraint.activate([
            sec3Title.topAnchor.constraint(equalTo: layoutScrollContent.topAnchor, constant: 6),
            sec3Title.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 28),

            card3.topAnchor.constraint(equalTo: sec3Title.bottomAnchor, constant: 7),
            card3.leadingAnchor.constraint(equalTo: layoutScrollContent.leadingAnchor, constant: 28),
            card3.trailingAnchor.constraint(equalTo: layoutScrollContent.trailingAnchor, constant: -28),
            card3.bottomAnchor.constraint(equalTo: layoutScrollContent.bottomAnchor, constant: -16)
        ])

        pages = [triggerPage, behaviorPage, layoutPage]
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

    public func showPage(_ index: Int) {
        guard index >= 0 && index < pages.count else { return }
        for (i, p) in pages.enumerated() {
            p.isHidden = (i != index)
        }
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        shelfSwitch.state = cfg.enableShelfPanel ? .on : .off
        shelfSwitch.isEnabled = cfg.enableSearchPanel
        let enabled = cfg.enableShelfPanel

        shelfRecorder?.isEnabled = enabled
        shelfRecorder?.currentBinding = cfg.shelfHotkey
        trackpadGesturePopUp.isEnabled = enabled
        if let idx = ShelfTrackpadGesture.allCases.firstIndex(of: cfg.shelfTrackpadGesture) {
            trackpadGesturePopUp.selectItem(at: idx)
        }

        pinSwitch.isEnabled = enabled
        pinSwitch.state = cfg.isShelfPinned ? .on : .off
        autoCloseLaunchSwitch.isEnabled = enabled
        autoCloseLaunchSwitch.state = cfg.autoCloseOnLaunch ? .on : .off
        autoCloseMouseExitSwitch.isEnabled = enabled
        autoCloseMouseExitSwitch.state = cfg.autoCloseOnMouseExit ? .on : .off

        orientationControl.isEnabled = enabled
        orientationControl.selectedSegment = (cfg.categoryOrientation == .vertical) ? 1 : 0

        iconSizeSlider.isEnabled = enabled
        iconSizeSlider.doubleValue = cfg.shelfIconScale * 100.0
        let pct = Int(round(cfg.shelfIconScale * 100.0))
        iconSizeBadge.stringValue = "\(pct)%"
        resetScaleButton.isEnabled = enabled && (pct != 100)

        itemSpacingSlider.isEnabled = enabled
        let currentSpacing = cfg.shelfItemSpacing
        itemSpacingSlider.doubleValue = currentSpacing
        let spacingInt = Int(round(currentSpacing))
        itemSpacingBadge.stringValue = "\(spacingInt) pt"
        resetSpacingButton.isEnabled = enabled && (spacingInt != 6)

        favoritesSwitch.isEnabled = enabled
        favoritesSwitch.state = cfg.enableFavoritesCategory ? .on : .off

        let missingCount = ConfigManager.shared.scanMissingItems().count
        if missingCount == 0 {
            shelfMissingItemsRow.subtitleLabel.stringValue = "当前所有抽屉项目目标路径均正常有效（0 个失效项）"
            shelfCleanMissingBtn.isEnabled = false
        } else {
            shelfMissingItemsRow.subtitleLabel.stringValue = "当前检测到 \(missingCount) 个失效启动项（可在抽屉右键重新定位，或在此一键清理）"
            shelfCleanMissingBtn.isEnabled = enabled
        }
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

    private func handleShelfRecorded(_ newBinding: HotkeyBinding) {
        let currentSearch = ConfigManager.shared.config.searchHotkey
        if newBinding == currentSearch {
            shelfRecorder?.currentBinding = ConfigManager.shared.config.shelfHotkey
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            alert.informativeText = "该快捷键已被「全盘搜索中枢」占用。请录入其他组合键，或前往全盘搜索设置调整。"
            alert.runModalAboveFloatingWindows()
            return
        }
        ConfigManager.shared.updateShelfHotkey(newBinding)
        HotkeyManager.shared.register(id: .shelf, binding: newBinding)
        shelfRecorder?.currentBinding = newBinding
    }

    private func handleShelfCleared() {
        let unassigned = HotkeyBinding(keyCode: 0, carbonModifiers: 0, displayString: "", specialTrigger: .none)
        ConfigManager.shared.updateShelfHotkey(unassigned)
        HotkeyManager.shared.unregister(id: .shelf)
    }

    @objc private func trackpadGestureChanged(_ sender: NSPopUpButton) {
        let gestures = ShelfTrackpadGesture.allCases
        guard gestures.indices.contains(sender.indexOfSelectedItem) else { return }
        let selected = gestures[sender.indexOfSelectedItem]
        ConfigManager.shared.updateShelfTrackpadGesture(selected)
    }

    @objc private func togglePin(_ sender: NSSwitch) {
        ConfigManager.shared.updateIsShelfPinned(sender.state == .on)
    }

    @objc private func toggleAutoCloseLaunch(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoCloseOnLaunch(sender.state == .on)
    }

    @objc private func toggleAutoCloseMouseExit(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoCloseOnMouseExit(sender.state == .on)
    }

    @objc private func orientationChanged(_ sender: SettingsLiquidSegmentedControl) {
        let newOrientation: CategoryOrientation = (sender.selectedSegment == 1) ? .vertical : .horizontal
        ConfigManager.shared.updateCategoryOrientation(newOrientation)
        NotificationCenter.default.post(name: .atoolsCategoryOrientationDidChange, object: nil)
    }

    @objc private func scaleSliderChanged(_ sender: NSSlider) {
        let val = round(sender.doubleValue)
        let scale = val / 100.0
        let pct = Int(val)
        iconSizeBadge.stringValue = "\(pct)%"
        resetScaleButton.isEnabled = (pct != 100)
        guard abs(scale - ConfigManager.shared.config.shelfIconScale) > 0.001 else { return }
        ConfigManager.shared.updateShelfIconScale(scale)
        NotificationCenter.default.post(name: .atoolsShelfIconSizeDidChange, object: nil)
    }

    @objc private func resetScaleToDefault() {
        iconSizeSlider.doubleValue = 100.0
        scaleSliderChanged(iconSizeSlider)
    }

    @objc private func spacingSliderChanged(_ sender: NSSlider) {
        let val = round(sender.doubleValue)
        let spacingInt = Int(val)
        itemSpacingBadge.stringValue = "\(spacingInt) pt"
        resetSpacingButton.isEnabled = (spacingInt != 6)
        guard abs(val - ConfigManager.shared.config.shelfItemSpacing) > 0.001 else { return }
        ConfigManager.shared.updateShelfItemSpacing(val)
    }

    @objc private func resetSpacingToDefault() {
        itemSpacingSlider.doubleValue = 6.0
        spacingSliderChanged(itemSpacingSlider)
    }

    @objc private func toggleFavorites(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableFavoritesCategory(sender.state == .on)
        NotificationCenter.default.post(name: .atoolsFavoritesToggleDidChange, object: nil)
    }

    @objc private func cleanShelfMissingItemsClicked() {
        let missing = ConfigManager.shared.scanMissingItems()
        guard !missing.isEmpty else { return }
        let previewLines = missing.prefix(8).map { "• [\($0.category.name)] \($0.item.name) (\($0.item.target))" }.joined(separator: "\n")
        let moreHint = missing.count > 8 ? "\n…等共 \(missing.count) 个失效项目" : ""
        let alert = NSAlert()
        alert.messageText = "确认一键清理 \(missing.count) 个失效启动项？"
        alert.informativeText = "以下项目因软件卸载或文件移动已失效，清理后将从对应分类中移除：\n\n\(previewLines)\(moreHint)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "立即清理")
        alert.addButton(withTitle: "取消")
        if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
            let removedCount = ConfigManager.shared.removeAllMissingItems()
            refresh()
            let done = NSAlert()
            done.messageText = "清理完成"
            done.informativeText = "已成功清理 \(removedCount) 个失效启动项。"
            done.alertStyle = .informational
            done.runModalAboveFloatingWindows()
        }
    }
}

