import Foundation
import AppKit

// MARK: - 5. Theme Tab View
public final class ThemeTabView: NSView {
    private var themeCards: [ThemeCardView] = []
    private var opacitySlider: NSSlider!
    private var opacityBadge: NSTextField!
    private var resetOpacityButton: SettingsResetButton!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "外观与主题", iconName: "paintbrush")
        addSubview(header)

        let scrollContent = NSView()
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeTabScrollView(contentView: scrollContent)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let sec1Title = makeSectionHeader(title: "外观风格")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        let themesStack = NSStackView()
        themesStack.translatesAutoresizingMaskIntoConstraints = false
        themesStack.orientation = .horizontal
        themesStack.distribution = .fillEqually
        themesStack.spacing = 14
        themesStack.alignment = .centerY

        themeCards.removeAll()
        for theme in AppTheme.allCases {
            let card = ThemeCardView(theme: theme, isSelected: ConfigManager.shared.config.theme == theme)
            card.onClick = { [weak self] sel in
                self?.handleThemeSelected(sel)
            }
            themeCards.append(card)
            themesStack.addArrangedSubview(card)
        }

        let themeRow = NSView()
        themeRow.translatesAutoresizingMaskIntoConstraints = false
        themeRow.addSubview(themesStack)
        NSLayoutConstraint.activate([
            themeRow.heightAnchor.constraint(equalToConstant: 108),
            themesStack.topAnchor.constraint(equalTo: themeRow.topAnchor, constant: 10),
            themesStack.bottomAnchor.constraint(equalTo: themeRow.bottomAnchor, constant: -10),
            themesStack.leadingAnchor.constraint(equalTo: themeRow.leadingAnchor, constant: 16),
            themesStack.trailingAnchor.constraint(equalTo: themeRow.trailingAnchor, constant: -16)
        ])
        card1.addRow(themeRow, isLast: true)

        let sec2Title = makeSectionHeader(title: "背景透明度")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let opacityContainer = NSView()
        opacityContainer.translatesAutoresizingMaskIntoConstraints = false

        opacitySlider = NSSlider(value: 90, minValue: 40, maxValue: 100, target: self, action: #selector(opacitySliderChanged(_:)))
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.numberOfTickMarks = 7
        opacitySlider.allowsTickMarkValuesOnly = false
        opacitySlider.isContinuous = true
        opacityContainer.addSubview(opacitySlider)

        opacityBadge = NSTextField(labelWithString: "90%")
        opacityBadge.translatesAutoresizingMaskIntoConstraints = false
        opacityBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        opacityBadge.textColor = .secondaryLabelColor
        opacityBadge.alignment = .left
        opacityContainer.addSubview(opacityBadge)

        resetOpacityButton = SettingsResetButton(title: "恢复默认", target: self, action: #selector(resetOpacityToDefault))
        opacityContainer.addSubview(resetOpacityButton)

        NSLayoutConstraint.activate([
            opacityContainer.widthAnchor.constraint(equalToConstant: 240),
            opacityContainer.heightAnchor.constraint(equalToConstant: 24),

            opacitySlider.leadingAnchor.constraint(equalTo: opacityContainer.leadingAnchor),
            opacitySlider.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            opacitySlider.widthAnchor.constraint(equalToConstant: 120),

            opacityBadge.leadingAnchor.constraint(equalTo: opacitySlider.trailingAnchor, constant: 6),
            opacityBadge.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            opacityBadge.widthAnchor.constraint(equalToConstant: 38),

            resetOpacityButton.leadingAnchor.constraint(equalTo: opacityBadge.trailingAnchor, constant: 8),
            resetOpacityButton.centerYAnchor.constraint(equalTo: opacityContainer.centerYAnchor),
            resetOpacityButton.trailingAnchor.constraint(equalTo: opacityContainer.trailingAnchor),
            resetOpacityButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        let rowOpacity = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "slider.horizontal.below.rectangle"),
            title: "透明度",
            subtitle: "调整面板背景的透明度，数值越高背景遮光越强",
            accessory: opacityContainer
        )
        card2.addRow(rowOpacity, isLast: true)

        NSLayoutConstraint.activate([
            sec1Title.topAnchor.constraint(equalTo: scrollContent.topAnchor, constant: 8),
            sec1Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card1.topAnchor.constraint(equalTo: sec1Title.bottomAnchor, constant: 7),
            card1.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card1.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),

            sec2Title.topAnchor.constraint(equalTo: card1.bottomAnchor, constant: 16),
            sec2Title.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),

            card2.topAnchor.constraint(equalTo: sec2Title.bottomAnchor, constant: 7),
            card2.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor, constant: 28),
            card2.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor, constant: -28),
            card2.bottomAnchor.constraint(equalTo: scrollContent.bottomAnchor, constant: -16)
        ])
    }

    public func refresh() {
        let cfg = ConfigManager.shared.config
        for card in themeCards {
            card.isSelected = (card.theme == cfg.theme)
        }
        opacitySlider.doubleValue = cfg.themeOpacity * 100.0
        let pct = Int(round(cfg.themeOpacity * 100.0))
        opacityBadge.stringValue = "\(pct)%"
        let defaultPct = Int(round(cfg.theme.defaultOpacity * 100.0))
        resetOpacityButton.isEnabled = (pct != defaultPct)
    }

    private func handleThemeSelected(_ theme: AppTheme) {
        ConfigManager.shared.updateTheme(theme)
        for card in themeCards {
            card.isSelected = (card.theme == theme)
        }
        let currentPct = Int(round(ConfigManager.shared.config.themeOpacity * 100.0))
        let defaultPct = Int(round(theme.defaultOpacity * 100.0))
        opacitySlider.doubleValue = Double(currentPct)
        opacityBadge.stringValue = "\(currentPct)%"
        resetOpacityButton.isEnabled = (currentPct != defaultPct)
        // Theme change notification is now posted by ConfigManager
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        let val = round(sender.doubleValue)
        let opacity = val / 100.0
        let pct = Int(val)
        opacityBadge.stringValue = "\(pct)%"
        let defaultPct = Int(round(ConfigManager.shared.config.theme.defaultOpacity * 100.0))
        resetOpacityButton.isEnabled = (pct != defaultPct)
        guard abs(opacity - ConfigManager.shared.config.themeOpacity) > 0.001 else { return }
        ConfigManager.shared.updateThemeOpacity(opacity)
        // Theme change notification is now posted by ConfigManager
    }

    @objc private func resetOpacityToDefault() {
        let defaultPct = round(ConfigManager.shared.config.theme.defaultOpacity * 100.0)
        opacitySlider.doubleValue = defaultPct
        opacitySliderChanged(opacitySlider)
    }
}

