import Foundation
import AppKit

/// 「关窗即退」应用名单编辑 sheet 内容视图。
///
/// 独立小视图：只读写 ConfigManager，不持有 GeneralTabView，设置窗关闭时即使
/// sheet 被先行收起也不会悬垂。勾选语义随「作用范围」变化：allApps 模式下名单为
/// 排除项，onlyListed 模式下为退出项。应用来源为 AppHotspotIndex 全量快照。
///
/// 性能契约：init 只构建空 UI，数据装填（loadDataIfNeeded）必须等视图挂到窗口后
/// 再执行。若在无窗口尺寸时同步设置 dataSource，NSTableView 会把全部应用行一次性
/// 建完（每行 2-7ms × 数百行 ≈ 数百毫秒主线程冻结，双击叠加 sheet 排队后更长，
/// 表现为设置窗"卡死"），见 CHANGELOG 十-修复记录。
public final class AutoQuitRulesEditorView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var apps: [IndexedApp] = []
    private var filtered: [IndexedApp] = []
    private var selectedBundleIDs: Set<String>
    private var isDataLoaded = false
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")

    public override var intrinsicContentSize: NSSize {
        return NSSize(width: 470, height: 430)
    }

    public override init(frame frameRect: NSRect) {
        self.selectedBundleIDs = Set(ConfigManager.shared.config.autoQuitAppRules)
        super.init(frame: frameRect)

        switch ConfigManager.shared.config.autoQuitMode {
        case .allApps:
            hintLabel.stringValue = "勾选的应用将不会被自动退出（排除名单）。"
        case .onlyListed:
            hintLabel.stringValue = "仅勾选的应用会被自动退出（退出名单）。"
        }
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索应用名称或 bundle ID"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.setAccessibilityLabel("名单搜索框")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AutoQuitAppColumn"))
        column.width = 430
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 34
        tableView.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }
        tableView.setAccessibilityLabel("应用名单列表")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        let cancelButton = SettingsPillButton(title: "取消", target: self, action: #selector(cancelAndClose))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\u{1b}" // Esc

        let saveButton = SettingsPillButton(title: "保存名单", style: .primary, target: self, action: #selector(saveAndClose))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.keyEquivalent = "\r" // Return

        addSubview(hintLabel)
        addSubview(searchField)
        addSubview(scrollView)
        addSubview(countLabel)
        addSubview(cancelButton)
        addSubview(saveButton)

        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            searchField.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            scrollView.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -10),

            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            countLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            countLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            saveButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
        updateCountLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func cancelOperation(_ sender: Any?) {
        cancelAndClose()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 下一个 runloop 周期装填数据：此时 sheet 已在屏幕上、表格已有最终尺寸，
        // NSTableView 只构建可见的十几行（约 30-60ms），打开瞬间不冻结。
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.loadDataIfNeeded()
            }
        }
    }

    private func loadDataIfNeeded() {
        guard !isDataLoaded else { return }
        isDataLoaded = true
        AppHotspotIndex.shared.refreshIfStale()
        apps = AppHotspotIndex.shared.allApps
        if apps.isEmpty {
            // 冷启动边缘：应用刚启动、索引首扫尚未完成。扫描结束后自动重载一次。
            AppHotspotIndex.shared.refreshIndex { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.window != nil, self.apps.isEmpty else { return }
                    self.apps = AppHotspotIndex.shared.allApps
                    self.rebuildFiltered()
                    self.tableView.reloadData()
                    runtimeLog("[AutoQuit] rules data reloaded after index scan: \(self.filtered.count) apps")
                }
            }
        }
        rebuildFiltered()
        tableView.reloadData()
        updateCountLabel()
        runtimeLog("[AutoQuit] rules data loaded: \(filtered.count) apps")
    }

    private func rebuildFiltered() {
        let query = searchField.stringValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var list = apps
        if !query.isEmpty {
            list = apps.filter { app in
                app.lowercasedAliases.contains(where: { $0.contains(query) })
                    || (app.bundleId ?? "").lowercased().contains(query)
            }
        }
        filtered = list.sorted {
            $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
        }
    }

    private func updateCountLabel() {
        countLabel.stringValue = "已选 \(selectedBundleIDs.count) 个应用"
    }

    @objc private func searchChanged() {
        guard isDataLoaded else { return }
        rebuildFiltered()
        tableView.reloadData()
    }

    @objc private func toggleRow(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, filtered.indices.contains(row), let bid = filtered[row].bundleId, !bid.isEmpty else { return }
        if sender.state == .on {
            selectedBundleIDs.insert(bid)
        } else {
            selectedBundleIDs.remove(bid)
        }
        updateCountLabel()
    }

    @objc private func saveAndClose() {
        ConfigManager.shared.updateAutoQuitRules(Array(selectedBundleIDs).sorted())
        closeSheet()
    }

    @objc private func cancelAndClose() {
        closeSheet()
    }

    private func closeSheet() {
        guard let sheet = window else { return }
        if let parent = sheet.sheetParent {
            parent.endSheet(sheet)
        } else {
            sheet.orderOut(nil)
            sheet.close()
        }
    }

    // MARK: - NSTableView

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return filtered.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let app = filtered[row]
        let isSelected = app.bundleId != nil && selectedBundleIDs.contains(app.bundleId!)

        let cell: AutoQuitAppTableCellView
        if let reused = tableView.makeView(withIdentifier: AutoQuitAppTableCellView.reuseIdentifier, owner: self) as? AutoQuitAppTableCellView {
            cell = reused
        } else {
            cell = AutoQuitAppTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 34))
            cell.identifier = AutoQuitAppTableCellView.reuseIdentifier
        }
        cell.configure(with: app, isSelected: isSelected, target: self, action: #selector(toggleRow(_:)))
        return cell
    }
}

// MARK: - Reusable Table Cell

public final class AutoQuitAppTableCellView: NSTableCellView {
    public static let reuseIdentifier = NSUserInterfaceItemIdentifier("AutoQuitAppTableCell")

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let iconImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let bidLabel = NSTextField(labelWithString: "")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        bidLabel.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = NSFont.systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail

        bidLabel.font = NSFont.systemFont(ofSize: 10)
        bidLabel.textColor = .secondaryLabelColor
        bidLabel.lineBreakMode = .byTruncatingMiddle
        bidLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bidLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [iconImageView, nameLabel, bidLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY

        addSubview(checkbox)
        addSubview(stack)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),

            stack.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    public func configure(with app: IndexedApp, isSelected: Bool, target: AnyObject?, action: Selector) {
        checkbox.target = target
        checkbox.action = action
        checkbox.state = (app.bundleId != nil && isSelected) ? .on : .off
        checkbox.isEnabled = app.bundleId != nil
        checkbox.toolTip = (app.bundleId == nil) ? "该应用没有 bundle ID，无法纳入名单" : nil
        checkbox.setAccessibilityLabel("选择 \(app.localizedName)")

        iconImageView.image = NSWorkspace.shared.icon(forFile: app.path)
        nameLabel.stringValue = app.localizedName
        bidLabel.stringValue = app.bundleId ?? "(无 bundleID)"
    }
}
