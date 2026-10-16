#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.20}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-45}"

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
    <false/>
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

### 🎨 界面与交互重构（滑动条与分类栏）
1. **抽屉滑动条现代化液态胶囊交互**：
   - 彻底剔除系统原生旧式白色槽体、轨道背景与边缘描边（消灭“外面一圈”）；
   - 锁定 Overlay 悬浮样式，防止外接鼠标或系统设置强行退化至旧版 legacy 槽体模式；
   - 自定义精致超薄圆角胶囊滑块（Knob），主题自适应半透明色，支持鼠标悬停（Hover）与拖拽（Dragging）微交互平滑提亮；
   - 封装防挤压智能容器 \`ModernScrollView\`，强制保持 \`contentView.frame = bounds\`，永不因滚动条扣减视口尺寸，彻底消灭挤压留白。
2. **分类栏防遮挡与零阻挡感**：
   - 几何物理层隔离：药丸安全区间严格位于 \`y ∈ [2, 28]\`，横向滚动条位于 \`y ∈ [31, 36]\`，留有 3pt 物理安全净空，彻底解决文字遮挡与点击拦截；
   - 空间严格守恒：水平 \`categoryBar\` 微调至 36pt，下方间距微调至 8pt，总顶部空间恒等 58pt，对下方应用网格布局 0 扰动。

### 🚀 新增功能与体验增强
3. **一键隐藏/显示桌面图标**：
   - 应用抽屉右键菜单新增「隐藏桌面图标 / 显示桌面图标」快捷入口（基于 \`DesktopIconManager\`），随时还原干净桌面。
4. **管理弹窗层级优化**：
   - 将分类重命名/删除/添加面板及应用编辑面板设置为浮于抽屉面板之上，避免被主抽屉遮挡。

### 🛡️ 稳定性与自动化自愈加固
5. **休眠/唤醒触控设备竞态防崩**：
   - 修复系统睡眠/唤醒时底座触控芯片电源断电重连竞态导致的崩溃，加入 \`willSleepNotification\` 安全停机与唤醒防抖。
6. **关窗自动退出兜底自愈**：
   - 解决系统沙盒应用（如「预览」Preview.app）在启动初期 PID 为 -1 导致的挂载失败问题，引入内核级 \`libproc\` 极速反查与全量自愈扫描。
7. **全盘搜索失焦时自动关闭修复**：
   - 彻底修复全盘搜索面板在点击屏幕外部空白处、桌面、其他应用窗口或切应用时未能自动关闭的问题；修正辅助工具判定算法，杜绝后台存活进程导致误判。"

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
