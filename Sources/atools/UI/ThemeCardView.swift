import Foundation
import AppKit

public final class ThemeCardView: NSView {
    public let theme: AppTheme
    public var isSelected: Bool {
        didSet {
            updateStyles()
        }
    }
    public var onClick: ((AppTheme) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let checkmarkImageView = NSImageView()
    private let previewBox = NSView()
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false {
        didSet { updateStyles() }
    }

    override public var mouseDownCanMoveWindow: Bool { false }

    public init(theme: AppTheme, isSelected: Bool = false) {
        self.theme = theme
        self.isSelected = isSelected
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        
        // Subtle shadow for depth
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        layer?.shadowRadius = 3
        layer?.shadowOpacity = 1.0

        // Preview Mockup Box
        previewBox.wantsLayer = true
        previewBox.layer?.cornerRadius = 6
        previewBox.layer?.masksToBounds = true
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewBox)

        setupPreviewMockup()

        // Title Label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = theme.title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        // Checkmark badge in top-right
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.image = ThumbnailPipeline.shared.symbolIcon(name: "checkmark.circle.fill", pointSize: 14, weight: .bold)
        checkmarkImageView.contentTintColor = GlassPalette.textPrimary(isDark: glassIsDark)
        addSubview(checkmarkImageView)

        NSLayoutConstraint.activate([
            // Width comes from the settings row's fill-equally stack (two themes share the row).
            widthAnchor.constraint(greaterThanOrEqualToConstant: 114),
            heightAnchor.constraint(equalToConstant: 88),

            previewBox.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            previewBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            previewBox.heightAnchor.constraint(equalToConstant: 50),

            titleLabel.topAnchor.constraint(equalTo: previewBox.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            checkmarkImageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            checkmarkImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 16),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateStyles()
    }

    private func setupPreviewMockup() {
        let isDark = theme.isDark
        previewBox.layer?.backgroundColor = (isDark
            ? NSColor(white: 0.10, alpha: 1.0)
            : NSColor(white: 0.88, alpha: 1.0)).cgColor
        previewBox.layer?.borderWidth = 0.5
        previewBox.layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)).cgColor

        let winView = NSView(frame: NSRect(x: 0, y: 0, width: 70, height: 36))
        winView.translatesAutoresizingMaskIntoConstraints = false
        winView.wantsLayer = true
        winView.layer?.cornerRadius = 5
        winView.layer?.borderWidth = 0.75
        winView.layer?.backgroundColor = (isDark
            ? NSColor(white: 0.16, alpha: 0.90)
            : NSColor(white: 0.97, alpha: 0.90)).cgColor
        winView.layer?.borderColor = (isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.12)).cgColor
        
        // Subtle shadow for the window mockup
        winView.layer?.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.3 : 0.1).cgColor
        winView.layer?.shadowOffset = CGSize(width: 0, height: 1)
        winView.layer?.shadowRadius = 2
        winView.layer?.shadowOpacity = 1.0
        previewBox.addSubview(winView)
        NSLayoutConstraint.activate([
            winView.centerXAnchor.constraint(equalTo: previewBox.centerXAnchor),
            winView.centerYAnchor.constraint(equalTo: previewBox.centerYAnchor),
            winView.widthAnchor.constraint(equalToConstant: 70),
            winView.heightAnchor.constraint(equalToConstant: 36)
        ])
        addWindowDetails(to: winView, isDark: isDark)
    }

    private func addWindowDetails(to win: NSView, isDark: Bool) {
        // Compact selection pill
        let accent = NSView(frame: NSRect(x: 5, y: 22, width: 14, height: 4))
        accent.wantsLayer = true
        accent.layer?.cornerRadius = 2
        accent.layer?.backgroundColor = (isDark ? NSColor.white.withAlphaComponent(0.72) : NSColor.black.withAlphaComponent(0.58)).cgColor
        win.addSubview(accent)

        // Line 1
        let line1 = NSView(frame: NSRect(x: 23, y: 22, width: 38, height: 3))
        line1.wantsLayer = true
        line1.layer?.cornerRadius = 1.5
        line1.layer?.backgroundColor = isDark ? NSColor(white: 1.0, alpha: 0.35).cgColor : NSColor(white: 0.0, alpha: 0.25).cgColor
        win.addSubview(line1)

        // Line 2
        let line2 = NSView(frame: NSRect(x: 5, y: 12, width: 10, height: 3))
        line2.wantsLayer = true
        line2.layer?.cornerRadius = 1.5
        line2.layer?.backgroundColor = isDark ? NSColor(white: 1.0, alpha: 0.20).cgColor : NSColor(white: 0.0, alpha: 0.15).cgColor
        win.addSubview(line2)

        // Line 3
        let line3 = NSView(frame: NSRect(x: 23, y: 12, width: 28, height: 3))
        line3.wantsLayer = true
        line3.layer?.cornerRadius = 1.5
        line3.layer?.backgroundColor = isDark ? NSColor(white: 1.0, alpha: 0.20).cgColor : NSColor(white: 0.0, alpha: 0.15).cgColor
        win.addSubview(line3)
    }

    private func updateStyles() {
        let isSysDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        checkmarkImageView.isHidden = !isSelected

        if isSelected {
            layer?.borderWidth = 1.5
            layer?.borderColor = (isSysDark
                ? NSColor.white.withAlphaComponent(0.25)
                : NSColor.black.withAlphaComponent(0.15)).cgColor
            layer?.backgroundColor = GlassPalette.accentFill(isDark: isSysDark).cgColor
            layer?.shadowRadius = 4
            layer?.shadowColor = NSColor.black.withAlphaComponent(isSysDark ? 0.2 : 0.1).cgColor
            titleLabel.textColor = GlassPalette.textPrimary(isDark: isSysDark)
            titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        } else {
            layer?.borderWidth = 1.0
            layer?.borderColor = (isSysDark
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.06)).cgColor
            layer?.backgroundColor = isHovered
                ? (isSysDark ? NSColor(white: 1.0, alpha: 0.06).cgColor : NSColor(white: 0.0, alpha: 0.04).cgColor)
                : (isSysDark ? NSColor(white: 1.0, alpha: 0.03).cgColor : NSColor(white: 0.0, alpha: 0.02).cgColor)
            layer?.shadowRadius = 3
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.08).cgColor
            titleLabel.textColor = .labelColor
            titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyles()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override public func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override public func mouseDown(with event: NSEvent) {
        onClick?(theme)
    }
}
