import Foundation
import AppKit

public extension Notification.Name {
    static let atoolsCategoryOrientationDidChange = Notification.Name("atoolsCategoryOrientationDidChange")
    static let atoolsShelfIconSizeDidChange = Notification.Name("atoolsShelfIconSizeDidChange")
    static let atoolsFavoritesToggleDidChange = Notification.Name("atoolsFavoritesToggleDidChange")
    static let atoolsPanelTogglesDidChange = Notification.Name("atoolsPanelTogglesDidChange")
    static let atoolsThemeDidChange = Notification.Name("atoolsThemeDidChange")
    static let atoolsAutoQuitDidChange = Notification.Name("atoolsAutoQuitDidChange")
    static let atoolsDidSelectSyntaxCommand = Notification.Name("atoolsDidSelectSyntaxCommand")
    static let atoolsAutoPasteOnSummonDidChange = Notification.Name("atoolsAutoPasteOnSummonDidChange")
    static let atoolsShelfDataDidChange = Notification.Name("atoolsShelfDataDidChange")
}

public extension NSAlert {
    /// The settings window and panels float at `.statusBar` or above. A plain `runModal()`
    /// alert opens at modal-panel level *behind* them, leaving an invisible modal loop that
    /// makes the app look frozen. Raise the alert above every ATools window first.
    ///
    /// NOTE: AppKit forcefully resets `window.level` to `.modalPanel` (8) internally upon entering `runModal()`.
    /// We dynamically enforce `targetLevel` both synchronously via `NSWindow.didUpdateNotification`
    /// and asynchronously via `NSModalPanelRunLoopMode` so the alert always floats above floating panels.
    @discardableResult
    func runModalAboveFloatingWindows(targetLevel: NSWindow.Level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)) -> NSApplication.ModalResponse {
        PanelCoordinator.shared.isModalDialogOpen = true
        defer {
            PanelCoordinator.shared.isModalDialogOpen = false
        }

        let target = targetLevel
        let alertWin = self.window
        alertWin.level = target

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: alertWin,
            queue: nil
        ) { [weak alertWin] _ in
            guard let alertWin = alertWin else { return }
            if alertWin.level.rawValue < target.rawValue {
                alertWin.level = target
                alertWin.orderFrontRegardless()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let timer = Timer(timeInterval: 0.001, repeats: false) { [weak alertWin] _ in
            guard let alertWin = alertWin else { return }
            alertWin.level = target
            alertWin.orderFrontRegardless()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: RunLoop.Mode(rawValue: "NSModalPanelRunLoopMode"))

        NSApp.activate(ignoringOtherApps: true)
        alertWin.makeKeyAndOrderFront(nil)
        alertWin.orderFrontRegardless()

        return runModal()
    }
}

public extension NSWindow {
    /// Runs a modal session while ensuring the window's level is maintained at or above `targetLevel`
    /// (preventing AppKit from demoting it to `.modalPanel` (8) during `runModal()`).
    /// Automatically handles both standard NSWindows and NSSavePanel / NSOpenPanel instances.
    @discardableResult
    func runModalAboveFloatingWindows(targetLevel: NSWindow.Level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)) -> NSApplication.ModalResponse {
        PanelCoordinator.shared.isModalDialogOpen = true
        defer {
            PanelCoordinator.shared.isModalDialogOpen = false
        }

        let target = targetLevel
        self.level = target

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: self,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.level.rawValue < target.rawValue {
                self.level = target
                self.orderFrontRegardless()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let timer = Timer(timeInterval: 0.001, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.level = target
            self.orderFrontRegardless()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: RunLoop.Mode(rawValue: "NSModalPanelRunLoopMode"))

        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()

        if let savePanel = self as? NSSavePanel {
            return savePanel.runModal()
        } else {
            return NSApp.runModal(for: self)
        }
    }
}

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    private static var sharedInstanceCreated = false

    /// Visibility check that doesn't instantiate the settings window as a side effect.
    public static var isWindowVisible: Bool {
        return visibleWindowFrame != nil
    }

    public static var visibleWindowFrame: NSRect? {
        guard sharedInstanceCreated, let win = shared.window, win.isVisible else { return nil }
        return win.frame
    }

    public static var isSettingsWindowKey: Bool {
        guard sharedInstanceCreated, let win = shared.window else { return false }
        return NSApp.keyWindow === win
    }

    private var sidebarView: SettingsSidebarView!
    private var contentContainer: NSView!

    // Tiered Lazy Loaded Tab Views
    private var generalView: GeneralTabView?
    private var shelfView: ShelfTabView?
    private var searchView: SearchTabView?
    private var autoQuitView: AutoQuitTabView?
    private var themeView: ThemeTabView?
    private var performanceView: PerformanceTabView?
    private var aboutView: AboutTabView?

    private var currentActiveView: NSView?

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "ATools 偏好设置"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor.windowBackgroundColor
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 780, height: 560)
        win.maxSize = NSSize(width: 780, height: 860)
        win.level = .normal
        super.init(window: win)
        SettingsWindowController.sharedInstanceCreated = true
        win.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showSettingsWindow() {
        // Diagnostic: every open path funnels here; log the exact caller chain when
        // debug logging is enabled (defaults write cc.atools.app atools.debugLog -bool YES).
        runtimeLog("[Settings] showSettingsWindow called from:\n" + Thread.callStackSymbols.prefix(16).joined(separator: "\n"))
        PanelCoordinator.shared.hideAllPanels(restoreFocus: false)
        guard let win = window else { return }
        win.setContentSize(NSSize(width: 780, height: 600))
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        switchToTab(sidebarView.selectedItem)

        // 延迟 1.2 秒发起静默更新检测，避开首屏渲染与窗口毛玻璃合成峰值（内部具备 4 小时间隔节流）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            UpdateManager.shared.checkForUpdates(isUserInitiated: false)
        }
    }

    public func selectTab(_ item: SettingsSidebarItem) {
        sidebarView.selectItem(item)
    }

    override public func cancelOperation(_ sender: Any?) {
        window?.performClose(sender)
    }

    public func windowWillClose(_ notification: Notification) {
        shelfView?.shelfRecorder?.stopRecording()
        searchView?.searchRecorder?.stopRecording()
        performanceView?.stopMonitor()

        // AutoQuit 名单编辑 sheet 挂在本窗口；先把 sheet 收起，避免其数据源
        // 随下方 autoQuitView 一起释放后出现悬垂回调。
        if let sheet = window?.attachedSheet {
            window?.endSheet(sheet)
        }

        currentActiveView?.removeFromSuperview()
        currentActiveView = nil
        generalView = nil
        shelfView = nil
        searchView = nil
        autoQuitView = nil
        themeView = nil
        performanceView = nil
        aboutView = nil

        // Dismissal Annealing: purge memory and notify guardian
        MemoryGuardian.shared.onPanelsDidHide()
    }

    private func setupUI() {
        guard let win = window, let windowContentView = win.contentView else { return }

        // Root Split View Layout
        sidebarView = SettingsSidebarView()
        windowContentView.addSubview(sidebarView)

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        windowContentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: windowContentView.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: windowContentView.bottomAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: windowContentView.leadingAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: 200),

            contentContainer.topAnchor.constraint(equalTo: windowContentView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: windowContentView.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: windowContentView.trailingAnchor),
            contentContainer.widthAnchor.constraint(equalToConstant: 580)
        ])

        sidebarView.onItemSelected = { [weak self] item in
            self?.switchToTab(item)
        }

        // Initialize default tab (General)
        switchToTab(.general)
    }

    private func switchToTab(_ item: SettingsSidebarItem) {
        shelfView?.shelfRecorder?.stopRecording()
        searchView?.searchRecorder?.stopRecording()
        if let sheet = window?.attachedSheet {
            window?.endSheet(sheet)
        }

        if let current = currentActiveView {
            if current === performanceView {
                performanceView?.stopMonitor()
            }
            current.removeFromSuperview()
            currentActiveView = nil
            // 及时卸载上一个非活跃标签视图，释放其关联的 NSHostingView、CALayer 树与重型控件内存
            generalView = nil
            shelfView = nil
            searchView = nil
            autoQuitView = nil
            themeView = nil
            performanceView = nil
            aboutView = nil
        }

        let targetView: NSView
        switch item {
        case .general:
            if generalView == nil { generalView = GeneralTabView() }
            generalView?.refresh()
            targetView = generalView!
        case .shelf:
            if shelfView == nil { shelfView = ShelfTabView() }
            shelfView?.refresh()
            targetView = shelfView!
        case .search:
            if searchView == nil { searchView = SearchTabView() }
            searchView?.refresh()
            targetView = searchView!
        case .autoQuit:
            if autoQuitView == nil { autoQuitView = AutoQuitTabView() }
            autoQuitView?.refresh()
            targetView = autoQuitView!
        case .theme:
            if themeView == nil { themeView = ThemeTabView() }
            themeView?.refresh()
            targetView = themeView!
        case .performance:
            if performanceView == nil { performanceView = PerformanceTabView() }
            performanceView?.refresh()
            performanceView?.startMonitor()
            targetView = performanceView!
        case .about:
            if aboutView == nil { aboutView = AboutTabView() }
            targetView = aboutView!
        }

        targetView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(targetView)

        NSLayoutConstraint.activate([
            targetView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            targetView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            targetView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            targetView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
        ])

        currentActiveView = targetView
    }
}
