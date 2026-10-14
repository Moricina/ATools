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

    /// 驱逐指定启动项或路径的缩略图缓存（用于更换自定义图标或重新定位目标后立即刷新）
    public func invalidateIcon(forItem item: LauncherItem) {
        cache.removeObject(forKey: item.target as NSString)
        if let custom = item.customIconPath, !custom.isEmpty {
            let customKey = Self.cacheKey(forPath: item.target, customIconPath: custom) as NSString
            cache.removeObject(forKey: customKey)
        }
    }

    public func invalidateIcon(forPath path: String, customIconPath: String? = nil) {
        cache.removeObject(forKey: path as NSString)
        if let custom = customIconPath, !custom.isEmpty {
            let customKey = Self.cacheKey(forPath: path, customIconPath: custom) as NSString
            cache.removeObject(forKey: customKey)
        }
    }

    public static func cacheKey(forPath path: String, customIconPath: String?) -> String {
        if let custom = customIconPath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return "custom:\(custom)|\(path)"
        }
        return path
    }

    /// 保留应用抽屉已固定的关键应用图标与自定义图标（防止重新展开抽屉时发生重绘或闪烁），同时清空全盘搜索中产生的临时文件缩略图缓存
    public func clearTransientSearchCache() {
        let allItems = ConfigManager.shared.config.categories.flatMap { $0.items }
        var keysToKeep = Set<String>()
        for item in allItems {
            keysToKeep.insert(item.target)
            if let custom = item.customIconPath, !custom.isEmpty {
                keysToKeep.insert(Self.cacheKey(forPath: item.target, customIconPath: custom))
            }
        }
        var shelfImages: [(NSString, NSImage, Int)] = []
        for k in keysToKeep {
            let nsKey = k as NSString
            if let img = cache.object(forKey: nsKey) {
                shelfImages.append((nsKey, img, Self.costBytes(for: img)))
            }
        }
        cache.removeAllObjects()
        for (k, img, cost) in shelfImages {
            cache.setObject(img, forKey: k, cost: cost)
        }
    }

    /// 优先读取 LauncherItem.customIconPath，若无或文件不存在则自动回退至 target 原生图标
    public func icon(forItem item: LauncherItem, completion: @escaping (NSImage) -> Void) {
        icon(forPath: item.target, customIconPath: item.customIconPath, completion: completion)
    }

    public func icon(forPath path: String, customIconPath: String? = nil, completion: @escaping (NSImage) -> Void) {
        let trimmedCustom = customIconPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidCustom: Bool
        if let c = trimmedCustom, !c.isEmpty, FileManager.default.fileExists(atPath: c) {
            hasValidCustom = true
        } else {
            hasValidCustom = false
        }

        let effectiveKeyString = hasValidCustom ? Self.cacheKey(forPath: path, customIconPath: trimmedCustom) : path
        let key = effectiveKeyString as NSString

        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let isApp = ext == "app"
        let isDir = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        // 若未设置自定义图标，对于普通文档直接返回共享类型图标
        if !hasValidCustom && !isApp && !isDir && !ext.isEmpty {
            if let generic = genericIcon(forExtension: ext) {
                completion(generic)
                return
            }
        }

        if pendingCallbacks[effectiveKeyString] != nil {
            pendingCallbacks[effectiveKeyString]?.append(completion)
            return
        }
        pendingCallbacks[effectiveKeyString] = [completion]

        // Generate thumbnail asynchronously
        renderQueue.addOperation { [weak self] in
            guard let self = self else { return }

            var finalImage: NSImage?

            // 1. 优先尝试读取 customIconPath (P0-1)
            if hasValidCustom, let customPath = trimmedCustom {
                if customPath.lowercased().hasSuffix(".app") {
                    let rawIcon = NSWorkspace.shared.icon(forFile: customPath)
                    finalImage = self.downsample(image: rawIcon, to: self.targetSize)
                } else if let loaded = NSImage(contentsOfFile: customPath) {
                    finalImage = self.downsample(image: loaded, to: self.targetSize)
                }
            }

            // 2. 对非应用目标尝试 QLThumbnailGenerator
            if finalImage == nil && !isApp && FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
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
                    box.close()
                }
                finalImage = box.take()
            }

            // 3. 回退到 NSWorkspace 图标并缩放
            if finalImage == nil {
                let rawIcon = NSWorkspace.shared.icon(forFile: path)
                finalImage = self.downsample(image: rawIcon, to: self.targetSize)
            }

            let fallbackType = UTType(filenameExtension: ext) ?? .data
            let result = finalImage ?? NSWorkspace.shared.icon(for: fallbackType)
            self.cache.setObject(result, forKey: key, cost: Self.costBytes(for: result))

            DispatchQueue.main.async {
                let callbacks = self.pendingCallbacks.removeValue(forKey: effectiveKeyString) ?? []
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

    /// 线程安全的透明通道保留灰阶渲染（用于 P0-2 失效启动项半透明灰阶图标展示）
    public func grayscaleImage(for image: NSImage) -> NSImage {
        let width = Int(targetSize.width * 2)
        let height = Int(targetSize.height * 2)
        let bytesPerRow = width * 4
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        let rect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(in: rect, from: CGRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        if let data = context.data {
            let ptr = data.assumingMemoryBound(to: UInt8.self)
            let totalBytes = width * height * 4
            var i = 0
            while i < totalBytes {
                let r = Int(ptr[i])
                let g = Int(ptr[i + 1])
                let b = Int(ptr[i + 2])
                let luma = UInt8(min(255, (77 * r + 150 * g + 29 * b) >> 8))
                ptr[i] = luma
                ptr[i + 1] = luma
                ptr[i + 2] = luma
                i += 4
            }
        }

        guard let cgImage = context.makeImage() else { return image }
        return NSImage(cgImage: cgImage, size: targetSize)
    }

    /// 将用户选择的 .png / .icns / .jpg / .app 图标归一化裁剪缩放为标准 256x256 PNG 数据（用于 P0-1 托管存储）
    public func normalizedCustomIconPNGData(from sourceURL: URL, pixelSize: Int = 256) -> Data? {
        let path = sourceURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let sourceImage: NSImage?
        if path.lowercased().hasSuffix(".app") {
            sourceImage = NSWorkspace.shared.icon(forFile: path)
        } else {
            sourceImage = NSImage(contentsOf: sourceURL)
        }
        guard let img = sourceImage, img.size.width > 0, img.size.height > 0 else { return nil }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let targetRect = CGRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize))
        // 等比居中缩放裁剪（对于非正方形图片保持比例居中绘制，避免拉伸变形）
        let srcW = img.size.width
        let srcH = img.size.height
        let scale = min(CGFloat(pixelSize) / srcW, CGFloat(pixelSize) / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawRect = CGRect(
            x: (CGFloat(pixelSize) - drawW) / 2.0,
            y: (CGFloat(pixelSize) - drawH) / 2.0,
            width: drawW,
            height: drawH
        )

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        context.clear(targetRect)
        context.interpolationQuality = .high
        img.draw(in: drawRect, from: CGRect(origin: .zero, size: img.size), operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
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
        let width = Int(size.width * 2)
        let height = Int(size.height * 2)
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        let rect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        context.interpolationQuality = .high
        image.draw(in: rect, from: CGRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return image }
        return NSImage(cgImage: cgImage, size: size)
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
