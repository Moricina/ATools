import AppKit

struct DesktopCompositor {
    // 逻辑画布尺寸 1600x1000（16:10 真实 MacBook Retina 屏幕比例）
    static let screenW: CGFloat = 1600
    static let screenH: CGFloat = 1000
    static let menubarH: CGFloat = 34
    
    static func composite(
        sourceImagePath: String,
        outputImagePath: String,
        isWindow: Bool,
        windowTitle: String? = nil,
        panelOffsetY: CGFloat = 0,
        customWidth: CGFloat? = nil
    ) {
        guard let srcImg = NSImage(contentsOfFile: sourceImagePath) else {
            print("❌ Failed to load \(sourceImagePath)")
            return
        }
        
        let canvas = NSImage(size: NSSize(width: screenW, height: screenH))
        canvas.lockFocus()
        
        // 1. 绘制原版深蓝色桌面壁纸（mac_blue.png 真实平铺居中）
        if let bg = NSImage(contentsOfFile: "/tmp/mac_blue.png") {
            let cropRect = NSRect(x: 0, y: (bg.size.height - screenH)/2, width: screenW, height: screenH)
            bg.draw(in: NSRect(x: 0, y: 0, width: screenW, height: screenH), from: cropRect, operation: .copy, fraction: 1.0)
        } else {
            let gradient = NSGradient(
                starting: NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.45, alpha: 1.0),
                ending: NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.65, alpha: 1.0)
            )
            gradient?.draw(in: NSRect(x: 0, y: 0, width: screenW, height: screenH), angle: 90)
        }
        
        // 2. macOS 深色壁纸顶栏磨砂自然阴影过渡（无生硬黑条）
        let topScrim = NSGradient(
            colors: [
                NSColor(white: 0.0, alpha: 0.46),
                NSColor(white: 0.0, alpha: 0.30),
                NSColor(white: 0.0, alpha: 0.10),
                NSColor(white: 0.0, alpha: 0.0)
            ],
            atLocations: [0.0, 0.42, 0.78, 1.0],
            colorSpace: .genericRGB
        )
        let scrimRect = NSRect(x: 0, y: screenH - 52, width: screenW, height: 52)
        topScrim?.draw(in: scrimRect, angle: -90)
        
        // 菜单栏文字排版与自然柔和阴影
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor(white: 0.0, alpha: 0.55)
        textShadow.shadowOffset = NSSize(width: 0, height: -1)
        textShadow.shadowBlurRadius = 2.0
        
        let appTitleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .bold),
            .foregroundColor: NSColor.white,
            .shadow: textShadow
        ]
        let menuAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor(white: 0.98, alpha: 1.0),
            .shadow: textShadow
        ]
        
        let textY = screenH - 24
        
        // 绘制 macOS 菜单栏左侧
        "".draw(at: NSPoint(x: 18, y: textY), withAttributes: appTitleAttr)
        "访达".draw(at: NSPoint(x: 40, y: textY), withAttributes: appTitleAttr)
        
        var curMenuX: CGFloat = 88
        for menu in ["文件", "编辑", "显示", "前往", "窗口", "帮助"] {
            menu.draw(at: NSPoint(x: curMenuX, y: textY), withAttributes: menuAttr)
            curMenuX += 46
        }
        
        // 绘制 ATools 菜单栏图标（对应图 4 真实效果）
        let iconBoxW: CGFloat = 28
        let iconBoxH: CGFloat = 22
        let iconBoxX = curMenuX + 10
        let iconBoxY = screenH - 28
        
        // 放大镜图标活动态背景方块
        let boxPath = NSBezierPath(roundedRect: NSRect(x: iconBoxX, y: iconBoxY, width: iconBoxW, height: iconBoxH), xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 1.0, alpha: 0.22).setFill()
        boxPath.fill()
        
        // 绘制高清晰度放大镜图标
        let symConfig = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
        if let magImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?.withSymbolConfiguration(symConfig) {
            let tintedMag = NSImage(size: magImg.size)
            tintedMag.lockFocus()
            NSColor.white.set()
            let r = NSRect(origin: .zero, size: magImg.size)
            magImg.draw(in: r, from: r, operation: .sourceOver, fraction: 1.0)
            tintedMag.unlockFocus()
            
            let magRect = NSRect(
                x: iconBoxX + (iconBoxW - magImg.size.width) / 2,
                y: iconBoxY + (iconBoxH - magImg.size.height) / 2,
                width: magImg.size.width,
                height: magImg.size.height
            )
            tintedMag.draw(in: magRect, from: NSRect(origin: .zero, size: tintedMag.size), operation: .sourceOver, fraction: 1.0)
        }
        
        // 紧接着绘制抽屉图标
        if let drawerImg = NSImage(systemSymbolName: "sidebar.squares.left", accessibilityDescription: nil)?.withSymbolConfiguration(symConfig) {
            let tintedDrawer = NSImage(size: drawerImg.size)
            tintedDrawer.lockFocus()
            NSColor(white: 0.95, alpha: 1.0).set()
            let r = NSRect(origin: .zero, size: drawerImg.size)
            drawerImg.draw(in: r, from: r, operation: .sourceOver, fraction: 1.0)
            tintedDrawer.unlockFocus()
            
            let drawerRect = NSRect(
                x: iconBoxX + iconBoxW + 8,
                y: iconBoxY + (iconBoxH - drawerImg.size.height) / 2,
                width: drawerImg.size.width,
                height: drawerImg.size.height
            )
            tintedDrawer.draw(in: drawerRect, from: NSRect(origin: .zero, size: tintedDrawer.size), operation: .sourceOver, fraction: 1.0)
        }
        
        // 绘制菜单栏右侧状态区
        let statusText = "拼   􀙇   􀜊   80% 􀛨   10月12日 周一 01:00"
        let statusSize = (statusText as NSString).size(withAttributes: menuAttr)
        statusText.draw(at: NSPoint(x: screenW - statusSize.width - 20, y: textY), withAttributes: menuAttr)
        
        // 【注意】：严禁绘制 Dock 栏，桌面保持纯净通透
        
        // 3. 计算窗口或面板的位置与缩放尺寸
        let targetW: CGFloat
        let titlebarH: CGFloat = isWindow ? 34 : 0
        let cornerRadius: CGFloat = 12
        
        if let cw = customWidth {
            targetW = cw
        } else if isWindow {
            targetW = 880
        } else {
            targetW = 680
        }
        
        let scale = targetW / srcImg.size.width
        let targetContentH = srcImg.size.height * scale
        let totalWinH = targetContentH + titlebarH
        
        let winX = (screenW - targetW) / 2
        let winY: CGFloat
        if isWindow {
            winY = (screenH - menubarH - totalWinH) / 2 + 10
        } else {
            winY = screenH - menubarH - totalWinH - 140 - panelOffsetY
        }
        
        let winRect = NSRect(x: winX, y: winY, width: targetW, height: totalWinH)
        
        if isWindow {
            // 偏好设置标准窗口
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0.0, alpha: 0.35)
            shadow.shadowOffset = NSSize(width: 0, height: -12)
            shadow.shadowBlurRadius = 32
            shadow.set()
            
            let shadowPath = NSBezierPath(roundedRect: winRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 1.0).setFill()
            shadowPath.fill()
            NSGraphicsContext.restoreGraphicsState()
            
            NSGraphicsContext.saveGraphicsState()
            let clipPath = NSBezierPath(roundedRect: winRect, xRadius: cornerRadius, yRadius: cornerRadius)
            clipPath.addClip()
            
            // 标题栏
            let tbRect = NSRect(x: winX, y: winY + targetContentH, width: targetW, height: titlebarH)
            NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.96, alpha: 1.0).setFill()
            tbRect.fill()
            
            NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.86, alpha: 1.0).setStroke()
            let tbLine = NSBezierPath()
            tbLine.move(to: NSPoint(x: winX, y: winY + targetContentH))
            tbLine.line(to: NSPoint(x: winX + targetW, y: winY + targetContentH))
            tbLine.lineWidth = 0.8
            tbLine.stroke()
            
            // 红黄绿三色按钮
            let btnY = winY + targetContentH + 10
            let btnRadius: CGFloat = 6.0
            
            let redPath = NSBezierPath(ovalIn: NSRect(x: winX + 16, y: btnY, width: btnRadius*2, height: btnRadius*2))
            NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.35, alpha: 1.0).setFill()
            redPath.fill()
            
            let yelPath = NSBezierPath(ovalIn: NSRect(x: winX + 36, y: btnY, width: btnRadius*2, height: btnRadius*2))
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1.0).setFill()
            yelPath.fill()
            
            let grnPath = NSBezierPath(ovalIn: NSRect(x: winX + 56, y: btnY, width: btnRadius*2, height: btnRadius*2))
            NSColor(calibratedRed: 0.16, green: 0.79, blue: 0.25, alpha: 1.0).setFill()
            grnPath.fill()
            
            if let title = windowTitle {
                let winTitleAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                    .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1.0)
                ]
                let tSize = (title as NSString).size(withAttributes: winTitleAttr)
                title.draw(at: NSPoint(x: winX + (targetW - tSize.width) / 2, y: btnY - 1), withAttributes: winTitleAttr)
            }
            
            let contentRect = NSRect(x: winX, y: winY, width: targetW, height: targetContentH)
            srcImg.draw(in: contentRect, from: NSRect(origin: .zero, size: srcImg.size), operation: .copy, fraction: 1.0)
            
            NSGraphicsContext.restoreGraphicsState()
            
            let borderPath = NSBezierPath(roundedRect: winRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(calibratedWhite: 0.80, alpha: 0.85).setStroke()
            borderPath.lineWidth = 0.8
            borderPath.stroke()
        } else {
            // 悬浮面板（搜索框 / 暂存架抽屉）：
            // 【核心遵循】：
            // 1. 软件界面内部已在 prepare_milky_panels.py 注入半透明乳白色（RGB 246, 246, 247, alpha 0.92）
            // 2. 软件界面外围绝对不画任何白色底板或白色方框！
            // 3. 仅施加一层原生的柔和环境阴影，直接绘制纯净的软件界面！
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0.0, alpha: 0.28)
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.shadowBlurRadius = 26
            shadow.set()
            
            let contentRect = NSRect(x: winX, y: winY, width: targetW, height: targetContentH)
            srcImg.draw(in: contentRect, from: NSRect(origin: .zero, size: srcImg.size), operation: .sourceOver, fraction: 1.0)
            
            NSGraphicsContext.restoreGraphicsState()
        }
        
        canvas.unlockFocus()
        
        // 导出 2x 视网膜清晰度图片（3200x2000）
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(screenW * 2),
            pixelsHigh: Int(screenH * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        rep?.size = NSSize(width: screenW, height: screenH)
        
        if let rep = rep {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            canvas.draw(in: NSRect(x: 0, y: 0, width: screenW, height: screenH), from: NSRect(origin: .zero, size: canvas.size), operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: outputImagePath))
                print("Generated 2x screenshot: \(outputImagePath)")
                return
            }
        }
        
        if let tiff = canvas.tiffRepresentation,
           let fallbackRep = NSBitmapImageRep(data: tiff),
           let png = fallbackRep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: outputImagePath))
            print("Generated screenshot: \(outputImagePath)")
        }
    }
    
    static func main() {
        let outputDir = "/Users/aurora/Downloads/软著申请材料/images"
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
        
        let appFullName = "ATools桌面分类启动与全盘搜索工具软件"
        
        // 任务列表：浮动面板采用预处理好的 _milky.png，确保界面内部是半透明白色，外圈无任何白框
        let tasks: [(src: String, out: String, isWin: Bool, title: String?, offset: CGFloat, width: CGFloat?)] = [
            // 1. 暂存架横向与纵向
            ("/tmp/shelf_preview_milky.png", "\(outputDir)/shelf_horizontal.png", false, nil, 0, 780),
            ("/tmp/shelf_vertical_preview_milky.png", "\(outputDir)/shelf_vertical.png", false, nil, 0, 360),
            
            // 2. 全盘搜索核心功能（直接呈现原生搜索框，内部半透明白，外围无任何白底）
            ("/tmp/search_collapsed_preview_milky.png", "\(outputDir)/search_collapsed.png", false, nil, 30, 680),
            ("/tmp/search_expanded_preview_milky.png", "\(outputDir)/search_expanded.png", false, nil, 0, 680),
            ("/tmp/search_syntax_selection_preview_milky.png", "\(outputDir)/search_syntax_selection.png", false, nil, 0, 680),
            ("/tmp/search_capsule_preview_milky.png", "\(outputDir)/search_capsule.png", false, nil, 0, 680),
            ("/tmp/search_autopaste_preview_milky.png", "\(outputDir)/search_autopaste.png", false, nil, 0, 680),
            
            // 3. 搜索辅助工具
            ("/tmp/search_calc_preview_milky.png", "\(outputDir)/search_calc.png", false, nil, 0, 680),
            ("/tmp/search_dict_preview_milky.png", "\(outputDir)/search_dict.png", false, nil, 0, 680),
            ("/tmp/search_sys_preview_milky.png", "\(outputDir)/search_sys.png", false, nil, 0, 680),
            
            // 4. 偏好设置各大选项卡（窗口标题规范全称）
            ("/tmp/settings_tab_0.png", "\(outputDir)/settings_tab_0.png", true, "\(appFullName) - 偏好设置 [常规]", 0, 880),
            ("/tmp/settings_tab_1.png", "\(outputDir)/settings_tab_1_page0.png", true, "\(appFullName) - 偏好设置 [应用抽屉 - 启用与唤出触发]", 0, 880),
            ("/tmp/settings_tab_shelf_page1.png", "\(outputDir)/settings_tab_1_page1.png", true, "\(appFullName) - 偏好设置 [应用抽屉 - 驻留形态与关闭行为]", 0, 880),
            ("/tmp/settings_tab_shelf_layout.png", "\(outputDir)/settings_tab_1_page2.png", true, "\(appFullName) - 偏好设置 [应用抽屉 - 分类与视觉排版]", 0, 880),
            ("/tmp/settings_tab_2.png", "\(outputDir)/settings_tab_2.png", true, "\(appFullName) - 偏好设置 [全盘搜索]", 0, 880),
            ("/tmp/settings_tab_3.png", "\(outputDir)/settings_tab_3.png", true, "\(appFullName) - 偏好设置 [关窗退出]", 0, 880),
            ("/tmp/settings_tab_4.png", "\(outputDir)/settings_tab_4.png", true, "\(appFullName) - 偏好设置 [外观与主题]", 0, 880),
            ("/tmp/settings_tab_5.png", "\(outputDir)/settings_tab_5.png", true, "\(appFullName) - 偏好设置 [运行与性能]", 0, 880),
            ("/tmp/settings_tab_6.png", "\(outputDir)/settings_tab_6.png", true, "\(appFullName) - 偏好设置 [关于]", 0, 880),
        ]
        
        for task in tasks {
            composite(
                sourceImagePath: task.src,
                outputImagePath: task.out,
                isWindow: task.isWin,
                windowTitle: task.title,
                panelOffsetY: task.offset,
                customWidth: task.width
            )
        }
        print("✅ All 19 desktop screenshots composited successfully into \(outputDir)!")
    }
}

DesktopCompositor.main()
