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

        // 2. Command + C 或 Option + Command + C (复制文件路径)
        if isCmd && key == "c" {
            // 如果输入框有选中的文字且未按 Option，优先执行文本复制
            if let editor = currentEditor() as? NSTextView, editor.selectedRange.length > 0 && !isOpt {
                return super.performKeyEquivalent(with: event)
            }
            customDelegate?.searchBarDidPressCopyPath(parent)
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


public final class SearchBarView: NSView, NSTextFieldDelegate {
    public weak var delegate: SearchBarDelegate? {
        didSet {
            textField.customDelegate = delegate
        }
    }

    private let iconImageView = NSImageView()
    public let textField = SearchTextField()
    private let clearButton = NSButton()
    private let glassEffectView = LiquidGlassContainerView()
    private var trackingArea: NSTrackingArea?
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
            glassEffectView.alphaValue = isMergedIntoSheet ? 0 : 1
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        textField.placeholderString = "搜索应用、全盘文件、计算或输入命令..."
        textField.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
        textField.delegate = self
        textField.customDelegate = nil
        textField.searchBarView = self
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

        NSLayoutConstraint.activate([
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassEffectView.topAnchor.constraint(equalTo: topAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20),

            textField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 32)
        ])
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
        if glassIsDark {
            glassEffectView.tintColor = GlassPalette.darkBaseTop
            glassEffectView.tintOpacity = (isFocused || isHovered) ? 0.82 : 0.76
        } else {
            glassEffectView.tintColor = GlassPalette.lightGlassTint
            glassEffectView.tintOpacity = (isFocused || isHovered) ? 0.66 : 0.58
        }
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
