import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupHotkeys()

        // Warm up in-memory app index
        AppHotspotIndex.shared.refreshIndex()

        // Preflight user directories to register TCC permissions
        preflightUserDirectoriesAccess()

        // Check for first launch to guide user directly in preferences
        let hasLaunchedKey = "atools.hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SettingsWindowController.shared.showSettingsWindow()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            HotkeyManager.shared.reloadFlagsMonitorsIfTrusted()
        }

        let config = ConfigManager.shared.config
        print("[ATools] Successfully launched.")
        print("         Shelf Hotkey:  \(config.shelfHotkey.displayString)")
        print("         Search Hotkey: \(config.searchHotkey.displayString)")
        runtimeLog("[App] ATools launched. PID: \(getpid()), FullDiskSearch: \(config.enableFullDiskSearch)")

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("cc.atools.testSearch"),
            object: nil,
            queue: .main
        ) { notif in
            let query = (notif.object as? String) ?? "毕业"
            runtimeLog("[Distributed] Received testSearch for query: '\(query)'")
            SearchCoordinator.shared.search(query: query) { results in
                runtimeLog("[Distributed] Search completed for '\(query)', count: \(results.count)")
                for r in results {
                    runtimeLog("   -> [\(r.type)] \(r.title) (\(r.subtitle))")
                }
            }
        }
    }

    private var shelfMenuItem: NSMenuItem?
    private var searchMenuItem: NSMenuItem?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass", pointSize: 16, weight: .medium)
            button.toolTip = "ATools - 快速启动与全盘搜索"
        }

        let menu = NSMenu()
        let config = ConfigManager.shared.config

        let shelfTitle = config.shelfHotkey.displayString.isEmpty ? "唤出应用分类" : "唤出应用分类 (\(config.shelfHotkey.displayString))"
        let shelfItem = NSMenuItem(title: shelfTitle, action: #selector(toggleShelf), keyEquivalent: "")
        shelfItem.target = self
        menu.addItem(shelfItem)
        self.shelfMenuItem = shelfItem

        let searchTitle = config.searchHotkey.displayString.isEmpty ? "唤出全盘搜索" : "唤出全盘搜索 (\(config.searchHotkey.displayString))"
        let searchItem = NSMenuItem(title: searchTitle, action: #selector(toggleSearch), keyEquivalent: "")
        searchItem.target = self
        menu.addItem(searchItem)
        self.searchMenuItem = searchItem

        menu.addItem(NSMenuItem.separator())

        let settingsMenuItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        let guideItem = NSMenuItem(title: "替换聚焦指南...", action: #selector(showDisableSpotlightGuide), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)

        let conflictItem = NSMenuItem(title: "检测聚焦快捷键冲突...", action: #selector(checkSpotlightConflict), keyEquivalent: "")
        conflictItem.target = self
        menu.addItem(conflictItem)

        let fdaItem = NSMenuItem(title: "授权完全磁盘访问...", action: #selector(openFullDiskAccessSettings), keyEquivalent: "")
        fdaItem.target = self
        menu.addItem(fdaItem)

        let appMgmtItem = NSMenuItem(title: "检查 App 管理权限...", action: #selector(openAppManagementSettings), keyEquivalent: "")
        appMgmtItem.target = self
        menu.addItem(appMgmtItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "关于 ATools", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出 ATools", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelTogglesChanged),
            name: .atoolsPanelTogglesDidChange,
            object: nil
        )

        updateMenuPanelStates()
    }

    @objc private func handlePanelTogglesChanged() {
        updateMenuPanelStates()
    }

    private func updateMenuPanelStates() {
        let config = ConfigManager.shared.config
        shelfMenuItem?.isEnabled = config.enableShelfPanel
        shelfMenuItem?.title = config.shelfHotkey.displayString.isEmpty
            ? "唤出应用分类"
            : "唤出应用分类 (\(config.shelfHotkey.displayString))"

        searchMenuItem?.isEnabled = config.enableSearchPanel
        searchMenuItem?.title = config.searchHotkey.displayString.isEmpty
            ? "唤出全盘搜索"
            : "唤出全盘搜索 (\(config.searchHotkey.displayString))"
    }

    private func setupHotkeys() {
        HotkeyManager.shared.onHotKeyTriggered = { id in
            switch id {
            case .shelf:
                PanelCoordinator.shared.togglePanel(.shelf)
            case .search:
                PanelCoordinator.shared.togglePanel(.search)
            }
        }
        HotkeyManager.shared.registerDefaultHotkeys()
    }

    @objc private func toggleShelf() {
        PanelCoordinator.shared.togglePanel(.shelf)
    }

    @objc private func toggleSearch() {
        PanelCoordinator.shared.togglePanel(.search)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettingsWindow()
    }

    @objc private func showDisableSpotlightGuide() {
        let alert = NSAlert()
        alert.messageText = "macOS 替换系统聚焦指南"
        alert.informativeText = """
        若要将 ATools 彻底替代系统 Spotlight，请按以下 2 步操作：

        【步骤 1：禁用系统聚焦快捷键】
        1. 打开「系统设置」->「键盘」->「键盘快捷键...」；
        2. 点击左侧列表中的「聚焦 (Spotlight)」；
        3. 取消勾选「显示聚焦搜索 (Cmd + 空格)」与「显示访达搜索窗口」；
        4. 随后即可在 ATools 中无冲突使用该热键！

        【步骤 2：从右上角菜单栏移除聚焦图标】
        1. 打开「系统设置」->「控制中心」；
        2. 找到「聚焦 (Spotlight)」选项；
        3. 下拉菜单选择「不在菜单栏中显示」。

        【技术提醒】
        请勿在终端执行 `mdutil -a -i off` 强行杀死后台索引，ATools 正是通过复用系统已建立的高效 mds 索引实现 0% 能耗秒搜，仅关闭界面与按键即可达到完美替换。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往键盘快捷键设置")
        alert.addButton(withTitle: "前往控制中心设置")
        alert.addButton(withTitle: "完成")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            HotkeyManager.shared.openSystemKeyboardSettings()
        } else if response == .alertSecondButtonReturn {
            openControlCenterSettings()
        }
    }

    @objc private func checkSpotlightConflict() {
        let isEnabled = HotkeyManager.shared.isSpotlightShortcutEnabled()
        let alert = NSAlert()
        alert.alertStyle = .informational
        if isEnabled {
            alert.messageText = "检测到系统 Spotlight 快捷键处于启用状态"
            alert.informativeText = "macOS 当前已将 Cmd + Space 分配给系统聚焦。\n\n若希望使用 ATools 彻底替代 Spotlight，请在系统设置中取消勾选系统聚焦快捷键。"
            alert.addButton(withTitle: "查看完整关闭指南")
            alert.addButton(withTitle: "前往键盘设置")
            alert.addButton(withTitle: "暂不处理")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                showDisableSpotlightGuide()
            } else if resp == .alertSecondButtonReturn {
                HotkeyManager.shared.openSystemKeyboardSettings()
            }
        } else {
            alert.messageText = "未检测到 Spotlight 快捷键冲突"
            alert.informativeText = "系统聚焦快捷键已关闭或未占用当前按键，ATools 可顺畅接管全局呼出！"
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    @objc private func openControlCenterSettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc private func openFullDiskAccessSettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc private func openAppManagementSettings() {
        LauncherExecutor.openSystemPrivacySettings(service: "Privacy_AppBundles")
    }

    private func preflightUserDirectoriesAccess() {
        DispatchQueue.global(qos: .utility).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let folders = ["Downloads", "Documents", "Desktop"]
            for folder in folders {
                let url = home.appendingPathComponent(folder)
                _ = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        let config = ConfigManager.shared.config
        alert.messageText = "ATools for Mac"
        alert.informativeText = """
        极轻量分类启动台 & 毫秒级全盘搜索中心

        • 🗂️ 应用分类工作台: \(config.shelfHotkey.displayString)
        • 🔎 全局搜索中枢: \(config.searchHotkey.displayString)
        • 🍃 纯原生 Swift + AppKit，常驻闲置内存 ~20MB
        • 🛡️ 零权限 Carbon 全局快捷键与动态应用索引
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quitApp() {
        HotkeyManager.shared.unregisterAll()
        NSApp.terminate(nil)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }
}
