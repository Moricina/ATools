import Foundation
import AppKit

public protocol CategoryBarDelegate: AnyObject {
    func categoryBar(_ bar: CategoryBarView, didSelectCategory category: Category)
    func categoryBarDidRequestAddCategory(_ bar: CategoryBarView)
    func categoryBar(_ bar: CategoryBarView, didRequestRenameCategory category: Category)
    func categoryBar(_ bar: CategoryBarView, didRequestDeleteCategory category: Category)
    func categoryBar(_ bar: CategoryBarView, didMoveCategoryFrom fromIndex: Int, to toIndex: Int)
    func categoryBar(_ bar: CategoryBarView, didMoveLauncherItem item: LauncherItem, to category: Category)
    func categoryBar(_ bar: CategoryBarView, didAddPaths paths: [String], to category: Category)
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// A single flowing liquid-glass capsule that slides between category pills.
/// It is the shared "selected" element: the pill text stays put while this
/// capsule glides from the old pill to the new one on selection change.
///
/// The capsule uses the same regular liquid-glass material as the drawer
/// backdrop. Only this compact selected-state frame remains; the category
/// container itself stays transparent.
private final class SelectionCapsuleView: NSView {
    private let glass = LiquidGlassContainerView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        glass.usesRegularGlass = true
        glass.softEdgeEnabled = false
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateColors() {
        let isDark = glassIsDark
        // Keep the selected capsule on exactly the same glass recipe as the
        // drawer backdrop; the compact shape alone provides the selection cue.
        if isDark {
            glass.tintColor = GlassPalette.darkBaseTop
            glass.tintOpacity = 0.72
        } else {
            glass.tintColor = GlassPalette.lightGlassTint
            glass.tintOpacity = 0.48
        }
    }

    func updateCornerRadius(_ radius: CGFloat) {
        glass.cornerRadius = radius
    }
}

public final class CategoryBarView: NSView, CategoryPillDelegate {
    public weak var delegate: CategoryBarDelegate?

    public var orientation: CategoryOrientation = .horizontal {
        didSet {
            if oldValue != orientation {
                updateOrientation()
            }
        }
    }

    private var categories: [Category] = []
    private var selectedCategoryId: UUID?
    private let stackView = FlippedStackView()
    private let scrollView = NSScrollView()
    private let selectionCapsule = SelectionCapsuleView()
    private var stackViewConstraints: [NSLayoutConstraint] = []
    private weak var selectedPill: CategoryPillView?

    override public var isFlipped: Bool { return true }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(AppConstants.categoryReorderType),
            NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType),
            .fileURL
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.layer?.borderWidth = 0

        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView
        // The flowing capsule sits below every pill so only its text remains
        // above it, giving the shared-element glide a clean silhouette.
        stackView.addSubview(selectionCapsule, positioned: .below, relativeTo: nil)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateOrientation()
    }

    private func updateOrientation() {
        NSLayoutConstraint.deactivate(stackViewConstraints)
        stackViewConstraints.removeAll()

        if orientation == .horizontal {
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = false
            stackView.orientation = .horizontal
            stackView.spacing = 6
            stackView.alignment = .centerY

            stackViewConstraints = [
                stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 4),
                stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 2),
                stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor, constant: -2),
                stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -4)
            ]
        } else {
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = true
            stackView.orientation = .vertical
            stackView.spacing = 5
            stackView.alignment = .width

            stackViewConstraints = [
                stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 3),
                stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -3),
                stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 4),
                stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -6)
            ]
        }
        NSLayoutConstraint.activate(stackViewConstraints)

        if !categories.isEmpty {
            reloadData(categories: categories, selectedId: selectedCategoryId)
        }
    }

    public func reloadData(categories: [Category], selectedId: UUID?) {
        self.categories = categories
        self.selectedCategoryId = selectedId ?? categories.first?.id

        for sub in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        for cat in categories {
            let pill = CategoryPillView(category: cat, isSelected: cat.id == self.selectedCategoryId, isVertical: orientation == .vertical)
            pill.delegate = self
            stackView.addArrangedSubview(pill)
            if orientation == .vertical {
                pill.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            }
        }

        // Pin the flowing capsule underneath the arranged pills and align it to
        // the currently selected pill without animation on initial layout.
        selectedPill = stackView.arrangedSubviews.first(where: { ($0 as? CategoryPillView)?.isSelected == true }) as? CategoryPillView
        // Pills were just inserted; without a layout pass their frames are still .zero.
        stackView.layoutSubtreeIfNeeded()
        layoutSelectionCapsule(animated: false)
        scrollSelectedPillIntoView(animated: false)
    }

    private func layoutSelectionCapsule(animated: Bool) {
        guard let pill = selectedPill else {
            selectionCapsule.isHidden = true
            return
        }
        selectionCapsule.isHidden = false
        selectionCapsule.updateCornerRadius(pill.layer?.cornerRadius ?? 15)
        selectionCapsule.updateColors()

        let target = pill.convert(pill.bounds, to: stackView)
        if animated {
            // Flow like a liquid: slide and stretch toward the new pill with a
            // soft, slightly-overshooting ease-out so it reads as inertia.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                ctx.allowsImplicitAnimation = true
                selectionCapsule.animator().frame = target
            }
        } else {
            selectionCapsule.frame = target
        }
    }

    override public func layout() {
        super.layout()
        // Don't cut a running glide short; the animation already targets the final frame.
        if !selectionCapsule.isHidden, selectionCapsule.layer?.animationKeys()?.isEmpty ?? true {
            layoutSelectionCapsule(animated: false)
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        selectionCapsule.updateColors()
    }

    // MARK: - Right Click on CategoryBarView (Blank Area)
    override public func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "CategoryBarMenu")
        let addItem = NSMenuItem(title: "新建分类...", action: #selector(contextAddCategory), keyEquivalent: "")
        addItem.image = ThumbnailPipeline.shared.symbolIcon(name: "plus", pointSize: 13)
        addItem.target = self
        menu.addItem(addItem)

        menu.addItem(NSMenuItem.separator())
        let isPinned = PanelCoordinator.shared.isShelfPinned
        let pinItem = NSMenuItem(
            title: isPinned ? "✓ 固定在桌面" : "固定在桌面",
            action: #selector(contextTogglePin),
            keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: ",")
        settingsItem.image = ThumbnailPipeline.shared.symbolIcon(name: "gearshape", pointSize: 13)
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        let closeItem = NSMenuItem(title: "关闭抽屉", action: #selector(contextCloseShelf), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextAddCategory() {
        delegate?.categoryBarDidRequestAddCategory(self)
    }

    @objc private func contextTogglePin() {
        PanelCoordinator.shared.isShelfPinned.toggle()
    }

    @objc private func contextOpenSettings() {
        SettingsWindowController.shared.showSettingsWindow()
    }

    @objc private func contextCloseShelf() {
        PanelCoordinator.shared.hideAllPanels()
    }

    // MARK: - CategoryPillDelegate
    public func categoryPillDidClick(_ pill: CategoryPillView) {
        self.selectedCategoryId = pill.category.id
        for view in stackView.arrangedSubviews {
            if let p = view as? CategoryPillView {
                p.isSelected = (p.category.id == pill.category.id)
            }
        }
        selectedPill = pill
        // Resolve pending pill layout first so the capsule glides to the final frame.
        stackView.layoutSubtreeIfNeeded()
        layoutSelectionCapsule(animated: true)
        scrollSelectedPillIntoView(animated: true)
        delegate?.categoryBar(self, didSelectCategory: pill.category)
    }

    /// Move the keyboard selection by one pill in the current orientation.
    @discardableResult
    public func moveSelection(by offset: Int) -> Bool {
        let pills = stackView.arrangedSubviews.compactMap { $0 as? CategoryPillView }
        guard !pills.isEmpty else { return false }
        let currentIndex = pills.firstIndex(where: { $0 === selectedPill }) ?? pills.firstIndex(where: { $0.isSelected }) ?? 0
        let targetIndex = max(0, min(pills.count - 1, currentIndex + offset))
        guard targetIndex != currentIndex else { return false }
        categoryPillDidClick(pills[targetIndex])
        return true
    }

    private func scrollSelectedPillIntoView(animated: Bool) {
        guard let pill = selectedPill else { return }
        stackView.layoutSubtreeIfNeeded()
        let target = pill.convert(pill.bounds, to: stackView)
        let visible = scrollView.contentView.bounds
        guard visible.intersects(target) == false else { return }
        let action = {
            _ = self.scrollView.contentView.scrollToVisible(target)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.allowsImplicitAnimation = true
                action()
            }
        } else {
            action()
        }
    }

    public func categoryPillDidRequestRename(_ pill: CategoryPillView) {
        delegate?.categoryBar(self, didRequestRenameCategory: pill.category)
    }

    public func categoryPillDidRequestDelete(_ pill: CategoryPillView) {
        delegate?.categoryBar(self, didRequestDeleteCategory: pill.category)
    }

    public func categoryPillDidRequestAdd() {
        delegate?.categoryBarDidRequestAddCategory(self)
    }

    public func categoryPill(_ pill: CategoryPillView, didMoveLauncherItemID id: UUID) {
        guard let item = categories.lazy.flatMap(\.items).first(where: { $0.id == id }) else { return }
        delegate?.categoryBar(self, didMoveLauncherItem: item, to: pill.category)
    }

    public func categoryPill(_ pill: CategoryPillView, didAddPaths paths: [String]) {
        delegate?.categoryBar(self, didAddPaths: paths, to: pill.category)
    }

    // MARK: - Dragging Destination Helpers
    private func pill(at windowPoint: NSPoint) -> CategoryPillView? {
        for subview in stackView.arrangedSubviews {
            if let pill = subview as? CategoryPillView {
                let local = pill.convert(windowPoint, from: nil)
                if pill.bounds.contains(local) {
                    return pill
                }
            }
        }

        // Fallback: If in the category bar margins or spacing, match closest pill
        var closestPill: CategoryPillView?
        var minDistance: CGFloat = .greatestFiniteMagnitude
        for subview in stackView.arrangedSubviews {
            if let pill = subview as? CategoryPillView {
                let pillRectInWindow = pill.convert(pill.bounds, to: nil)
                let dist: CGFloat
                if orientation == .horizontal {
                    dist = abs(pillRectInWindow.midX - windowPoint.x)
                } else {
                    dist = abs(pillRectInWindow.midY - windowPoint.y)
                }
                if dist < minDistance {
                    minDistance = dist
                    closestPill = pill
                }
            }
        }
        return closestPill
    }

    private func updateDropTargetHighlight(at windowLocation: NSPoint) {
        let targetPill = pill(at: windowLocation)
        for subview in stackView.arrangedSubviews {
            if let pill = subview as? CategoryPillView {
                pill.isDropTarget = (pill === targetPill)
            }
        }
    }

    private func clearDropTargetHighlight() {
        for subview in stackView.arrangedSubviews {
            if let pill = subview as? CategoryPillView {
                pill.isDropTarget = false
            }
        }
    }

    // MARK: - NSDraggingDestination
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.categoryReorderType)) == true {
            return .move
        }

        let isInternalMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        let isFile = pboard.types?.contains(.fileURL) == true
        if isInternalMove || isFile {
            updateDropTargetHighlight(at: sender.draggingLocation)
            return isInternalMove ? .move : .copy
        }

        return []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.categoryReorderType)) == true {
            return .move
        }

        let isInternalMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        let isFile = pboard.types?.contains(.fileURL) == true
        if isInternalMove || isFile {
            updateDropTargetHighlight(at: sender.draggingLocation)
            return isInternalMove ? .move : .copy
        }

        return []
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTargetHighlight()
    }

    override public func draggingEnded(_ sender: NSDraggingInfo) {
        clearDropTargetHighlight()
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        clearDropTargetHighlight()

        let pboard = sender.draggingPasteboard

        // 1. Category Reorder
        if pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.categoryReorderType)) == true {
            guard let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.categoryReorderType)),
                  let sourceId = UUID(uuidString: idString),
                  let sourceIndex = categories.firstIndex(where: { $0.id == sourceId }) else {
                return false
            }

            let loc = convert(sender.draggingLocation, from: nil)
            // "Insert before" slot in the original order; `count` means "after the last pill".
            var insertionSlot = categories.count

            for (idx, subview) in stackView.arrangedSubviews.enumerated() {
                if let pill = subview as? CategoryPillView {
                    let pillFrame = convert(pill.bounds, from: pill)
                    let isBefore = orientation == .horizontal ? loc.x < pillFrame.midX : loc.y < pillFrame.midY
                    if isBefore {
                        insertionSlot = idx
                        break
                    }
                }
            }

            // Once the source is removed, every slot after it shifts left by one.
            let targetIndex = min(categories.count - 1, insertionSlot > sourceIndex ? insertionSlot - 1 : insertionSlot)
            guard targetIndex != sourceIndex else { return true }
            delegate?.categoryBar(self, didMoveCategoryFrom: sourceIndex, to: targetIndex)
            return true
        }

        // 2. Launcher Item Move onto Category
        if let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)),
           let id = UUID(uuidString: idString),
           let targetPill = pill(at: sender.draggingLocation),
           let item = categories.lazy.flatMap(\.items).first(where: { $0.id == id }) {
            delegate?.categoryBar(self, didMoveLauncherItem: item, to: targetPill.category)
            return true
        }

        // 3. External File drop onto Category
        let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: readOptions) as? [URL],
           !urls.isEmpty,
           let targetPill = pill(at: sender.draggingLocation) {
            let paths = urls.map { $0.path }
            delegate?.categoryBar(self, didAddPaths: paths, to: targetPill.category)
            return true
        }

        return false
    }
}
