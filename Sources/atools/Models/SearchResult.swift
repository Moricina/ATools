import Foundation
import AppKit

public enum SearchResultType: String, Codable {
    case application
    case file
    case folder
    case calculator
    case dictionary
    case systemAction
    case webSearch
}

public struct SearchResult: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let path: String?
    public let type: SearchResultType
    public let score: Int
    public var icon: NSImage?
    public var action: (() -> Void)?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        path: String? = nil,
        type: SearchResultType,
        score: Int = 0,
        icon: NSImage? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
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
            let query = title.replacingOccurrences(of: "在浏览器中搜索 \"", with: "").replacingOccurrences(of: "\"", with: "")
            if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                return url as NSURL
            }
            return nil
        case .systemAction:
            return nil
        }
    }
}
