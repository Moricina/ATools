import Foundation
import AppKit

// MARK: - 7. About Tab View
public final class AboutTabView: NSView {
    private let statusLabel = NSTextField(labelWithString: "点击右侧按钮连接 GitHub 检查最新发布版本")
    private let actionButton = SettingsPillButton(title: "")
    private let progressIndicator = NSProgressIndicator()
    private let releaseNotesBox = NSView()
    private let releaseNotesText = NSTextView()
    private var releaseNotesHeightConstraint: NSLayoutConstraint?

    public init() {
        super.init(frame: .zero)
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateStateChanged),
            name: UpdateManager.stateDidChangeNotification,
            object: nil
        )
        updateUIState()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "关于 ATools", iconName: "info.circle")
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

        // Section 1: 软件更新与版本
        let sec1Title = makeSectionHeader(title: "软件版本与更新")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        let currentVer = UpdateManager.shared.currentAppVersion
        let verLabel = NSTextField(labelWithString: "v\(currentVer)")
        verLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        verLabel.textColor = .secondaryLabelColor
        let rowVer = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "sparkles"),
            title: "ATools for macOS (v\(currentVer))",
            subtitle: "极简启动抽屉与全盘搜索",
            accessory: verLabel
        )
        card1.addRow(rowVer)

        // Action Container
        let actionContainer = NSView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionContainer.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            actionButton.leadingAnchor.constraint(greaterThanOrEqualTo: actionContainer.leadingAnchor),
            actionContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            actionContainer.heightAnchor.constraint(equalToConstant: 32)
        ])

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.cell?.wraps = true
        statusLabel.cell?.isScrollable = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowUpdate = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.triangle.2.circlepath"),
            title: "检查与安装更新",
            subtitle: "检查并更新至最新发布版本",
            accessory: actionContainer
        )
        card1.addRow(rowUpdate, isLast: false)

        // Download Progress & Status Row (Clean arranged subview inside card1)
        let updateDetailView = NSView()
        updateDetailView.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0.0
        progressIndicator.maxValue = 1.0
        progressIndicator.doubleValue = 0.0
        progressIndicator.isHidden = true
        updateDetailView.addSubview(progressIndicator)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        updateDetailView.addSubview(statusLabel)

        // Release Notes Box (folded by default)
        releaseNotesBox.translatesAutoresizingMaskIntoConstraints = false
        releaseNotesBox.wantsLayer = true
        releaseNotesBox.layer?.cornerRadius = 8
        releaseNotesBox.layer?.backgroundColor = NSColor.clear.cgColor
        let notesBackground = NSVisualEffectView()
        notesBackground.translatesAutoresizingMaskIntoConstraints = false
        notesBackground.material = .contentBackground
        notesBackground.blendingMode = .withinWindow
        notesBackground.state = .active
        releaseNotesBox.addSubview(notesBackground)
        NSLayoutConstraint.activate([
            notesBackground.leadingAnchor.constraint(equalTo: releaseNotesBox.leadingAnchor),
            notesBackground.trailingAnchor.constraint(equalTo: releaseNotesBox.trailingAnchor),
            notesBackground.topAnchor.constraint(equalTo: releaseNotesBox.topAnchor),
            notesBackground.bottomAnchor.constraint(equalTo: releaseNotesBox.bottomAnchor)
        ])
        releaseNotesBox.isHidden = true
        updateDetailView.addSubview(releaseNotesBox)

        let scrollNotes = NSScrollView()
        scrollNotes.translatesAutoresizingMaskIntoConstraints = false
        scrollNotes.hasVerticalScroller = true
        scrollNotes.drawsBackground = false

        releaseNotesText.isEditable = false
        releaseNotesText.isSelectable = true
        releaseNotesText.font = NSFont.systemFont(ofSize: 11)
        releaseNotesText.textColor = .labelColor
        releaseNotesText.backgroundColor = .clear
        releaseNotesText.textContainerInset = NSSize(width: 8, height: 8)
        releaseNotesText.isVerticallyResizable = true
        releaseNotesText.isHorizontallyResizable = false
        releaseNotesText.autoresizingMask = [.width]
        releaseNotesText.textContainer?.widthTracksTextView = true
        scrollNotes.documentView = releaseNotesText
        releaseNotesBox.addSubview(scrollNotes)

        let notesHeight = releaseNotesBox.heightAnchor.constraint(equalToConstant: 0)
        releaseNotesHeightConstraint = notesHeight

        card1.addRow(updateDetailView, isLast: true)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: updateDetailView.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: updateDetailView.leadingAnchor, constant: 48),
            statusLabel.trailingAnchor.constraint(equalTo: updateDetailView.trailingAnchor, constant: -16),

            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            progressIndicator.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 6),

            releaseNotesBox.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 6),
            releaseNotesBox.leadingAnchor.constraint(equalTo: updateDetailView.leadingAnchor, constant: 16),
            releaseNotesBox.trailingAnchor.constraint(equalTo: updateDetailView.trailingAnchor, constant: -16),
            notesHeight,
            releaseNotesBox.bottomAnchor.constraint(equalTo: updateDetailView.bottomAnchor, constant: -12),

            scrollNotes.topAnchor.constraint(equalTo: releaseNotesBox.topAnchor),
            scrollNotes.leadingAnchor.constraint(equalTo: releaseNotesBox.leadingAnchor),
            scrollNotes.trailingAnchor.constraint(equalTo: releaseNotesBox.trailingAnchor),
            scrollNotes.bottomAnchor.constraint(equalTo: releaseNotesBox.bottomAnchor)
        ])

        // Section 2: 系统兼容性与架构
        let sec2Title = makeSectionHeader(title: "系统规格")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        let archLabel = NSTextField(labelWithString: AboutTabView.currentArchitectureLabel)
        archLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        archLabel.textColor = .secondaryLabelColor
        let rowArch = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "cpu"),
            title: "原生架构支持",
            subtitle: "适配 macOS 12 及以上系统",
            accessory: archLabel
        )
        card2.addRow(rowArch)

        let rowStack = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "curlybraces"),
            title: "精纯 Swift + 原生 AppKit 架构",
            subtitle: "零 Electron/Web 视图臃肿，零第三方二进制框架依赖",
            accessory: nil
        )
        card2.addRow(rowStack, isLast: true)

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

    private static var currentArchitectureLabel: String {
        // Read the Mach-O header via NSBundle instead of spawning /usr/bin/lipo synchronously
        // on the main thread when the About tab is built.
        let architectures = Bundle.main.executableArchitectures?.map { $0.intValue } ?? []
        let hasArm = architectures.contains(NSBundleExecutableArchitectureARM64)
        let hasIntel = architectures.contains(NSBundleExecutableArchitectureX86_64)
        if hasArm && hasIntel {
            return "Universal (Apple Silicon + Intel)"
        }
        if hasArm {
            return "Apple Silicon (arm64)"
        }
        if hasIntel {
            return "Intel (x86_64)"
        }
        return "当前 Mac 原生架构"
    }

    @objc private func handleUpdateStateChanged() {
        updateUIState()
    }

    @objc private func actionButtonClicked() {
        switch UpdateManager.shared.currentState {
        case .idle, .upToDate:
            UpdateManager.shared.checkForUpdates(isUserInitiated: true)
        case .error:
            UpdateManager.shared.retry()
        case .available:
            UpdateManager.shared.startUpdate()
        case .downloading:
            UpdateManager.shared.cancelUpdate()
        case .checking, .preparing:
            break
        }
    }

    private func updateUIState() {
        let state = UpdateManager.shared.currentState
        switch state {
        case .idle:
            statusLabel.stringValue = "点击「检查更新」连接 GitHub 获取最新版本。"
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "检查更新"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            hideReleaseNotes()

        case .checking:
            statusLabel.stringValue = "正在连接 GitHub 检查版本发布..."
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "检查中..."
            actionButton.isEnabled = false
            progressIndicator.isHidden = true
            hideReleaseNotes()

        case .upToDate(let ver):
            statusLabel.stringValue = "当前版本已是最新 (v\(ver))。"
            statusLabel.textColor = .labelColor
            actionButton.title = "重新检查"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            hideReleaseNotes()

        case .available(let release):
            statusLabel.stringValue = "发现新版本 \(release.version)（\(release.name)）。"
            statusLabel.textColor = .labelColor
            actionButton.title = "立即更新"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            showReleaseNotes(release.body)

        case .downloading(let progress):
            let percent = Int(progress * 100)
            statusLabel.stringValue = "正在下载更新安装包 (\(percent)%)..."
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "取消"
            actionButton.isEnabled = true
            progressIndicator.isHidden = false
            progressIndicator.doubleValue = progress

        case .preparing:
            statusLabel.stringValue = "正在准备更新并重启..."
            statusLabel.textColor = .secondaryLabelColor
            actionButton.title = "更新中..."
            actionButton.isEnabled = false
            progressIndicator.isHidden = false
            progressIndicator.doubleValue = 1.0

        case .error(let msg):
            statusLabel.stringValue = msg
            statusLabel.textColor = .labelColor
            actionButton.title = "重试"
            actionButton.isEnabled = true
            progressIndicator.isHidden = true
            hideReleaseNotes()
        }
    }

    private func showReleaseNotes(_ text: String) {
        // GitHub release body 是 Markdown；直接塞纯文本会把 `**`、`-` 原样露出来。
        releaseNotesText.textStorage?.setAttributedString(MarkdownText.render(text))
        releaseNotesBox.isHidden = false
        releaseNotesHeightConstraint?.constant = 110
        layoutSubtreeIfNeeded()
    }

    private func hideReleaseNotes() {
        releaseNotesBox.isHidden = true
        releaseNotesHeightConstraint?.constant = 0
        layoutSubtreeIfNeeded()
    }
}
