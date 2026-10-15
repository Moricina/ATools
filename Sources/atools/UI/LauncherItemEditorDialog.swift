import Foundation
import AppKit
import UniformTypeIdentifiers

/// P0-1：启动项深度属性编辑器弹窗（对标 GlassDesk AppEntryEditor.cs）
/// 支持新建启动项或可视化修改现有启动项的显示名称、目标路径重定位、启动参数、工作目录、多音字/生僻字搜索别名标签（tags）及替换/恢复自定义图标。
public final class LauncherItemEditorDialog: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var item: LauncherItem
    private let categoryId: UUID?
    private let isCreatingNew: Bool
    private var onSaved: ((LauncherItem) -> Void)?

    // 暂存的图标变更状态（点击“保存修改”时才真正写入磁盘，点击“取消”零副作用）
    private var pendingCustomIconSourceURL: URL?
    private var didResetCustomIcon: Bool = false

    private let iconPreviewContainer = NSView()
    private let iconImageView = NSImageView()
    private let iconStatusLabel = NSTextField(labelWithString: "")
    private var replaceIconButton: SettingsPillButton!
    private var resetIconButton: SettingsPillButton!

    private let nameField = NSTextField()
    private let targetField = NSTextField()
    private let targetMissingBadge = NSTextField(labelWithString: "")
    private var relocateButton: SettingsPillButton!
    private let argumentsField = NSTextField()
    private let workingDirField = NSTextField()
    private var browseWorkingDirButton: SettingsPillButton!
    private let tagsField = NSTextField()

    private static var activeDialog: LauncherItemEditorDialog?

    public static func present(
        for item: LauncherItem,
        in categoryId: UUID? = nil,
        onSaved: ((LauncherItem) -> Void)? = nil
    ) {
        presentInternal(item: item, categoryId: categoryId, isCreatingNew: false, onSaved: onSaved)
    }

    public static func presentCreateNew(
        in categoryId: UUID?,
        onCreated: ((LauncherItem) -> Void)? = nil
    ) {
        let blankItem = LauncherItem(name: "", itemType: .application, target: "")
        presentInternal(item: blankItem, categoryId: categoryId, isCreatingNew: true, onSaved: onCreated)
    }

    private static func presentInternal(
        item: LauncherItem,
        categoryId: UUID?,
        isCreatingNew: Bool,
        onSaved: ((LauncherItem) -> Void)?
    ) {
        let dialog = LauncherItemEditorDialog(
            item: item,
            categoryId: categoryId,
            isCreatingNew: isCreatingNew,
            onSaved: onSaved
        )
        activeDialog = dialog

        guard let win = dialog.window else { return }
        PanelCoordinator.shared.isModalDialogOpen = true
        defer {
            PanelCoordinator.shared.isModalDialogOpen = false
            activeDialog = nil
        }

        win.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        win.center()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: win)
    }

    private init(
        item: LauncherItem,
        categoryId: UUID?,
        isCreatingNew: Bool,
        onSaved: ((LauncherItem) -> Void)?
    ) {
        self.item = item
        self.categoryId = categoryId
        self.isCreatingNew = isCreatingNew
        self.onSaved = onSaved

        let contentRect = NSRect(x: 0, y: 0, width: 500, height: 440)
        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "编辑启动项属性"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 500, height: 440)
        win.maxSize = NSSize(width: 500, height: 440)

        let isDark = ConfigManager.shared.config.theme.isDark
        win.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        super.init(window: win)
        win.delegate = self
        setupUI()
        populateValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let rootEffect = NSVisualEffectView()
        rootEffect.translatesAutoresizingMaskIntoConstraints = false
        rootEffect.material = .hudWindow
        rootEffect.blendingMode = .behindWindow
        rootEffect.state = .active
        contentView.addSubview(rootEffect)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        // Header
        let headerTitle = NSTextField(labelWithString: "编辑启动项属性")
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        headerTitle.textColor = .labelColor
        container.addSubview(headerTitle)

        let headerSubtitle = NSTextField(labelWithString: "自定义图标、显示名称、启动参数、工作目录与多音字/缩写搜索别名")
        headerSubtitle.translatesAutoresizingMaskIntoConstraints = false
        headerSubtitle.font = NSFont.systemFont(ofSize: 11.5)
        headerSubtitle.textColor = .secondaryLabelColor
        container.addSubview(headerSubtitle)

        // 1. Icon Preview & Replacement Section
        iconPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
        iconPreviewContainer.wantsLayer = true
        iconPreviewContainer.layer?.cornerRadius = 14
        iconPreviewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
        iconPreviewContainer.layer?.borderWidth = 0.5
        iconPreviewContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(iconPreviewContainer)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconPreviewContainer.addSubview(iconImageView)

        replaceIconButton = SettingsPillButton(title: "更换图标...", target: self, action: #selector(selectCustomIcon))
        replaceIconButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(replaceIconButton)

        resetIconButton = SettingsPillButton(title: "恢复默认图标", target: self, action: #selector(resetCustomIcon))
        resetIconButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resetIconButton)

        iconStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        iconStatusLabel.font = NSFont.systemFont(ofSize: 11)
        iconStatusLabel.textColor = .secondaryLabelColor
        iconStatusLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(iconStatusLabel)

        // 2. Form Fields
        let nameLabel = makeFieldLabel("显示名称：")
        configureTextField(nameField, placeholder: "启动项在抽屉与搜索中显示的名称")
        container.addSubview(nameLabel)
        container.addSubview(nameField)

        let targetLabel = makeFieldLabel("目标路径：")
        configureTextField(targetField, placeholder: "/Applications/Example.app")
        targetField.delegate = self
        let initialTargetBtnTitle = (isCreatingNew && item.target.isEmpty) ? "选择目标..." : "重新定位..."
        relocateButton = SettingsPillButton(title: initialTargetBtnTitle, target: self, action: #selector(relocateTargetClicked))
        relocateButton.translatesAutoresizingMaskIntoConstraints = false

        targetMissingBadge.translatesAutoresizingMaskIntoConstraints = false
        targetMissingBadge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        targetMissingBadge.textColor = .systemOrange
        targetMissingBadge.isHidden = true

        container.addSubview(targetLabel)
        container.addSubview(targetField)
        container.addSubview(relocateButton)
        container.addSubview(targetMissingBadge)

        let argsLabel = makeFieldLabel("启动参数：")
        configureTextField(argumentsField, placeholder: "可选：如 --incognito --disable-gpu（支持双引号包裹空格）")
        container.addSubview(argsLabel)
        container.addSubview(argumentsField)

        let wdLabel = makeFieldLabel("工作目录：")
        configureTextField(workingDirField, placeholder: "可选：启动应用或执行脚本时的默认工作目录")
        browseWorkingDirButton = SettingsPillButton(title: "选择目录...", target: self, action: #selector(selectWorkingDirectory))
        browseWorkingDirButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wdLabel)
        container.addSubview(workingDirField)
        container.addSubview(browseWorkingDirButton)

        let tagsLabel = makeFieldLabel("搜索别名：")
        configureTextField(tagsField, placeholder: "多个别名用逗号分隔，用于生僻字/多音字或缩写检索（如 wx, 聊天）")
        container.addSubview(tagsLabel)
        container.addSubview(tagsField)

        let tagsHint = NSTextField(labelWithString: "提示：搜索别名同时支持在应用抽屉按键过滤与全盘搜索中直接命中（含拼音与首字母）。")
        tagsHint.translatesAutoresizingMaskIntoConstraints = false
        tagsHint.font = NSFont.systemFont(ofSize: 11)
        tagsHint.textColor = .tertiaryLabelColor
        container.addSubview(tagsHint)

        // Bottom Buttons
        let cancelBtn = SettingsPillButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.keyEquivalent = "\u{1b}"
        container.addSubview(cancelBtn)

        let saveBtn = SettingsPillButton(title: "保存修改", style: .primary, target: self, action: #selector(saveClicked))
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.keyEquivalent = "\r"
        container.addSubview(saveBtn)

        let labelWidth: CGFloat = 68

        NSLayoutConstraint.activate([
            rootEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rootEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            headerTitle.topAnchor.constraint(equalTo: container.topAnchor),
            headerTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            headerSubtitle.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 4),
            headerSubtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerSubtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Icon section
            iconPreviewContainer.topAnchor.constraint(equalTo: headerSubtitle.bottomAnchor, constant: 16),
            iconPreviewContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconPreviewContainer.widthAnchor.constraint(equalToConstant: 64),
            iconPreviewContainer.heightAnchor.constraint(equalToConstant: 64),

            iconImageView.centerXAnchor.constraint(equalTo: iconPreviewContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconPreviewContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            replaceIconButton.topAnchor.constraint(equalTo: iconPreviewContainer.topAnchor, constant: 4),
            replaceIconButton.leadingAnchor.constraint(equalTo: iconPreviewContainer.trailingAnchor, constant: 14),

            resetIconButton.centerYAnchor.constraint(equalTo: replaceIconButton.centerYAnchor),
            resetIconButton.leadingAnchor.constraint(equalTo: replaceIconButton.trailingAnchor, constant: 8),

            iconStatusLabel.topAnchor.constraint(equalTo: replaceIconButton.bottomAnchor, constant: 8),
            iconStatusLabel.leadingAnchor.constraint(equalTo: iconPreviewContainer.trailingAnchor, constant: 14),
            iconStatusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Row 1: Name
            nameLabel.topAnchor.constraint(equalTo: iconPreviewContainer.bottomAnchor, constant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 24),

            // Row 2: Target
            targetLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            targetLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            targetLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            targetField.centerYAnchor.constraint(equalTo: targetLabel.centerYAnchor),
            targetField.leadingAnchor.constraint(equalTo: targetLabel.trailingAnchor, constant: 6),
            targetField.trailingAnchor.constraint(equalTo: relocateButton.leadingAnchor, constant: -8),
            targetField.heightAnchor.constraint(equalToConstant: 24),

            relocateButton.centerYAnchor.constraint(equalTo: targetField.centerYAnchor),
            relocateButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            targetMissingBadge.topAnchor.constraint(equalTo: targetField.bottomAnchor, constant: 3),
            targetMissingBadge.leadingAnchor.constraint(equalTo: targetField.leadingAnchor),
            targetMissingBadge.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Row 3: Arguments
            argsLabel.topAnchor.constraint(equalTo: targetField.bottomAnchor, constant: 22),
            argsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            argsLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            argumentsField.centerYAnchor.constraint(equalTo: argsLabel.centerYAnchor),
            argumentsField.leadingAnchor.constraint(equalTo: argsLabel.trailingAnchor, constant: 6),
            argumentsField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            argumentsField.heightAnchor.constraint(equalToConstant: 24),

            // Row 4: Working Directory
            wdLabel.topAnchor.constraint(equalTo: argumentsField.bottomAnchor, constant: 14),
            wdLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wdLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            workingDirField.centerYAnchor.constraint(equalTo: wdLabel.centerYAnchor),
            workingDirField.leadingAnchor.constraint(equalTo: wdLabel.trailingAnchor, constant: 6),
            workingDirField.trailingAnchor.constraint(equalTo: browseWorkingDirButton.leadingAnchor, constant: -8),
            workingDirField.heightAnchor.constraint(equalToConstant: 24),

            browseWorkingDirButton.centerYAnchor.constraint(equalTo: workingDirField.centerYAnchor),
            browseWorkingDirButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Row 5: Tags (Aliases)
            tagsLabel.topAnchor.constraint(equalTo: workingDirField.bottomAnchor, constant: 14),
            tagsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tagsLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            tagsField.centerYAnchor.constraint(equalTo: tagsLabel.centerYAnchor),
            tagsField.leadingAnchor.constraint(equalTo: tagsLabel.trailingAnchor, constant: 6),
            tagsField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tagsField.heightAnchor.constraint(equalToConstant: 24),

            tagsHint.topAnchor.constraint(equalTo: tagsField.bottomAnchor, constant: 6),
            tagsHint.leadingAnchor.constraint(equalTo: tagsField.leadingAnchor),
            tagsHint.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Footer buttons
            saveBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            saveBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -10),
            cancelBtn.centerYAnchor.constraint(equalTo: saveBtn.centerYAnchor)
        ])

        window?.initialFirstResponder = isCreatingNew ? targetField : nameField
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .right
        return label
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 12.5)
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .exterior
        field.lineBreakMode = .byTruncatingTail
    }

    private func populateValues() {
        nameField.stringValue = item.name
        targetField.stringValue = item.target
        argumentsField.stringValue = item.executionContext?.formattedArgumentsString ?? ""
        workingDirField.stringValue = item.executionContext?.workingDirectory ?? ""
        tagsField.stringValue = item.formattedTagsString

        refreshIconPreview()
        refreshTargetValidationState()
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === targetField else { return }
        let trimmedTarget = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTarget.isEmpty {
            let expanded = (trimmedTarget as NSString).expandingTildeInPath
            if nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               FileManager.default.fileExists(atPath: expanded) {
                nameField.stringValue = Self.defaultDisplayName(forPath: expanded)
            }
        }
        refreshTargetValidationState()
        refreshIconPreview()
    }

    private static func defaultDisplayName(forPath path: String) -> String {
        var displayName = FileManager.default.displayName(atPath: path)
        if displayName.lowercased().hasSuffix(".app") {
            displayName = (displayName as NSString).deletingPathExtension
        }
        return displayName
    }

    private func refreshIconPreview() {
        let effectiveCustomPath: String?
        if let stagedURL = pendingCustomIconSourceURL {
            effectiveCustomPath = stagedURL.path
        } else if didResetCustomIcon {
            effectiveCustomPath = nil
        } else {
            effectiveCustomPath = item.customIconPath
        }

        let currentTarget = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.target
            : (targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath

        if let custom = effectiveCustomPath, !custom.isEmpty, FileManager.default.fileExists(atPath: custom) {
            resetIconButton.isEnabled = true
            iconStatusLabel.stringValue = "当前使用自定义图标：\((custom as NSString).lastPathComponent)"
        } else {
            resetIconButton.isEnabled = false
            iconStatusLabel.stringValue = "当前使用系统默认图标（支持选择 .png / .icns / .app 替换）"
        }

        if currentTarget.isEmpty && effectiveCustomPath == nil {
            iconImageView.image = ThumbnailPipeline.shared.symbolIcon(name: "app.dashed", pointSize: 36)
            return
        }

        ThumbnailPipeline.shared.icon(forPath: currentTarget, customIconPath: effectiveCustomPath) { [weak self] img in
            self?.iconImageView.image = img
        }
    }

    private func refreshTargetValidationState() {
        let path = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCreatingNew && path.isEmpty {
            targetMissingBadge.isHidden = true
            return
        }
        var tempItem = item
        tempItem.target = (path as NSString).expandingTildeInPath
        if tempItem.checkTargetMissing() {
            let btnTitle = (isCreatingNew && item.target.isEmpty) ? "选择目标..." : "重新定位..."
            targetMissingBadge.stringValue = "⚠️ 当前目标路径不存在，请点击右侧「\(btnTitle)」修复路径"
            targetMissingBadge.isHidden = false
        } else {
            targetMissingBadge.isHidden = true
        }
    }

    @objc private func selectCustomIcon() {
        let panel = NSOpenPanel()
        panel.title = "选择自定义图标（支持 .png / .icns / .jpg / .app）"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.png, .icns, .jpeg, .tiff, .applicationBundle, .image]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)

        if panel.runModal() == .OK, let url = panel.url {
            pendingCustomIconSourceURL = url
            didResetCustomIcon = false
            refreshIconPreview()
        }
    }

    @objc private func resetCustomIcon() {
        pendingCustomIconSourceURL = nil
        didResetCustomIcon = true
        refreshIconPreview()
    }

    @objc private func relocateTargetClicked() {
        let panel = NSOpenPanel()
        if isCreatingNew || item.name.isEmpty {
            panel.title = "选择启动项的目标应用、文件或脚本"
        } else {
            panel.title = "重新定位启动项「\(item.name)」的目标文件或应用"
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)

        let existingParent = (targetField.stringValue as NSString).expandingTildeInPath
        let parentDir = (existingParent as NSString).deletingLastPathComponent
        if !existingParent.isEmpty, FileManager.default.fileExists(atPath: parentDir) {
            panel.directoryURL = URL(fileURLWithPath: parentDir)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }

        if panel.runModal() == .OK, let url = panel.url {
            targetField.stringValue = url.path
            if nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nameField.stringValue = Self.defaultDisplayName(forPath: url.path)
            }
            refreshTargetValidationState()
            refreshIconPreview()
        }
    }

    @objc private func selectWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择工作目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)

        if panel.runModal() == .OK, let url = panel.url {
            workingDirField.stringValue = url.path
        }
    }

    @objc private func cancelClicked() {
        closeDialog()
    }

    @objc private func saveClicked() {
        let trimmedTarget = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            NSSound.beep()
            window?.makeFirstResponder(targetField)
            return
        }
        let standardizedTarget = (trimmedTarget as NSString).expandingTildeInPath
        var trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            trimmedName = Self.defaultDisplayName(forPath: standardizedTarget)
            if trimmedName.isEmpty {
                trimmedName = (standardizedTarget as NSString).lastPathComponent
            }
        }
        guard !trimmedName.isEmpty else {
            NSSound.beep()
            window?.makeFirstResponder(nameField)
            return
        }

        var updated = item
        updated.name = trimmedName
        updated.target = standardizedTarget
        if updated.itemType == .application || updated.itemType == .fileOrFolder {
            updated.itemType = updated.target.lowercased().hasSuffix(".app") ? .application : .fileOrFolder
        }

        // 处理自定义图标托管
        if let sourceURL = pendingCustomIconSourceURL {
            if let managedPath = ConfigManager.shared.importCustomIcon(from: sourceURL, for: updated.id) {
                updated.customIconPath = managedPath
            }
        } else if didResetCustomIcon {
            updated.customIconPath = nil
        }

        // 处理启动参数与工作目录
        let parsedArgs = ExecutionContext.parseArguments(argumentsField.stringValue)
        let rawWD = workingDirField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWD = rawWD.isEmpty ? nil : (rawWD as NSString).expandingTildeInPath

        var ctx = updated.executionContext ?? ExecutionContext()
        ctx.arguments = parsedArgs
        ctx.workingDirectory = normalizedWD
        updated.executionContext = ctx.isEmpty ? nil : ctx

        // 处理搜索别名标签 (tags)
        updated.tags = LauncherItem.parseTags(tagsField.stringValue)

        if isCreatingNew {
            let targetCatId = categoryId ?? ConfigManager.shared.config.categories.first?.id
            if let catId = targetCatId {
                ConfigManager.shared.addItems([updated], to: catId)
            }
        } else {
            ConfigManager.shared.updateItem(updated, in: categoryId)
        }
        let callback = onSaved
        closeDialog()
        callback?(updated)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeDialog()
        return false
    }

    private func closeDialog() {
        if let win = window {
            if NSApp.modalWindow === win {
                NSApp.stopModal()
            }
            win.orderOut(nil)
        }
    }
}
