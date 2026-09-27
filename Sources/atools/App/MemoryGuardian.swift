import Foundation
import AppKit

public final class MemoryGuardian {
    public static let shared = MemoryGuardian()
    private var annealWorkItem: DispatchWorkItem?

    private init() {}

    public func onPanelsDidHide() {
        // 1. Immediate tier: cancel ongoing searches and spotlight queries
        SearchCoordinator.shared.cancelPendingSearches()

        // 2. Delayed tier: dynamic anneal delay from config, purge memory and return dirty pages
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
        // 3. System kernel tier: actively return unused heap dirty pages back to XNU
        DispatchQueue.global(qos: .background).async {
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
        }
    }
}
