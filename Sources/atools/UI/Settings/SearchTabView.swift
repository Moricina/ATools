import Foundation
import AppKit

// MARK: - 3. Search Tab View
public final class SearchTabView: NSView, NSTextFieldDelegate {
    public private(set) var searchRecorder: HotkeyRecorderControl?
    private var searchSwitch: NSSwitch!
    private var diskSearchSwitch: NSSwitch!
    private var autoPasteSwitch: NSSwitch!
    private var dictSwitch: NSSwitch!
    private var calcSwitch: NSSwitch!
    private var limitControl: SettingsLiquidSegmentedControl!
    private var webSearchSwitch: NSSwitch!
    private var enginePopUp: SettingsLiquidPopUpButton!
    private var customURLField: NSTextField!
    private var pageContainer: NSView!
    private var pages: [NSView] = []
    private var headerView: SettingsHeaderView!
    private var hotFolderStack: NSStackView!

    // 排除范围页控件
    private var excludeCachesSwitch: NSSwitch!
    private var excludeLogsSwitch: NSSwitch!
    private var excludeDevSwitch: NSSwitch!
    private var excludeUserLibSwitch: NSSwitch!
    private var excludeTrashSwitch: NSSwitch!
    private var excludeHiddenSwitch: NSSwitch!
    private var customExclusionStack: NSStackView!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        headerView = SettingsHeaderView(title: "全盘搜索", iconName: "magnifyingglass", tabs: ["搜索选项", "排除范围", "扩展与平替", "网络搜索"])
        addSubview(headerView)

        pageContainer = NSView()
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageContainer)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            pageContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Page 0: 搜索选项
        let optionsPage = NSView()
        let optionsScrollContent = NSView()
        let optionsScroll = makeTabScrollView(contentView: optionsScrollContent)
        optionsPage.addSubview(optionsScroll)
        NSLayoutConstraint.activate([
            optionsScroll.topAnchor.constraint(equalTo: optionsPage.topAnchor),
            optionsScroll.leadingAnchor.constraint(equalTo: optionsPage.leadingAnchor),
            optionsScroll.trailingAnchor.constraint(equalTo: optionsPage.trailingAnchor),
            optionsScroll.bottomAnchor.constraint(equalTo: optionsPage.bottomAnchor)
        ])

        // Section 0: 启用与呼出快捷键
        let sec0Title = makeSectionHeader(title: "启用与呼出快捷键")
        optionsScrollContent.addSubview(sec0Title)

        let card0 = SettingsCardView()
        card0.translatesAutoresizingMaskIntoConstraints = false
        optionsScrollContent.addSubview(card0)

        searchSwitch = NSSwitch()
        searchSwitch.target = self
        searchSwitch.action = #selector(toggleSearchPanel(_:))
        let rowSearch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass"),
            title: "启用全盘搜索",
            subtitle: "通过快捷键呼出全盘文件与应用搜索",
            accessory: searchSwitch
        )
        card0.addRow(rowSearch)

        let recorder = HotkeyRecorderControl(binding: ConfigManager.shared.config.searchHotkey)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 210).isActive = true
        recorder.onChange = { [weak self] newBinding in
            self?.handleSearchRecorded(newBinding)
        }
        recorder.onClear = { [weak self] in
            self?.handleSearchCleared()
        }
        self.searchRecorder = recorder
        let rowRecorder = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "keyboard"),
            title: "快捷键",
            subtitle: "支持按下组合键或双击修饰键（如双击 ⌥）",
            accessory: recorder
        )
        card0.addRow(rowRecorder, isLast: true)

        let sec1Title = makeSectionHeader(title: "搜索选项与结果数量")
        optionsScrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        optionsScrollContent.addSubview(card1)

        diskSearchSwitch = NSSwitch()
        diskSearchSwitch.target = self
        diskSearchSwitch.action = #selector(toggleDiskSearch(_:))
        let rowDisk = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "opticaldiscdrive"),
            title: "全盘文件搜索",
            subtitle: "使用系统索引快速检索全盘文件",
            accessory: diskSearchSwitch
        )
        card1.addRow(rowDisk)

        limitControl = SettingsLiquidSegmentedControl(labels: ["30 条", "50 条", "80 条", "120 条"], target: self, action: #selector(limitChanged(_:)))
        let rowLimit = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "list.number"),
            title: "搜索结果条数",
            subtitle: "设置搜索结果列表的最大展示条数",
            accessory: limitControl
        )
        card1.addRow(rowLimit)

        autoPasteSwitch = NSSwitch()
        autoPasteSwitch.target = self
        autoPasteSwitch.action = #selector(toggleAutoPaste(_:))
        let rowAutoPaste = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "doc.on.clipboard"),
            title: "复制后呼出自动粘贴",
            subtitle: "复制文本后短时间内呼出搜索，自动填入并开始检索",
            accessory: autoPasteSwitch
        )
        card1.addRow(rowAutoPaste, isLast: true)

        NSLayoutConstraint.activate([
            sec0Title.topAnchor.constraint(equalTo: optionsScrollContent.topAnchor, constant: 6),
            sec0Title.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            card0.topAnchor.constraint(equalTo: sec0Title.bottomAnchor, constant: 7),
            card0.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            card0.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28),

            sec1Title.topAnchor.constraint(equalTo: card0.bottomAnchor, constant: 16),
            sec1Title.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 7),
            card1.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28)
        ])

        // 自定义热目录：内存快照白名单（只进快照，不影响全盘检索范围）
        let secHotTitle = makeSectionHeader(title: "自定义热目录")
        optionsScrollContent.addSubview(secHotTitle)

        let cardHot = SettingsCardView()
        cardHot.translatesAutoresizingMaskIntoConstraints = false
        cardHot.onDropFolders = { [weak self] droppedPaths in
            var addedCount = 0
            for path in droppedPaths {
                if ConfigManager.shared.addHotFolder(path) {
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                self?.reloadHotFolderRows()
            } else {
                NSSound.beep()
            }
        }
        optionsScrollContent.addSubview(cardHot)

        let hotFolderContainer = NSView()
        hotFolderContainer.translatesAutoresizingMaskIntoConstraints = false
        cardHot.addRow(hotFolderContainer, isLast: true)

        hotFolderStack = NSStackView()
        hotFolderStack.orientation = .vertical
        hotFolderStack.spacing = 0
        hotFolderStack.distribution = .fill
        hotFolderStack.alignment = .leading
        hotFolderStack.translatesAutoresizingMaskIntoConstraints = false
        hotFolderContainer.addSubview(hotFolderStack)
        NSLayoutConstraint.activate([
            hotFolderStack.topAnchor.constraint(equalTo: hotFolderContainer.topAnchor),
            hotFolderStack.bottomAnchor.constraint(equalTo: hotFolderContainer.bottomAnchor),
            hotFolderStack.leadingAnchor.constraint(equalTo: hotFolderContainer.leadingAnchor),
            hotFolderStack.trailingAnchor.constraint(equalTo: hotFolderContainer.trailingAnchor),
            hotFolderStack.widthAnchor.constraint(equalTo: hotFolderContainer.widthAnchor)
        ])

        NSLayoutConstraint.activate([
            secHotTitle.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 16),
            secHotTitle.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),

            cardHot.topAnchor.constraint(equalTo: secHotTitle.bottomAnchor, constant: 7),
            cardHot.leadingAnchor.constraint(equalTo: optionsScrollContent.leadingAnchor, constant: 28),
            cardHot.trailingAnchor.constraint(equalTo: optionsScrollContent.trailingAnchor, constant: -28),
            cardHot.bottomAnchor.constraint(equalTo: optionsScrollContent.bottomAnchor, constant: -16)
        ])
        reloadHotFolderRows()

        // Page 1: 排除范围 (对齐 Alfred Search Scope 设计)
        let exclusionPage = NSView()
        let exclusionScrollContent = NSView()
        let exclusionScroll = makeTabScrollView(contentView: exclusionScrollContent)
        exclusionPage.addSubview(exclusionScroll)
        NSLayoutConstraint.activate([
            exclusionScroll.topAnchor.constraint(equalTo: exclusionPage.topAnchor),
            exclusionScroll.leadingAnchor.constraint(equalTo: exclusionPage.leadingAnchor),
            exclusionScroll.trailingAnchor.constraint(equalTo: exclusionPage.trailingAnchor),
            exclusionScroll.bottomAnchor.constraint(equalTo: exclusionPage.bottomAnchor)
        ])

        let secPresetTitle = makeSectionHeader(title: "常用排除预设 (快捷过滤)")
        exclusionScrollContent.addSubview(secPresetTitle)

        let cardPreset = SettingsCardView()
        cardPreset.translatesAutoresizingMaskIntoConstraints = false
        exclusionScrollContent.addSubview(cardPreset)

        excludeCachesSwitch = NSSwitch()
        excludeCachesSwitch.target = self
        excludeCachesSwitch.action = #selector(toggleExcludeCaches(_:))
        let tileCaches = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "archivebox"),
            title: "排除系统与应用缓存",
            toolTip: "自动过滤 ~/Library/Caches, /Library/Caches 及各类 WebKit 临时缓存数据",
            toggleSwitch: excludeCachesSwitch
        )

        excludeUserLibSwitch = NSSwitch()
        excludeUserLibSwitch.target = self
        excludeUserLibSwitch.action = #selector(toggleExcludeUserLib(_:))
        let tileUserLib = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "folder.badge.gearshape"),
            title: "排除资源库 (~/Library)",
            toolTip: "过滤 ~/Library 目录中的系统配置文件",
            toggleSwitch: excludeUserLibSwitch
        )
        cardPreset.addRow(makeDualTileRow(left: tileCaches, right: tileUserLib))

        excludeLogsSwitch = NSSwitch()
        excludeLogsSwitch.target = self
        excludeLogsSwitch.action = #selector(toggleExcludeLogs(_:))
        let tileLogs = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "doc.text.magnifyingglass"),
            title: "排除系统日志与崩溃报告",
            toolTip: "自动过滤 ~/Library/Logs, /var/log, DiagnosticReports 及系统崩溃堆栈文件",
            toggleSwitch: excludeLogsSwitch
        )

        excludeTrashSwitch = NSSwitch()
        excludeTrashSwitch.target = self
        excludeTrashSwitch.action = #selector(toggleExcludeTrash(_:))
        let tileTrash = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "trash"),
            title: "排除废纸篓与临时目录",
            toolTip: "自动过滤 ~/.Trash, /private/var/folders, /tmp 等已丢弃与临时文件夹",
            toggleSwitch: excludeTrashSwitch
        )
        cardPreset.addRow(makeDualTileRow(left: tileLogs, right: tileTrash))

        excludeDevSwitch = NSSwitch()
        excludeDevSwitch.target = self
        excludeDevSwitch.action = #selector(toggleExcludeDev(_:))
        let tileDev = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "hammer"),
            title: "排除开发依赖与构建产物",
            toolTip: "自动过滤 node_modules, DerivedData, .build, target, __pycache__, .gradle 等工程副产物",
            toggleSwitch: excludeDevSwitch
        )

        excludeHiddenSwitch = NSSwitch()
        excludeHiddenSwitch.target = self
        excludeHiddenSwitch.action = #selector(toggleExcludeHidden(_:))
        let tileHidden = SettingsToggleTileView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "eye.slash"),
            title: "排除版本控制与隐藏文件",
            toolTip: "自动过滤 .git, .svn 及以 \".\" 开头的系统级隐藏文件与隐藏文件夹",
            toggleSwitch: excludeHiddenSwitch
        )
        cardPreset.addRow(makeDualTileRow(left: tileDev, right: tileHidden), isLast: true)

        NSLayoutConstraint.activate([
            secPresetTitle.topAnchor.constraint(equalTo: exclusionScrollContent.topAnchor, constant: 6),
            secPresetTitle.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),

            cardPreset.topAnchor.constraint(equalTo: secPresetTitle.bottomAnchor, constant: 7),
            cardPreset.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            cardPreset.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28)
        ])

        // 自定义排除目录 (黑名单)
        let secCustomTitle = makeSectionHeader(title: "自定义排除目录 (黑名单)")
        exclusionScrollContent.addSubview(secCustomTitle)

        let cardCustom = SettingsCardView()
        cardCustom.translatesAutoresizingMaskIntoConstraints = false
        cardCustom.onDropFolders = { [weak self] droppedPaths in
            var addedCount = 0
            for path in droppedPaths {
                if ConfigManager.shared.addCustomExcludedPath(path) {
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                self?.reloadCustomExclusionRows()
            } else {
                NSSound.beep()
            }
        }
        exclusionScrollContent.addSubview(cardCustom)

        let customContainer = NSView()
        customContainer.translatesAutoresizingMaskIntoConstraints = false
        cardCustom.addRow(customContainer, isLast: true)

        customExclusionStack = NSStackView()
        customExclusionStack.orientation = .vertical
        customExclusionStack.spacing = 0
        customExclusionStack.distribution = .fill
        customExclusionStack.alignment = .leading
        customExclusionStack.translatesAutoresizingMaskIntoConstraints = false
        customContainer.addSubview(customExclusionStack)
        NSLayoutConstraint.activate([
            customExclusionStack.topAnchor.constraint(equalTo: customContainer.topAnchor),
            customExclusionStack.bottomAnchor.constraint(equalTo: customContainer.bottomAnchor),
            customExclusionStack.leadingAnchor.constraint(equalTo: customContainer.leadingAnchor),
            customExclusionStack.trailingAnchor.constraint(equalTo: customContainer.trailingAnchor),
            customExclusionStack.widthAnchor.constraint(equalTo: customContainer.widthAnchor)
        ])

        let exclusionTipLabel = NSTextField(labelWithString: "提示：排除目录可避免检索不相关的系统文件，提升搜索速度。")
        exclusionTipLabel.translatesAutoresizingMaskIntoConstraints = false
        exclusionTipLabel.font = NSFont.systemFont(ofSize: 11)
        exclusionTipLabel.textColor = .secondaryLabelColor
        exclusionTipLabel.cell?.wraps = true
        exclusionTipLabel.maximumNumberOfLines = 2
        exclusionTipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        exclusionScrollContent.addSubview(exclusionTipLabel)

        NSLayoutConstraint.activate([
            secCustomTitle.topAnchor.constraint(equalTo: cardPreset.bottomAnchor, constant: 16),
            secCustomTitle.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),

            cardCustom.topAnchor.constraint(equalTo: secCustomTitle.bottomAnchor, constant: 7),
            cardCustom.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            cardCustom.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28),

            exclusionTipLabel.topAnchor.constraint(equalTo: cardCustom.bottomAnchor, constant: 10),
            exclusionTipLabel.leadingAnchor.constraint(equalTo: exclusionScrollContent.leadingAnchor, constant: 28),
            exclusionTipLabel.trailingAnchor.constraint(equalTo: exclusionScrollContent.trailingAnchor, constant: -28),
            exclusionTipLabel.bottomAnchor.constraint(equalTo: exclusionScrollContent.bottomAnchor, constant: -16)
        ])
        reloadCustomExclusionRows()

        // Page 2: 扩展功能
        let extPage = NSView()
        let extScrollContent = NSView()
        let extScroll = makeTabScrollView(contentView: extScrollContent)
        extPage.addSubview(extScroll)
        NSLayoutConstraint.activate([
            extScroll.topAnchor.constraint(equalTo: extPage.topAnchor),
            extScroll.leadingAnchor.constraint(equalTo: extPage.leadingAnchor),
            extScroll.trailingAnchor.constraint(equalTo: extPage.trailingAnchor),
            extScroll.bottomAnchor.constraint(equalTo: extPage.bottomAnchor)
        ])

        let sec2Title = makeSectionHeader(title: "即时计算与本地词典")
        extScrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        extScrollContent.addSubview(card2)

        calcSwitch = NSSwitch()
        calcSwitch.target = self
        calcSwitch.action = #selector(toggleCalc(_:))
        let rowCalc = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "number.square"),
            title: "数学计算",
            subtitle: "输入数学算式即时求解，回车复制结果",
            accessory: calcSwitch
        )
        card2.addRow(rowCalc)

        dictSwitch = NSSwitch()
        dictSwitch.target = self
        dictSwitch.action = #selector(toggleDict(_:))
        let rowDict = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "character.book.closed"),
            title: "本地词典查询",
            subtitle: "输入单词即时显示释义，回车打开词典应用",
            accessory: dictSwitch
        )
        card2.addRow(rowDict, isLast: true)

        let secSpotTitle = makeSectionHeader(title: "快捷键冲突与系统设置")
        extScrollContent.addSubview(secSpotTitle)

        let cardSpot = SettingsCardView()
        cardSpot.translatesAutoresizingMaskIntoConstraints = false
        extScrollContent.addSubview(cardSpot)

        let setCmdSpaceBtn = SettingsPillButton(title: "设为 ⌘Space", target: self, action: #selector(setCommandSpaceHotkey))
        let rowSetCmdSpace = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "command"),
            title: "将快捷键设为 ⌘Space",
            subtitle: "如与系统聚焦快捷键冲突，请前往系统设置调整",
            accessory: setCmdSpaceBtn
        )
        cardSpot.addRow(rowSetCmdSpace)

        let openKbBtn = SettingsPillButton(title: "系统键盘设置...", target: self, action: #selector(openKeyboardSettings))
        let rowKb = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "keyboard"),
            title: "系统键盘设置...",
            subtitle: "前往系统设置调整或关闭系统聚焦快捷键",
            accessory: openKbBtn
        )
        cardSpot.addRow(rowKb)

        let openCcBtn = SettingsPillButton(title: "控制中心设置...", target: self, action: #selector(openControlCenterSettings))
        let rowCc = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "switch.2"),
            title: "系统控制中心设置...",
            subtitle: "前往系统设置管理顶部菜单栏中的聚焦图标",
            accessory: openCcBtn
        )
        cardSpot.addRow(rowCc, isLast: true)

        let spotlightTip = NSTextField(labelWithString: "提示：若将系统聚焦快捷键关闭，可将 ⌘Space 分配给 ATools 使用。")
        spotlightTip.translatesAutoresizingMaskIntoConstraints = false
        spotlightTip.font = NSFont.systemFont(ofSize: 11)
        spotlightTip.textColor = .secondaryLabelColor
        spotlightTip.cell?.wraps = true
        spotlightTip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        extScrollContent.addSubview(spotlightTip)

        NSLayoutConstraint.activate([
            sec2Title.topAnchor.constraint(equalTo: extScrollContent.topAnchor, constant: 6),
            sec2Title.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 7),
            card2.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),

            secSpotTitle.topAnchor.constraint(equalTo: card2.bottomAnchor, constant: 16),
            secSpotTitle.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),

            cardSpot.topAnchor.constraint(equalTo: secSpotTitle.bottomAnchor, constant: 7),
            cardSpot.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 28),
            cardSpot.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),

            spotlightTip.topAnchor.constraint(equalTo: cardSpot.bottomAnchor, constant: 10),
            spotlightTip.leadingAnchor.constraint(equalTo: extScrollContent.leadingAnchor, constant: 32),
            spotlightTip.trailingAnchor.constraint(equalTo: extScrollContent.trailingAnchor, constant: -28),
            spotlightTip.bottomAnchor.constraint(equalTo: extScrollContent.bottomAnchor, constant: -16)
        ])

        // Page 2: 网络搜索
        let webPage = NSView()
        let webScrollContent = NSView()
        let webScroll = makeTabScrollView(contentView: webScrollContent)
        webPage.addSubview(webScroll)
        NSLayoutConstraint.activate([
            webScroll.topAnchor.constraint(equalTo: webPage.topAnchor),
            webScroll.leadingAnchor.constraint(equalTo: webPage.leadingAnchor),
            webScroll.trailingAnchor.constraint(equalTo: webPage.trailingAnchor),
            webScroll.bottomAnchor.constraint(equalTo: webPage.bottomAnchor)
        ])

        let sec3Title = makeSectionHeader(title: "网页搜索")
        webScrollContent.addSubview(sec3Title)

        let card3 = SettingsCardView()
        card3.translatesAutoresizingMaskIntoConstraints = false
        webScrollContent.addSubview(card3)

        webSearchSwitch = NSSwitch()
        webSearchSwitch.target = self
        webSearchSwitch.action = #selector(toggleWebSearch(_:))
        let rowWebSearch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "network"),
            title: "网页搜索",
            subtitle: "未搜到本地结果时，支持快捷跳转至浏览器搜索",
            accessory: webSearchSwitch
        )
        card3.addRow(rowWebSearch)

        enginePopUp = SettingsLiquidPopUpButton()
        enginePopUp.translatesAutoresizingMaskIntoConstraints = false
        enginePopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
        enginePopUp.target = self
        enginePopUp.action = #selector(engineChanged(_:))
        for engine in WebSearchEngine.allCases {
            enginePopUp.addItem(withTitle: engine.title)
        }
        let rowEngine = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "globe"),
            title: "默认搜索引擎",
            subtitle: "选择网页搜索所使用的搜索引擎",
            accessory: enginePopUp
        )
        card3.addRow(rowEngine)

        customURLField = NSTextField()
        customURLField.placeholderString = "https://www.google.com/search?q={query}"
        customURLField.isEditable = true
        customURLField.isSelectable = true
        customURLField.bezelStyle = .roundedBezel
        customURLField.font = NSFont.systemFont(ofSize: 12)
        customURLField.delegate = self
        customURLField.target = self
        customURLField.action = #selector(customURLSubmitted(_:))
        customURLField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        customURLField.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let rowCustomURL = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "link"),
            title: "自定义搜索地址",
            subtitle: "仅在引擎选择「自定义」时生效，支持 {query} 或 %s 占位符",
            accessory: customURLField
        )
        card3.addRow(rowCustomURL, isLast: true)

        let tipLabel = NSTextField(labelWithString: "提示：支持使用 {query} 或 %s 作为关键词占位符。")
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont.systemFont(ofSize: 11)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.cell?.wraps = true
        tipLabel.maximumNumberOfLines = 2
        tipLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        webScrollContent.addSubview(tipLabel)

        NSLayoutConstraint.activate([
            sec3Title.topAnchor.constraint(equalTo: webScrollContent.topAnchor, constant: 6),
            sec3Title.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),

            card3.topAnchor.constraint(equalTo: sec3Title.bottomAnchor, constant: 7),
            card3.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),
            card3.trailingAnchor.constraint(equalTo: webScrollContent.trailingAnchor, constant: -28),

            tipLabel.topAnchor.constraint(equalTo: card3.bottomAnchor, constant: 10),
            tipLabel.leadingAnchor.constraint(equalTo: webScrollContent.leadingAnchor, constant: 28),
            tipLabel.trailingAnchor.constraint(equalTo: webScrollContent.trailingAnchor, constant: -28),
            tipLabel.bottomAnchor.constraint(equalTo: webScrollContent.bottomAnchor, constant: -16)
        ])

        pages = [optionsPage, exclusionPage, extPage, webPage]
        for (idx, page) in pages.enumerated() {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
            ])
            page.isHidden = (idx != 0)
        }

        headerView.onSegmentChanged = { [weak self] index in
            self?.showPage(index)
        }
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        searchSwitch?.state = cfg.enableSearchPanel ? .on : .off
        searchSwitch?.isEnabled = cfg.enableShelfPanel
        let enabled = cfg.enableSearchPanel

        searchRecorder?.isEnabled = enabled
        searchRecorder?.currentBinding = cfg.searchHotkey

        diskSearchSwitch?.isEnabled = enabled
        autoPasteSwitch?.isEnabled = enabled
        calcSwitch?.isEnabled = enabled
        dictSwitch?.isEnabled = enabled
        limitControl?.isEnabled = enabled
        webSearchSwitch?.isEnabled = enabled

        reloadHotFolderRows()
        reloadCustomExclusionRows()
        diskSearchSwitch.state = cfg.enableFullDiskSearch ? .on : .off
        autoPasteSwitch.state = cfg.autoPasteOnSummonAfterCopy ? .on : .off
        calcSwitch.state = cfg.enableCalculator ? .on : .off
        dictSwitch.state = cfg.enableDictionary ? .on : .off

        excludeCachesSwitch.state = cfg.searchExcludeCaches ? .on : .off
        excludeLogsSwitch.state = cfg.searchExcludeLogs ? .on : .off
        excludeDevSwitch.state = cfg.searchExcludeDeveloper ? .on : .off
        excludeUserLibSwitch.state = cfg.searchExcludeUserLibrary ? .on : .off
        excludeTrashSwitch.state = cfg.searchExcludeTrash ? .on : .off
        excludeHiddenSwitch.state = cfg.searchExcludeHidden ? .on : .off

        switch cfg.searchResultLimit {
        case ..<40: limitControl.selectedSegment = 0
        case ..<65: limitControl.selectedSegment = 1
        case ..<100: limitControl.selectedSegment = 2
        default: limitControl.selectedSegment = 3
        }

        webSearchSwitch.state = cfg.enableWebSearch ? .on : .off
        if let idx = WebSearchEngine.allCases.firstIndex(of: cfg.webSearchEngine) {
            enginePopUp.selectItem(at: idx)
        }
        customURLField.stringValue = cfg.customWebSearchURL
        updateWebSearchUIState()
    }

    private func updateWebSearchUIState() {
        let isWebEnabled = (webSearchSwitch.state == .on)
        enginePopUp.isEnabled = isWebEnabled
        let isCustom = (enginePopUp.indexOfSelectedItem == WebSearchEngine.allCases.firstIndex(of: .custom))
        customURLField.isEnabled = isWebEnabled && isCustom
        customURLField.alphaValue = (isWebEnabled && isCustom) ? 1.0 : 0.5
    }

    private func showPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        for (idx, page) in pages.enumerated() {
            page.isHidden = (idx != index)
        }
    }

    @objc private func toggleDiskSearch(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableFullDiskSearch(sender.state == .on)
    }

    @objc private func toggleAutoPaste(_ sender: NSSwitch) {
        ConfigManager.shared.updateAutoPasteOnSummonAfterCopy(sender.state == .on)
    }

    // MARK: - 自定义热目录列表

    private func reloadHotFolderRows() {
        guard hotFolderStack != nil else { return }
        for view in hotFolderStack.arrangedSubviews {
            hotFolderStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        func addRow(_ view: NSView) {
            // 必须先入栈再激活宽度约束：激活时两视图需在同一层级
            //（否则 “no common ancestor” 直接抛 NSGenericException）。
            hotFolderStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: hotFolderStack.widthAnchor).isActive = true
        }

        let folders = ConfigManager.shared.config.extraHotFolders
        if folders.isEmpty {
            addRow(makeEmptyHotFolderRow())
        } else {
            for (index, path) in folders.enumerated() {
                if index > 0 { addRow(makeSeparator()) }
                addRow(makeHotFolderRow(path: path))
            }
            addRow(makeSeparator())
            addRow(makeAddHotFolderRow(count: folders.count))
        }
    }

    private func makeEmptyHotFolderRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "添加自定义热目录…")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .controlAccentColor
        row.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "默认已覆盖下载/桌面/文稿 · 可点击右侧添加，或直接从访达拖拽文件夹至此")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        row.addSubview(subtitle)

        let addBtn = SettingsIconButton(
            symbolName: "plus.circle.fill",
            accessibilityLabel: "添加",
            target: self,
            action: #selector(addHotFolderClicked(_:))
        )
        addBtn.normalTintColor = .controlAccentColor
        addBtn.hoverTintColor = .controlAccentColor
        addBtn.toolTip = "添加热目录"
        row.addSubview(addBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -6),

            addBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeHotFolderRow(path: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = ThumbnailPipeline.shared.symbolIcon(name: "folder")
        icon.contentTintColor = .secondaryLabelColor
        row.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(titleLabel)

        let pathLabel = NSTextField(labelWithString: path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(pathLabel)

        let removeBtn = SettingsIconButton(
            symbolName: "minus.circle.fill",
            accessibilityLabel: "移除",
            target: self,
            action: #selector(removeHotFolderClicked(_:))
        )
        removeBtn.normalTintColor = .secondaryLabelColor
        removeBtn.hoverTintColor = .systemRed
        removeBtn.identifier = NSUserInterfaceItemIdentifier(path)
        removeBtn.toolTip = "从热目录移除"
        row.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5)
        ])
        return row
    }

    private func makeAddHotFolderRow(count: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "添加目录…")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .controlAccentColor
        row.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "已添加 \(count)/\(ConfigManager.maxExtraHotFolders) · 可点击添加，或直接从访达将文件夹拖拽至此")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        row.addSubview(subtitle)

        let addBtn = SettingsIconButton(
            symbolName: "plus.circle.fill",
            accessibilityLabel: "添加",
            target: self,
            action: #selector(addHotFolderClicked(_:))
        )
        addBtn.normalTintColor = .controlAccentColor
        addBtn.hoverTintColor = .controlAccentColor
        addBtn.toolTip = "添加热目录"
        addBtn.isEnabled = count < ConfigManager.maxExtraHotFolders
        row.addSubview(addBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5),

            addBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeHotFolderInfoRow(subtitle: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: subtitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])
        return row
    }

    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        ])
        return container
    }

    @objc private func removeHotFolderClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        ConfigManager.shared.removeHotFolder(path)
        reloadHotFolderRows()
    }

    @objc private func addHotFolderClicked(_ sender: Any?) {
        guard ConfigManager.shared.config.extraHotFolders.count < ConfigManager.maxExtraHotFolders else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "添加"
        panel.message = "选择加入热目录快照的文件夹（深度 3 层，每目录上限 25,000 条）"
        guard panel.runModalAboveFloatingWindows() == .OK, let url = panel.url else { return }
        if ConfigManager.shared.addHotFolder(url.path) {
            reloadHotFolderRows()
        } else {
            let alert = NSAlert()
            alert.messageText = "无法添加该目录"
            alert.informativeText = "目录不存在、与已有热目录重复或互相包含、或已达到上限（\(ConfigManager.maxExtraHotFolders) 个）。"
            alert.alertStyle = .warning
            alert.runModalAboveFloatingWindows()
        }
    }

    // MARK: - 自定义排除目录列表与事件

    private func reloadCustomExclusionRows() {
        guard customExclusionStack != nil else { return }
        for view in customExclusionStack.arrangedSubviews {
            customExclusionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        func addRow(_ view: NSView) {
            customExclusionStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: customExclusionStack.widthAnchor).isActive = true
        }

        let paths = ConfigManager.shared.config.customExcludedPaths
        if !paths.isEmpty {
            for (index, path) in paths.enumerated() {
                if index > 0 { addRow(makeSeparator()) }
                addRow(makeCustomExclusionRow(path: path))
            }
            addRow(makeSeparator())
        }
        addRow(makeAddCustomExclusionRow(count: paths.count))
    }

    private func makeCustomExclusionRow(path: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = ThumbnailPipeline.shared.symbolIcon(name: "folder.badge.minus")
        icon.contentTintColor = .secondaryLabelColor
        row.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(titleLabel)

        let pathLabel = NSTextField(labelWithString: path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        row.addSubview(pathLabel)

        let removeBtn = SettingsIconButton(
            symbolName: "minus.circle.fill",
            accessibilityLabel: "移除",
            target: self,
            action: #selector(removeCustomExclusionClicked(_:))
        )
        removeBtn.normalTintColor = .secondaryLabelColor
        removeBtn.hoverTintColor = .systemRed
        removeBtn.identifier = NSUserInterfaceItemIdentifier(path)
        removeBtn.toolTip = "从排除目录中移除"
        row.addSubview(removeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 44),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeBtn.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5)
        ])
        return row
    }

    private func makeAddCustomExclusionRow(count: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "添加排除目录…")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .controlAccentColor
        row.addSubview(titleLabel)

        let desc = (count == 0)
            ? "暂无自定义排除目录 · 可点击添加，或直接从访达将文件夹拖拽至此"
            : "已添加 \(count)/\(ConfigManager.maxCustomExcludedPaths) · 可点击添加，或直接从访达将文件夹拖拽至此"
        let subtitle = NSTextField(labelWithString: desc)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        row.addSubview(subtitle)

        let addBtn = SettingsIconButton(
            symbolName: "plus.circle.fill",
            accessibilityLabel: "添加",
            target: self,
            action: #selector(addCustomExclusionClicked(_:))
        )
        addBtn.normalTintColor = .controlAccentColor
        addBtn.hoverTintColor = .controlAccentColor
        addBtn.toolTip = "选择文件夹添加至排除黑名单"
        addBtn.isEnabled = count < ConfigManager.maxCustomExcludedPaths
        row.addSubview(addBtn)

        let resetBtn = SettingsResetButton(title: "恢复默认", target: self, action: #selector(resetCustomExclusionClicked(_:)))
        resetBtn.toolTip = "清空自定义排除目录"
        resetBtn.isEnabled = count > 0
        row.addSubview(resetBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),

            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetBtn.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: resetBtn.leadingAnchor, constant: -8),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -5),

            resetBtn.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -8),
            resetBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            addBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeCustomExclusionInfoRow(subtitle: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: subtitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])
        return row
    }

    @objc private func addCustomExclusionClicked(_ sender: Any?) {
        guard ConfigManager.shared.config.customExcludedPaths.count < ConfigManager.maxCustomExcludedPaths else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "排除"
        panel.message = "选择要从全盘搜索中排除的文件夹"
        guard panel.runModalAboveFloatingWindows() == .OK, let url = panel.url else { return }
        if ConfigManager.shared.addCustomExcludedPath(url.path) {
            reloadCustomExclusionRows()
        } else {
            let alert = NSAlert()
            alert.messageText = "无法排除该目录"
            alert.informativeText = "该目录不存在、已被包含在已有排除项中、或是系统根/用户家目录，或已达到最大排除数量（\(ConfigManager.maxCustomExcludedPaths) 个）。"
            alert.alertStyle = .warning
            alert.runModalAboveFloatingWindows()
        }
    }

    @objc private func removeCustomExclusionClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        ConfigManager.shared.removeCustomExcludedPath(path)
        reloadCustomExclusionRows()
    }

    @objc private func resetCustomExclusionClicked(_ sender: Any?) {
        ConfigManager.shared.resetCustomExcludedPathsToDefault()
        reloadCustomExclusionRows()
    }

    @objc private func toggleExcludeCaches(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeCaches(sender.state == .on)
    }

    @objc private func toggleExcludeLogs(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeLogs(sender.state == .on)
    }

    @objc private func toggleExcludeDev(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeDeveloper(sender.state == .on)
    }

    @objc private func toggleExcludeUserLib(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeUserLibrary(sender.state == .on)
    }

    @objc private func toggleExcludeTrash(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeTrash(sender.state == .on)
    }

    @objc private func toggleExcludeHidden(_ sender: NSSwitch) {
        ConfigManager.shared.updateSearchExcludeHidden(sender.state == .on)
    }

    @objc private func toggleCalc(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableCalculator(sender.state == .on)
    }

    @objc private func toggleDict(_ sender: NSSwitch) {
        ConfigManager.shared.updateEnableDictionary(sender.state == .on)
    }

    @objc private func limitChanged(_ sender: SettingsLiquidSegmentedControl) {
        let limits = [30, 50, 80, 120]
        let selected = limits[max(0, min(limits.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateSearchResultLimit(selected)
    }

    @objc private func toggleWebSearch(_ sender: NSSwitch) {
        let isEnabled = (sender.state == .on)
        ConfigManager.shared.updateEnableWebSearch(isEnabled)
        updateWebSearchUIState()
    }

    @objc private func engineChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < WebSearchEngine.allCases.count {
            ConfigManager.shared.updateWebSearchEngine(WebSearchEngine.allCases[idx])
        }
        updateWebSearchUIState()
    }

    @objc private func customURLSubmitted(_ sender: NSTextField) {
        ConfigManager.shared.updateCustomWebSearchURL(sender.stringValue)
        window?.makeFirstResponder(nil)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf == customURLField {
            ConfigManager.shared.updateCustomWebSearchURL(tf.stringValue)
        }
    }

    @objc private func toggleSearchPanel(_ sender: NSSwitch) {
        let desired = (sender.state == .on)
        if !ConfigManager.shared.updateEnableSearchPanel(desired) {
            NSSound.beep()
            sender.state = .on
        } else {
            if desired {
                HotkeyManager.shared.register(id: .search, binding: ConfigManager.shared.config.searchHotkey)
            } else {
                HotkeyManager.shared.unregister(id: .search)
                // K-03: 委托给 PanelCoordinator 受控关闭并释放监听与搜索任务
                PanelCoordinator.shared.disableAndHidePanel(.search)
            }
            NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
            refresh()
        }
    }

    private func handleSearchRecorded(_ newBinding: HotkeyBinding) {
        let currentShelf = ConfigManager.shared.config.shelfHotkey
        if newBinding == currentShelf {
            searchRecorder?.currentBinding = ConfigManager.shared.config.searchHotkey
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "快捷键冲突"
            alert.informativeText = "该快捷键已被「应用分类工作台」占用。请录入其他组合键，或前往应用抽屉设置调整。"
            alert.runModalAboveFloatingWindows()
            return
        }
        // Y-06 & Y-07: 两阶段提交，仅当底层热键注册成功后才写入 ConfigManager 并广播菜单栏刷新通知
        if HotkeyManager.shared.register(id: .search, binding: newBinding) {
            ConfigManager.shared.updateSearchHotkey(newBinding)
            searchRecorder?.currentBinding = newBinding
            NotificationCenter.default.post(name: .atoolsHotkeysDidChange, object: nil)
        } else {
            searchRecorder?.currentBinding = ConfigManager.shared.config.searchHotkey
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "快捷键注册失败"
            alert.informativeText = "该快捷键可能已被系统或其他软件占用，请更换其他按键组合。"
            alert.runModalAboveFloatingWindows()
        }
    }

    private func handleSearchCleared() {
        let unassigned = HotkeyBinding(keyCode: 0, carbonModifiers: 0, displayString: "", specialTrigger: .none)
        HotkeyManager.shared.unregister(id: .search)
        ConfigManager.shared.updateSearchHotkey(unassigned)
        NotificationCenter.default.post(name: .atoolsHotkeysDidChange, object: nil)
    }

    @objc private func setCommandSpaceHotkey() {
        let display = HotkeyDisplayFormatter.displayString(keyCode: 49, carbonModifiers: 256)
        let cmdSpace = HotkeyBinding(keyCode: 49, carbonModifiers: 256, displayString: display, specialTrigger: .none)
        handleSearchRecorded(cmdSpace)
    }

    @objc private func openKeyboardSettings() {
        HotkeyManager.shared.openSystemKeyboardSettings()
    }

    @objc private func openControlCenterSettings() {
        if #available(macOS 13.0, *), let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            if NSWorkspace.shared.open(url) { return }
        }
        let script = "tell application \"System Settings\"\nactivate\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func makeDualTileRow(left: NSView, right: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(left)
        row.addSubview(right)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 38),

            left.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            left.topAnchor.constraint(equalTo: row.topAnchor),
            left.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            right.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            right.topAnchor.constraint(equalTo: row.topAnchor),
            right.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            left.widthAnchor.constraint(equalTo: right.widthAnchor)
        ])
        return row
    }
}



