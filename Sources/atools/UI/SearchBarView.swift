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
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override public func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
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
        layer?.cornerRadius = 10
        updateBackgroundStyles()

        // Icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.image = ThumbnailPipeline.shared.symbolIcon(name: "magnifyingglass", pointSize: 17, weight: .medium)
        iconImageView.contentTintColor = .secondaryLabelColor
        addSubview(iconImageView)

        // Text Field
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        textField.placeholderString = "搜索应用、全盘文件、计算或输入命令..."
        textField.delegate = self
        textField.customDelegate = nil
        textField.searchBarView = self
        addSubview(textField)

        // Clear Button
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.image = ThumbnailPipeline.shared.symbolIcon(name: "xmark.circle.fill", pointSize: 15, weight: .medium)
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
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
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.04).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(white: 0.0, alpha: 0.07).cgColor
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundStyles()
    }

    public func controlTextDidChange(_ obj: Notification) {
        let currentText = textField.stringValue
        runtimeLog("[SearchBarView] controlTextDidChange: '\(currentText)'")
        clearButton.isHidden = currentText.isEmpty
        delegate?.searchBar(self, didChangeQuery: currentText)
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
