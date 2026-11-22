import Foundation
import AppKit

/// 新装应用关窗退出名单询问浮层控制器（非抢焦原生毛玻璃胶囊卡片，支持单应用一键勾选生效与多应用聚合）
public final class AutoQuitNewAppPromptController: NSObject {
    public static let shared = AutoQuitNewAppPromptController()

    private var panel: NSPanel?
    private var countdownTimer: Timer?
    private var remainingSeconds: Double = 0
    private var isHovered: Bool = false
    private var isPreviewSession: Bool = false
    private var presentationGeneration: Int = 0

    /// 当前待询问的新应用队列（按 bundleId 去重保序）
    public private(set) var pendingApps: [IndexedApp] = []
    /// 会话级已忽略 Bundle ID（与 ConfigManager 持久化名单双重防重，彻底阻断并发通知导致的二次弹出）
    private var sessionDismissedBundleIDs: Set<String> = []
    private var debounceWorkItem: DispatchWorkItem?
    private var discoveryObserver: NSObjectProtocol?

    // UI 控件引用（便于单测断言与状态刷新）
    public private(set) var visualEffectView: NSVisualEffectView?
    public private(set) var iconImageView: NSImageView?
    public private(set) var titleLabel: NSTextField?
    public private(set) var subtitleLabel: NSTextField?
    public private(set) var confirmButton: NSButton?
    public private(set) var ignoreButton: NSButton?

    private override init() {
        super.init()
    }

    public func startListening() {
        guard discoveryObserver == nil else { return }
        discoveryObserver = NotificationCenter.default.addObserver(
            forName: .atoolsNewAppsDiscoveredForAutoQuit,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let apps = note.object as? [IndexedApp],
                  !apps.isEmpty else { return }
            self.enqueueDiscoveredApps(apps)
        }
    }

    /// 供运行时或测试注入新发现的应用列表
    public func enqueueDiscoveredApps(_ apps: [IndexedApp], debounceSeconds: Double = 0.6) {
        assert(Thread.isMainThread)
        let cfg = ConfigManager.shared.config
        guard cfg.enableAutoQuit && cfg.promptAutoQuitOnNewApp else { return }

        if isPreviewSession {
            isPreviewSession = false
            pendingApps.removeAll()
        }

        let currentRules = Set(cfg.currentAutoQuitAppRules.map { $0.lowercased() })
        let dismissedBids = Set(cfg.dismissedAutoQuitPromptBundleIds.map { $0.lowercased() }).union(sessionDismissedBundleIDs)
        var existingBids = Set(pendingApps.compactMap { $0.bundleId?.lowercased() })

        for app in apps {
            guard let bid = app.bundleId, !bid.isEmpty else { continue }
            guard !AppHotspotIndex.isNestedInsideAppBundle(app.path) else { continue }
            let lowerBid = bid.lowercased()
            guard !dismissedBids.contains(lowerBid) else { continue }
            guard !AutoQuitManager.systemExcludedBundleIDs.contains(bid) else { continue }
            guard !AutoQuitManager.isProtectedApp(bundleID: bid) else { continue }
            guard !currentRules.contains(lowerBid) else { continue }
            if existingBids.insert(lowerBid).inserted {
                pendingApps.append(app)
            }
        }

        guard !pendingApps.isEmpty else { return }

        debounceWorkItem?.cancel()
        if debounceSeconds <= 0 {
            presentCurrentPendingApps()
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.presentCurrentPendingApps()
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
        }
    }

    /// 立即展示当前队列中的新应用询问浮层
    public func presentCurrentPendingApps(autoDismissSeconds: Double = 8.0) {
        assert(Thread.isMainThread)
        guard !pendingApps.isEmpty else { return }
        let cfg = ConfigManager.shared.config
        guard cfg.enableAutoQuit && cfg.promptAutoQuitOnNewApp else {
            pendingApps.removeAll()
            return
        }

        presentationGeneration &+= 1
        buildPanelIfNeeded()
        configureContent(for: pendingApps, mode: cfg.autoQuitMode)
        positionPanelOnScreen()

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.invalidateShadow()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel?.animator().alphaValue = 1.0
        }

        startCountdown(seconds: autoDismissSeconds)
    }

    /// 演示预览：直接触发一次模拟新装 VPN 应用的右上角询问浮层（不写入真实配置）
    public func presentPreviewVPNPrompt(autoDismissSeconds: Double = 15.0) {
        assert(Thread.isMainThread)
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        isPreviewSession = true
        pendingApps = [
            IndexedApp(
                name: "Clash Verge",
                localizedName: "Clash Verge",
                path: "/Applications/Clash Verge.app",
                bundleId: "io.github.clash-verge"
            )
        ]

        let mode = ConfigManager.shared.config.autoQuitMode
        presentationGeneration &+= 1
        buildPanelIfNeeded()
        configureContent(for: pendingApps, mode: mode)
        positionPanelOnScreen()

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.invalidateShadow()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel?.animator().alphaValue = 1.0
        }

        startCountdown(seconds: autoDismissSeconds)
    }

    public func dismiss(clearPending: Bool = true) {
        assert(Thread.isMainThread)
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        isHovered = false
        if clearPending {
            pendingApps.removeAll()
            isPreviewSession = false
        }

        guard let win = panel else { return }
        presentationGeneration &+= 1
        let dismissGen = presentationGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, self.presentationGeneration == dismissGen else { return }
            win.orderOut(nil)
            if self.panel === win {
                self.panel = nil
                self.visualEffectView = nil
                self.iconImageView = nil
                self.titleLabel = nil
                self.subtitleLabel = nil
                self.confirmButton = nil
                self.ignoreButton = nil
            }
        })
    }

    private func startCountdown(seconds: Double) {
        countdownTimer?.invalidate()
        remainingSeconds = seconds
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isHovered { return }
            self.remainingSeconds -= 0.25
            if self.remainingSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.dismiss(clearPending: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func configureContent(for apps: [IndexedApp], mode: AutoQuitMode) {
        if apps.count == 1, let app = apps.first {
            let appName = app.localizedName.isEmpty ? app.name : app.localizedName
            let bid = app.bundleId ?? ""
            let isNetworkOrVPN = AutoQuitQuirks.shared.isLikelyNetworkOrBackgroundTool(
                bundleID: bid,
                name: appName,
                path: app.path
            )

            if FileManager.default.fileExists(atPath: app.path) {
                iconImageView?.image = NSWorkspace.shared.icon(forFile: app.path)
            } else {
                iconImageView?.image = NSWorkspace.shared.icon(for: .application)
            }

            titleLabel?.stringValue = "新安装「\(appName)」"
            switch mode {
            case .allApps:
                if isNetworkOrVPN {
                    subtitleLabel?.stringValue = "⚡ 检测到 VPN/网络工具，建议勾选加入排除名单保活"
                    subtitleLabel?.textColor = .systemOrange
                } else {
                    subtitleLabel?.stringValue = "是否在当前「排除名单」中勾选并立即生效？"
                    subtitleLabel?.textColor = .secondaryLabelColor
                }
                confirmButton?.title = "勾选排除"
            case .onlyListed:
                if isNetworkOrVPN {
                    subtitleLabel?.stringValue = "⚡ 检测到 VPN/常驻工具，建议忽略以保持后台常驻"
                    subtitleLabel?.textColor = .systemOrange
                } else {
                    subtitleLabel?.stringValue = "是否在当前「退出名单」中勾选并立即生效？"
                    subtitleLabel?.textColor = .secondaryLabelColor
                }
                confirmButton?.title = "勾选退出"
            }
            ignoreButton?.title = "忽略"
        } else {
            if let first = apps.first, FileManager.default.fileExists(atPath: first.path) {
                iconImageView?.image = NSWorkspace.shared.icon(forFile: first.path)
            } else {
                iconImageView?.image = ThumbnailPipeline.shared.symbolIcon(name: "sparkles", pointSize: 22, weight: .semibold)
            }
            let names = apps.prefix(2).map { $0.localizedName.isEmpty ? $0.name : $0.localizedName }.joined(separator: "、")
            titleLabel?.stringValue = "发现 \(apps.count) 个新安装应用"
            let listName = (mode == .allApps) ? "排除名单" : "退出名单"
            subtitleLabel?.stringValue = "含 \(names) 等，是否打开「\(listName)」勾选生效？"
            subtitleLabel?.textColor = .secondaryLabelColor
            confirmButton?.title = "勾选名单..."
            ignoreButton?.title = "忽略"
        }
    }

    /// 响应用户点击主确认按钮（单应用直接写入当前模式名单并生效；多应用打开名单编辑器并置顶高亮）
    @objc public func handleConfirmClicked() {
        let appsSnapshot = pendingApps
        let mode = ConfigManager.shared.config.autoQuitMode

        if appsSnapshot.count == 1, let app = appsSnapshot.first, let bid = app.bundleId, !bid.isEmpty {
            let wasPreview = isPreviewSession
            if !wasPreview {
                _ = ConfigManager.shared.addAutoQuitRule(bid, for: mode)
            }
            let appName = app.localizedName.isEmpty ? app.name : app.localizedName
            let listTitle = (mode == .allApps) ? "排除名单" : "退出名单"
            titleLabel?.stringValue = "已加入\(listTitle)并生效"
            subtitleLabel?.stringValue = wasPreview ? "「\(appName)」配置已实时更新（演示模式，未写入配置）" : "「\(appName)」配置已实时更新"
            subtitleLabel?.textColor = .systemGreen
            confirmButton?.isHidden = true
            ignoreButton?.isHidden = true
            pendingApps.removeAll()
            countdownTimer?.invalidate()
            countdownTimer = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.dismiss(clearPending: true)
            }
        } else if appsSnapshot.count >= 2 {
            let bids = Set(appsSnapshot.compactMap { $0.bundleId })
            dismiss(clearPending: true)
            SettingsWindowController.shared.showAutoQuitRulesEditor(highlightedBundleIDs: bids)
        } else {
            dismiss(clearPending: true)
        }
    }

    @objc public func handleIgnoreClicked() {
        if !isPreviewSession {
            let ignoredBids = pendingApps.compactMap { $0.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !ignoredBids.isEmpty {
                for bid in ignoredBids {
                    sessionDismissedBundleIDs.insert(bid.lowercased())
                }
                ConfigManager.shared.markAutoQuitPromptDismissed(ignoredBids)
            }
        }
        dismiss(clearPending: true)
    }

    private let panelWidth: CGFloat = 490
    private let panelHeight: CGFloat = 64
    private let panelCornerRadius: CGFloat = 16

    private func positionPanelOnScreen() {
        guard let win = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width: CGFloat = min(panelWidth, max(360, visibleFrame.width - 36))
        let height: CGFloat = panelHeight
        let x = visibleFrame.maxX - width - 18
        let y = visibleFrame.maxY - height - 18

        win.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if let effectView = visualEffectView as? HoverTrackingVisualEffectView {
            effectView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            effectView.updateRoundedMask()
        }
        win.contentView?.layoutSubtreeIfNeeded()
        win.invalidateShadow()
    }

    private func buildPanelIfNeeded() {
        if panel != nil {
            confirmButton?.isHidden = false
            ignoreButton?.isHidden = false
            return
        }

        let width: CGFloat = panelWidth
        let height: CGFloat = panelHeight
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false

        let visualEffect = HoverTrackingVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.cornerRadius = panelCornerRadius
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor.clear.cgColor
        visualEffect.layer?.cornerRadius = panelCornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor
        visualEffect.updateRoundedMask()
        visualEffect.onHoverChanged = { [weak self] hovering in
            self?.isHovered = hovering
        }
        self.visualEffectView = visualEffect

        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.widthAnchor.constraint(equalToConstant: 36).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        self.iconImageView = iconView
        container.addArrangedSubview(iconView)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let tLabel = NSTextField(labelWithString: "发现新应用")
        tLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        tLabel.textColor = .labelColor
        tLabel.usesSingleLineMode = true
        tLabel.maximumNumberOfLines = 1
        tLabel.lineBreakMode = .byTruncatingTail
        tLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.titleLabel = tLabel

        let sLabel = NSTextField(labelWithString: "是否加入当前模式名单并生效？")
        sLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        sLabel.textColor = .secondaryLabelColor
        sLabel.usesSingleLineMode = true
        sLabel.maximumNumberOfLines = 1
        sLabel.lineBreakMode = .byTruncatingTail
        sLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.subtitleLabel = sLabel

        textStack.addArrangedSubview(tLabel)
        textStack.addArrangedSubview(sLabel)
        container.addArrangedSubview(textStack)

        let cBtn = CapsuleActionButton(title: "勾选排除", isPrimary: true, target: self, action: #selector(handleConfirmClicked))
        cBtn.setContentHuggingPriority(.required, for: .horizontal)
        cBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        cBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        cBtn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.confirmButton = cBtn
        container.addArrangedSubview(cBtn)

        let iBtn = CapsuleActionButton(title: "忽略", isPrimary: false, target: self, action: #selector(handleIgnoreClicked))
        iBtn.setContentHuggingPriority(.required, for: .horizontal)
        iBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        iBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        iBtn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.ignoreButton = iBtn
        container.addArrangedSubview(iBtn)

        visualEffect.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            container.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor)
        ])
        p.contentView = visualEffect
        self.panel = p
    }
}

private final class HoverTrackingVisualEffectView: NSVisualEffectView {
    var onHoverChanged: ((Bool) -> Void)?
    var cornerRadius: CGFloat = 16 {
        didSet {
            if oldValue != cornerRadius {
                updateRoundedMask()
            }
        }
    }
    private var trackingArea: NSTrackingArea?
    private var lastMaskSize: CGSize = .zero
    private var lastMaskRadius: CGFloat = -1

    /// 使用显式圆角 `maskImage` 裁剪 `.behindWindow` 毛玻璃渲染表面，
    /// 彻底消除 macOS 上仅靠 `layer.cornerRadius` 导致窗口四个角溢出的白底/方角瑕疵。
    func updateRoundedMask() {
        guard bounds.width > 1, bounds.height > 1 else {
            maskImage = nil
            lastMaskSize = .zero
            lastMaskRadius = -1
            return
        }
        guard bounds.size != lastMaskSize || cornerRadius != lastMaskRadius else { return }
        lastMaskSize = bounds.size
        lastMaskRadius = cornerRadius
        let size = bounds.size
        let radius = cornerRadius
        let img = NSImage(size: size, flipped: false) {
            let path = NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = false
        maskImage = img
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        window?.invalidateShadow()
    }

    override func layout() {
        super.layout()
        updateRoundedMask()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

/// 自定义胶囊按钮：禁用 AppKit 默认 .inline 灰底高亮，保证悬停/按下状态下文字与背景对比度始终清晰
private final class CapsuleActionButton: NSButton {
    private let isPrimary: Bool
    private var isPointerInside = false
    private var hoverTrackingArea: NSTrackingArea?

    init(title: String, isPrimary: Bool, target: AnyObject?, action: Selector?) {
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.focusRingType = .none
        self.font = NSFont.systemFont(ofSize: 11.5, weight: isPrimary ? .semibold : .medium)
        self.wantsLayer = true
        self.layer?.cornerRadius = 13
        self.layer?.masksToBounds = true
        self.title = title
        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var title: String {
        didSet { refreshTitle() }
    }

    override var isHighlighted: Bool {
        didSet { refreshBackground() }
    }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + 20, height: 26)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        refreshBackground()
    }

    private func refreshAppearance() {
        refreshTitle()
        refreshBackground()
    }

    private func refreshTitle() {
        let textColor: NSColor = isPrimary ? .white : .labelColor
        let font = NSFont.systemFont(ofSize: 11.5, weight: isPrimary ? .semibold : .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func refreshBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isPrimary {
                let base = NSColor.controlAccentColor
                if isHighlighted {
                    layer?.backgroundColor = (base.blended(withFraction: 0.22, of: .black) ?? base).cgColor
                } else if isPointerInside {
                    layer?.backgroundColor = (base.blended(withFraction: 0.10, of: .black) ?? base).cgColor
                } else {
                    layer?.backgroundColor = base.cgColor
                }
            } else {
                let alpha: CGFloat = isHighlighted ? 0.22 : (isPointerInside ? 0.15 : 0.09)
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
            }
        }
    }
}
