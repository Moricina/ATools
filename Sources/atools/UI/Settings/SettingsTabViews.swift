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
    private var launchOnLoginSwitch: NSSwitch!
    private var autoCloseDeactivateSwitch: NSSwitch!
    private var backupExportRow: SettingsRowView!
    private var rollbackSnapshotBtn: SettingsPillButton!
    private var missingItemsRow: SettingsRowView!
    private var cleanMissingBtn: SettingsPillButton!

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

        let headerView = SettingsHeaderView(title: "常规", iconName: "gearshape")
        addSubview(headerView)

        let scrollContent = NSView()
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

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

        // 1. 基础与系统
        let sec1Title = makeSectionHeader(title: "基础与系统")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

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

        autoCloseDeactivateSwitch = NSSwitch()
        autoCloseDeactivateSwitch.target = self
        autoCloseDeactivateSwitch.action = #selector(toggleAutoCloseDeactivate(_:))
        let rowCloseDeactivate = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "macwindow.badge.plus"),
            title: "失焦时自动关闭",
            subtitle: "点击面板外部任意工作区或切换应用时自动收起窗口",
            accessory: autoCloseDeactivateSwitch,
            minHeight: 46
        )
        card1.addRow(rowCloseDeactivate, isLast: true)

        // 2. 备份与恢复数据 (P0-3 & P0-2)
        let secBackupTitle = makeSectionHeader(title: "备份与恢复数据")
        scrollContent.addSubview(secBackupTitle)

        let backupCard = SettingsCardView()
        backupCard.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(backupCard)

        let exportBtn = SettingsPillButton(title: "导出备份...", target: self, action: #selector(exportBackupClicked))
        backupExportRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "externaldrive.badge.plus"),
            title: "导出配置与图标全量备份",
            subtitle: "将 config.json、自定义图标目录 icons/ 与校验清单打包导出为 .atoolsbackup",
            accessory: exportBtn
        )
        backupCard.addRow(backupExportRow)

        let restoreButtonsStack = NSStackView()
        restoreButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        restoreButtonsStack.orientation = .horizontal
        restoreButtonsStack.spacing = 8
        restoreButtonsStack.alignment = .centerY

        rollbackSnapshotBtn = SettingsPillButton(title: "回滚快照", target: self, action: #selector(rollbackSnapshotClicked))
        let importBtn = SettingsPillButton(title: "导入恢复...", style: .primary, target: self, action: #selector(importBackupClicked))
        restoreButtonsStack.addArrangedSubview(rollbackSnapshotBtn)
        restoreButtonsStack.addArrangedSubview(importBtn)

        let rowRestore = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.counterclockwise.icloud"),
            title: "从备份恢复与快照回滚",
            subtitle: "恢复前先在内存干跑校验 JSON 与 SHA-256，自动创建 pre-restore 快照并自愈跨机图标路径",
            accessory: restoreButtonsStack
        )
        backupCard.addRow(rowRestore)

        cleanMissingBtn = SettingsPillButton(title: "一键清理失效项", target: self, action: #selector(cleanMissingItemsClicked))
        missingItemsRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "wand.and.stars"),
            title: "一键清理全部失效项目",
            subtitle: "扫描并移除所有分类中已被卸载或移动的失效启动项",
            accessory: cleanMissingBtn
        )
        backupCard.addRow(missingItemsRow, isLast: true)

        // 3. 系统安全与隐私权限（直接平铺展示在下方）
        let sec2Title = makeSectionHeader(title: "系统安全与隐私权限")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let axBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openAccessibilitySettings))
        let rowAx = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hand.raised"),
            title: "辅助功能权限 (Accessibility)",
            subtitle: "用于快捷键全局监听、关窗退出窗口感知等系统特性",
            accessory: axBtn
        )
        card2.addRow(rowAx)

        let fdaBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openFullDiskAccessSettings))
        let rowFDA = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "lock.shield"),
            title: "完全磁盘访问权限 (Full Disk Access)",
            subtitle: "若搜不到“下载”或“文稿”等受 TCC 保护的目录文件，请前往系统设置授权",
            accessory: fdaBtn
        )
        card2.addRow(rowFDA, isLast: true)

        let permTip = NSTextField(labelWithString: "权限提示：本软件所有功能均在本地运行，零网络上传，完全尊重您的隐私与系统安全。")
        permTip.translatesAutoresizingMaskIntoConstraints = false
        permTip.font = NSFont.systemFont(ofSize: 11)
        permTip.textColor = .secondaryLabelColor
        permTip.cell?.wraps = true
        permTip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollContent.addSubview(permTip)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: scrollContent.topAnchor, constant: 8),
            sec1Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 7),
            card1.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            secBackupTitle.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 16),
            secBackupTitle.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            backupCard.topAnchor.constraint(equalTo: secBackupTitle.bottomAnchor, constant: 7),
            backupCard.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            backupCard.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            sec2Title.topAnchor.constraint(equalTo: backupCard.bottomAnchor, constant: 16),
            sec2Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 7),
            card2.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            permTip.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 10),
            permTip.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            permTip.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),
            permTip.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -16)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        launchOnLoginSwitch.state = LaunchAtLoginController.shared.isEnabled ? .on : .off
        autoCloseDeactivateSwitch.state = cfg.autoCloseOnDeactivate ? .on : .off

        let totalCats = cfg.categories.count
        let totalItems = cfg.categories.reduce(0) { $0 + $1.items.count }
        let customIconCount = cfg.categories.flatMap { $0.items }.filter { ($0.customIconPath ?? "").isEmpty == false }.count
        backupExportRow.subtitleLabel.stringValue = "打包导出 config.json、icons/ 与 manifest.json（当前 \(totalCats) 个分类、\(totalItems) 个项目、\(customIconCount) 个自定义图标）"

        let snapshots = BackupService.shared.listPreRestoreSnapshots()
        rollbackSnapshotBtn.isEnabled = !snapshots.isEmpty
        rollbackSnapshotBtn.toolTip = snapshots.first.map { "回滚至最近一次恢复前快照：\($0.lastPathComponent)" } ?? "尚无恢复前自动快照"

        let missingList = ConfigManager.shared.scanMissingItems()
        if missingList.isEmpty {
            missingItemsRow.subtitleLabel.stringValue = "所有分类中的启动项目标路径均有效（0 个失效项目）"
            cleanMissingBtn.isEnabled = false
        } else {
            missingItemsRow.subtitleLabel.stringValue = "检测到 \(missingList.count) 个失效启动项（目标已被移动或卸载），支持一键清理"
            cleanMissingBtn.isEnabled = true
        }
    }

    @objc private func exportBackupClicked() {
        let panel = NSSavePanel()
        panel.title = "导出 ATools 配置与自定义图标备份"
        panel.prompt = "导出备份"
        panel.nameFieldStringValue = BackupService.defaultBackupFolderName()
        panel.canCreateDirectories = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)

        guard panel.runModalAboveFloatingWindows() == .OK, let destURL = panel.url else { return }

        do {
            let manifest = try BackupService.shared.exportBackup(to: destURL)
            let alert = NSAlert()
            alert.messageText = "全量备份导出成功"
            alert.informativeText = """
            已成功打包导出至：
            \(destURL.path)

            • 分类数量：\(manifest.categoriesCount) 个
            • 启动项数：\(manifest.totalItemsCount) 个
            • 托管图标：\(manifest.customIcons.count) 个
            • 校验摘要：\(manifest.configSHA256.prefix(16))...
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "完成")
            alert.addButton(withTitle: "在访达中显示")
            if alert.runModalAboveFloatingWindows() == .alertSecondButtonReturn {
                NSWorkspace.shared.selectFile(destURL.path, inFileViewerRootedAtPath: "")
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出备份失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModalAboveFloatingWindows()
        }
    }

    @objc private func importBackupClicked() {
        let panel = NSOpenPanel()
        panel.title = "选择要恢复的 .atoolsbackup 归档目录或 config.json 文件"
        panel.prompt = "预校验并恢复"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)

        guard panel.runModalAboveFloatingWindows() == .OK, let srcURL = panel.url else { return }

        // 1. 恢复前内存干跑预校验 (Dry-Run Pre-Validation)
        switch BackupService.shared.validateBackup(at: srcURL) {
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "备份预校验未通过（已拒绝覆盖）"
            alert.informativeText = """
            恢复前内存干跑校验发现问题，当前现有配置未受任何影响：

            错误原因：\(error.localizedDescription)
            """
            alert.alertStyle = .critical
            alert.runModalAboveFloatingWindows()
            return

        case .success(let validation):
            let confirmAlert = NSAlert()
            confirmAlert.messageText = "预校验通过，是否确认恢复备份？"
            confirmAlert.informativeText = """
            内存干跑校验已通过（SHA-256 哈希与版本兼容性完整无损）：

            • 备份来源：\(srcURL.lastPathComponent)
            • 创建时间：\(validation.createdAtDisplay)
            • 恢复内容：\(validation.categoriesCount) 个分类、\(validation.totalItemsCount) 个启动项、\(validation.customIconsCount) 个自定义图标
            • 跨机自愈：自动重映射 \(validation.healedIconPathsCount) 个图标路径与 \(validation.healedUserPathsCount) 个用户目录路径
            • 安全快照：恢复前将自动把当前配置备份至 backups/pre-restore-*
            """
            confirmAlert.alertStyle = .warning
            confirmAlert.addButton(withTitle: "确认恢复")
            confirmAlert.addButton(withTitle: "取消")

            guard confirmAlert.runModalAboveFloatingWindows() == .alertFirstButtonReturn else { return }

            do {
                let (_, snapshotURL) = try BackupService.shared.restoreBackup(from: srcURL, createSnapshot: true)
                refresh()
                let doneAlert = NSAlert()
                doneAlert.messageText = "备份恢复成功"
                let snapName = snapshotURL?.lastPathComponent ?? "无"
                doneAlert.informativeText = "已成功恢复 \(validation.categoriesCount) 个分类与 \(validation.totalItemsCount) 个启动项，跨机图标路径已自动自愈。\n\n恢复前安全快照已保存至：\(snapName)"
                doneAlert.alertStyle = .informational
                doneAlert.runModalAboveFloatingWindows()
            } catch {
                let errAlert = NSAlert()
                errAlert.messageText = "恢复备份失败"
                errAlert.informativeText = error.localizedDescription
                errAlert.alertStyle = .critical
                errAlert.runModalAboveFloatingWindows()
            }
        }
    }

    @objc private func rollbackSnapshotClicked() {
        let snapshots = BackupService.shared.listPreRestoreSnapshots()
        guard let latest = snapshots.first else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "回滚至恢复前安全快照"
        alert.informativeText = "确定要回滚到最近一次恢复前的自动快照「\(latest.lastPathComponent)」吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确认回滚")
        alert.addButton(withTitle: "取消")

        guard alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn else { return }

        do {
            let result = try BackupService.shared.rollbackToLatestSnapshot()
            refresh()
            let done = NSAlert()
            done.messageText = "已成功回滚至恢复前快照"
            done.informativeText = "已还原 \(result.categoriesCount) 个分类与 \(result.totalItemsCount) 个启动项。"
            done.alertStyle = .informational
            done.runModalAboveFloatingWindows()
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "快照回滚失败"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .critical
            errAlert.runModalAboveFloatingWindows()
        }
    }

    @objc private func cleanMissingItemsClicked() {
        let missing = ConfigManager.shared.scanMissingItems()
        guard !missing.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无需清理"
            alert.informativeText = "当前所有分类中的启动项路径均有效，未发现失效项目。"
            alert.runModalAboveFloatingWindows()
            return
        }

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

    @objc private func toggleLaunchOnLogin(_ sender: NSSwitch) {
        do {
            try LaunchAtLoginController.shared.setEnabled(sender.state == .on)
        } catch {
            sender.state = (sender.state == .on) ? .off : .on
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = error.localizedDescription
            alert.runModalAboveFloatingWindows()
        }
    }

    @objc private func toggleAutoCloseDeactivate(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoCloseOnDeactivate(sender.state == .on)
    }

    @objc private func openAccessibilitySettings() {
        HotkeyManager.openAccessibilitySettings()
    }

    @objc private func openFullDiskAccessSettings() {
        if #available(macOS 13.0, *), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
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
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            alert.informativeText = "该快捷键已被「全盘搜索中枢」占用。请录入其他组合键，或前往全盘搜索设置调整。"
            alert.runModalAboveFloatingWindows()
            shelfRecorder?.currentBinding = ConfigManager.shared.config.shelfHotkey
            return
        }
        ConfigManager.shared.updateShelfHotkey(newBinding)
        HotkeyManager.shared.register(id: .shelf, binding: newBinding)
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

// MARK: - 3. Search Tab View
public final class SearchTabView: NSView, NSTextFieldDelegate {
    public private(set) var searchRecorder: HotkeyRecorderControl?
    private var searchSwitch: NSSwitch!
    private var diskSearchSwitch: NSSwitch!
    private var autoPasteSwitch: NSSwitch!
    private var dictSwitch: NSSwitch!
    private var calcSwitch: NSSwitch!
    private var limitControl: SettingsLiquidSegmentedControl!
    private var webSearchSwitch: NSSwitch!
    private var enginePopUp: SettingsLiquidPopUpButton!
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

        headerView = SettingsHeaderView(title: "全盘搜索", iconName: "magnifyingglass", tabs: ["搜索选项", "排除范围", "扩展与平替", "网络搜索"])
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

        // Section 0: 启用与呼出快捷键
        let sec0Title = makeSectionHeader(title: "启用与呼出快捷键")
        optionsScrollContent.addSubview(sec0Title)

        let card0 = SettingsCardView()
        card0.translatesAutoresizingMaskIntoConstraints = false
        optionsScrollContent.addSubview(card0)

        searchSwitch = NSSwitch()
        searchSwitch.target = self
        searchSwitch.action = #selector(toggleSearchPanel(_:))
        let rowSearch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass"),
            title: "启用全盘搜索中枢",
            subtitle: "开启后支持快捷键呼出、全盘文件极速检索与内置扩展工具",
            accessory: searchSwitch
        )
        card0.addRow(rowSearch)

        let recorder = HotkeyRecorderControl(binding: ConfigManager.shared.config.searchHotkey)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 210).isActive = true
        recorder.onChange = { [weak self] newBinding in
            self?.handleSearchRecorded(newBinding)
        }
        recorder.onClear = { [weak self] in
            self?.handleSearchCleared()
        }
        self.searchRecorder = recorder
        let rowRecorder = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "keyboard"),
            title: "专属呼出快捷键",
            subtitle: "默认 ⌥Space，支持键盘任意组合键或双击修饰键 (如 2× ⌥)",
            accessory: recorder
        )
        card0.addRow(rowRecorder, isLast: true)

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

        limitControl = SettingsLiquidSegmentedControl(labels: ["30 条", "50 条", "80 条 (推荐)", "120 条"], target: self, action: #selector(limitChanged(_:)))
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
            sec0Title.topAnchor.constraint(equalTo: optionsScrollContent.topAnchor, constant: 6),
            sec0Title.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            card0.topAnchor.constraint(equalTo: sec0Title.bottomAnchor, constant: 7),
            card0.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            card0.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28),

            sec1Title.topAnchor.constraint(equalTo: card0.bottomAnchor, constant: 16),
            sec1Title.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 7),
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
            secHotTitle.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 16),
            secHotTitle.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            cardHot.topAnchor.constraint(equalTo: secHotTitle.bottomAnchor, constant: 7),
            cardHot.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            cardHot.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28),
            cardHot.bottomAnchor.constraint(equalTo: optionsScrollContent.bottomAnchor, constant: -16)
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
        let tileCaches = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "archivebox"),
            title: "排除系统与应用缓存",
            toolTip: "自动过滤 ~/Library/Caches, /Library/Caches 及各类 WebKit 临时缓存数据",
            toggleSwitch: excludeCachesSwitch
        )

        excludeUserLibSwitch = NSSwitch()
        excludeUserLibSwitch.target = self
        excludeUserLibSwitch.action = #selector(toggleExcludeUserLib(_:))
        let tileUserLib = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "folder.badge.gearshape"),
            title: "排除资源库 (~/Library)",
            toolTip: "参照 Alfred 核心规则过滤系统配置杂项；智能保留 iCloud 云盘与各类第三方网盘文档",
            toggleSwitch: excludeUserLibSwitch
        )
        cardPreset.addRow(makeDualTileRow(left: tileCaches, right: tileUserLib))

        excludeLogsSwitch = NSSwitch()
        excludeLogsSwitch.target = self
        excludeLogsSwitch.action = #selector(toggleExcludeLogs(_:))
        let tileLogs = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "doc.text.magnifyingglass"),
            title: "排除系统日志与崩溃报告",
            toolTip: "自动过滤 ~/Library/Logs, /var/log, DiagnosticReports 及系统崩溃堆栈文件",
            toggleSwitch: excludeLogsSwitch
        )

        excludeTrashSwitch = NSSwitch()
        excludeTrashSwitch.target = self
        excludeTrashSwitch.action = #selector(toggleExcludeTrash(_:))
        let tileTrash = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "trash"),
            title: "排除废纸篓与临时目录",
            toolTip: "自动过滤 ~/.Trash, /private/var/folders, /tmp 等已丢弃与临时文件夹",
            toggleSwitch: excludeTrashSwitch
        )
        cardPreset.addRow(makeDualTileRow(left: tileLogs, right: tileTrash))

        excludeDevSwitch = NSSwitch()
        excludeDevSwitch.target = self
        excludeDevSwitch.action = #selector(toggleExcludeDev(_:))
        let tileDev = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hammer"),
            title: "排除开发依赖与构建产物",
            toolTip: "自动过滤 node_modules, DerivedData, .build, target, __pycache__, .gradle 等工程副产物",
            toggleSwitch: excludeDevSwitch
        )

        excludeHiddenSwitch = NSSwitch()
        excludeHiddenSwitch.target = self
        excludeHiddenSwitch.action = #selector(toggleExcludeHidden(_:))
        let tileHidden = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "eye.slash"),
            title: "排除版本控制与隐藏文件",
            toolTip: "自动过滤 .git, .svn 及以 \".\" 开头的系统级隐藏文件与隐藏文件夹",
            toggleSwitch: excludeHiddenSwitch
        )
        cardPreset.addRow(makeDualTileRow(left: tileDev, right: tileHidden), isLast: true)

        NSLayoutConstraint.activate([
            secPresetTitle.topAnchor.constraint(equalTo: exclusionScrollContent.topAnchor, constant: 6),
            secPresetTitle.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),

            cardPreset.topAnchor.constraint(equalTo: secPresetTitle.bottomAnchor, constant: 7),
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
            secCustomTitle.topAnchor.constraint(equalTo: cardPreset.bottomAnchor, constant: 16),
            secCustomTitle.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),

            cardCustom.topAnchor.constraint(equalTo: secCustomTitle.bottomAnchor, constant: 7),
            cardCustom.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            cardCustom.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28),

            exclusionTipLabel.topAnchor.constraint(equalTo: cardCustom.bottomAnchor, constant: 10),
            exclusionTipLabel.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            exclusionTipLabel.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28),
            exclusionTipLabel.bottomAnchor.constraint(equalTo: exclusionScrollContent.bottomAnchor, constant: -16)
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

        let secSpotTitle = makeSectionHeader(title: "Spotlight 权威平替指引")
        extScrollContent.addSubview(secSpotTitle)

        let cardSpot = SettingsCardView()
        cardSpot.translatesAutoresizingMaskIntoConstraints = false
        extScrollContent.addSubview(cardSpot)

        let setCmdSpaceBtn = SettingsPillButton(title: "设为 ⌘Space", target: self, action: #selector(setCommandSpaceHotkey))
        let rowSetCmdSpace = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "command"),
            title: "一键将全盘搜索快捷键设为 ⌘Space",
            subtitle: "无缝替代系统聚焦呼出体验，若系统快捷键冲突，请前往下方系统设置关闭",
            accessory: setCmdSpaceBtn
        )
        cardSpot.addRow(rowSetCmdSpace)

        let openKbBtn = SettingsPillButton(title: "系统键盘设置...", target: self, action: #selector(openKeyboardSettings))
        let rowKb = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "keyboard"),
            title: "打开系统键盘快捷键设置",
            subtitle: "前往「键盘」->「键盘快捷键」->「聚焦」，取消勾选“显示聚焦搜索”",
            accessory: openKbBtn
        )
        cardSpot.addRow(rowKb)

        let openCcBtn = SettingsPillButton(title: "控制中心设置...", target: self, action: #selector(openControlCenterSettings))
        let rowCc = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "switch.2"),
            title: "打开系统控制中心设置",
            subtitle: "前往「控制中心」->「聚焦」，可从 macOS 顶部菜单栏移除系统聚焦图标",
            accessory: openCcBtn
        )
        cardSpot.addRow(rowCc, isLast: true)

        let spotlightTip = NSTextField(labelWithString: "提示：将系统聚焦快捷键取消后，⌘Space 将由 ATools 独占接管，提供毫秒级全盘搜索。")
        spotlightTip.translatesAutoresizingMaskIntoConstraints = false
        spotlightTip.font = NSFont.systemFont(ofSize: 11)
        spotlightTip.textColor = .secondaryLabelColor
        spotlightTip.cell?.wraps = true
        spotlightTip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        extScrollContent.addSubview(spotlightTip)

        NSLayoutConstraint.activate([
            sec2Title.topAnchor.constraint(equalTo: extScrollContent.topAnchor, constant: 6),
            sec2Title.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 7),
            card2.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),

            secSpotTitle.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 16),
            secSpotTitle.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),

            cardSpot.topAnchor.constraint(equalTo: secSpotTitle.bottomAnchor, constant: 7),
            cardSpot.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),
            cardSpot.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),

            spotlightTip.topAnchor.constraint(equalTo: cardSpot.bottomAnchor, constant: 10),
            spotlightTip.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 32),
            spotlightTip.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),
            spotlightTip.bottomAnchor.constraint(equalTo: extScrollContent.bottomAnchor, constant: -16)
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

        enginePopUp = SettingsLiquidPopUpButton()
        enginePopUp.translatesAutoresizingMaskIntoConstraints = false
        enginePopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
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
            sec3Title.topAnchor.constraint(equalTo: webScrollContent.topAnchor, constant: 6),
            sec3Title.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),

            card3.topAnchor.constraint(equalTo: sec3Title.bottomAnchor, constant: 7),
            card3.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),
            card3.trailingAnchor.constraint(equalTo: webScrollContent.trailingAnchor, constant: -28),

            tipLabel.topAnchor.constraint(equalTo: card3.bottomAnchor, constant: 10),
            tipLabel.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),
            tipLabel.trailingAnchor.constraint(equalTo: webScrollContent.trailingAnchor, constant: -28),
            tipLabel.bottomAnchor.constraint(equalTo: webScrollContent.bottomAnchor, constant: -16)
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
        searchSwitch?.state = cfg.enableSearchPanel ? .on : .off
        searchSwitch?.isEnabled = cfg.enableShelfPanel
        let enabled = cfg.enableSearchPanel

        searchRecorder?.isEnabled = enabled
        searchRecorder?.currentBinding = cfg.searchHotkey

        diskSearchSwitch?.isEnabled = enabled
        autoPasteSwitch?.isEnabled = enabled
        calcSwitch?.isEnabled = enabled
        dictSwitch?.isEnabled = enabled
        limitControl?.isEnabled = enabled
        webSearchSwitch?.isEnabled = enabled

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
            addRow(makeEmptyHotFolderRow())
        } else {
            for (index, path) in folders.enumerated() {
                if index > 0 { addRow(makeSeparator()) }
                addRow(makeHotFolderRow(path: path))
            }
            addRow(makeSeparator())
            addRow(makeAddHotFolderRow(count: folders.count))
        }
    }

    private func makeEmptyHotFolderRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "添加自定义热目录…")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .controlAccentColor
        row.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "默认已覆盖下载/桌面/文稿 · 可点击右侧添加，或直接从访达拖拽文件夹至此")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        row.addSubview(subtitle)

        let addBtn = SettingsIconButton(
            symbolName: "plus.circle.fill",
            accessibilityLabel: "添加",
            target: self,
            action: #selector(addHotFolderClicked(_:))
        )
        addBtn.normalTintColor = .controlAccentColor
        addBtn.hoverTintColor = .controlAccentColor
        addBtn.toolTip = "添加热目录"
        row.addSubview(addBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -6),

            addBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
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

        let removeBtn = SettingsIconButton(
            symbolName: "minus.circle.fill",
            accessibilityLabel: "移除",
            target: self,
            action: #selector(removeHotFolderClicked(_:))
        )
        removeBtn.normalTintColor = .secondaryLabelColor
        removeBtn.hoverTintColor = .systemRed
        removeBtn.identifier = NSUserInterfaceItemIdentifier(path)
        removeBtn.toolTip = "从热目录移除"
        row.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5)
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

        let addBtn = SettingsIconButton(
            symbolName: "plus.circle.fill",
            accessibilityLabel: "添加",
            target: self,
            action: #selector(addHotFolderClicked(_:))
        )
        addBtn.normalTintColor = .controlAccentColor
        addBtn.hoverTintColor = .controlAccentColor
        addBtn.toolTip = "添加热目录"
        addBtn.isEnabled = count < ConfigManager.maxExtraHotFolders
        row.addSubview(addBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5),

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
        guard panel.runModalAboveFloatingWindows() == .OK, let url = panel.url else { return }
        if ConfigManager.shared.addHotFolder(url.path) {
            reloadHotFolderRows()
        } else {
            let alert = NSAlert()
            alert.messageText = "无法添加该目录"
            alert.informativeText = "目录不存在、与已有热目录重复或互相包含、或已达到上限（\(ConfigManager.maxExtraHotFolders) 个）。"
            alert.alertStyle = .warning
            alert.runModalAboveFloatingWindows()
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
        if !paths.isEmpty {
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

        let removeBtn = SettingsIconButton(
            symbolName: "minus.circle.fill",
            accessibilityLabel: "移除",
            target: self,
            action: #selector(removeCustomExclusionClicked(_:))
        )
        removeBtn.normalTintColor = .secondaryLabelColor
        removeBtn.hoverTintColor = .systemRed
        removeBtn.identifier = NSUserInterfaceItemIdentifier(path)
        removeBtn.toolTip = "从排除目录中移除"
        row.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5)
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

        let desc = (count == 0)
            ? "暂无自定义排除目录 · 可点击添加，或直接从访达将文件夹拖拽至此"
            : "已添加 \(count)/\(ConfigManager.maxCustomExcludedPaths) · 可点击添加，或直接从访达将文件夹拖拽至此"
        let subtitle = NSTextField(labelWithString: desc)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        row.addSubview(subtitle)

        let addBtn = SettingsIconButton(
            symbolName: "plus.circle.fill",
            accessibilityLabel: "添加",
            target: self,
            action: #selector(addCustomExclusionClicked(_:))
        )
        addBtn.normalTintColor = .controlAccentColor
        addBtn.hoverTintColor = .controlAccentColor
        addBtn.toolTip = "选择文件夹添加至排除黑名单"
        addBtn.isEnabled = count < ConfigManager.maxCustomExcludedPaths
        row.addSubview(addBtn)

        let resetBtn = SettingsResetButton(title: "恢复默认", target: self, action: #selector(resetCustomExclusionClicked(_:)))
        resetBtn.toolTip = "清空自定义排除目录"
        resetBtn.isEnabled = count > 0
        row.addSubview(resetBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: resetBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5),

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
        guard panel.runModalAboveFloatingWindows() == .OK, let url = panel.url else { return }
        if ConfigManager.shared.addCustomExcludedPath(url.path) {
            reloadCustomExclusionRows()
        } else {
            let alert = NSAlert()
            alert.messageText = "无法排除该目录"
            alert.informativeText = "该目录不存在、已被包含在已有排除项中、或是系统根/用户家目录，或已达到最大排除数量（\(ConfigManager.maxCustomExcludedPaths) 个）。"
            alert.alertStyle = .warning
            alert.runModalAboveFloatingWindows()
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

    @objc private func limitChanged(_ sender: SettingsLiquidSegmentedControl) {
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

    private func handleSearchRecorded(_ newBinding: HotkeyBinding) {
        let currentShelf = ConfigManager.shared.config.shelfHotkey
        if newBinding == currentShelf {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            alert.informativeText = "该快捷键已被「应用分类工作台」占用。请录入其他组合键，或前往应用抽屉设置调整。"
            alert.runModalAboveFloatingWindows()
            searchRecorder?.currentBinding = ConfigManager.shared.config.searchHotkey
            return
        }
        ConfigManager.shared.updateSearchHotkey(newBinding)
        HotkeyManager.shared.register(id: .search, binding: newBinding)
    }

    private func handleSearchCleared() {
        let unassigned = HotkeyBinding(keyCode: 0, carbonModifiers: 0, displayString: "", specialTrigger: .none)
        ConfigManager.shared.updateSearchHotkey(unassigned)
        HotkeyManager.shared.unregister(id: .search)
    }

    @objc private func setCommandSpaceHotkey() {
        let display = HotkeyDisplayFormatter.displayString(keyCode: 49, carbonModifiers: 256)
        let cmdSpace = HotkeyBinding(keyCode: 49, carbonModifiers: 256, displayString: display, specialTrigger: .none)
        handleSearchRecorded(cmdSpace)
        searchRecorder?.currentBinding = cmdSpace
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

    private func makeDualTileRow(left: NSView, right: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(left)
        row.addSubview(right)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 38),

            left.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            left.topAnchor.constraint(equalTo: row.topAnchor),
            left.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            right.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            right.topAnchor.constraint(equalTo: row.topAnchor),
            right.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            left.widthAnchor.constraint(equalTo: right.widthAnchor)
        ])
        return row
    }
}



// MARK: - 5. Theme Tab View
public final class ThemeTabView: NSView {
    private var themeCards: [ThemeCardView] = []
    private var opacitySlider: NSSlider!
    private var opacityBadge: NSTextField!
    private var resetOpacityButton: SettingsResetButton!

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

        opacityBadge = NSTextField(labelWithString: "90%")
        opacityBadge.translatesAutoresizingMaskIntoConstraints = false
        opacityBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        opacityBadge.textColor = .secondaryLabelColor
        opacityBadge.alignment = .left
        opacityContainer.addSubview(opacityBadge)

        resetOpacityButton = SettingsResetButton(title: "恢复默认", target: self, action: #selector(resetOpacityToDefault))
        opacityContainer.addSubview(resetOpacityButton)

        NSLayoutConstraint.activate([
            opacityContainer.widthAnchor.constraint(equalToConstant: 240),
            opacityContainer.heightAnchor.constraint(equalToConstant: 24),

            opacitySlider.leadingAnchor.constraint(equalTo: opacityContainer.leadingAnchor),
            opacitySlider.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            opacitySlider.widthAnchor.constraint(equalToConstant: 120),

            opacityBadge.leadingAnchor.constraint(equalTo: opacitySlider.trailingAnchor, constant: 6),
            opacityBadge.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            opacityBadge.widthAnchor.constraint(equalToConstant: 38),

            resetOpacityButton.leadingAnchor.constraint(equalTo: opacityBadge.trailingAnchor, constant: 8),
            resetOpacityButton.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            resetOpacityButton.trailingAnchor.constraint(equalTo: opacityContainer.trailingAnchor),
            resetOpacityButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        let rowOpacity = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "slider.horizontal.below.rectangle"),
            title: "面板背景透明度",
            subtitle: "40% 轻透玻璃，数值越高遮光越强 (默认 90%)",
            accessory: opacityContainer
        )
        card2.addRow(rowOpacity, isLast: true)

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
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -16)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        for card in themeCards {
            card.isSelected = (card.theme == cfg.theme)
        }
        opacitySlider.doubleValue = cfg.themeOpacity * 100.0
        let pct = Int(round(cfg.themeOpacity * 100.0))
        opacityBadge.stringValue = "\(pct)%"
        resetOpacityButton.isEnabled = (pct != 90)
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
        opacityBadge.stringValue = "\(pct)%"
        resetOpacityButton.isEnabled = (pct != 90)
        guard abs(opacity - ConfigManager.shared.config.themeOpacity) > 0.001 else { return }
        ConfigManager.shared.updateThemeOpacity(opacity)
        // Theme change notification is now posted by ConfigManager
    }

    @objc private func resetOpacityToDefault() {
        opacitySlider.doubleValue = 90.0
        opacitySliderChanged(opacitySlider)
    }
}

// MARK: - 6. Performance Tab View
public final class PerformanceTabView: NSView {
    private var memLabel = NSTextField(labelWithString: "正在测量...")
    private var purgeStatusLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var annealControl: SettingsLiquidSegmentedControl!
    private var debounceControl: SettingsLiquidSegmentedControl!
    private var cacheControl: SettingsLiquidSegmentedControl!

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

        annealControl = SettingsLiquidSegmentedControl(labels: ["1.5s (激进省电)", "3.0s (推荐平衡)", "10.0s (宽松缓存)"], target: self, action: #selector(annealChanged(_:)))
        let rowAnneal = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "timer"),
            title: "面板隐藏退火延迟",
            subtitle: "面板关闭后经过此延迟自动触发内存脏页回收",
            accessory: annealControl
        )
        card2.addRow(rowAnneal)

        debounceControl = SettingsLiquidSegmentedControl(labels: ["50ms (极速)", "150ms (均衡)", "300ms (节能)"], target: self, action: #selector(debounceChanged(_:)))
        let rowDebounce = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "waveform.path"),
            title: "全盘搜索防抖延迟",
            subtitle: "控制打字时的 Spotlight 检索流式触发间隔",
            accessory: debounceControl
        )
        card2.addRow(rowDebounce)

        cacheControl = SettingsLiquidSegmentedControl(labels: ["4 MB", "6 MB (默认)", "12 MB"], target: self, action: #selector(cacheLimitChanged(_:)))
        let rowCache = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "photo.stack"),
            title: "缩略图缓存池上限",
            subtitle: "限制 QuickLook 文件与 App 图标的最大驻留容量",
            accessory: cacheControl
        )
        card2.addRow(rowCache, isLast: true)

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
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -16)
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

    @objc private func annealChanged(_ sender: SettingsLiquidSegmentedControl) {
        let delays = [1.5, 3.0, 10.0]
        let sel = delays[max(0, min(delays.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateMemoryAnnealDelay(sel)
    }

    @objc private func debounceChanged(_ sender: SettingsLiquidSegmentedControl) {
        let ms = [50, 150, 300]
        let sel = ms[max(0, min(ms.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateSearchDebounceMs(sel)
    }

    @objc private func cacheLimitChanged(_ sender: SettingsLiquidSegmentedControl) {
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
            title: "ATools for macOS (v\(currentVer))",
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
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -16)
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
