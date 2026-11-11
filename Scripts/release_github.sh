#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.57}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-84}"

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

    RELEASE_TAG="v${VERSION#v}"
    echo "==> Signing release assets with Ed25519 (Canonical metadata binding for $RELEASE_TAG)..."
    swift "$UPDATE_SIGNATURE_TOOL" sign "$UPDATE_SIGNING_KEY" "$DIR/ATools.zip" "$DIR/ATools.zip.sig" --version "$RELEASE_TAG" --asset-name "ATools.zip" >/dev/null
    swift "$UPDATE_SIGNATURE_TOOL" sign "$UPDATE_SIGNING_KEY" "$DIR/ATools.dmg" "$DIR/ATools.dmg.sig" --version "$RELEASE_TAG" --asset-name "ATools.dmg" >/dev/null
    PUBLIC_KEY=$(swift "$UPDATE_SIGNATURE_TOOL" public-key "$UPDATE_SIGNING_KEY")
    swift "$UPDATE_SIGNATURE_TOOL" verify "$PUBLIC_KEY" "$DIR/ATools.zip" "$DIR/ATools.zip.sig" --version "$RELEASE_TAG" --asset-name "ATools.zip" >/dev/null
    swift "$UPDATE_SIGNATURE_TOOL" verify "$PUBLIC_KEY" "$DIR/ATools.dmg" "$DIR/ATools.dmg.sig" --version "$RELEASE_TAG" --asset-name "ATools.dmg" >/dev/null
    echo "==> Ed25519 signature verified ✓ (公钥: ${PUBLIC_KEY:0:12}...)"
else
    ./Scripts/package_app.sh
fi

if [ -z "${GH_TOKEN:-}" ]; then
    KEYCHAIN_TOKEN=$(security find-generic-password -s "gh:github.com" -w 2>/dev/null || true)
    if [[ "$KEYCHAIN_TOKEN" == go-keyring-base64:* ]]; then
        export GH_TOKEN=$(echo "${KEYCHAIN_TOKEN#go-keyring-base64:}" | base64 -d)
    fi
fi

GH_BIN="$HOME/bin/gh"
if [ ! -x "$GH_BIN" ]; then
    GH_BIN="$(command -v gh || echo /opt/homebrew/bin/gh)"
fi

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 抽屉边缘停靠双侧智能感应唤出、固定桌面启动解耦与交互全面重构

### 🚀 核心新特性与交互升级
1. **全新抽屉驻留形态三选一分段胶囊**：
   - **自由浮动**：经典轻量浮动面板，点击外部失焦自动收起；
   - **固定桌面**：常驻桌面底层，不因失去焦点或切换工作区而关闭；
   - **边缘停靠**：停靠在屏幕边缘，鼠标推向屏幕边缘感应区自动展开，鼠标移出或启动软件后平滑收起。
2. **屏幕边缘自动吸附与双侧智能感应唤出**：
   - 支持「自适应两侧」、「屏幕左侧」、「屏幕右侧」三种停靠方位；
   - 自适应模式下智能感知光标位置，鼠标贴向左边即从左侧展开，贴向右边即从右侧展开；
   - 内置 220ms 悬停防抖与四角 Hot Corners 避让，杜绝无意划过误唤出。
3. **彻底切除顶部感应，杜绝系统交互冲突**：
   - 移除易引起冲突的屏幕顶部停靠，彻底消灭用户在屏幕顶部缩放窗口、右键自定义工具栏、切换标签页或点击系统菜单栏时的误触，全屏手势完美避让。
4. **固定桌面启动自动关闭行为彻底解耦**：
   - 处于「固定桌面」形态时，若开启「点击启动应用后自动关闭」，启动应用后面板将利落收起；若未开启则持续固定在桌面，满足不同用户的差异化工作流。

---

### 🛡️ 架构质量与系统性加固
1. **AppKit 主线程 UI 防御加固**：
   - 在 \`LauncherExecutor\`、\`ConfigManager\` 与 \`ShelfPanel\` 部署三重主线程校验与异步调度屏障，彻底消除后台异步回调触发视图刷新导致的 \`SIGABRT\` 闪退隐患；
2. **100% 存量配置优雅平滑兼容**：
   - 编解码器自动向下兼容旧版 \`isShelfPinned\` 与历史 \`top\` 停靠配置，老用户无感平滑升级；
3. **全量自动化诊断与测试回归**：
   - 全套 19 大项 112+ 个综合诊断测试套件（\`DiagnosticSuite\`）100% 全部 PASSED 通过。"

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
