import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// 幽灵底板尺寸匹配器（支持区间容差）
public struct GhostWindowSize: Equatable, Sendable {
    public let widthMin: Double
    public let widthMax: Double
    public let heightMin: Double
    public let heightMax: Double

    public init(w: Double, h: Double, tolerance: Double = 25.0) {
        self.widthMin = max(0, w - tolerance)
        self.widthMax = w + tolerance
        self.heightMin = max(0, h - tolerance)
        self.heightMax = h + tolerance
    }

    public func matches(width: Double, height: Double) -> Bool {
        return (widthMin...widthMax).contains(width) && (heightMin...heightMax).contains(height)
    }
}

/// 针对特定应用行为的规则模型（替代主循环中的硬编码）
public struct AppQuirkRule: Sendable {
    public let id: String
    public let name: String
    public let bundleIDPrefixes: [String]
    public let ownerNameKeywords: [String]
    public let offscreenTitles: Set<String>
    public let ghostSizes: [GhostWindowSize]
    public let isVirtualizationOrContainer: Bool
    public let companionBundleIDs: [String]
    public let terminateHelpersInBundle: Bool
    public let cleanAllOffscreenWindows: Bool
    public let cleanEmptyTitleOffscreenWindows: Bool
    public let exactTitleMatchOnly: Bool

    public init(
        id: String,
        name: String,
        bundleIDPrefixes: [String] = [],
        ownerNameKeywords: [String] = [],
        offscreenTitles: Set<String> = [],
        ghostSizes: [GhostWindowSize] = [],
        isVirtualizationOrContainer: Bool = false,
        companionBundleIDs: [String] = [],
        terminateHelpersInBundle: Bool = false,
        cleanAllOffscreenWindows: Bool = false,
        cleanEmptyTitleOffscreenWindows: Bool = false,
        exactTitleMatchOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIDPrefixes = bundleIDPrefixes
        self.ownerNameKeywords = ownerNameKeywords
        self.offscreenTitles = Set(offscreenTitles.map { $0.lowercased() })
        self.ghostSizes = ghostSizes
        self.isVirtualizationOrContainer = isVirtualizationOrContainer
        self.companionBundleIDs = companionBundleIDs
        self.terminateHelpersInBundle = terminateHelpersInBundle
        self.cleanAllOffscreenWindows = cleanAllOffscreenWindows
        self.cleanEmptyTitleOffscreenWindows = cleanEmptyTitleOffscreenWindows
        self.exactTitleMatchOnly = exactTitleMatchOnly
    }

    public func matches(bundleID: String?, ownerName: String?) -> Bool {
        let lowerBid = (bundleID ?? "").lowercased()
        let lowerOwner = (ownerName ?? "").lowercased()

        for prefix in bundleIDPrefixes {
            if lowerBid.hasPrefix(prefix.lowercased()) || lowerBid.contains(prefix.lowercased()) {
                return true
            }
        }
        for kw in ownerNameKeywords {
            if lowerOwner.contains(kw.lowercased()) {
                return true
            }
        }
        return false
    }

    public func shouldCleanOffscreen(title: String, width: Double, height: Double, spaces: [UInt64] = [], currentSpace: UInt64 = 0) -> Bool {
        // 核心安全屏障 A：若窗口明确属于其他未激活桌面 Space（isWindowOnAnotherSpace），且具备业务视窗基础尺寸，
        // 则其必然是用户置于其他桌面 Space 的合法活跃视窗，享有最高级豁免权，严禁被 cleanAllOffscreenWindows 清洗！
        if AutoQuitQuirks.isWindowOnAnotherSpace(spaces: spaces, currentSpace: currentSpace) && width > 120 && height > 70 {
            return false
        }
        if cleanAllOffscreenWindows {
            // 核心安全屏障 B：全屏尺寸（如 1512x982、2560x1440 等）属于有效全屏业务视窗，绝不被 cleanAllOffscreenWindows 清洗
            if AutoQuitQuirks.isNativeFullscreenSize(width: width, height: height) {
                return false
            }
            return true
        }
        let lowerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanEmptyTitleOffscreenWindows && lowerTitle.isEmpty {
            // 全屏尺寸的放映/无标题全屏窗口绝不是关窗残留底板（如 1512x830）
            if AutoQuitQuirks.isNativeFullscreenSize(width: width, height: height) {
                return false
            }
            return true
        }
        if !lowerTitle.isEmpty {
            let isMatchedTitle: Bool
            if offscreenTitles.contains(lowerTitle) {
                isMatchedTitle = true
            } else if !exactTitleMatchOnly {
                isMatchedTitle = offscreenTitles.contains(where: { !$0.isEmpty && lowerTitle.contains($0) })
            } else {
                isMatchedTitle = false
            }

            if isMatchedTitle {
                // 关键安全门禁：当规则显式配置了幽灵尺寸 (ghostSizes) 时，
                // 仅当窗口尺寸命中预设的 ghostSizes，或属于微型辅助浮窗 (<= 500x380) 时才作为离屏幽灵清理；
                // 正常大尺寸业务视窗（如 WPS 首页 1512x870、常规文档等）绝不可仅因标题命中离屏词典而被误杀！
                if !ghostSizes.isEmpty {
                    let matchesGhostSize = ghostSizes.contains(where: { $0.matches(width: width, height: height) })
                    if matchesGhostSize || (width <= 500 && height <= 380) {
                        return true
                    }
                    return false
                }
                return true
            }
        }
        for size in ghostSizes {
            if size.matches(width: width, height: height) {
                return true
            }
        }
        return false
    }
}

/// 规则引擎单例与内置 Quirks 库
public final class AutoQuitQuirks: @unchecked Sendable {
    public static let shared = AutoQuitQuirks()

    /// 内置通用设置与偏好词典（小写）
    public static let genericSettingsTitles: Set<String> = [
        "设置", "偏好设置", "settings", "preferences", "preference"
    ]

    /// 系统辅助与代理视图名称（小写）
    public static let systemProxyNames: Set<String> = [
        "touch bar", "focus proxy", "item status", "emoji & symbols", "focusproxy"
    ]

    /// 常见内部 CEF 控件名称（小写）
    public static let internalCefViewNames: Set<String> = [
        "convtablistview", "convtabtopbar", "mainmenupanelview", "form"
    ]

    /// 通用 CEF/AppKit 离屏缓冲画布模板尺寸
    public static let genericCefGhostSizes: [GhostWindowSize] = [
        GhostWindowSize(w: 640, h: 508, tolerance: 20),
        GhostWindowSize(w: 600, h: 600, tolerance: 20),
        GhostWindowSize(w: 640, h: 480, tolerance: 20),
        GhostWindowSize(w: 500, h: 500, tolerance: 25)
    ]

    /// 内置针对已知疑难应用的兼容规则
    public let builtinRules: [AppQuirkRule] = [
        // 虚拟机、模拟器与容器平台保护（常驻后台/无感融合/杜绝崩溃及数据丢失）
        AppQuirkRule(
            id: "parallels",
            name: "Parallels Desktop",
            bundleIDPrefixes: ["com.parallels."],
            ownerNameKeywords: ["parallels"],
            isVirtualizationOrContainer: true
        ),
        AppQuirkRule(
            id: "vmware",
            name: "VMware Fusion",
            bundleIDPrefixes: ["com.vmware."],
            ownerNameKeywords: ["vmware"],
            isVirtualizationOrContainer: true
        ),
        AppQuirkRule(
            id: "utm",
            name: "UTM",
            bundleIDPrefixes: ["com.utmapp."],
            ownerNameKeywords: ["utm"],
            isVirtualizationOrContainer: true
        ),
        AppQuirkRule(
            id: "virtualbox",
            name: "VirtualBox",
            bundleIDPrefixes: ["org.virtualbox."],
            ownerNameKeywords: ["virtualbox"],
            isVirtualizationOrContainer: true
        ),
        AppQuirkRule(
            id: "docker",
            name: "Docker",
            bundleIDPrefixes: ["com.docker."],
            ownerNameKeywords: ["docker"],
            isVirtualizationOrContainer: true
        ),
        AppQuirkRule(
            id: "android_emulator",
            name: "Android Emulator",
            bundleIDPrefixes: ["com.google.android.simulator", "com.android.emulator"],
            ownerNameKeywords: ["qemu-system", "emulator"],
            isVirtualizationOrContainer: true
        ),

        // 国产/特定 CEF/AppKit 应用离屏底板与残留图层清洗规则
        AppQuirkRule(
            id: "wps",
            name: "WPS Office",
            bundleIDPrefixes: ["com.kingsoft.wpsoffice"],
            ownerNameKeywords: ["wps", "wpsoffice"],
            offscreenTitles: ["wps office", "首页", "稻壳素材", "快速访问工具栏"],
            ghostSizes: [GhostWindowSize(w: 420, h: 154, tolerance: 15)],
            terminateHelpersInBundle: true,
            cleanEmptyTitleOffscreenWindows: true,
            exactTitleMatchOnly: true
        ),
        AppQuirkRule(
            id: "quark",
            name: "夸克网盘",
            bundleIDPrefixes: ["com.quark.desktop", "com.quark"],
            ownerNameKeywords: ["夸克", "quark"],
            offscreenTitles: ["夸克", "quark", "分享链接", "图片预览"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "tencent_docs",
            name: "腾讯文档",
            bundleIDPrefixes: ["com.tencent.tencentdocs"],
            ownerNameKeywords: ["qqexdoc", "tencentdocs"],
            offscreenTitles: ["腾讯文档", "tencentdocs"],
            ghostSizes: [GhostWindowSize(w: 1366, h: 800, tolerance: 25)],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "dingtalk",
            name: "钉钉",
            bundleIDPrefixes: ["com.dingtalk.mac", "com.alibaba.DingTalkMac"],
            ownerNameKeywords: ["dingtalk", "钉钉"],
            offscreenTitles: ["钉钉", "dingtalk"],
            ghostSizes: [GhostWindowSize(w: 500, h: 372, tolerance: 15)],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "netease_music",
            name: "网易云音乐",
            bundleIDPrefixes: ["com.netease.163music"],
            ownerNameKeywords: ["网易云音乐", "163music", "neteasemusic"],
            offscreenTitles: ["网易云音乐", "163music"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "weread",
            name: "微信读书",
            bundleIDPrefixes: ["com.tencent.weread"],
            ownerNameKeywords: ["微信读书", "weread"],
            offscreenTitles: ["微信读书", "weread"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "baidu_netdisk",
            name: "百度网盘",
            bundleIDPrefixes: ["com.baidu.BaiduNetdiskMac", "com.baidu.netdisk"],
            ownerNameKeywords: ["百度网盘", "baidunetdisk"],
            offscreenTitles: ["百度网盘", "baidunetdisk", "同步空间", "悬浮窗"],
            ghostSizes: [
                GhostWindowSize(w: 200, h: 80, tolerance: 30),
                GhostWindowSize(w: 710, h: 680, tolerance: 30)
            ],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "thunder",
            name: "迅雷",
            bundleIDPrefixes: ["com.xunlei.Thunder", "com.xunlei.xlplayer"],
            ownerNameKeywords: ["迅雷", "thunder"],
            offscreenTitles: ["迅雷", "thunder"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "qq_music",
            name: "QQ音乐",
            bundleIDPrefixes: ["com.tencent.QQMusic"],
            ownerNameKeywords: ["qq音乐", "qqmusic"],
            offscreenTitles: ["qq音乐", "qqmusic"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "lark",
            name: "飞书",
            bundleIDPrefixes: ["com.electron.lark", "com.bytedance.ee.lark"],
            ownerNameKeywords: ["飞书", "lark"],
            offscreenTitles: ["飞书", "lark"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "aurapane",
            name: "AuraPane",
            bundleIDPrefixes: ["com.dochi.AuraPane", "cc.atools.aurapane"],
            ownerNameKeywords: ["aurapane"],
            offscreenTitles: ["设置", "settings", "preferences", "偏好设置"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "jianpian",
            name: "荐片",
            bundleIDPrefixes: ["com.jianpian."],
            ownerNameKeywords: ["荐片", "jianpian"],
            offscreenTitles: ["荐片", "jianpian", "荐片播放器"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "uuremote",
            name: "UU远程",
            bundleIDPrefixes: ["com.netease.uuremote"],
            ownerNameKeywords: ["uu远程", "uuremote", "uu remote"],
            offscreenTitles: ["uu远程", "uuremote"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_calendar",
            name: "日历",
            bundleIDPrefixes: ["com.apple.ical", "com.apple.mobilecal", "com.apple.Calendar"],
            ownerNameKeywords: ["calendar", "日历", "ical"],
            offscreenTitles: ["calendar", "日历"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_notes",
            name: "备忘录",
            bundleIDPrefixes: ["com.apple.Notes"],
            ownerNameKeywords: ["notes", "备忘录"],
            offscreenTitles: ["备忘录", "notes", "最近删除", "所有 icloud", "所有icloud", "快速备忘录", "quick note"],
            ghostSizes: [GhostWindowSize(w: 500, h: 500, tolerance: 30)],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_appstore",
            name: "App Store",
            bundleIDPrefixes: ["com.apple.AppStore"],
            ownerNameKeywords: ["app store", "appstore"],
            offscreenTitles: ["app store", "appstore", "商店"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_safari",
            name: "Safari 浏览器",
            bundleIDPrefixes: ["com.apple.Safari"],
            ownerNameKeywords: ["safari"],
            offscreenTitles: ["safari", "start page", "起始页"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_textedit",
            name: "文本编辑",
            bundleIDPrefixes: ["com.apple.TextEdit"],
            ownerNameKeywords: ["textedit", "文本编辑"],
            offscreenTitles: ["textedit", "文本编辑"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_reminders",
            name: "提醒事项",
            bundleIDPrefixes: ["com.apple.reminders"],
            ownerNameKeywords: ["reminders", "提醒事项"],
            offscreenTitles: ["reminders", "提醒事项"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_music",
            name: "音乐",
            bundleIDPrefixes: ["com.apple.Music"],
            ownerNameKeywords: ["music", "音乐"],
            offscreenTitles: ["music", "音乐", "mini player", "迷你播放程序"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_podcasts",
            name: "播客",
            bundleIDPrefixes: ["com.apple.podcasts"],
            ownerNameKeywords: ["podcasts", "播客"],
            offscreenTitles: ["podcasts", "播客", "mini player", "迷你播放程序"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_tv",
            name: "视频",
            bundleIDPrefixes: ["com.apple.TV"],
            ownerNameKeywords: ["tv", "视频"],
            offscreenTitles: ["tv", "视频"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_maps",
            name: "地图",
            bundleIDPrefixes: ["com.apple.Maps"],
            ownerNameKeywords: ["maps", "地图"],
            offscreenTitles: ["maps", "地图"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_weather",
            name: "天气",
            bundleIDPrefixes: ["com.apple.weather"],
            ownerNameKeywords: ["weather", "天气"],
            offscreenTitles: ["weather", "天气"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "apple_calculator",
            name: "计算器",
            bundleIDPrefixes: ["com.apple.calculator"],
            ownerNameKeywords: ["calculator", "计算器"],
            offscreenTitles: ["calculator", "计算器"],
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "oppo_connect",
            name: "OPPO 互联",
            bundleIDPrefixes: ["com.oplus.devicespace", "com.heytap."],
            ownerNameKeywords: ["oplus", "oppo", "o+connect", "devicespace"],
            offscreenTitles: ["oppo 互联", "o+connect", "devicespace"],
            ghostSizes: [
                GhostWindowSize(w: 370, h: 313, tolerance: 25),
                GhostWindowSize(w: 1252, h: 710, tolerance: 30)
            ],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "gemini",
            name: "Google Gemini",
            bundleIDPrefixes: ["com.google.GeminiMacOS"],
            ownerNameKeywords: ["gemini"],
            offscreenTitles: ["gemini"],
            ghostSizes: [
                GhostWindowSize(w: 500, h: 500, tolerance: 25)
            ],
            companionBundleIDs: ["com.google.GeminiMacOS.launcher"],
            terminateHelpersInBundle: true
        ),
        AppQuirkRule(
            id: "tencent_yuanbao",
            name: "腾讯元宝",
            bundleIDPrefixes: ["com.tencent.yuanbao"],
            ownerNameKeywords: ["元宝", "yuanbao"],
            offscreenTitles: ["元宝", "yuanbao", "tencent yuanbao"],
            ghostSizes: [
                GhostWindowSize(w: 1200, h: 800, tolerance: 50),
                GhostWindowSize(w: 500, h: 500, tolerance: 30)
            ],
            companionBundleIDs: ["com.tencent.yuanbao.helper"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "zcode",
            name: "ZCode",
            bundleIDPrefixes: ["dev.zcode.app", "dev.zcode."],
            ownerNameKeywords: ["zcode"],
            offscreenTitles: ["zcode"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "tencent_meeting",
            name: "腾讯会议",
            bundleIDPrefixes: ["com.tencent.meeting"],
            ownerNameKeywords: ["tencentmeeting", "腾讯会议", "wemeet"],
            offscreenTitles: ["tencentmeeting", "腾讯会议", "wemeet"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "artcraft_launcher",
            name: "ArtCraft Launcher",
            bundleIDPrefixes: ["ai.storyteller.artcraft-launcher"],
            ownerNameKeywords: ["artcraft launcher", "artcraft"],
            offscreenTitles: ["artcraft launcher", "artcraft"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "tgent",
            name: "Tgent",
            bundleIDPrefixes: ["com.dbappsecurity.sdpTgent", "com.dbappsecurity."],
            ownerNameKeywords: ["tgent", "sdptgent", "安恒"],
            offscreenTitles: ["tgent", "安全网关", "控制中心", "sdptgent"],
            ghostSizes: [
                GhostWindowSize(w: 920, h: 600, tolerance: 30)
            ],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "dstaff",
            name: "dstaff",
            bundleIDPrefixes: ["com.dbappsecurity.dstaff"],
            ownerNameKeywords: ["dstaff"],
            offscreenTitles: ["dstaff"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "deepseek_harness",
            name: "DeepSeek Harness",
            bundleIDPrefixes: ["com.deepseek.dsh"],
            ownerNameKeywords: ["deepseek", "dsh"],
            offscreenTitles: ["deepseek", "dsh"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "atrust",
            name: "aTrust",
            bundleIDPrefixes: ["com.sangfor.tray", "com.sangfor.atrust"],
            ownerNameKeywords: ["atrust", "sangfor", "深信服"],
            offscreenTitles: ["atrust", "sangfor", "深信服"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "tscanplus",
            name: "TscanPlus",
            bundleIDPrefixes: ["com.wails.tscanplus"],
            ownerNameKeywords: ["tscanplus"],
            offscreenTitles: ["tscanplus"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "otty",
            name: "Otty",
            bundleIDPrefixes: ["io.appmakes.otty"],
            ownerNameKeywords: ["otty"],
            offscreenTitles: ["otty"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        ),
        AppQuirkRule(
            id: "siyuan",
            name: "思源笔记",
            bundleIDPrefixes: ["org.b3log.siyuan"],
            ownerNameKeywords: ["siyuan", "思源"],
            offscreenTitles: ["siyuan", "思源笔记", "思源"],
            terminateHelpersInBundle: true,
            cleanAllOffscreenWindows: true
        )
    ]

    private init() {}

    /// 获取主应用显式声明的伴生 Helper Bundle ID 集合
    public func companionBundleIDs(for bundleID: String?, ownerName: String?) -> [String] {
        guard let rule = matchRule(bundleID: bundleID, ownerName: ownerName) else { return [] }
        return rule.companionBundleIDs
    }

    /// 获取主应用是否允许联动清理其 Bundle 内的伴生 Helper
    public func shouldTerminateHelpersInBundle(for bundleID: String?, ownerName: String?) -> Bool {
        guard let rule = matchRule(bundleID: bundleID, ownerName: ownerName) else { return false }
        return rule.terminateHelpersInBundle
    }

    /// 判断应用是否属于受保护的虚拟化/模拟器/容器类应用
    public func isProtectedVirtualizationApp(bundleID: String?, ownerName: String? = nil) -> Bool {
        guard let bid = bundleID, !bid.isEmpty else { return false }
        for rule in builtinRules where rule.isVirtualizationOrContainer {
            if rule.matches(bundleID: bid, ownerName: ownerName) {
                return true
            }
        }
        return false
    }

    /// 匹配针对该 App 的特定规则
    public func matchRule(bundleID: String?, ownerName: String?) -> AppQuirkRule? {
        for rule in builtinRules {
            if rule.matches(bundleID: bundleID, ownerName: ownerName) {
                return rule
            }
        }
        return nil
    }

    /// 识别 Native 全屏物理窗口尺寸（匹配连接的任意屏幕物理尺寸，或标准全屏分辨率；严格排除 830 等关窗残留底板）
    public static func isNativeFullscreenSize(width: Double, height: Double) -> Bool {
        guard width >= 600 && height >= 400 else { return false }

        #if canImport(AppKit)
        for screen in NSScreen.screens {
            let f = screen.frame
            // 1. 物理屏幕完整全屏尺寸（无菜单栏无 Dock，例如 1512x982、2560x1440 等）
            if abs(f.width - width) <= 4.0 && abs(f.height - height) <= 4.0 {
                return true
            }
            // 2. 全屏保留顶栏模式（例如 1512x949，高度差在 40pt 内，但 1512x830 差距 152pt 严格不匹配）
            if abs(f.width - width) <= 4.0 && abs(f.height - height) <= 40.0 {
                return true
            }
        }
        #endif

        // 兜底常见 Mac / 视网膜全屏物理分辨率
        let standardResolutions: [(w: Double, h: Double)] = [
            (1512, 982), (1512, 949), (1728, 1117), (1728, 1084),
            (1440, 900), (1680, 1050), (1920, 1080), (1920, 1200),
            (2560, 1440), (2560, 1600), (3024, 1964), (3456, 2234),
            (3840, 2160), (5120, 2880)
        ]
        for res in standardResolutions {
            if abs(res.w - width) <= 4.0 && abs(res.h - height) <= 4.0 {
                return true
            }
        }
        return false
    }

    /// 空间几何判定：判断窗口是否真正物理位于其他未激活的桌面 Space
    public static func isWindowOnAnotherSpace(spaces: [UInt64], currentSpace: UInt64) -> Bool {
        guard !spaces.isEmpty else { return false }
        // 军师 Fail-Safe 铁律：当系统未能获取到当前活跃 Space ID (currentSpace == 0) 时，
        // 保守判定为可能处于其他 Space，绝不贸然清洗，宁保活不误杀！
        if currentSpace == 0 {
            return true
        }
        return !spaces.contains(currentSpace)
    }

    /// 启发式幽灵图层过滤（Y-01：收窄在屏窗口尺寸启发式，仅针对特定 BundleID 离屏图层或无标题微元过滤，保护正常小面板与工具条）
    public func isGhostWindow(
        bundleID: String?,
        ownerName: String?,
        title: String,
        width: Double,
        height: Double,
        isOnScreen: Bool,
        spaces: [UInt64] = [],
        currentSpace: UInt64 = 0
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. 过滤系统代理与极小辅助部件
        if Self.systemProxyNames.contains(lower) { return true }
        if Self.internalCefViewNames.contains(lower) { return true }

        // 2. 极小状态栏图标/光标微元（对在屏有标题的工具面板予以保留，仅过滤无标题状态横条或 <=44x44 微元）
        if width <= 44 && height <= 44 { return true }
        if height <= 36 && trimmed.isEmpty { return true }
        if !isOnScreen && height <= 48 { return true }
        if !isOnScreen && width <= 80 && height <= 60 { return true }

        // 3. 通用 CEF 离屏缓冲模板尺寸（仅在离屏或特定已知 CEF 应用无标题时生效）
        if trimmed.isEmpty && (!isOnScreen || matchRule(bundleID: bundleID, ownerName: ownerName) != nil) {
            for size in Self.genericCefGhostSizes {
                if size.matches(width: width, height: height) {
                    return true
                }
            }
        }

        // 4. 若为在屏窗口，具备有效业务尺寸且非上述微元，则绝非幽灵底板
        if isOnScreen {
            return false
        }

        // 4.1 核心 Space 豁免铁律：当且仅当窗口明确归属于其他未激活桌面 Space（isWindowOnAnotherSpace），
        // 且具备基本业务视窗尺寸（width > 120 && height > 70），无论当前处于哪个 Space，
        // 绝非脱壳/关窗 orderOut: 残留底板，享有最高级豁免权！
        if AutoQuitQuirks.isWindowOnAnotherSpace(spaces: spaces, currentSpace: currentSpace) && width > 120 && height > 70 {
            return false
        }

        // 5. 以下为针对离屏 (isOnScreen == false) 且非跨 Space 活跃窗口的深度清洗逻辑：
        // 5.1 匹配已知应用的专用 Quirks 规则
        if let rule = matchRule(bundleID: bundleID, ownerName: ownerName) {
            if rule.shouldCleanOffscreen(title: trimmed, width: width, height: height, spaces: spaces, currentSpace: currentSpace) {
                return true
            }
            if trimmed.isEmpty && !rule.ghostSizes.isEmpty {
                for size in rule.ghostSizes {
                    if size.matches(width: width, height: height) {
                        return true
                    }
                }
            }
        }

        // 5.2 通用 AppKit 设置窗口 orderOut: 残留
        if Self.genericSettingsTitles.contains(lower) {
            return true
        }

        // 5.3 日历等 AppKit 应用关窗后残留下等于 App 名的无名/同名离屏图层
        if let on = ownerName, !on.isEmpty {
            let lowerOn = on.lowercased()
            if lower == lowerOn {
                // 若为全屏业务视窗，绝非关窗残留底板
                if Self.isNativeFullscreenSize(width: width, height: height) {
                    return false
                }
                return true
            }
        }

        return false
    }
}
