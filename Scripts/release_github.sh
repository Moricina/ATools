#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.35}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-61}"

# 若 .build/release/ATools 已由增量编译生成且指定跳过重复编译，则直接复用已有二进制以实现 3 秒急速打包
if [ "${ATOOLS_SKIP_BUILD:-0}" = "1" ] && [ -x "$DIR/.build/release/ATools" ]; then
    echo "==> Using prebuilt Release binary at .build/release/ATools ($VERSION build $BUILD_NUMBER)..."
    APP_BUNDLE="$DIR/ATools.app"
    CONTENTS="$APP_BUNDLE/Contents"
    MACOS="$CONTENTS/MacOS"
    RESOURCES="$CONTENTS/Resources"
    UPDATE_SIGNING_KEY="${ATOOLS_UPDATE_SIGNING_KEY:-$HOME/.config/atools/update-signing.key}"
    UPDATE_SIGNATURE_TOOL="$DIR/Scripts/update_signature.swift"

    rm -rf "$APP_BUNDLE"
    mkdir -p "$MACOS" "$RESOURCES"
    cp "$DIR/.build/release/ATools" "$MACOS/ATools"
    chmod +x "$MACOS/ATools"
    if [ -f "$DIR/Resources/AppIcon.icns" ]; then
        cp "$DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    fi

    cat << EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ATools</string>
    <key>CFBundleIdentifier</key>
    <string>cc.atools.app</string>
    <key>CFBundleName</key>
    <string>ATools</string>
    <key>CFBundleDisplayName</key>
    <string>ATools</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>ATools 需要访问“下载”文件夹以提供快速全盘文件搜索与直接打开服务</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>ATools 需要访问“文稿”文件夹以提供快速全盘文件搜索与直接打开服务</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>ATools 需要访问“桌面”文件夹以提供快速全盘文件搜索与直接打开服务</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ATools 需要自动化支持以协助调度与打开应用</string>
</dict>
</plist>
EOF
    touch "$APP_BUNDLE"

    if security find-certificate -c "ATools Sign" >/dev/null 2>&1; then
        echo "==> Signing ATools.app with identity: ATools Sign..."
        codesign --force --deep --sign "ATools Sign" "$APP_BUNDLE"
    else
        echo "==> Signing ATools.app with ad-hoc signature..."
        codesign --force --deep --sign "-" "$APP_BUNDLE"
    fi
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

    echo "==> Creating ATools.zip and ATools.dmg..."
    rm -f "$DIR/ATools.zip" "$DIR/ATools.dmg"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIR/ATools.zip"

    DMG_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/atools_dmg_staging.XXXXXX")"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "ATools" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DIR/ATools.dmg" >/dev/null
    rm -rf "$DMG_STAGING"

    echo "==> Signing release assets with Ed25519..."
    swift "$UPDATE_SIGNATURE_TOOL" sign "$UPDATE_SIGNING_KEY" "$DIR/ATools.zip" "$DIR/ATools.zip.sig" >/dev/null
    swift "$UPDATE_SIGNATURE_TOOL" sign "$UPDATE_SIGNING_KEY" "$DIR/ATools.dmg" "$DIR/ATools.dmg.sig" >/dev/null
    PUBLIC_KEY=$(swift "$UPDATE_SIGNATURE_TOOL" public-key "$UPDATE_SIGNING_KEY")
    swift "$UPDATE_SIGNATURE_TOOL" verify "$PUBLIC_KEY" "$DIR/ATools.zip" "$DIR/ATools.zip.sig" >/dev/null
    swift "$UPDATE_SIGNATURE_TOOL" verify "$PUBLIC_KEY" "$DIR/ATools.dmg" "$DIR/ATools.dmg.sig" >/dev/null
    echo "==> Ed25519 signature verified ✓ (公钥: ${PUBLIC_KEY:0:12}...)"
else
    ./Scripts/package_app.sh
fi

GH_BIN="$HOME/bin/gh"
if [ ! -x "$GH_BIN" ]; then
    GH_BIN="$(command -v gh || echo /opt/homebrew/bin/gh)"
fi

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 更新说明

### 🚀 抽屉启动器重大体验升级 (Shelf Evolution)
1. **新装应用静默感知与自动入库**：
   - 基于 FSEvents 深度防抖感知应用安装与变动，零额外常驻守护进程；
   - 自动校验 bundle 完整性并录入指定分类，搭载 Tombstone 墓碑机制防手动删除后复活。
2. **多应用拖拽合并文件夹与液态毛玻璃浮层 (Folder Nesting)**：
   - 拖拽图标至另一图标中心区域悬停 0.45 秒即可合并建文件夹；
   - 呈现原生液态毛玻璃浮层、四宫格微缩图、内联双击重命名标题、右键“移出文件夹”与空文件夹自愈清理。
3. **单项全局快捷键与 ⌘1~⌘9 抽屉秒启**：
   - 支持为任意单项配置独占全局快捷键；
   - 抽屉激活时原生支持 \`⌘1\` ~ \`⌘9\` 直出秒启前 9 个应用。
4. **启动频次智能排序**：
   - 自动追踪应用启动计次与最近启动时间，分类右键支持按使用频次一键重新降序排列。
5. **橡皮筋框选多选与批量原子操作 (Marquee Batch Actions)**：
   - 抽屉空白处按住鼠标拖拽拉出半透明液态虚线选框，支持 \`⌘\`/\`⇧\` 连续增减选；
   - 右键选区支持批量移除入墓碑、批量原子搬移至指定分类、批量一键合并新建文件夹。

---

### 🛡️ 关窗退出 (AutoQuit) 三维现代化重构
1. **全面剥离录屏权限依赖（向 SwiftQuit 看齐）**：
   - 彻底移除 \`CGPreflightScreenCaptureAccess\`，仅需系统「辅助功能 (Accessibility)」授权即可无缝工作；
   - 权限与职责严格隔离：AX 语义负责窗口列表与角色，WindowServer 仅核验零隐私权限公开几何数据。
2. **声明式规则库与通用幽灵图层过滤引擎 (AutoQuitQuirks)**：
   - 解耦写死的硬编码名单，建立集中式规则引擎；
   - 自动化清洗系统代理视图、CEF 缓冲画布、通用设置/偏好窗口 orderOut 残余与微型光标。
3. **原生液态毛玻璃可撤销倒计时 HUD**：
   - 退出前在屏幕底部弹出轻柔倒计时胶囊与「取消」按钮，撤销后当次会话智能抑制；
   - 零按键拦截、零常驻显存，退出后即刻释放 Window Backing Store。
4. **决策诊断流水线与设置页检查器 (Trace & Inspector)**：
   - 纯值类型环形缓冲区记录最近 50 条裁决，设置页增设「诊断与决策历史」独立面板，支持一键导出排障报告。
5. **OPPO 互联等 Electron 应用 \`win.hide()\` 离屏层专项根治**：
   - 准确过滤隐藏至托盘或后台的离屏窗口残余，双向权威确诊零窗，点击红叉即刻安全退出。"

echo "==> Publishing GitHub Release v${VERSION} to Moricina/ATools..."
if "$GH_BIN" release view "v${VERSION}" --repo Moricina/ATools >/dev/null 2>&1; then
    "$GH_BIN" release upload "v${VERSION}" --repo Moricina/ATools \
        "$DIR/ATools.dmg" "$DIR/ATools.zip" "$DIR/ATools.dmg.sig" "$DIR/ATools.zip.sig" --clobber
else
    "$GH_BIN" release create "v${VERSION}" --repo Moricina/ATools \
        --title "ATools v${VERSION}" \
        --notes "$NOTES" \
        "$DIR/ATools.dmg" "$DIR/ATools.zip" "$DIR/ATools.dmg.sig" "$DIR/ATools.zip.sig"
fi

echo "==> GitHub Release v${VERSION} 发布成功！"
