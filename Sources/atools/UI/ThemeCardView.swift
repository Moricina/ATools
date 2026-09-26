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
        checkmarkImageView.contentTintColor = .controlAccentColor
        addSubview(checkmarkImageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 114),
            heightAnchor.constraint(equalToConstant: 88),

            previewBox.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            previewBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            previewBox.heightAnchor.constraint(equalToConstant: 48),

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
        // Gradient / Background for mockup
        let isDark = theme.isDark
        let isLiquid = theme.isLiquid

        if isLiquid {
            // Blue/gold wallpaper background like macOS Sonoma
            let bgLayer = CAGradientLayer()
            bgLayer.frame = CGRect(x: 0, y: 0, width: 98, height: 48)
            if isDark {
                bgLayer.colors = [
                    NSColor(red: 0.12, green: 0.20, blue: 0.38, alpha: 1.0).cgColor,
                    NSColor(red: 0.28, green: 0.22, blue: 0.15, alpha: 1.0).cgColor,
                    NSColor(red: 0.08, green: 0.15, blue: 0.32, alpha: 1.0).cgColor
                ]
            } else {
                bgLayer.colors = [
                    NSColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1.0).cgColor,
                    NSColor(red: 0.85, green: 0.70, blue: 0.45, alpha: 1.0).cgColor,
                    NSColor(red: 0.25, green: 0.50, blue: 0.85, alpha: 1.0).cgColor
                ]
            }
            bgLayer.startPoint = CGPoint(x: 0, y: 0)
            bgLayer.endPoint = CGPoint(x: 1, y: 1)
            previewBox.layer?.addSublayer(bgLayer)

            // Miniature window in center
            let winView = NSView(frame: NSRect(x: 14, y: 6, width: 70, height: 36))
            winView.wantsLayer = true
            winView.layer?.cornerRadius = 5
            winView.layer?.borderWidth = 0.5
            if isDark {
                winView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.82).cgColor
                winView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
            } else {
                winView.layer?.backgroundColor = NSColor(white: 0.96, alpha: 0.82).cgColor
                winView.layer?.borderColor = NSColor(white: 0.0, alpha: 0.15).cgColor
            }
            previewBox.addSubview(winView)
            addWindowDetails(to: winView, isDark: isDark)
        } else {
            // Solid wallpaper background
            previewBox.layer?.backgroundColor = isDark
                ? NSColor(white: 0.18, alpha: 1.0).cgColor
                : NSColor(white: 0.88, alpha: 1.0).cgColor

            // Miniature solid window
            let winView = NSView(frame: NSRect(x: 14, y: 6, width: 70, height: 36))
            winView.wantsLayer = true
            winView.layer?.cornerRadius = 5
            winView.layer?.borderWidth = 0.5
            if isDark {
                winView.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor
                winView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
            } else {
                winView.layer?.backgroundColor = NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0).cgColor
                winView.layer?.borderColor = NSColor(white: 0.0, alpha: 0.12).cgColor
            }
            previewBox.addSubview(winView)
            addWindowDetails(to: winView, isDark: isDark)
        }
    }

    private func addWindowDetails(to win: NSView, isDark: Bool) {
        // Accent blue pill / sidebar
        let accent = NSView(frame: NSRect(x: 5, y: 22, width: 14, height: 4))
        accent.wantsLayer = true
        accent.layer?.cornerRadius = 2
        accent.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
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
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isSysDark ? 0.18 : 0.10).cgColor
            titleLabel.textColor = .controlAccentColor
            titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        } else {
            layer?.borderWidth = 0.5
            layer?.borderColor = isSysDark ? NSColor(white: 1.0, alpha: 0.12).cgColor : NSColor(white: 0.0, alpha: 0.12).cgColor
            layer?.backgroundColor = isHovered
                ? (isSysDark ? NSColor(white: 1.0, alpha: 0.06).cgColor : NSColor(white: 0.0, alpha: 0.04).cgColor)
                : NSColor.clear.cgColor
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
