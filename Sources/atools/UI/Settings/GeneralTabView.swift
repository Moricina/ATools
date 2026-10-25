import Foundation
import AppKit

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
        let importBtn = SettingsPillButton(title: "导入恢复...", target: self, action: #selector(importBackupClicked))
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

