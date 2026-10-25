import Foundation
import AppKit

final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

func makeTabScrollView(contentView: NSView) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let flipped = FlippedContainerView()
    flipped.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = flipped

    flipped.addSubview(contentView)
    contentView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        flipped.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        flipped.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        flipped.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        flipped.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

        contentView.topAnchor.constraint(equalTo: flipped.topAnchor),
        contentView.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
        contentView.bottomAnchor.constraint(equalTo: flipped.bottomAnchor)
    ])

    return scrollView
}

func makeSectionHeader(title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
    label.textColor = .labelColor
    return label
}

