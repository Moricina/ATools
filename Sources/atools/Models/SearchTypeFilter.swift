import Foundation
import AppKit

public enum SearchTypeFilter: String, CaseIterable, Identifiable, Codable {
    case all = "all"
    case application = "application"
    case document = "document"
    case image = "image"
    case media = "media"
    case code = "code"
    case archive = "archive"
    case folder = "folder"

    public static let defaultOrderStrings: [String] = [
        "all", "application", "document", "image", "media", "code", "archive", "folder"
    ]

    public static func resolvedOrder(from storedStrings: [String]) -> [SearchTypeFilter] {
        var result: [SearchTypeFilter] = []
        var seen = Set<SearchTypeFilter>()
        for str in storedStrings {
            if let f = SearchTypeFilter(rawValue: str), !seen.contains(f) {
                result.append(f)
                seen.insert(f)
            }
        }
        for f in SearchTypeFilter.allCases where !seen.contains(f) {
            result.append(f)
        }
        return result
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "全部"
        case .application: return "应用"
        case .document: return "文档"
        case .image: return "图片"
        case .media: return "媒体"
        case .code: return "代码"
        case .archive: return "压缩包"
        case .folder: return "文件夹"
        }
    }

    public var iconSymbolName: String {
        switch self {
        case .all: return "sparkles"
        case .application: return "app.badge"
        case .document: return "doc.text"
        case .image: return "photo"
        case .media: return "play.tv"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "archivebox"
        case .folder: return "folder"
        }
    }

    public var shortcutNumber: Int {
        switch self {
        case .all: return 1
        case .application: return 2
        case .document: return 3
        case .image: return 4
        case .media: return 5
        case .code: return 6
        case .archive: return 7
        case .folder: return 8
        }
    }

    /// 典型文件扩展名集合（小写）
    public var extensions: Set<String> {
        switch self {
        case .all:
            return []
        case .application:
            return ["app", "prefpane"]
        case .document:
            return [
                "pdf", "doc", "docx", "txt", "md", "markdown", "pages", "numbers", "key",
                "keynote", "xlsx", "xls", "pptx", "ppt", "csv", "rtf", "epub", "mobi"
            ]
        case .image:
            return [
                "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "heif", "psd", "ai",
                "tiff", "tif", "bmp", "ico", "raw", "cr2", "nef"
            ]
        case .media:
            return [
                "mp4", "mov", "mkv", "avi", "webm", "flv", "wmv", "mp3", "flac", "wav",
                "aac", "m4a", "ogg", "wma"
            ]
        case .code:
            return [
                "swift", "py", "js", "ts", "jsx", "tsx", "c", "cpp", "cc", "cxx", "h", "hpp",
                "m", "mm", "sh", "bash", "zsh", "json", "yaml", "yml", "xml", "html", "css",
                "scss", "sass", "less", "rs", "go", "java", "kt", "kts", "rb", "php", "sql",
                "lua", "r", "dart", "vue", "scala"
            ]
        case .archive:
            return [
                "zip", "tar", "gz", "tgz", "7z", "rar", "dmg", "iso", "pkg", "xz", "bz2", "zst"
            ]
        case .folder:
            return []
        }
    }

    /// CoreServices MDQuery 专用的 ContentType 过滤谓词片段。
    /// 当返回 nil 时表示无额外 ContentType 限制。
    public var mdQueryContentTypePredicate: String? {
        switch self {
        case .all:
            return nil
        case .application:
            // 应用直接走 Layer 1 AppHotspotIndex，跳过 MDQuery
            return nil
        case .document:
            return "(kMDItemContentTypeTree == 'public.composite-content' || kMDItemContentTypeTree == 'public.text')"
        case .image:
            return "(kMDItemContentTypeTree == 'public.image')"
        case .media:
            return "(kMDItemContentTypeTree == 'public.audiovisual-content')"
        case .code:
            // 现代语言通配补充，解决 .ts, .go, .rs, .json, .yaml 等 UTType 脱节问题
            return "((kMDItemContentTypeTree == 'public.source-code' || kMDItemContentTypeTree == 'public.script') || (kMDItemFSName == '*.ts'c || kMDItemFSName == '*.go'c || kMDItemFSName == '*.rs'c || kMDItemFSName == '*.json'c || kMDItemFSName == '*.yaml'c || kMDItemFSName == '*.yml'c || kMDItemFSName == '*.html'c || kMDItemFSName == '*.css'c))"
        case .archive:
            return "(kMDItemContentTypeTree == 'public.archive' || kMDItemContentTypeTree == 'com.apple.disk-image')"
        case .folder:
            return "(kMDItemContentTypeTree == 'public.folder')"
        }
    }

    /// 热目录快照内存极速判定
    public func matches(filename: String, isDirectory: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .application:
            return filename.hasSuffix(".app") || filename.hasSuffix(".prefPane")
        case .folder:
            return isDirectory && !filename.hasSuffix(".app")
        case .document, .image, .media, .code, .archive:
            if isDirectory { return false }
            let ext = (filename as NSString).pathExtension.lowercased()
            return extensions.contains(ext)
        }
    }

    /// 从用户输入中提取前缀语法，如 "doc: report" 或 "code: main.swift" 或 "#img logo"
    public static func extractPrefix(from text: String) -> (filter: SearchTypeFilter, query: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let prefixes: [(prefix: String, filter: SearchTypeFilter)] = [
            ("all:", .all), ("全部:", .all), ("#all", .all), ("/all ", .all), ("/all:", .all),
            ("app:", .application), ("应用:", .application), ("#app", .application), ("/app ", .application), ("/app:", .application),
            ("doc:", .document), ("文档:", .document), ("#doc", .document), ("/doc ", .document), ("/doc:", .document),
            ("img:", .image), ("pic:", .image), ("图片:", .image), ("#img", .image), ("#pic", .image), ("/img ", .image), ("/img:", .image), ("/pic ", .image), ("/pic:", .image),
            ("media:", .media), ("video:", .media), ("audio:", .media), ("媒体:", .media), ("#media", .media), ("/media ", .media), ("/media:", .media), ("/video ", .media), ("/video:", .media),
            ("code:", .code), ("代码:", .code), ("#code", .code), ("/code ", .code), ("/code:", .code),
            ("archive:", .archive), ("zip:", .archive), ("压缩包:", .archive), ("#zip", .archive), ("/zip ", .archive), ("/zip:", .archive), ("/archive ", .archive), ("/archive:", .archive),
            ("folder:", .folder), ("dir:", .folder), ("文件夹:", .folder), ("#folder", .folder), ("#dir", .folder), ("/folder ", .folder), ("/folder:", .folder), ("/dir ", .folder), ("/dir:", .folder)
        ]

        let lower = trimmed.lowercased()
        for p in prefixes {
            if lower.hasPrefix(p.prefix) {
                let rest = String(trimmed.dropFirst(p.prefix.count)).trimmingCharacters(in: .whitespaces)
                return (p.filter, rest)
            }
        }
        return nil
    }
}
