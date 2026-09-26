import Foundation
import AppKit

public protocol CategoryBarDelegate: AnyObject {
    func categoryBar(_ bar: CategoryBarView, didSelectCategory category: Category)
    func categoryBarDidRequestAddCategory(_ bar: CategoryBarView)
    func categoryBar(_ bar: CategoryBarView, didRequestRenameCategory category: Category)
    func categoryBar(_ bar: CategoryBarView, didRequestDeleteCategory category: Category)
    func categoryBar(_ bar: CategoryBarView, didMoveCategoryFrom fromIndex: Int, to toIndex: Int)
    func categoryBar(_ bar: CategoryBarView, didMoveLauncherItem item: LauncherItem, to category: Category)
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
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
    private var stackViewConstraints: [NSLayoutConstraint] = []

    override public var isFlipped: Bool { return true }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        registerForDraggedTypes([NSPasteboard.PasteboardType(AppConstants.categoryReorderType)])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

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
            scrollView.hasHorizontalScroller = false
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
    }

    // MARK: - Right Click on CategoryBarView (Blank Area)
    override public func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "CategoryBarMenu")
        let addItem = NSMenuItem(title: "➕ 新建分类...", action: #selector(contextAddCategory), keyEquivalent: "")
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

        let settingsItem = NSMenuItem(title: "⚙️ 偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: ",")
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
        delegate?.categoryBar(self, didSelectCategory: pill.category)
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

    // MARK: - NSDraggingDestination (Category Reorder)
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.categoryReorderType)) == true else {
            return []
        }
        return .move
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.categoryReorderType)) == true else {
            return []
        }
        return .move
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let idString = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(AppConstants.categoryReorderType)),
              let sourceId = UUID(uuidString: idString),
              let sourceIndex = categories.firstIndex(where: { $0.id == sourceId }) else {
            return false
        }

        let loc = convert(sender.draggingLocation, from: nil)
        var targetIndex = categories.count - 1

        for (idx, subview) in stackView.arrangedSubviews.enumerated() {
            if let pill = subview as? CategoryPillView {
                let pillFrame = convert(pill.bounds, from: pill)
                if orientation == .horizontal {
                    if loc.x < pillFrame.midX {
                        targetIndex = idx
                        break
                    }
                } else {
                    if loc.y < pillFrame.midY {
                        targetIndex = idx
                        break
                    }
                }
            }
        }

        delegate?.categoryBar(self, didMoveCategoryFrom: sourceIndex, to: targetIndex)
        return true
    }
}
