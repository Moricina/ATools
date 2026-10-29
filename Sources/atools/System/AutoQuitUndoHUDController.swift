import Foundation
import AppKit

/// 关窗退出撤销浮层控制器（轻量级原生胶囊 HUD，无常驻显存，按需实例化）
public final class AutoQuitUndoHUDController {
    public static let shared = AutoQuitUndoHUDController()

    private var hudWindow: NSPanel?
    private var dismissTimer: Timer?
    private var countdownTimer: Timer?
    private var remainingSeconds: Double = 0
    private var currentPid: pid_t = 0
    private var onCancelHandler: ((pid_t) -> Void)?

    private var iconImageView: NSImageView?
    private var messageLabel: NSTextField?
    private var cancelButton: NSButton?

    private init() {}

    /// 展示退出倒计时 HUD
    public func showCountdown(
        for app: NSRunningApplication,
        seconds: Double,
        onCancel: @escaping (pid_t) -> Void
    ) {
        assert(Thread.isMainThread)
        currentPid = app.processIdentifier
        remainingSeconds = seconds
        onCancelHandler = onCancel

        buildHUDWindowIfNeeded()

        let appName = app.localizedName ?? "应用"
        iconImageView?.image = app.icon ?? NSWorkspace.shared.icon(for: .application)
        updateMessageLabel(appName: appName, seconds: Int(ceil(remainingSeconds)))

        positionHUDOnScreen()
        hudWindow?.alphaValue = 0
        hudWindow?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            hudWindow?.animator().alphaValue = 1.0
        }

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remainingSeconds -= 0.5
            let secInt = Int(ceil(max(0, self.remainingSeconds)))
            self.updateMessageLabel(appName: appName, seconds: secInt)
            if self.remainingSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
            }
        }
    }

    /// 隐藏并彻底销毁 HUD（释放窗口显存）
    public func dismiss() {
        assert(Thread.isMainThread)
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let win = hudWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            win.orderOut(nil)
            self?.hudWindow = nil
            self?.iconImageView = nil
            self?.messageLabel = nil
            self?.cancelButton = nil
        })
    }

    private func updateMessageLabel(appName: String, seconds: Int) {
        if seconds > 0 {
            messageLabel?.stringValue = "\(appName) 将在 \(seconds) 秒后退出"
        } else {
            messageLabel?.stringValue = "\(appName) 即将退出"
        }
    }

    private func positionHUDOnScreen() {
        guard let win = hudWindow else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width: CGFloat = 290
        let height: CGFloat = 46
        let x = visibleFrame.origin.x + (visibleFrame.width - width) / 2.0
        let y = visibleFrame.origin.y + 72 // 位于屏幕底部 Dock 上方舒适视线区

        win.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func buildHUDWindowIfNeeded() {
        if hudWindow != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // 原生毛玻璃背景
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 290, height: 46))
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 23
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor

        let container = NSStackView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 12)

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        self.iconImageView = iconView
        container.addArrangedSubview(iconView)

        let label = NSTextField(labelWithString: "应用即将退出")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.messageLabel = label
        container.addArrangedSubview(label)

        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(handleCancelClicked))
        cancelBtn.bezelStyle = .inline
        cancelBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 11
        cancelBtn.widthAnchor.constraint(equalToConstant: 48).isActive = true
        cancelBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        self.cancelButton = cancelBtn
        container.addArrangedSubview(cancelBtn)

        visualEffect.addSubview(container)
        panel.contentView = visualEffect
        self.hudWindow = panel
    }

    @objc private func handleCancelClicked() {
        let pid = currentPid
        dismiss()
        onCancelHandler?(pid)
    }
}
