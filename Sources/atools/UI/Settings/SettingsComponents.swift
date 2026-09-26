import Foundation
import AppKit

/// 现代 macOS 卡片式容器视图 (自适应浅/深色背景与微高光圆角描边)
public final class SettingsCardView: NSView {
    private let stackView = NSStackView()

    public init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        updateColors()

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.distribution = .fill
        stackView.alignment = .leading
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    public override func updateLayer() {
        super.updateLayer()
        updateColors()
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            layer?.backgroundColor = NSColor(white: 0.17, alpha: 0.85).cgColor
            layer?.borderColor = NSColor(white: 0.28, alpha: 0.8).cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.98, alpha: 0.95).cgColor
            layer?.borderColor = NSColor(white: 0.85, alpha: 0.9).cgColor
        }
    }

    /// 添加一行设置项，并在需要时在行间插入标准 Inset 分割线
    public func addRow(_ rowView: NSView, isLast: Bool = false) {
        rowView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
        ])

        if !isLast {
            let separatorContainer = NSView()
            separatorContainer.translatesAutoresizingMaskIntoConstraints = false
            separatorContainer.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

            let line = NSBox()
            line.translatesAutoresizingMaskIntoConstraints = false
            line.boxType = .separator
            separatorContainer.addSubview(line)

            NSLayoutConstraint.activate([
                line.topAnchor.constraint(equalTo: separatorContainer.topAnchor),
                line.bottomAnchor.constraint(equalTo: separatorContainer.bottomAnchor),
                line.leadingAnchor.constraint(equalTo: separatorContainer.leadingAnchor, constant: 16),
                line.trailingAnchor.constraint(equalTo: separatorContainer.trailingAnchor, constant: -16)
            ])

            stackView.addArrangedSubview(separatorContainer)
            NSLayoutConstraint.activate([
                separatorContainer.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                separatorContainer.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
            ])
        }
    }
}

/// 标准设置行视图：左侧图标 + 主标题 + 详细副标题说明，右侧控件
public final class SettingsRowView: NSView {
    public let titleLabel = NSTextField(labelWithString: "")
    public let subtitleLabel = NSTextField(labelWithString: "")
    public let iconImageView = NSImageView()
    public let accessoryContainer = NSView()

    public init(
        icon: NSImage? = nil,
        title: String,
        subtitle: String? = nil,
        accessory: NSView? = nil,
        minHeight: CGFloat = 46
    ) {
        super.init(frame: .zero)
        setupUI(icon: icon, title: title, subtitle: subtitle, accessory: accessory, minHeight: minHeight)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupUI(icon: NSImage?, title: String, subtitle: String?, accessory: NSView?, minHeight: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        textStack.addArrangedSubview(titleLabel)

        if let sub = subtitle, !sub.isEmpty {
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel.stringValue = sub
            subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.cell?.wraps = true
            subtitleLabel.maximumNumberOfLines = 2
            textStack.addArrangedSubview(subtitleLabel)
        }

        addSubview(textStack)

        var leftAnchorConstraint = textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        if let icon = icon {
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            iconImageView.image = icon
            iconImageView.contentTintColor = .controlAccentColor
            addSubview(iconImageView)

            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: 18),
                iconImageView.heightAnchor.constraint(equalToConstant: 18)
            ])
            leftAnchorConstraint = textStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12)
        }
        leftAnchorConstraint.isActive = true

        accessoryContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessoryContainer)

        if let accessory = accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            accessoryContainer.addSubview(accessory)
            NSLayoutConstraint.activate([
                accessory.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
                accessory.bottomAnchor.constraint(equalTo: accessoryContainer.bottomAnchor),
                accessory.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
                accessory.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: accessoryContainer.leadingAnchor, constant: -12),

            accessoryContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            accessoryContainer.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// 模块大标题与次级分段胶囊 Tab 头部视图
public final class SettingsHeaderView: NSView {
    public let iconView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    public let segmentedControl = NSSegmentedControl()
    public var onSegmentChanged: ((Int) -> Void)?

    public init(title: String, iconName: String, tabs: [String] = []) {
        super.init(frame: .zero)
        setupUI(title: title, iconName: iconName, tabs: tabs)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupUI(title: String, iconName: String, tabs: [String]) {
        translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = ThumbnailPipeline.shared.symbolIcon(name: iconName, pointSize: 20, weight: .semibold)
        iconView.contentTintColor = .labelColor
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor)
        ])

        if !tabs.isEmpty {
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false
            segmentedControl.segmentCount = tabs.count
            for (idx, tabTitle) in tabs.enumerated() {
                segmentedControl.setLabel(tabTitle, forSegment: idx)
            }
            segmentedControl.selectedSegment = 0
            segmentedControl.target = self
            segmentedControl.action = #selector(segmentChanged(_:))
            if #available(macOS 11.0, *) {
                segmentedControl.trackingMode = .selectOne
            }
            addSubview(segmentedControl)

            NSLayoutConstraint.activate([
                segmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
                segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
                segmentedControl.heightAnchor.constraint(equalToConstant: 26),
                segmentedControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
            ])
        } else {
            bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12).isActive = true
        }
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        onSegmentChanged?(sender.selectedSegment)
    }
}
