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
            subtitle: "登录系统后自动启动 ATools",
            accessory: launchOnLoginSwitch
        )
        card1.addRow(rowLaunch)

        autoCloseDeactivateSwitch = NSSwitch()
        autoCloseDeactivateSwitch.target = self
        autoCloseDeactivateSwitch.action = #selector(toggleAutoCloseDeactivate(_:))
        let rowCloseDeactivate = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "macwindow.badge.plus"),
            title: "失焦时自动关闭",
            subtitle: "点击面板外部或切换应用时自动关闭面板",
            accessory: autoCloseDeactivateSwitch,
            minHeight: 46
        )
        card1.addRow(rowCloseDeactivate, isLast: true)

        // 2. 备份与恢复数据 (P0-3 & P0-2)
        let secBackupTitle = makeSectionHeader(title: "配置备份与恢复")
        scrollContent.addSubview(secBackupTitle)

        let backupCard = SettingsCardView()
        backupCard.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(backupCard)

        let exportBtn = SettingsPillButton(title: "导出备份...", target: self, action: #selector(exportBackupClicked))
        backupExportRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "externaldrive.badge.plus"),
            title: "导出备份",
            subtitle: "将应用分类、启动项及自定义图标打包导出",
            accessory: exportBtn
        )
        backupCard.addRow(backupExportRow)

        let restoreContainer = NSView()
        restoreContainer.translatesAutoresizingMaskIntoConstraints = false

        rollbackSnapshotBtn = SettingsPillButton(title: "回滚快照", target: self, action: #selector(rollbackSnapshotClicked))
        rollbackSnapshotBtn.translatesAutoresizingMaskIntoConstraints = false

        let importBtn = SettingsPillButton(title: "导入恢复...", target: self, action: #selector(importBackupClicked))
        importBtn.translatesAutoresizingMaskIntoConstraints = false

        restoreContainer.addSubview(rollbackSnapshotBtn)
        restoreContainer.addSubview(importBtn)

        NSLayoutConstraint.activate([
            importBtn.trailingAnchor.constraint(equalTo: restoreContainer.trailingAnchor),
            importBtn.centerYAnchor.constraint(equalTo: restoreContainer.centerYAnchor),
            importBtn.topAnchor.constraint(greaterThanOrEqualTo: restoreContainer.topAnchor),
            importBtn.bottomAnchor.constraint(lessThanOrEqualTo: restoreContainer.bottomAnchor),

            rollbackSnapshotBtn.trailingAnchor.constraint(equalTo: importBtn.leadingAnchor, constant: -8),
            rollbackSnapshotBtn.leadingAnchor.constraint(equalTo: restoreContainer.leadingAnchor),
            rollbackSnapshotBtn.centerYAnchor.constraint(equalTo: restoreContainer.centerYAnchor),
            rollbackSnapshotBtn.topAnchor.constraint(greaterThanOrEqualTo: restoreContainer.topAnchor),
            rollbackSnapshotBtn.bottomAnchor.constraint(lessThanOrEqualTo: restoreContainer.bottomAnchor)
        ])

        let rowRestore = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.counterclockwise.icloud"),
            title: "恢复备份与快照",
            subtitle: "从备份文件恢复配置，或回滚至最近的自动备份快照",
            accessory: restoreContainer
        )
        backupCard.addRow(rowRestore)

        cleanMissingBtn = SettingsPillButton(title: "清理失效项", target: self, action: #selector(cleanMissingItemsClicked))
        missingItemsRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "wand.and.stars"),
            title: "清理失效项目",
            subtitle: "移除已被删除或移动的启动项",
            accessory: cleanMissingBtn
        )
        backupCard.addRow(missingItemsRow, isLast: true)

        // 3. 系统权限
        let sec2Title = makeSectionHeader(title: "系统权限")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let axBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openAccessibilitySettings))
        let rowAx = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hand.raised"),
            title: "辅助功能权限",
            subtitle: "用于全局快捷键与窗口状态识别",
            accessory: axBtn
        )
        card2.addRow(rowAx)

        let fdaBtn = SettingsPillButton(title: "前往授权...", target: self, action: #selector(openFullDiskAccessSettings))
        let rowFDA = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "lock.shield"),
            title: "完全磁盘访问权限",
            subtitle: "用于搜索“下载”、“文稿”等受保护的系统目录",
            accessory: fdaBtn
        )
        card2.addRow(rowFDA, isLast: true)

        let permTip = NSTextField(labelWithString: "提示：所有数据均在本地存储与处理，无需联网即可使用。")
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
        backupExportRow.subtitleLabel.stringValue = "导出当前 \(totalCats) 个分类、\(totalItems) 个项目及图标备份"

        let snapshots = BackupService.shared.listPreRestoreSnapshots()
        rollbackSnapshotBtn.isEnabled = !snapshots.isEmpty
        rollbackSnapshotBtn.toolTip = snapshots.first.map { "回滚至最近一次恢复前快照：\($0.lastPathComponent)" } ?? "尚无恢复前自动快照"

        let missingList = ConfigManager.shared.scanMissingItems()
        if missingList.isEmpty {
            missingItemsRow.subtitleLabel.stringValue = "所有启动项路径均有效"
            cleanMissingBtn.isEnabled = false
        } else {
            missingItemsRow.subtitleLabel.stringValue = "检测到 \(missingList.count) 个已被移动或删除的启动项"
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
            alert.messageText = "备份导出成功"
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
        let parentWin = self.window
        let missing = ConfigManager.shared.scanMissingItems()
        guard !missing.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无需清理"
            alert.informativeText = "当前所有分类中的启动项路径均有效，未发现失效项目。"
            alert.runModalAboveFloatingWindows(centeredIn: parentWin)
            return
        }

        let previewLines = missing.prefix(8).map { "• [\($0.category.name)] \($0.item.name) (\($0.item.target))" }.joined(separator: "\n")
        let moreHint = missing.count > 8 ? "\n…等共 \(missing.count) 个失效项目" : ""

        let alert = NSAlert()
        alert.messageText = "确认清理 \(missing.count) 个失效启动项？"
        alert.informativeText = "以下项目因已被移动或删除已失效，清理后将从对应分类中移除：\n\n\(previewLines)\(moreHint)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "立即清理")
        alert.addButton(withTitle: "取消")

        if alert.runModalAboveFloatingWindows(centeredIn: parentWin) == .alertFirstButtonReturn {
            let removedCount = ConfigManager.shared.removeAllMissingItems()
            refresh()
            let done = NSAlert()
            done.messageText = "清理完成"
            done.informativeText = "已成功清理 \(removedCount) 个失效启动项。"
            done.alertStyle = .informational
            done.runModalAboveFloatingWindows(centeredIn: parentWin)
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

