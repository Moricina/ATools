import Foundation
import AppKit

/// 关窗退出决策审查与诊断面板
public final class AutoQuitInspectorSheet: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var segmentedControl: NSSegmentedControl!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var copyReportButton: SettingsPillButton!
    private var closeButton: SettingsPillButton!
    private var emptyLabel: NSTextField!

    private var currentModeIndex: Int = 0 // 0: 决策流水线, 1: 当前监视应用

    private var decisionRecords: [AutoQuitDecisionRecord] = []
    private var monitoredAppsSnapshot: [(name: String, bundleID: String, pid: pid_t, axCount: String, wsCount: String, rule: String)] = []

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        reloadContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        wantsLayer = true

        let headerLabel = NSTextField(labelWithString: "关窗退出运行记录与诊断")
        headerLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        segmentedControl = NSSegmentedControl(labels: ["退出历史记录", "当前监视应用"], trackingMode: .selectOne, target: self, action: #selector(segmentChanged(_:)))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentedControl)

        copyReportButton = SettingsPillButton(title: "复制诊断报告", target: self, action: #selector(copyReport))
        copyReportButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copyReportButton)

        tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        addSubview(scrollView)

        emptyLabel = NSTextField(labelWithString: "暂无记录")
        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        closeButton = SettingsPillButton(title: "关闭", target: self, action: #selector(closeSheet))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            copyReportButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            copyReportButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            segmentedControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 14),
            segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -14),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 80)
        ])

        setupColumns()
    }

    private func setupColumns() {
        while !tableView.tableColumns.isEmpty {
            tableView.removeTableColumn(tableView.tableColumns[0])
        }

        if currentModeIndex == 0 {
            // 决策流水线表格列
            let colTime = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
            colTime.title = "时间"
            colTime.width = 110
            tableView.addTableColumn(colTime)

            let colApp = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
            colApp.title = "应用"
            colApp.width = 100
            tableView.addTableColumn(colApp)

            let colDecision = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("decision"))
            colDecision.title = "裁决"
            colDecision.width = 85
            tableView.addTableColumn(colDecision)

            let colWindows = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("windows"))
            colWindows.title = "AX / WS 窗口"
            colWindows.width = 90
            tableView.addTableColumn(colWindows)

            let colReason = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("reason"))
            colReason.title = "决策原因与详情"
            colReason.width = 240
            tableView.addTableColumn(colReason)
        } else {
            // 活跃监视列表表格列
            let colApp = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("appName"))
            colApp.title = "应用名称"
            colApp.width = 130
            tableView.addTableColumn(colApp)

            let colPid = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
            colPid.title = "PID"
            colPid.width = 55
            tableView.addTableColumn(colPid)

            let colBid = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bundleID"))
            colBid.title = "Bundle ID"
            colBid.width = 180
            tableView.addTableColumn(colBid)

            let colWin = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("winCount"))
            colWin.title = "当前窗口 (AX/WS)"
            colWin.width = 110
            tableView.addTableColumn(colWin)

            let colRule = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
            colRule.title = "匹配规则"
            colRule.width = 130
            tableView.addTableColumn(colRule)
        }
    }

    public func reloadContent() {
        if currentModeIndex == 0 {
            decisionRecords = AutoQuitDecisionTrace.shared.recentRecords()
            emptyLabel.isHidden = !decisionRecords.isEmpty
            emptyLabel.stringValue = "暂无最近决策流水"
        } else {
            monitoredAppsSnapshot = AutoQuitManager.shared.currentWatchedAppsSnapshot()
            emptyLabel.isHidden = !monitoredAppsSnapshot.isEmpty
            emptyLabel.stringValue = "暂无处于活跃监视中的应用（或总开关未开启）"
        }
        tableView.reloadData()
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        currentModeIndex = sender.selectedSegment
        setupColumns()
        reloadContent()
    }

    @objc private func copyReport() {
        let report = AutoQuitDecisionTrace.shared.generateDiagnosticReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)

        let originalTitle = copyReportButton.title
        copyReportButton.title = "已复制到剪贴板 ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyReportButton.title = originalTitle
        }
    }

    @objc private func closeSheet() {
        window?.sheetParent?.endSheet(window!)
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return (currentModeIndex == 0) ? decisionRecords.count : monitoredAppsSnapshot.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn else { return nil }
        let cellID = NSUserInterfaceItemIdentifier("Cell_\(col.identifier.rawValue)")
        var text = ""

        if currentModeIndex == 0 {
            guard decisionRecords.indices.contains(row) else { return nil }
            let record = decisionRecords[row]
            switch col.identifier.rawValue {
            case "time":
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm:ss.SSS"
                text = fmt.string(from: record.timestamp)
            case "app":
                text = record.appName
            case "decision":
                text = record.decision.rawValue
            case "windows":
                let ax = record.axWindowCount.map(String.init) ?? "-"
                let ws = record.wsWindowCount.map(String.init) ?? "-"
                text = "\(ax) / \(ws)"
            case "reason":
                text = record.reasonCode + (record.detail.isEmpty ? "" : " (\(record.detail))")
            default: break
            }
        } else {
            guard monitoredAppsSnapshot.indices.contains(row) else { return nil }
            let app = monitoredAppsSnapshot[row]
            switch col.identifier.rawValue {
            case "appName": text = app.name
            case "pid": text = "\(app.pid)"
            case "bundleID": text = app.bundleID
            case "winCount": text = "\(app.axCount) / \(app.wsCount)"
            case "rule": text = app.rule
            default: break
            }
        }

        var cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField
        if cell == nil {
            cell = NSTextField(labelWithString: text)
            cell?.identifier = cellID
            cell?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell?.lineBreakMode = .byTruncatingTail
        } else {
            cell?.stringValue = text
        }
        return cell
    }
}
