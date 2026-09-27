import AppKit

/// Overlay scroller that keeps the system knob and suppresses only the track slot.
///
/// AppKit exposes the knob and slot as separate drawing hooks so overlay
/// scrollers can fade them independently. Leaving the event hooks untouched
/// preserves dragging, page clicks, and normal scrolling behavior.
final class KnobOnlyScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Intentionally empty: the knob is still drawn by AppKit's drawKnob.
    }
}
