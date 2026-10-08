import Foundation
import AppKit

public protocol SearchBarDelegate: AnyObject {
    func searchBar(_ searchBar: SearchBarView, didChangeQuery query: String)
    func searchBarDidPressArrowDown(_ searchBar: SearchBarView)
    func searchBarDidPressArrowUp(_ searchBar: SearchBarView)
    func searchBarDidPressEnter(_ searchBar: SearchBarView, isCommandPressed: Bool)
    func searchBarDidPressEscape(_ searchBar: SearchBarView)
    func searchBarDidPressCopyPath(_ searchBar: SearchBarView)
    func searchBarDidPressRevealInFinder(_ searchBar: SearchBarView)
    func searchBarDidRequestCycleFilter(_ searchBar: SearchBarView, forward: Bool)
    func searchBar(_ searchBar: SearchBarView, didRequestSelectFilterNumber number: Int)
    func searchBarDidRequestAutocompleteSyntax(_ searchBar: SearchBarView)
    func searchBarDidRequestRemoveSyntaxCapsule(_ searchBar: SearchBarView)
}

public final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override public func drawingRect(forBounds rect: NSRect) -> NSRect {
        let newRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let delta = (rect.height - textSize.height) / 2.0
        if delta > 0 {
            return NSRect(
                x: newRect.origin.x,
                y: newRect.origin.y + delta,
                width: newRect.width,
                height: newRect.height - delta
            )
        }
        return newRect
    }

    override public func titleRect(forBounds rect: NSRect) -> NSRect {
        return drawingRect(forBounds: rect)
    }

    override public func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        textObj.drawsBackground = false
        textObj.backgroundColor = .clear
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override public func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        textObj.drawsBackground = false
        textObj.backgroundColor = .clear
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

public final class SearchTextField: NSTextField {
    public weak var customDelegate: SearchBarDelegate?
    public weak var searchBarView: SearchBarView?

    override public class var cellClass: AnyClass? {
        get { VerticallyCenteredTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    // MARK: - Clipboard & Editing Support

    public private(set) var lastHandledPasteboardChangeCount: Int = -1

    public func pasteFromClipboard() {
        guard let parent = searchBarView ?? (superview as? SearchBarView) else { return }
        let pb = NSPasteboard.general
        lastHandledPasteboardChangeCount = pb.changeCount
        var textToPaste: String?

        if let str = pb.string(forType: .string), !str.isEmpty {
            textToPaste = str
        } else if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first {
            textToPaste = first.lastPathComponent
        }

        guard let text = textToPaste, !text.isEmpty else { return }

        let sanitized = text.replacingOccurrences(of: "\r\n", with: " ")
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "\r", with: " ")

        if let editor = currentEditor() as? NSTextView {
            editor.insertText(sanitized, replacementRange: editor.selectedRange)
        } else {
            window?.makeFirstResponder(self)
            if let editor = currentEditor() as? NSTextView {
                editor.insertText(sanitized, replacementRange: editor.selectedRange)
            } else {
                parent.text = sanitized
                parent.delegate?.searchBar(parent, didChangeQuery: sanitized)
            }
        }
    }

    /// 双保险兜底：若在搜索面板唤出期间剪贴板发生了新变动（如用户在外部 AuraSnap / Maccy 剪贴板中选定了条目），
    /// 且尚未被原生 ⌘V 或 pasteFromClipboard 处理过，进行安全单次填入
    @discardableResult
    public func pasteLatestFromClipboardIfNeeded(since initialCount: Int) -> Bool {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount > initialCount, currentCount != lastHandledPasteboardChangeCount else {
            return false
        }
        pasteFromClipboard()
        return true
    }

    @objc public func paste(_ sender: Any?) {
        pasteFromClipboard()
    }

    @objc public func copy(_ sender: Any?) {
        if let editor = currentEditor() as? NSTextView, editor.selectedRange.length > 0 {
            editor.copy(sender)
        } else if let parent = searchBarView ?? (superview as? SearchBarView) {
            customDelegate?.searchBarDidPressCopyPath(parent)
        }
    }

    @objc public func cut(_ sender: Any?) {
        if let editor = currentEditor() as? NSTextView, editor.selectedRange.length > 0 {
            editor.cut(sender)
        }
    }

    @objc override public func selectAll(_ sender: Any?) {
        if let editor = currentEditor() as? NSTextView {
            editor.selectAll(sender)
        } else {
            selectText(sender)
        }
    }

    override public func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "编辑")
        let cutItem = menu.addItem(withTitle: "剪切", action: #selector(cut(_:)), keyEquivalent: "x")
        let copyItem = menu.addItem(withTitle: "拷贝", action: #selector(copy(_:)), keyEquivalent: "c")
        let pasteItem = menu.addItem(withTitle: "粘贴", action: #selector(paste(_:)), keyEquivalent: "v")
        menu.addItem(.separator())
        let selectAllItem = menu.addItem(withTitle: "全选", action: #selector(selectAll(_:)), keyEquivalent: "a")

        cutItem.target = self
        copyItem.target = self
        pasteItem.target = self
        selectAllItem.target = self

        let hasSelection: Bool
        if let editor = currentEditor() as? NSTextView {
            hasSelection = editor.selectedRange.length > 0
        } else {
            hasSelection = false
        }
        cutItem.isEnabled = hasSelection
        copyItem.isEnabled = hasSelection || (searchBarView != nil)
        let pb = NSPasteboard.general
        pasteItem.isEnabled = pb.string(forType: .string)?.isEmpty == false || (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.isEmpty == false

        return menu
    }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        // If user is currently composing marked text in IME (e.g. typing Chinese pinyin), do not intercept
        if let editor = currentEditor() as? NSTextView, editor.hasMarkedText() {
            return super.performKeyEquivalent(with: event)
        }

        guard let parent = searchBarView ?? (superview as? SearchBarView) else {
            return super.performKeyEquivalent(with: event)
        }

        let isCmd = event.modifierFlags.contains(.command)
        let isOpt = event.modifierFlags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased()

        // 1. Command + R (在访达中显示)
        if isCmd && !isOpt && key == "r" {
            customDelegate?.searchBarDidPressRevealInFinder(parent)
            return true
        }

        // 2. Command + C 或 Option + Command + C (复制选中文本 或 复制选中文件路径)
        if isCmd && key == "c" {
            // 如果输入框有选中的文字且未按 Option，优先执行文本复制
            if let editor = currentEditor() as? NSTextView, editor.selectedRange.length > 0 && !isOpt {
                editor.copy(nil)
                return true
            }
            customDelegate?.searchBarDidPressCopyPath(parent)
            return true
        }

        // 3. Command + V (粘贴剪贴板内容/文件名为搜索词)
        if isCmd && !isOpt && key == "v" {
            pasteFromClipboard()
            return true
        }

        // 4. Command + A (全选输入框文本)
        if isCmd && !isOpt && key == "a" {
            selectAll(nil)
            return true
        }

        // 5. Command + X (剪切选中文本)
        if isCmd && !isOpt && key == "x" {
            cut(nil)
            return true
        }

        // 6. Command + Z / Shift + Command + Z (撤销 / 重做)
        if isCmd && !isOpt && key == "z" {
            let isShift = event.modifierFlags.contains(.shift)
            let um = (currentEditor() as? NSTextView)?.undoManager ?? undoManager
            if let um = um {
                if isShift {
                    if um.canRedo { um.redo(); return true }
                } else {
                    if um.canUndo { um.undo(); return true }
                }
            }
        }

        // 7. Tab / Shift + Tab (切换文件类型筛选 或 斜杠语法自动补全)
        if event.keyCode == 48 { // Tab
            let isShift = event.modifierFlags.contains(.shift)
            let currentText = parent.text.trimmingCharacters(in: .whitespaces)
            if !isShift && currentText.hasPrefix("/") && !currentText.contains(" ") {
                customDelegate?.searchBarDidRequestAutocompleteSyntax(parent)
                return true
            }
            customDelegate?.searchBarDidRequestCycleFilter(parent, forward: !isShift)
            return true
        }

        // 8. Command + 1~8 (快捷选择分类)
        if isCmd && !isOpt, let chars = event.charactersIgnoringModifiers, let num = Int(chars), (1...8).contains(num) {
            customDelegate?.searchBar(parent, didRequestSelectFilterNumber: num)
            return true
        }

        if event.keyCode == 125 { // Arrow Down
            customDelegate?.searchBarDidPressArrowDown(parent)
            return true
        } else if event.keyCode == 126 { // Arrow Up
            customDelegate?.searchBarDidPressArrowUp(parent)
            return true
        } else if event.keyCode == 36 || event.keyCode == 76 { // Enter / Numpad Enter
            let cmd = event.modifierFlags.contains(.command)
            customDelegate?.searchBarDidPressEnter(parent, isCommandPressed: cmd)
            return true
        } else if event.keyCode == 53 { // Escape
            customDelegate?.searchBarDidPressEscape(parent)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}


/// 现代 macOS 搜索框指令胶囊 Token 视图 (对齐图二：图标 + 标题 + 关闭小叉)
public final class SyntaxCapsuleView: NSView {
    public let iconImageView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    public let removeButton = NSButton()
    public var onRemove: (() -> Void)?

    private var isHovered: Bool = false {
        didSet { updateAppearance() }
    }
    private var trackingArea: NSTrackingArea?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        // 抗拉伸抗挤压优先级设为最高，保证胶囊尺寸严格紧凑贴合内容
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byClipping
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(titleLabel)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .inline
        removeButton.isBordered = false
        removeButton.image = ThumbnailPipeline.shared.symbolIcon(name: "xmark", pointSize: 8, weight: .bold)
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        removeButton.toolTip = "清除指令"
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 13),
            iconImageView.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            removeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 3),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 12),
            removeButton.heightAnchor.constraint(equalToConstant: 12)
        ])

        updateAppearance()
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    public func configure(with command: SearchSyntaxCommand) {
        iconImageView.image = ThumbnailPipeline.shared.symbolIcon(name: command.iconSymbolName, pointSize: 11, weight: .medium)
        titleLabel.stringValue = command.name
        updateAppearance()
    }

    public func updateAppearance() {
        let isDark = ConfigManager.shared.config.theme.isDark
        if isDark {
            layer?.backgroundColor = isHovered
                ? NSColor.white.withAlphaComponent(0.18).cgColor
                : NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
            titleLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
            iconImageView.contentTintColor = NSColor(white: 0.90, alpha: 1.0)
            removeButton.contentTintColor = isHovered ? NSColor.white : NSColor(white: 0.65, alpha: 1.0)
        } else {
            layer?.backgroundColor = isHovered
                ? NSColor.black.withAlphaComponent(0.09).cgColor
                : NSColor.black.withAlphaComponent(0.06).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.black.withAlphaComponent(0.10).cgColor
            titleLabel.textColor = NSColor(white: 0.15, alpha: 1.0)
            iconImageView.contentTintColor = NSColor(white: 0.25, alpha: 1.0)
            removeButton.contentTintColor = isHovered ? NSColor(white: 0.10, alpha: 1.0) : NSColor(white: 0.45, alpha: 1.0)
        }
    }
}

public final class SearchBarView: NSView, NSTextFieldDelegate {
    public weak var delegate: SearchBarDelegate? {
        didSet {
            textField.customDelegate = delegate
        }
    }

    private let iconImageView = NSImageView()
    public let syntaxCapsuleView = SyntaxCapsuleView()
    public let textField = SearchTextField()
    private let clearButton = NSButton()
    private let glassEffectView = LiquidGlassContainerView()
    private var trackingArea: NSTrackingArea?

    public private(set) var activeSyntaxCommand: SearchSyntaxCommand?

    private var textFieldLeadingToIconConstraint: NSLayoutConstraint!
    private var textFieldLeadingToCapsuleConstraint: NSLayoutConstraint!
    private var capsuleLeadingToIconConstraint: NSLayoutConstraint!

    private var isFocused: Bool = false {
        didSet {
            updateGlassTint()
            updateBackgroundStyles()
        }
    }
    private var isHovered: Bool = false {
        didSet {
            updateGlassTint()
            updateBackgroundStyles()
        }
    }

    /// When the search panel expands, the capsule's own glass and outline hand over to the
    /// results sheet, which starts exactly at the capsule's rect and grows downward — so the
    /// capsule appears to stretch into the sheet instead of sitting inside a second panel.
    public var isMergedIntoSheet: Bool = false {
        didSet {
            guard oldValue != isMergedIntoSheet else { return }
            updateGlassTint()
            updateBackgroundStyles()
        }
    }

    public var text: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            clearButton.isHidden = newValue.isEmpty
        }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: .atoolsThemeDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleThemeChanged() {
        updateGlassTint()
        updateBackgroundStyles()
        syntaxCapsuleView.updateAppearance()
        textField.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
        updatePlaceholder()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = false
        updateBackgroundStyles()

        // Native macOS 26 liquid-glass capsule behind the controls. The host
        // layer stays transparent so the glass shader is the only surface.
        glassEffectView.cornerRadius = 20
        glassEffectView.usesRegularGlass = true
        glassEffectView.softEdgeEnabled = false
        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassEffectView)
        updateGlassTint()

        // Icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.image = ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass", pointSize: 17, weight: .medium)
        iconImageView.contentTintColor = .secondaryLabelColor
        addSubview(iconImageView)

        // Syntax Capsule View (默认隐藏，挂载指令时显式展开)
        syntaxCapsuleView.isHidden = true
        syntaxCapsuleView.onRemove = { [weak self] in
            guard let self = self else { return }
            self.delegate?.searchBarDidRequestRemoveSyntaxCapsule(self)
        }
        addSubview(syntaxCapsuleView)

        // Text Field
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.drawsBackground = false
        if let textFieldCell = textField.cell as? NSTextFieldCell {
            textFieldCell.drawsBackground = false
            textFieldCell.backgroundColor = .clear
        }
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        textField.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
        updatePlaceholder()
        textField.delegate = self
        textField.customDelegate = nil
        textField.searchBarView = self
        textField.setAccessibilityLabel("搜索输入框")
        addSubview(textField)

        // Clear Button
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.image = ThumbnailPipeline.shared.symbolIcon(name: "xmark.circle.fill", pointSize: 15, weight: .medium)
        clearButton.contentTintColor = GlassPalette.textTertiary(isDark: glassIsDark)
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isHidden = true
        addSubview(clearButton)

        capsuleLeadingToIconConstraint = syntaxCapsuleView.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8)
        textFieldLeadingToCapsuleConstraint = textField.leadingAnchor.constraint(equalTo: syntaxCapsuleView.trailingAnchor, constant: 8)
        textFieldLeadingToIconConstraint = textField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10)

        NSLayoutConstraint.activate([
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassEffectView.topAnchor.constraint(equalTo: topAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            syntaxCapsuleView.centerYAnchor.constraint(equalTo: centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20),

            textFieldLeadingToIconConstraint,
            textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    public func setSyntaxCommand(_ command: SearchSyntaxCommand?) {
        activeSyntaxCommand = command
        if let command = command {
            syntaxCapsuleView.configure(with: command)
            syntaxCapsuleView.isHidden = false
            NSLayoutConstraint.deactivate([textFieldLeadingToIconConstraint])
            NSLayoutConstraint.activate([capsuleLeadingToIconConstraint, textFieldLeadingToCapsuleConstraint])
        } else {
            syntaxCapsuleView.isHidden = true
            NSLayoutConstraint.deactivate([capsuleLeadingToIconConstraint, textFieldLeadingToCapsuleConstraint])
            NSLayoutConstraint.activate([textFieldLeadingToIconConstraint])
        }
        updatePlaceholder()
    }

    private func updatePlaceholder() {
        let text = activeSyntaxCommand != nil ? "在 \(activeSyntaxCommand!.name) 中搜索..." : "搜索应用、全盘文件、计算或输入命令..."
        let isDark = glassIsDark
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: GlassPalette.textTertiary(isDark: isDark),
            .font: NSFont.systemFont(ofSize: 18, weight: .regular)
        ]
        textField.placeholderString = text
        textField.placeholderAttributedString = NSAttributedString(string: text, attributes: attrs)
    }

    private func updateBackgroundStyles() {
        let isDark = glassIsDark

        // The native glass view carries the surface; the host layer stays clear
        // so the liquid blur is the only visible material.
        layer?.backgroundColor = NSColor.clear.cgColor

        if isMergedIntoSheet {
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
            iconImageView.contentTintColor = GlassPalette.textSecondary(isDark: isDark)
            return
        }

        if isFocused {
            layer?.borderWidth = 0.75
            layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
            layer?.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
            layer?.shadowOpacity = 0.20
            layer?.shadowRadius = 12
            layer?.shadowOffset = CGSize(width: 0, height: 5)
            iconImageView.contentTintColor = GlassPalette.textPrimary(isDark: isDark)
            return
        }

        layer?.borderWidth = 0.75
        layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
        layer?.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
        layer?.shadowOpacity = isHovered ? 0.16 : 0.10
        layer?.shadowRadius = isHovered ? 10 : 8
        layer?.shadowOffset = CGSize(width: 0, height: isHovered ? 4 : 3)
        iconImageView.contentTintColor = GlassPalette.textSecondary(isDark: isDark)
    }

    /// Keep the search capsule's glass tint in sync with the active theme so
    /// the light theme stays a bright white surface and the dark theme keeps
    /// its deep liquid look.
    private func updateGlassTint() {
        let profile = SearchGlassSurfaceProfile.resolved(
            isDark: glassIsDark,
            isEmphasized: isFocused || isHovered,
            themeOpacity: ConfigManager.shared.config.themeOpacity
        )
        glassEffectView.tintColor = profile.tintColor
        glassEffectView.tintOpacity = profile.tintOpacity
        glassEffectView.alphaValue = isMergedIntoSheet ? 0 : profile.surfaceAlpha
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlassTint()
        updateBackgroundStyles()
        textField.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
    }

    public func controlTextDidChange(_ obj: Notification) {
        let currentText = textField.stringValue
        clearButton.isHidden = currentText.isEmpty
        delegate?.searchBar(self, didChangeQuery: currentText)
    }

    public func controlTextDidBeginEditing(_ obj: Notification) {
        if let editor = textField.currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
        }
        isFocused = true
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        isFocused = false
    }

    @objc private func clearClicked() {
        text = ""
        delegate?.searchBar(self, didChangeQuery: "")
        window?.makeFirstResponder(textField)
    }

    public func focus() {
        window?.makeFirstResponder(textField)
    }
}
