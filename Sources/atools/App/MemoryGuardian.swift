import Foundation
import AppKit

public final class MemoryGuardian {
    public static let shared = MemoryGuardian()
    private var annealWorkItem: DispatchWorkItem?

    private init() {}

    public func onPanelsDidHide() {
        // 1. Immediate tier: cancel ongoing searches and spotlight queries
        SpotlightBridge.shared.stop()

        // 2. Delayed tier: dynamic anneal delay from config, purge memory and return dirty pages
        annealWorkItem?.cancel()
        let delay = ConfigManager.shared.config.memoryAnnealDelay
        let work = DispatchWorkItem { [weak self] in
            self?.performDeepPurge()
        }
        annealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func performImmediatePurge() {
        annealWorkItem?.cancel()
        performDeepPurge()
    }

    private func performDeepPurge() {
        ThumbnailPipeline.shared.clearCache()

        // 3. System kernel tier: actively return unused heap dirty pages back to XNU
        DispatchQueue.global(qos: .background).async {
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
        }
    }
}
