import Foundation

/// Centralized tunables for app indexing, search and thumbnail caching.
/// Values are preserved from the original scattered literals to avoid behavior changes.
public enum AppConstants {
    /// Maximum in-memory application results surfaced by the instant search layer.
    public static let instantAppResultCount = 15

    /// Maximum directory depth scanned while building the application hotspot index.
    public static let appIndexScanDepth = 2

    /// Maximum directory depth scanned inside Spotlight hot folders (Downloads/Desktop/Documents).
    public static let spotlightHotFolderDepth = 3

    /// Hard cap on entries kept per hot folder snapshot (bounds worst-case string memory
    /// on machines with very large Downloads trees; full results still come from Spotlight).
    public static let hotFolderEntryCap = 25_000

    /// Hard cap on the number of auto-detected "常用" applications.
    public static let commonApplicationsLimit = 6

    /// Thumbnail cache object-count limits.
    public static let thumbnailCacheCountLimit = 250
    public static let genericCacheCountLimit = 150

    /// Bitmap byte estimate used when the image's backing bytes cannot be measured directly.
    public static let fallbackImageCostBytes = 64 * 64 * 4

    /// Custom pasteboard types used for internal drag-and-drop.
    public static let shelfItemReorderType = "cc.atools.shelf-item-reorder"
    public static let shelfItemMoveType = "cc.atools.shelf-item-move"
    public static let categoryReorderType = "cc.atools.category-reorder"
}
