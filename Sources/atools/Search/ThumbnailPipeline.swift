import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

public final class ThumbnailPipeline {
    public static let shared = ThumbnailPipeline()

    private let cache = NSCache<NSString, NSImage>()
    private let genericCache = NSCache<NSString, NSImage>()
    private let targetSize = CGSize(width: 64, height: 64)
    /// Bounded concurrency: icon rendering is CPU-bound, and an unbounded concurrent queue
    /// spun up one thread per shelf item.
    private let renderQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "cc.atools.thumbnail"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 4
        return q
    }()
    /// Main-thread only: callbacks waiting for an icon that is already being rendered.
    private var pendingCallbacks: [String: [(NSImage) -> Void]] = [:]

    private init() {
        cache.countLimit = AppConstants.thumbnailCacheCountLimit
        cache.totalCostLimit = 6 * 1024 * 1024 // 6 MB default limit
        genericCache.countLimit = AppConstants.genericCacheCountLimit
        genericCache.totalCostLimit = 6 * 1024 * 1024 // 6 MB default limit
    }

    public func updateCostLimit(mb: Int) {
        let bytes = mb * 1024 * 1024
        cache.totalCostLimit = bytes
        genericCache.totalCostLimit = bytes
    }

    public func clearCache() {
        cache.removeAllObjects()
        genericCache.removeAllObjects()
    }

    public func icon(forPath path: String, completion: @escaping (NSImage) -> Void) {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let isApp = ext == "app"
        let isDir = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        // For common documents, return shared generic icon immediately
        if !isApp && !isDir && !ext.isEmpty {
            if let generic = genericIcon(forExtension: ext) {
                completion(generic)
                return
            }
        }

        if pendingCallbacks[path] != nil {
            pendingCallbacks[path]?.append(completion)
            return
        }
        pendingCallbacks[path] = [completion]

        // Generate thumbnail asynchronously
        renderQueue.addOperation { [weak self] in
            guard let self = self else { return }

            let url = URL(fileURLWithPath: path)
            var finalImage: NSImage?

            // For non-apps, try QLThumbnailGenerator
            if !isApp && FileManager.default.fileExists(atPath: path) {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: self.targetSize,
                    scale: 2.0,
                    representationTypes: .thumbnail
                )
                let semaphore = DispatchSemaphore(value: 0)
                let box = ThumbnailResultBox()
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                    box.store(rep?.nsImage)
                    semaphore.signal()
                }
                if semaphore.wait(timeout: .now() + 0.08) == .timedOut {
                    // The generator may still call back later; never let it write concurrently.
                    box.close()
                }
                finalImage = box.take()
            }

            // Fallback to NSWorkspace icon downsampled
            if finalImage == nil {
                let rawIcon = NSWorkspace.shared.icon(forFile: path)
                finalImage = self.downsample(image: rawIcon, to: self.targetSize)
            }

            let fallbackType = UTType(filenameExtension: ext) ?? .data
            let result = finalImage ?? NSWorkspace.shared.icon(for: fallbackType)
            self.cache.setObject(result, forKey: key, cost: Self.costBytes(for: result))

            DispatchQueue.main.async {
                let callbacks = self.pendingCallbacks.removeValue(forKey: path) ?? []
                callbacks.forEach { $0(result) }
            }
        }
    }

    public func genericIcon(forExtension ext: String) -> NSImage? {
        let key = ext as NSString
        if let cached = genericCache.object(forKey: key) {
            return cached
        }

        let type = UTType(filenameExtension: ext) ?? .data
        let raw = NSWorkspace.shared.icon(for: type)
        let downsampled = downsample(image: raw, to: targetSize)
        genericCache.setObject(downsampled, forKey: key, cost: Self.costBytes(for: downsampled))
        return downsampled
    }

    public func symbolIcon(name: String, pointSize: CGFloat = 22, weight: NSFont.Weight = .regular) -> NSImage {
        let key = "symbol:\(name)_\(Int(pointSize))_\(weight.rawValue)" as NSString
        if let cached = genericCache.object(forKey: key) {
            return cached
        }

        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            let configured = (img.withSymbolConfiguration(config) ?? img).copy() as! NSImage
            configured.isTemplate = true
            genericCache.setObject(configured, forKey: key, cost: Self.costBytes(for: configured))
            return configured
        }

        let fallback = NSWorkspace.shared.icon(for: .data)
        return fallback
    }

    /// Estimates the resident byte cost of an image using its backing pixel data when measurable,
    /// falling back to a conservative constant for small icons/symbols.
    private static func costBytes(for image: NSImage) -> Int {
        var size = image.size
        if let rep = image.representations.first {
            size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        let estimate = Int(max(1, size.width)) * Int(max(1, size.height)) * 4
        return max(AppConstants.fallbackImageCostBytes, estimate)
    }

    private func downsample(image: NSImage, to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size),
                   from: CGRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

/// Hands a QuickLook result across threads; late callbacks after a timeout are dropped.
private final class ThumbnailResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var image: NSImage?
    private var isClosed = false

    func store(_ newImage: NSImage?) {
        lock.lock()
        if !isClosed { image = newImage }
        lock.unlock()
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }

    func take() -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return image
    }
}
