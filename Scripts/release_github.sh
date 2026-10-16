#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.22}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-47}"

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

### 🎨 默认主题与视觉质感升级
1. **默认主题切换为「原生液态（浅色）」**：
   - 全新安装及默认配置更新为 Apple 官方顶级光学折射「原生液态（浅色）」，默认透明度锁定为 40% 水滴透镜，开箱即享晶莹通透的现代 macOS 美学。
2. **主题体系清晰重命名与独立架构**：
   - 彻底梳理主题命名，原「液态玻璃」正式更名为「磨砂玻璃（深色/浅色）」，与物理光学透镜流的「原生液态」形成清晰双材质矩阵；
   - 偏好设置中新增动态默认透明度重置与材质特性引导。
3. **磨砂玻璃分类胶囊重塑为纯净白瓷质感**：
   - 剥离微型胶囊内嵌套系统级折射透镜引起的噪点与横截切线，采用轻量化纯 CALayer 驱动，浅色模式呈现纯白白瓷质感，文字对比度极高，消除一切杂色与折射畸变。

### 📐 应用抽屉紧凑布局与视觉舒适度优化
4. **分类药丸与应用图标间距缩减**：
   - 将水平排版下药丸底部至应用图标顶部的视觉净间距由原本过宽的 28pt 缩减至紧凑舒适的 18pt（总间距由 34pt 缩减至 24pt）；
   - 兼顾舒适呼吸感与排版紧凑度，彻底消灭大面积尴尬空档；
   - 网格槽位计算、拖拽排序磁滞防抖与让位动画 100% 保持精准坐标守恒。

### 🌟 全主题分类胶囊柔和漫射阴影（根治生硬截断）
5. **全链路解除父级图层裁剪**：
   - 彻底修复 \`CategoryBarView\`、\`scrollView\`、\`contentView\` 及 \`stackView\` 默认裁剪图层导致的胶囊下边缘平底直线截断与首个药丸左侧直角切口 Bug；
   - 坐标系统一严格对齐 CoreAnimation 翻转轴。
6. **重塑全主题微环境顺光投影**：
   - 磨砂玻璃（深色）：阴影浓度由 0.32 降至 0.16，漫射半径增至 6.0pt，彻底消除生硬粗黑块与平底切口；
   - 磨砂玻璃（浅色）：采用 0.08 超轻柔微阶调黑与 5.0pt 宽阔漫射，呈现通透白瓷微悬浮；
   - 原生液态（深色/浅色）：统一顺光向下漫射，配合纯净折射透镜，达成全角度优雅微浮动。"

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
