import Foundation
import AppKit

public final class CategoryInputDialog: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(labelWithString: "")
    private let inputContainer = LiquidInputContainerView()
    private let inputBackdrop = NativeLiquidSelectionBackdrop(cornerRadius: 17)
    private let textField = NSTextField()
    private let cancelButton = NSButton()
    private let confirmButton = NSButton()

    private var onCompletion: ((String?) -> Void)?
    private static var activeDialogs: [CategoryInputDialog] = []

    public static func prompt(
        title: String,
        prompt: String,
        placeholder: String = "",
        initialValue: String = "",
        confirmTitle: String = "确定",
        in parentWindow: NSWindow? = nil,
        completion: @escaping (String?) -> Void
    ) {
        let dialog = CategoryInputDialog(
            titleText: title,
            promptText: prompt,
            placeholder: placeholder,
            initialValue: initialValue,
            confirmTitle: confirmTitle
        )
        dialog.onCompletion = completion

        guard let win = dialog.window else {
            completion(nil)
            return
        }

        activeDialogs.append(dialog)
        if let parent = parentWindow {
            let pFrame = parent.frame
            let x = pFrame.origin.x + (pFrame.width - win.frame.width) / 2
            let y = pFrame.origin.y + (pFrame.height - win.frame.height) / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            win.center()
        }

        win.runModalAboveFloatingWindows()
        dialog.finish(with: nil)
    }

    public init(
        titleText: String,
        promptText: String,
        placeholder: String,
        initialValue: String,
        confirmTitle: String
    ) {
        let contentRect = NSRect(x: 0, y: 0, width: 340, height: 172)
        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.isMovableByWindowBackground = true

        super.init(window: win)
        window?.delegate = self

        setupUI(
            titleText: titleText,
            promptText: promptText,
            placeholder: placeholder,
            initialValue: initialValue,
            confirmTitle: confirmTitle
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(
        titleText: String,
        promptText: String,
        placeholder: String,
        initialValue: String,
        confirmTitle: String
    ) {
        guard let contentView = window?.contentView else { return }

        // Container view
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        // Title (Bold 14pt, zero icon)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = titleText
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // Prompt
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.stringValue = promptText
        promptLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        promptLabel.textColor = .secondaryLabelColor
        container.addSubview(promptLabel)

        // 🌟 原生液态水滴输入框容器 (Native Liquid Capsule Container)
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.wantsLayer = true
        inputContainer.layer?.masksToBounds = false
        inputContainer.onMouseDown = { [weak self] in
            guard let self = self, let win = self.window else { return }
            win.makeFirstResponder(self.textField)
        }
        container.addSubview(inputContainer)

        // 🌟 原生液态玻璃底层水滴透镜 (Apple .glassEffect + 顶部天光 + 360°发丝高光切边)
        inputBackdrop.translatesAutoresizingMaskIntoConstraints = false
        inputBackdrop.cornerRadius = 17
        inputBackdrop.isSelected = true // 保持微晶莹通透水滴表面张力
        inputContainer.addSubview(inputBackdrop)

        // Text field (居中、无系统方框、无刺眼外框)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.drawsBackground = false
        if let cell = textField.cell as? NSTextFieldCell {
            cell.drawsBackground = false
            cell.backgroundColor = .clear
        }
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textField.alignment = .center // 🌟 水平正中间对齐
        textField.stringValue = initialValue
        textField.target = self
        textField.action = #selector(confirmClicked)
        textField.delegate = self
        inputContainer.addSubview(textField)

        updateColors(placeholder: placeholder)

        // Cancel button
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.title = "取消"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}" // Esc key
        container.addSubview(cancelButton)

        // Confirm button
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.title = confirmTitle
        confirmButton.bezelStyle = .rounded
        confirmButton.target = self
        confirmButton.action = #selector(confirmClicked)
        confirmButton.keyEquivalent = "\r" // Enter key
        confirmButton.bezelColor = GlassPalette.accentText(isDark: confirmButton.glassIsDark)
        container.addSubview(confirmButton)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            promptLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            promptLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            promptLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // 液态胶囊输入框外框
            inputContainer.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 12),
            inputContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 34),

            // 液态底衬填满胶囊
            inputBackdrop.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            inputBackdrop.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            inputBackdrop.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            inputBackdrop.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),

            // 输入框居中排列，留足左右 14pt 呼吸间距
            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -14),
            textField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),

            confirmButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            confirmButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        window?.initialFirstResponder = textField
    }

    private func updateColors(placeholder: String) {
        guard let win = window else { return }
        let isDark = win.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        inputBackdrop.isDark = isDark
        textField.textColor = GlassPalette.textPrimary(isDark: isDark)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: GlassPalette.textTertiary(isDark: isDark),
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .paragraphStyle: paragraph
        ]
        textField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: attrs)
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        if let ph = textField.placeholderAttributedString?.string {
            updateColors(placeholder: ph)
        }
    }

    @objc private func cancelClicked() {
        finish(with: nil)
    }

    @objc private func confirmClicked() {
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(with: text)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(with: nil)
        return true
    }

    private func finish(with value: String?) {
        guard let completion = onCompletion else { return }
        onCompletion = nil

        if let window = window {
            if let parent = window.sheetParent {
                parent.endSheet(window, returnCode: value == nil ? .cancel : .OK)
            } else if NSApp.modalWindow === window {
                NSApp.stopModal(withCode: value == nil ? .cancel : .OK)
            }
            window.orderOut(nil)
        }

        Self.activeDialogs.removeAll { $0 === self }
        completion(value)
    }
}

/// 🌟 原生液态输入框点击穿透与自动对焦交互容器
private final class LiquidInputContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }
}
