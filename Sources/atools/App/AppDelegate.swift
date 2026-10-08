import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMainMenu()
        setupStatusItem()
        setupHotkeys()
        TrackpadGestureManager.shared.startListeningIfEnabled()
        AutoQuitManager.shared.startIfEnabled()
        PasteboardRecencyTracker.shared.startMonitoringIfNeeded()

        // Warm up in-memory app index (its initializer performs the first scan)
        _ = AppHotspotIndex.shared

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
            AutoQuitManager.shared.reloadIfTrusted()
        }

        let config = ConfigManager.shared.config
        print("[ATools] Successfully launched.")
        print("         Shelf Hotkey:  \(config.shelfHotkey.displayString)")
        print("         Search Hotkey: \(config.searchHotkey.displayString)")
        runtimeLog("[App] ATools launched. PID: \(getpid()), FullDiskSearch: \(config.enableFullDiskSearch)")

        // Raw key trace for diagnosing accidental-shortcut reports (debug log only;
        // runtimeLog is a no-op unless atools.debugLog is enabled).
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            Self.traceRawEvent(event, source: "local")
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            Self.traceRawEvent(event, source: "global")
        }

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

    /// AppKit routes ⌘C/⌘V/⌘X/⌘A/⌘Z to text fields through main-menu key equivalents. An
    /// accessory app without a main menu therefore can't paste into the search bar, the
    /// category name dialog or the custom search URL field. The menu is never shown.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 ATools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private var shelfMenuItem: NSMenuItem?
    private var searchMenuItem: NSMenuItem?
    private var autoQuitMenuItem: NSMenuItem?

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

        let autoQuitItem = NSMenuItem(title: "关闭窗口即退出", action: #selector(toggleAutoQuitFromMenu), keyEquivalent: "")
        autoQuitItem.target = self
        menu.addItem(autoQuitItem)
        self.autoQuitMenuItem = autoQuitItem

        menu.addItem(NSMenuItem.separator())

        let settingsMenuItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAutoQuitConfigChanged),
            name: .atoolsAutoQuitDidChange,
            object: nil
        )

        updateMenuPanelStates()
        updateAutoQuitMenuItem()
    }

    @objc private func handlePanelTogglesChanged() {
        updateMenuPanelStates()
    }

    @objc private func handleAutoQuitConfigChanged() {
        updateAutoQuitMenuItem()
    }

    private func updateAutoQuitMenuItem() {
        autoQuitMenuItem?.state = ConfigManager.shared.config.enableAutoQuit ? .on : .off
    }

    /// 状态栏快捷开关。开启但未授权时同样走授权引导（与设置页一致）；
    /// AutoQuitManager 在授权前保持空闲，授权后应用被激活即热启动。
    @objc private func toggleAutoQuitFromMenu() {
        let enabling = !ConfigManager.shared.config.enableAutoQuit
        ConfigManager.shared.updateEnableAutoQuit(enabling)
        if enabling && !HotkeyManager.isAccessibilityTrusted() {
            let alert = NSAlert()
            alert.messageText = "「关闭窗口即退出」需要辅助功能授权"
            alert.informativeText = "监听其他应用窗口的关闭事件，需要 macOS「系统设置」->「隐私与安全性」->「辅助功能」中允许 ATools。\n\nATools 仅感知窗口数量变化，绝不读取任何窗口内容或键入信息。是否前往授权？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "前往系统设置")
            alert.addButton(withTitle: "稍后开启")
            if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
                HotkeyManager.openAccessibilitySettings()
            }
        }
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
            runtimeLog("[Hotkey] onHotKeyTriggered(\(id))")
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

    private static func traceRawEvent(_ event: NSEvent, source: String) {
        guard runtimeLogEnabled else { return }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let chars = event.characters ?? ""
        runtimeLog("[RawKey] \(source) \(event.type.rawValue) code=\(event.keyCode) chars=\(chars.debugDescription) mods=\(mods.rawValue)")
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
        alert.runModalAboveFloatingWindows()
    }

    @objc private func quitApp() {
        HotkeyManager.shared.unregisterAll()
        NSApp.terminate(nil)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        AutoQuitManager.shared.stop()
        ConfigManager.shared.flushPendingSave()
        HotkeyManager.shared.unregisterAll()
    }
}
