import Foundation
import AppKit

public final class MemoryGuardian {
    public static let shared = MemoryGuardian()
    private var annealWorkItem: DispatchWorkItem?
    private var pendingHotCacheDrop = false

    private init() {}

    public func onPanelsDidHide() {
        // 1. Immediate tier: cancel ongoing searches and spotlight queries
        SearchCoordinator.shared.cancelPendingSearches()

        // 2. Delayed tier: debounced quiet-period anneal (also drops the hot-folder snapshot)
        scheduleAnneal(dropHotCache: true)
    }

    /// Debounced quiet-period purge. Also scheduled after search activity:
    /// rapid typing churns hundreds of transient allocations (metadata queries,
    /// result closures) and the freed pages stay dirty inside the malloc zones
    /// until a pressure relief runs — measured as +20MB footprint creep after
    /// a 30-query burst with no purge scheduled.
    ///
    /// - Parameter dropHotCache: sticky across reschedules; only cleared when the
    ///   purge actually runs, so a late search delivery can't cancel a hide request.
    public func scheduleAnneal(dropHotCache: Bool = false) {
        if dropHotCache { pendingHotCacheDrop = true }
        annealWorkItem?.cancel()
        let delay = ConfigManager.shared.config.memoryAnnealDelay
        let work = DispatchWorkItem { [weak self] in
            self?.performDeepPurge()
        }
        annealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Manual "一键深度释放": also drops the icon caches.
    public func performImmediatePurge() {
        annealWorkItem?.cancel()
        ThumbnailPipeline.shared.clearCache()
        performDeepPurge()
    }

    /// Automatic anneal after hide. The icon caches (bounded by NSCache cost/count limits and
    /// evicted by the system under memory pressure) are kept: clearing them 3s after every
    /// hide forced every shelf icon to be re-rendered and pop in on the next open.
    private func performDeepPurge() {
        // Hot-folder snapshot: dropped only on the panel-hide path. The show path
        // re-warms it (maxAge=5s) anyway, and while the panel is open the snapshot
        // keeps serving instant hot-file results across typing pauses.
        if pendingHotCacheDrop {
            pendingHotCacheDrop = false
            SpotlightBridge.shared.dropHotFolderCache()
        }
        // 清理全盘搜索产生的临时文件缩略图缓存，保留已固定的抽屉应用图标
        ThumbnailPipeline.shared.clearTransientSearchCache()

        // 显式释放隐藏面板的离屏非活跃状态与多余临时缓冲
        PanelCoordinator.shared.purgeDormantOffscreenBuffers()

        // System kernel tier: actively return unused heap dirty pages back to XNU across all malloc zones
        DispatchQueue.global(qos: .background).async {
            var zones: UnsafeMutablePointer<vm_address_t>?
            var count: UInt32 = 0
            if malloc_get_all_zones(mach_task_self_, nil, &zones, &count) == KERN_SUCCESS, let zones = zones {
                for i in 0..<Int(count) {
                    if let zone = UnsafeMutablePointer<malloc_zone_t>(bitPattern: UInt(zones[i])) {
                        malloc_zone_pressure_relief(zone, 0)
                    }
                }
            }
        }
    }
}
