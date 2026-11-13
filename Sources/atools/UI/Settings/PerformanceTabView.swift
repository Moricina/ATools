import Foundation
import AppKit

// MARK: - 6. Performance Tab View
public final class PerformanceTabView: NSView {
    private var memLabel = NSTextField(labelWithString: "正在测量...")
    private var purgeStatusLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var annealControl: SettingsLiquidSegmentedControl!
    private var debounceControl: SettingsLiquidSegmentedControl!
    private var cacheControl: SettingsLiquidSegmentedControl!

    public init() {
        super.init(frame: .zero)
        setupUI()
        refresh()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public func startMonitor() {
        stopMonitor()
        updateMemoryMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemoryMetrics()
        }
    }

    public func stopMonitor() {
        timer?.invalidate()
        timer = nil
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView(title: "运行与性能", iconName: "gauge.with.dots.needle.bottom.50percent")
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

        let sec1Title = makeSectionHeader(title: "内存监测与释放")
        scrollContent.addSubview(sec1Title)

        let card1 = SettingsCardView()
        card1.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card1)

        memLabel.translatesAutoresizingMaskIntoConstraints = false
        memLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        memLabel.textColor = .labelColor
        memLabel.alignment = .right

        let purgeBtn = SettingsPillButton(title: "释放内存", target: self, action: #selector(handlePurge))

        let memRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "memorychip"),
            title: "内存占用",
            subtitle: "当前进程的实际物理内存占用",
            accessory: memLabel
        )
        card1.addRow(memRow)

        let actionRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "sparkles"),
            title: "释放内存缓存",
            subtitle: "清空临时图标缓存并释放闲置内存",
            accessory: purgeBtn
        )
        card1.addRow(actionRow)

        purgeStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        purgeStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        purgeStatusLabel.textColor = .secondaryLabelColor
        purgeStatusLabel.alignment = .right
        purgeStatusLabel.stringValue = "上次释放：尚未执行"

        let statusRow = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "arrow.triangle.2.circlepath"),
            title: "释放结果",
            subtitle: "显示最近一次释放的内存差值",
            accessory: purgeStatusLabel
        )
        card1.addRow(statusRow, isLast: true)

        let sec2Title = makeSectionHeader(title: "响应与缓存设置")
        scrollContent.addSubview(sec2Title)

        let card2 = SettingsCardView()
        card2.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.addSubview(card2)

        annealControl = SettingsLiquidSegmentedControl(labels: ["1.5 秒", "3.0 秒", "10.0 秒"], target: self, action: #selector(annealChanged(_:)))
        let rowAnneal = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "timer"),
            title: "面板收起后内存释放延迟",
            subtitle: "面板关闭后等待设定的时间自动释放闲置内存",
            accessory: annealControl
        )
        card2.addRow(rowAnneal)

        debounceControl = SettingsLiquidSegmentedControl(labels: ["50ms", "150ms", "300ms"], target: self, action: #selector(debounceChanged(_:)))
        let rowDebounce = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "waveform.path"),
            title: "搜索防抖延迟",
            subtitle: "控制连续输入时触发搜索的等待间隔",
            accessory: debounceControl
        )
        card2.addRow(rowDebounce)

        cacheControl = SettingsLiquidSegmentedControl(labels: ["4 MB", "6 MB", "12 MB"], target: self, action: #selector(cacheLimitChanged(_:)))
        let rowCache = SettingsRowView(
            icon: ThumbnailPipeline.shared.symbolIcon(name: "photo.stack"),
            title: "缩略图缓存上限",
            subtitle: "设置文件预览与应用图标的最大缓存容量",
            accessory: cacheControl
        )
        card2.addRow(rowCache, isLast: true)

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
        switch cfg.memoryAnnealDelay {
        case ..<2.0: annealControl.selectedSegment = 0
        case ..<6.0: annealControl.selectedSegment = 1
        default: annealControl.selectedSegment = 2
        }

        switch cfg.searchDebounceMs {
        case ..<100: debounceControl.selectedSegment = 0
        case ..<250: debounceControl.selectedSegment = 1
        default: debounceControl.selectedSegment = 2
        }

        switch cfg.thumbnailCacheLimitMB {
        case ..<5: cacheControl.selectedSegment = 0
        case ..<10: cacheControl.selectedSegment = 1
        default: cacheControl.selectedSegment = 2
        }

        updateMemoryMetrics()
    }

    private func updateMemoryMetrics() {
        memLabel.stringValue = String(format: "%.1f MB", currentFootprintMB())
    }

    /// Apple 官方的物理内存口径（task_vm_info.phys_footprint），与「活动监视器」
    /// 的内存列一致。此前使用 MACH_TASK_BASIC_INFO.resident_size（RSS），它把与
    /// 其他进程共享的 dyld 共享缓存和框架文本页也计入本进程，读数可达真实物理
    /// 占用的 2–3 倍（实测 RSS ≈128MB vs 真实足迹 ≈47MB）。
    private func currentFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.phys_footprint) / (1024.0 * 1024.0)
        }
        return 0
    }

    @objc private func handlePurge() {
        let before = currentFootprintMB()
        MemoryGuardian.shared.performImmediatePurge()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            let after = currentFootprintMB()
            self.updateMemoryMetrics()
            let delta = before - after
            if delta > 0.05 {
                self.purgeStatusLabel.textColor = .secondaryLabelColor
                self.purgeStatusLabel.stringValue = String(format: "已释放 %.1f MB", delta)
            } else {
                self.purgeStatusLabel.textColor = .secondaryLabelColor
                self.purgeStatusLabel.stringValue = "缓存已清空，内存占用无明显变化"
            }
        }
    }

    @objc private func annealChanged(_ sender: SettingsLiquidSegmentedControl) {
        let delays = [1.5, 3.0, 10.0]
        let sel = delays[max(0, min(delays.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateMemoryAnnealDelay(sel)
    }

    @objc private func debounceChanged(_ sender: SettingsLiquidSegmentedControl) {
        let ms = [50, 150, 300]
        let sel = ms[max(0, min(ms.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateSearchDebounceMs(sel)
    }

    @objc private func cacheLimitChanged(_ sender: SettingsLiquidSegmentedControl) {
        let mbs = [4, 6, 12]
        let sel = mbs[max(0, min(mbs.count - 1, sender.selectedSegment))]
        ConfigManager.shared.updateThumbnailCacheLimitMB(sel)
    }
}

