import AppKit

/// Modern liquid-glass floating capsule scroller.
///
/// Suppresses track slot, borders, and legacy grooves entirely ("外面一圈").
/// Renders an ultra-sleek, standalone rounded capsule knob with dynamic theme tint,
/// supporting hover and drag states while preserving overlay auto-fade and mouse dragging.
public class KnobOnlyScroller: NSScroller {
    override public class var isCompatibleWithOverlayScrollers: Bool { true }

    override public var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override public var isOpaque: Bool { false }

    override public func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Intentionally empty: suppress all track slots, background grooves, and borders
    }

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }

    private var isDragging = false {
        didSet {
            if oldValue != isDragging {
                needsDisplay = true
            }
        }
    }

    private var trackingArea: NSTrackingArea?

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
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

    override public func mouseDown(with event: NSEvent) {
        isDragging = true
        super.mouseDown(with: event)
    }

    override public func mouseUp(with event: NSEvent) {
        isDragging = false
        super.mouseUp(with: event)
    }

    private var isDarkMode: Bool {
        if let win = window {
            let app = win.appearance ?? win.effectiveAppearance
            if let match = app.bestMatch(from: [.darkAqua, .aqua]) {
                return match == .darkAqua
            }
        }
        return ConfigManager.shared.config.theme.isDark
    }

    override public func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override public func drawKnob() {
        guard knobProportion > 0 && knobProportion < 1 else { return }

        let isVert = bounds.height >= bounds.width
        let r = rect(for: .knob)
        let active = isHovered || isDragging
        let dark = isDarkMode

        let knobColor: NSColor
        if dark {
            knobColor = NSColor(white: 1.0, alpha: active ? 0.55 : 0.28)
        } else {
            knobColor = NSColor(white: 0.12, alpha: active ? 0.45 : 0.22)
        }

        let path: NSBezierPath
        if isVert {
            let knobW: CGFloat = 4.5
            let margin: CGFloat = 2.0
            let minH: CGFloat = 22.0
            let h = max(r.height, minH)
            let available = max(0, bounds.height - h - margin * 2)
            let y = margin + CGFloat(doubleValue) * available
            let x = bounds.width - knobW - margin
            let knobRect = NSRect(x: x, y: y, width: knobW, height: h)
            path = NSBezierPath(roundedRect: knobRect, xRadius: knobW / 2, yRadius: knobW / 2)
        } else {
            let knobH: CGFloat = 2.5
            let margin: CGFloat = 1.0
            let minW: CGFloat = 24.0
            let w = max(r.width, minW)
            let available = max(0, bounds.width - w - margin * 2)
            let x = margin + CGFloat(doubleValue) * available
            let y = bounds.height - knobH - margin
            let knobRect = NSRect(x: x, y: y, width: w, height: knobH)
            path = NSBezierPath(roundedRect: knobRect, xRadius: knobH / 2, yRadius: knobH / 2)
        }

        knobColor.setFill()
        path.fill()
    }
}

/// A modern overlay-locked NSScrollView that suppresses legacy layout shrinkage,
/// keeping full content bounds while displaying sleek floating capsule scrollers.
public class ModernScrollView: NSScrollView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureDefaults()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDefaults()
    }

    private func configureDefaults() {
        scrollerStyle = .overlay
        autohidesScrollers = true
        drawsBackground = false
        backgroundColor = .clear
        contentView.drawsBackground = false
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override public var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override public var hasVerticalScroller: Bool {
        didSet {
            if hasVerticalScroller && !(verticalScroller is KnobOnlyScroller) {
                verticalScroller = KnobOnlyScroller()
            }
        }
    }

    override public var hasHorizontalScroller: Bool {
        didSet {
            if hasHorizontalScroller && !(horizontalScroller is KnobOnlyScroller) {
                horizontalScroller = KnobOnlyScroller()
            }
        }
    }

    override public func tile() {
        super.tile()
        // Ensure contentView is never compressed by legacy scrollbar space reservation
        contentView.frame = bounds
        if let vs = verticalScroller {
            let w: CGFloat = 8
            vs.frame = NSRect(x: max(0, bounds.width - w), y: 0, width: min(w, bounds.width), height: bounds.height)
        }
        if let hs = horizontalScroller {
            let h: CGFloat = 5
            hs.frame = NSRect(x: 0, y: max(0, bounds.height - h), width: bounds.width, height: min(h, bounds.height))
        }
    }
}
