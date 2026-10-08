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
}

public extension NSAlert {
    /// The settings window and panels float at `.statusBar` or above. A plain `runModal()`
    /// alert opens at modal-panel level *behind* them, leaving an invisible modal loop that
    /// makes the app look frozen. Raise the alert above every ATools window first.
    @discardableResult
    func runModalAboveFloatingWindows() -> NSApplication.ModalResponse {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
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
    private var hotkeysView: HotkeysTabView?
    private var themeView: ThemeTabView?
    private var performanceView: PerformanceTabView?
    private var aboutView: AboutTabView?

    private var currentActiveView: NSView?

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ATools 偏好设置"
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 780, height: 600)
        win.maxSize = NSSize(width: 780, height: 800)
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
        win.setContentSize(NSSize(width: 780, height: 620))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        switchToTab(sidebarView.selectedItem)
    }

    public func selectTab(_ item: SettingsSidebarItem) {
        sidebarView.selectItem(item)
    }

    public func windowWillClose(_ notification: Notification) {
        hotkeysView?.shelfRecorder.stopRecording()
        hotkeysView?.searchRecorder.stopRecording()
        performanceView?.stopMonitor()

        // AutoQuit 名单编辑 sheet 挂在本窗口；先把 sheet 收起，避免其数据源
        // 随下方 generalView 一起释放后出现悬垂回调。
        if let sheet = window?.attachedSheet {
            window?.endSheet(sheet)
        }

        // Release every cached tab view. They are plain config-driven forms that
        // are rebuilt lazily by switchToTab on the next open; keeping all seven
        // alive forever pinned several MB of views, tracking areas and AutoLayout
        // objects for a window that is opened rarely.
        currentActiveView?.removeFromSuperview()
        currentActiveView = nil
        generalView = nil
        shelfView = nil
        searchView = nil
        hotkeysView = nil
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
        if let current = currentActiveView {
            if current === performanceView {
                performanceView?.stopMonitor()
            }
            current.removeFromSuperview()
            currentActiveView = nil
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
        case .hotkeys:
            if hotkeysView == nil { hotkeysView = HotkeysTabView() }
            hotkeysView?.refresh()
            targetView = hotkeysView!
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
