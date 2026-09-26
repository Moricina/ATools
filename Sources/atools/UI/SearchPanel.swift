import Foundation
import AppKit

public final class SearchViewController: NSViewController, SearchBarDelegate, SearchResultsTableDelegate {
    public let searchBar = SearchBarView()
    public let resultsTable = SearchResultsTableView()
    private let hintsBar = NSTextField(labelWithString: "")

    private var collapsedConstraints: [NSLayoutConstraint] = []
    private var expandedConstraints: [NSLayoutConstraint] = []
    public private(set) var isExpanded: Bool = false

    override public func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 72))
        setupLayout()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        searchBar.delegate = self
        searchBar.textField.customDelegate = self
        resultsTable.delegate = self
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

        // Fixed base constraints: Search Bar pinned at the top
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchBar.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Collapsed state: view.bottom anchored directly to searchBar
        collapsedConstraints = [
            searchBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ]

        // Expanded state: resultsTable + hintsBar constraints
        expandedConstraints = [
            resultsTable.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            resultsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            resultsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            resultsTable.bottomAnchor.constraint(equalTo: hintsBar.topAnchor, constant: -4),

            hintsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hintsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hintsBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            hintsBar.heightAnchor.constraint(equalToConstant: 16)
        ]

        // Default to collapsed state
        NSLayoutConstraint.activate(collapsedConstraints)
        resultsTable.isHidden = true
        hintsBar.isHidden = true
    }

    public func prepareForDisplay() {
        searchBar.text = ""
        resultsTable.updateResults([])
        updatePanelHeight(hasResults: false, resultCount: 0, animated: false)
        searchBar.focus()
    }

    public func updatePanelHeight(hasResults: Bool, resultCount: Int, animated: Bool = true) {
        let targetHeight: CGFloat = !hasResults ? 72 : min(520, 72 + CGFloat(resultCount) * 52 + 36)
        let expanding = targetHeight > 72

        if expanding != isExpanded {
            isExpanded = expanding
            if expanding {
                NSLayoutConstraint.deactivate(collapsedConstraints)
                NSLayoutConstraint.activate(expandedConstraints)
                resultsTable.isHidden = false
                hintsBar.isHidden = false
            } else {
                NSLayoutConstraint.deactivate(expandedConstraints)
                NSLayoutConstraint.activate(collapsedConstraints)
                resultsTable.isHidden = true
                hintsBar.isHidden = true
            }
        }

        guard let window = view.window else { return }
        let currentFrame = window.frame
        let targetY = currentFrame.maxY - targetHeight
        let targetFrame = NSRect(x: currentFrame.origin.x, y: targetY, width: currentFrame.width, height: targetHeight)

        if animated && window.isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }, completionHandler: {
                window.invalidateShadow()
            })
        } else {
            window.setFrame(targetFrame, display: true)
            window.invalidateShadow()
        }
    }

    // MARK: - SearchBarDelegate
    public func searchBar(_ searchBar: SearchBarView, didChangeQuery query: String) {
        runtimeLog("[SearchVC] didChangeQuery: '\(query)'")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SearchCoordinator.shared.search(query: "") { [weak self] _ in
                self?.resultsTable.updateResults([])
                self?.updatePanelHeight(hasResults: false, resultCount: 0, animated: true)
            }
            return
        }

        SearchCoordinator.shared.search(query: query) { [weak self] results in
            runtimeLog("[SearchVC] received results count: \(results.count) for query: '\(query)'")
            self?.resultsTable.updateResults(results)
            self?.updatePanelHeight(hasResults: !results.isEmpty, resultCount: results.count, animated: true)
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
            updatePanelHeight(hasResults: false, resultCount: 0, animated: true)
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
        updatePanelHeight(hasResults: false, resultCount: 0, animated: false)
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
        self.level = .floating
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
