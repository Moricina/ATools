import Foundation
import CoreGraphics

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
        cleanAllOffscreenWindows: Bool = false
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

    public func shouldCleanOffscreen(title: String, width: Double, height: Double) -> Bool {
        if cleanAllOffscreenWindows {
            return true
        }
        let lowerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !lowerTitle.isEmpty {
            if offscreenTitles.contains(lowerTitle) {
                return true
            }
            // 军师加固 1：遍历特征词进行包含模糊匹配，彻底覆盖单窗口应用动态会话标题（如 "会话 - 腾讯元宝"）
            for keyword in offscreenTitles {
                if !keyword.isEmpty && lowerTitle.contains(keyword) {
                    return true
                }
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
            ghostSizes: [GhostWindowSize(w: 420, h: 154, tolerance: 15)]
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
            offscreenTitles: ["百度网盘", "baidunetdisk"],
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
            bundleIDPrefixes: ["cc.atools.aurapane"],
            ownerNameKeywords: ["aurapane"],
            offscreenTitles: ["设置", "settings", "preferences", "偏好设置"]
        ),
        AppQuirkRule(
            id: "apple_calendar",
            name: "日历",
            bundleIDPrefixes: ["com.apple.ical"],
            ownerNameKeywords: ["calendar", "日历"],
            offscreenTitles: ["calendar", "日历"]
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
            ]
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

    /// 启发式幽灵图层过滤（Y-01：收窄在屏窗口尺寸启发式，仅针对特定 BundleID 离屏图层或无标题微元过滤，保护正常小面板与工具条）
    public func isGhostWindow(
        bundleID: String?,
        ownerName: String?,
        title: String,
        width: Double,
        height: Double,
        isOnScreen: Bool
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

        // 5. 以下为针对离屏 (isOnScreen == false) 窗口的深度清洗逻辑：
        // 5.1 匹配已知应用的专用 Quirks 规则
        if let rule = matchRule(bundleID: bundleID, ownerName: ownerName) {
            if rule.shouldCleanOffscreen(title: trimmed, width: width, height: height) {
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
                return true
            }
        }

        return false
    }
}
