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
        // System kernel tier: actively return unused heap dirty pages back to XNU
        DispatchQueue.global(qos: .background).async {
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
        }
    }
}
