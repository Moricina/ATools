import Foundation
import AppKit

public enum SearchResultType: String, Codable, Sendable {
    case application
    case file
    case folder
    case calculator
    case dictionary
    case systemAction
    case webSearch
    case syntaxCommand
}

/// 军师加固点 2：后台检索线程统一产出的轻量不可变跨隔离区安全载荷（严格 Sendable 合规，不持有 NSImage 与逃逸闭包）。
/// 跨入 @MainActor / 主线程边界后再调用 `materializeSearchResult()` 绑定图片与交互动作。
public struct RawSearchResultPayload: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let path: String?
    public let customIconPath: String?
    public let type: SearchResultType
    public let score: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        path: String? = nil,
        customIconPath: String? = nil,
        type: SearchResultType,
        score: Int = 0
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.customIconPath = customIconPath
        self.type = type
        self.score = score
    }

    public func materializeSearchResult() -> SearchResult {
        let targetPath = self.path
        return SearchResult(
            id: id,
            title: title,
            subtitle: subtitle,
            path: path,
            customIconPath: customIconPath,
            type: type,
            score: score,
            icon: nil,
            action: targetPath.map { p in
                { LauncherExecutor.open(path: p) }
            }
        )
    }
}

public struct SearchResult: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let path: String?
    public let customIconPath: String?
    public let type: SearchResultType
    public let score: Int
    public var icon: NSImage?
    public var action: (() -> Void)?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        path: String? = nil,
        customIconPath: String? = nil,
        type: SearchResultType,
        score: Int = 0,
        icon: NSImage? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.customIconPath = customIconPath
        self.type = type
        self.score = score
        self.icon = icon
        self.action = action
    }
}

extension SearchResult {
    /// 标准化导出 NSPasteboardWriting，用于拖拽至微信、QQ、钉钉、访达等外部应用
    public var pasteboardWriter: (any NSPasteboardWriting)? {
        switch type {
        case .application, .file, .folder:
            guard let p = path, !p.isEmpty, FileManager.default.fileExists(atPath: p) else { return nil }
            return URL(fileURLWithPath: p) as NSURL
        case .calculator:
            // 剥离 "= " 前缀，输出纯计算结果数值
            let rawText = title.hasPrefix("= ") ? String(title.dropFirst(2)) : title
            return rawText as NSString
        case .dictionary:
            return "\(title): \(subtitle)" as NSString
        case .webSearch:
            // The web result id is "web_<query>"; honour the user's configured engine.
            guard id.hasPrefix("web_") else { return nil }
            let query = String(id.dropFirst(4))
            let config = ConfigManager.shared.config
            return config.webSearchEngine.searchURL(for: query, customTemplate: config.customWebSearchURL) as NSURL?
        case .systemAction, .syntaxCommand:
            return nil
        }
    }
}
