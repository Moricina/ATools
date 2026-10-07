import Foundation
import AppKit

public enum SearchSyntaxActionType: Equatable {
    case applyFilter(SearchTypeFilter)
    case webSearch
    case calculator
    case systemAction(id: String)
}

public struct SearchSyntaxCommand: Identifiable, Equatable {
    public let id: String
    public let trigger: String           // e.g. "/doc"
    public let name: String              // e.g. "文档"
    public let iconSymbolName: String    // e.g. "doc.text"
    public let description: String       // e.g. "仅搜索 Word, PDF, Markdown 等文档"
    public let filter: SearchTypeFilter?
    public let actionType: SearchSyntaxActionType
    public let aliases: [String]         // e.g. ["/dir"] for "/folder"

    public init(
        id: String,
        trigger: String,
        name: String,
        iconSymbolName: String,
        description: String,
        filter: SearchTypeFilter? = nil,
        actionType: SearchSyntaxActionType,
        aliases: [String] = []
    ) {
        self.id = id
        self.trigger = trigger
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.description = description
        self.filter = filter
        self.actionType = actionType
        self.aliases = aliases
    }

    public static let allCommands: [SearchSyntaxCommand] = [
        SearchSyntaxCommand(
            id: "cmd_doc",
            trigger: "/doc",
            name: "文档",
            iconSymbolName: "doc.text",
            description: "仅搜索 Word、PDF、Excel、PPT、Markdown 等文档",
            filter: .document,
            actionType: .applyFilter(.document)
        ),
        SearchSyntaxCommand(
            id: "cmd_code",
            trigger: "/code",
            name: "代码",
            iconSymbolName: "chevron.left.forwardslash.chevron.right",
            description: "仅搜索 Swift、Python、TS、Go、Rust、JSON 等源代码",
            filter: .code,
            actionType: .applyFilter(.code)
        ),
        SearchSyntaxCommand(
            id: "cmd_app",
            trigger: "/app",
            name: "应用",
            iconSymbolName: "app.badge",
            description: "仅搜索与启动应用程序，支持拼音首拼与极速直出",
            filter: .application,
            actionType: .applyFilter(.application)
        ),
        SearchSyntaxCommand(
            id: "cmd_img",
            trigger: "/img",
            name: "图片",
            iconSymbolName: "photo",
            description: "仅搜索 PNG、JPG、SVG、WebP、HEIC 等图像文件",
            filter: .image,
            actionType: .applyFilter(.image),
            aliases: ["/pic"]
        ),
        SearchSyntaxCommand(
            id: "cmd_media",
            trigger: "/media",
            name: "音视频",
            iconSymbolName: "play.tv",
            description: "仅搜索 MP4、MOV、MP3、FLAC 等音视频文件",
            filter: .media,
            actionType: .applyFilter(.media),
            aliases: ["/video", "/audio"]
        ),
        SearchSyntaxCommand(
            id: "cmd_zip",
            trigger: "/zip",
            name: "压缩包",
            iconSymbolName: "archivebox",
            description: "仅搜索 ZIP、RAR、7z、TAR、DMG 等存档文件",
            filter: .archive,
            actionType: .applyFilter(.archive),
            aliases: ["/archive"]
        ),
        SearchSyntaxCommand(
            id: "cmd_folder",
            trigger: "/folder",
            name: "文件夹",
            iconSymbolName: "folder",
            description: "仅搜索普通目录与工作夹",
            filter: .folder,
            actionType: .applyFilter(.folder),
            aliases: ["/dir"]
        ),
        SearchSyntaxCommand(
            id: "cmd_web",
            trigger: "/web",
            name: "网页",
            iconSymbolName: "globe",
            description: "在默认浏览器中进行网页搜索",
            actionType: .webSearch,
            aliases: ["/g"]
        ),
        SearchSyntaxCommand(
            id: "cmd_calc",
            trigger: "/calc",
            name: "计算器",
            iconSymbolName: "equal",
            description: "快速计算数学算式（如 /calc 1024*768）",
            actionType: .calculator
        ),
        SearchSyntaxCommand(
            id: "cmd_lock",
            trigger: "/lock",
            name: "锁屏",
            iconSymbolName: "lock.fill",
            description: "立即锁定当前 Mac 屏幕",
            actionType: .systemAction(id: "lock_screen")
        ),
        SearchSyntaxCommand(
            id: "cmd_sleep",
            trigger: "/sleep",
            name: "睡眠",
            iconSymbolName: "moon.fill",
            description: "让系统立即进入睡眠模式",
            actionType: .systemAction(id: "sleep")
        ),
        SearchSyntaxCommand(
            id: "cmd_empty",
            trigger: "/empty",
            name: "清空废纸篓",
            iconSymbolName: "trash.fill",
            description: "安全清空系统废纸篓",
            actionType: .systemAction(id: "empty_trash")
        ),
        SearchSyntaxCommand(
            id: "cmd_restart",
            trigger: "/restart",
            name: "重启",
            iconSymbolName: "arrow.clockwise",
            description: "重新启动这台 Mac",
            actionType: .systemAction(id: "restart")
        )
    ]

    /// 根据用户输入前缀过滤指令（如 "/" 返回全部，"/d" 返回 doc / dir，"/c" 返回 code / calc）
    public static func matching(prefix: String) -> [SearchSyntaxCommand] {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let clean = trimmed.lowercased()

        if clean == "/" {
            return allCommands
        }

        let term = clean.dropFirst() // e.g. "d" from "/d"
        return allCommands.filter { cmd in
            let cmdTrigger = cmd.trigger.lowercased().dropFirst() // e.g. "doc"
            if cmdTrigger.hasPrefix(term) { return true }
            if cmd.name.lowercased().contains(term) { return true }
            for alias in cmd.aliases {
                let aliasTrigger = alias.lowercased().dropFirst()
                if aliasTrigger.hasPrefix(term) { return true }
            }
            return false
        }
    }
}
