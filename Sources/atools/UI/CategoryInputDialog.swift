import Foundation
import AppKit

public final class CategoryInputDialog: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(labelWithString: "")
    private let textField = NSTextField()
    private let cancelButton = NSButton()
    private let confirmButton = NSButton()

    private var onCompletion: ((String?) -> Void)?

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

        win.center()
        let session = NSApp.beginModalSession(for: win)
        while NSApp.runModalSession(session) == .continue {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        NSApp.endModalSession(session)
    }

    private init(
        titleText: String,
        promptText: String,
        placeholder: String,
        initialValue: String,
        confirmTitle: String
    ) {
        let contentRect = NSRect(x: 0, y: 0, width: 340, height: 160)
        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)

        super.init(window: win)

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

        // Text field
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = placeholder
        textField.stringValue = initialValue
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.focusRingType = .exterior
        textField.target = self
        textField.action = #selector(confirmClicked)
        container.addSubview(textField)

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

            textField.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 12),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textField.heightAnchor.constraint(equalToConstant: 26),

            confirmButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            confirmButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        window?.initialFirstResponder = textField
    }

    @objc private func cancelClicked() {
        window?.orderOut(nil)
        NSApp.stopModal(withCode: .cancel)
        onCompletion?(nil)
    }

    @objc private func confirmClicked() {
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        window?.orderOut(nil)
        NSApp.stopModal(withCode: .OK)
        onCompletion?(text)
    }
}
