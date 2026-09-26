import Foundation
import AppKit

public final class FlippedView: NSView {
    override public var isFlipped: Bool { true }
}

public final class SearchViewController: NSViewController, SearchBarDelegate, SearchResultsTableDelegate {
    public static let collapsedHeight: CGFloat = 72
    public static let expandedHeight: CGFloat = 520

    public let searchBar = SearchBarView()
    public let resultsTable = SearchResultsTableView()
    private let hintsBar = NSTextField(labelWithString: "")

    private var collapsedConstraints: [NSLayoutConstraint] = []
    private var expandedConstraints: [NSLayoutConstraint] = []
    public private(set) var isExpanded: Bool = false
    private var anchorTopY: CGFloat?

    override public func loadView() {
        let flippedView = FlippedView(frame: NSRect(x: 0, y: 0, width: 680, height: Self.collapsedHeight))
        flippedView.wantsLayer = true
        flippedView.layer?.masksToBounds = true
        self.view = flippedView
        setupLayout()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        searchBar.delegate = self
        searchBar.textField.customDelegate = self
        resultsTable.delegate = self
    }

    public func setInitialScreenAnchor(topY: CGFloat) {
        self.anchorTopY = topY
    }

    private func setupLayout() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        resultsTable.translatesAutoresizingMaskIntoConstraints = false
        hintsBar.translatesAutoresizingMaskIntoConstraints = false

        hintsBar.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hintsBar.textColor = .tertiaryLabelColor
        hintsBar.alignment = .right
        hintsBar.stringValue = "⌘C 复制路径   ⌘R 访达显示   ⏎ 打开   Esc 退出"

        view.addSubview(searchBar)
        view.addSubview(resultsTable)
        view.addSubview(hintsBar)

        // 基础固定布局：搜索框固定顶部 (高度 44，上边距 14，宽度两边各留 14)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchBar.heightAnchor.constraint(equalToConstant: 44)
        ])

        // 折叠态严格锁定：下边距固定为 14pt，确保折叠时上下边距严格对称（总高度精准 72pt）
        collapsedConstraints = [
            searchBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ]

        let hintsBottomConstraint = hintsBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        hintsBottomConstraint.priority = NSLayoutConstraint.Priority(999)

        // 展开态约束：仅在展开到 520pt 时激活
        expandedConstraints = [
            resultsTable.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            resultsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            resultsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            resultsTable.bottomAnchor.constraint(equalTo: hintsBar.topAnchor, constant: -4),

            hintsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hintsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hintsBottomConstraint,
            hintsBar.heightAnchor.constraint(equalToConstant: 16)
        ]

        NSLayoutConstraint.activate(collapsedConstraints)
        resultsTable.isHidden = true
        hintsBar.isHidden = true
    }

    public func prepareForDisplay() {
        searchBar.text = ""
        resultsTable.updateResults([])
        setPanelExpanded(false, animated: false)
        searchBar.focus()
    }

    /// 双稳态展开/折叠控制：输入删除至空时平滑淡出结果并收缩窗口，彻底杜绝残影与断续卡顿
    public func setPanelExpanded(_ expand: Bool, animated: Bool = true) {
        guard expand != isExpanded || !animated else { return }
        isExpanded = expand

        guard let window = view.window else {
            if expand {
                NSLayoutConstraint.deactivate(collapsedConstraints)
                NSLayoutConstraint.activate(expandedConstraints)
            } else {
                NSLayoutConstraint.deactivate(expandedConstraints)
                NSLayoutConstraint.activate(collapsedConstraints)
            }
            resultsTable.isHidden = !expand
            hintsBar.isHidden = !expand
            return
        }

        let targetHeight: CGFloat = expand ? Self.expandedHeight : Self.collapsedHeight
        let topY = anchorTopY ?? window.frame.maxY
        let targetY = topY - targetHeight
        let targetFrame = NSRect(x: window.frame.origin.x, y: targetY, width: window.frame.width, height: targetHeight)

        if animated && window.isVisible {
            if expand {
                NSLayoutConstraint.deactivate(collapsedConstraints)
                NSLayoutConstraint.activate(expandedConstraints)
                resultsTable.alphaValue = 1.0
                hintsBar.alphaValue = 1.0
                resultsTable.isHidden = false
                hintsBar.isHidden = false

                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.20
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                    ctx.allowsImplicitAnimation = false
                    window.animator().setFrame(targetFrame, display: true)
                }, completionHandler: {
                    window.invalidateShadow()
                })
            } else {
                // 收拢态优化：立即解除展开态列表约束，避免底部被 96pt 最小高度卡住
                NSLayoutConstraint.deactivate(expandedConstraints)

                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.10
                    resultsTable.animator().alphaValue = 0.0
                    hintsBar.animator().alphaValue = 0.0
                })

                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                    ctx.allowsImplicitAnimation = false
                    window.animator().setFrame(targetFrame, display: true)
                }, completionHandler: { [weak self] in
                    guard let self = self, !self.isExpanded else { return }
                    NSLayoutConstraint.activate(self.collapsedConstraints)
                    self.resultsTable.isHidden = true
                    self.hintsBar.isHidden = true
                    self.resultsTable.alphaValue = 1.0
                    self.hintsBar.alphaValue = 1.0
                    self.resultsTable.updateResults([])
                    window.setFrame(targetFrame, display: true)
                    window.invalidateShadow()
                })
            }
        } else {
            if expand {
                NSLayoutConstraint.deactivate(collapsedConstraints)
                NSLayoutConstraint.activate(expandedConstraints)
            } else {
                NSLayoutConstraint.deactivate(expandedConstraints)
                NSLayoutConstraint.activate(collapsedConstraints)
                resultsTable.updateResults([])
            }
            resultsTable.alphaValue = 1.0
            hintsBar.alphaValue = 1.0
            resultsTable.isHidden = !expand
            hintsBar.isHidden = !expand
            window.setFrame(targetFrame, display: true)
            window.invalidateShadow()
        }
    }

    public func updatePanelHeight(hasResults: Bool, resultCount: Int, animated: Bool = true) {
        setPanelExpanded(hasResults, animated: animated)
    }

    // MARK: - SearchBarDelegate
    public func searchBar(_ searchBar: SearchBarView, didChangeQuery query: String) {
        runtimeLog("[SearchVC] didChangeQuery: '\(query)'")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 文字删空立即执行主线程平滑折叠，无需等待后台异步队列回传
            SearchCoordinator.shared.search(query: "") { _ in }
            setPanelExpanded(false, animated: true)
            return
        }

        // 只要有文字输入，立即平滑展开到标准工作区 520pt（若已展开则无任何布局抖动）
        setPanelExpanded(true, animated: true)

        SearchCoordinator.shared.search(query: query) { [weak self] results in
            runtimeLog("[SearchVC] received results count: \(results.count) for query: '\(query)'")
            // 若在搜索计算期间用户已经删空，丢弃过期的结果，防止正在收拢时突发重绘
            guard let self = self, self.isExpanded else { return }
            self.resultsTable.updateResults(results)
        }
    }

    public func searchBarDidPressArrowDown(_ searchBar: SearchBarView) {
        resultsTable.selectNext()
    }

    public func searchBarDidPressArrowUp(_ searchBar: SearchBarView) {
        resultsTable.selectPrevious()
    }

    public func searchBarDidPressEnter(_ searchBar: SearchBarView, isCommandPressed: Bool) {
        resultsTable.executeSelected(isCommandPressed: isCommandPressed)
    }

    public func searchBarDidPressEscape(_ searchBar: SearchBarView) {
        if !searchBar.text.isEmpty {
            searchBar.text = ""
            resultsTable.updateResults([])
            setPanelExpanded(false, animated: true)
        } else {
            PanelCoordinator.shared.hideAllPanels()
        }
    }

    public func searchBarDidPressCopyPath(_ searchBar: SearchBarView) {
        if resultsTable.copySelectedPath() {
            dismissSearchPanel()
        }
    }

    public func searchBarDidPressRevealInFinder(_ searchBar: SearchBarView) {
        if resultsTable.revealSelectedInFinder() {
            dismissSearchPanel()
        }
    }

    private func dismissSearchPanel() {
        PanelCoordinator.shared.hideAllPanels()
        searchBar.text = ""
        resultsTable.updateResults([])
        setPanelExpanded(false, animated: false)
    }

    // MARK: - SearchResultsTableDelegate
    public func searchResultsTable(_ table: SearchResultsTableView, didSelectResult result: SearchResult, isCommandPressed: Bool) {
        dismissSearchPanel()

        if isCommandPressed, let path = result.path {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let action = result.action {
            action()
        } else if let path = result.path {
            LauncherExecutor.open(path: path)
        }
    }

    public func searchResultsTable(_ table: SearchResultsTableView, didCompleteDragResult result: SearchResult) {
        dismissSearchPanel()
    }

    public func searchResultsTableDidRequestDismiss(_ table: SearchResultsTableView) {
        dismissSearchPanel()
    }
}

public final class SearchPanel: NSPanel {
    public let searchViewController = SearchViewController()

    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 72)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.acceptsMouseMovedEvents = true

        let backdrop = VisualEffectBackdropView(frame: contentRect)
        backdrop.autoresizingMask = [.width, .height]
        self.contentView = backdrop

        searchViewController.view.frame = backdrop.bounds
        searchViewController.view.autoresizingMask = [.width, .height]
        backdrop.addSubview(searchViewController.view)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: .atoolsThemeDidChange,
            object: nil
        )
        updateWindowAppearanceForTheme()
    }

    @objc private func handleThemeChanged() {
        updateWindowAppearanceForTheme()
    }

    private func updateWindowAppearanceForTheme() {
        let theme = ConfigManager.shared.config.theme
        self.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    public func prepareForDisplay() {
        searchViewController.prepareForDisplay()
    }
}
