#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.28}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-54}"

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

### 🛡️ 虚拟化平台与 Windows 子应用物理级永久豁免
1. **全链路物理级豁免防护网**：
   - 新增 \`isProtectedVirtualizationApp\` 物理级防火墙，针对 \`com.parallels.\` 前缀及包含 parallels 的所有进程（包括 Parallels Desktop 控制台、Windows 11 虚拟机主核心、Dock Helper、Coherence Helper 以及所有 Windows 映射应用 Stub）执行 100% 永久物理级豁免；
   - 绝不纳管、不轮询、不终止虚拟机及其子应用，彻底终结切换应用时 Windows 虚拟机崩溃与未保存数据丢失风险；
   - 同步硬排除 VMware Fusion (\`com.vmware.\`)、UTM (\`com.utmapp.\`)、VirtualBox (\`org.virtualbox.\`)、Docker Desktop (\`com.docker.\`) 与 Android 模拟器。

### 🪟 跨虚拟桌面 (Spaces) / 全屏切换误杀彻底终结与三重防护网
1. **彻底移除后台静默应用的无差别轮询**：
   - 明确生命周期契约：AutoQuit 仅允许对“当前前台活跃应用（\`app.isActive\`）”或“最近 3 秒内接收到明确窗口关闭通知（\`recentlyHadCloseEvent\`）”的应用执行零窗求值；
   - 处于后台静默运行的应用绝对不进行轮询扫描，从根源上杜绝后台定时器在全屏或多桌面下偷袭杀进程；
2. **Space 切换重构**：
   - 检测到虚拟桌面切换时，直接撤销已排队的退出任务，彻底移除旧有的 2.5 秒延时复查自杀机制；
3. **\`executePendingQuit\` 终极防线兜底拦截**：
   - 在 1 秒倒计时结束准备调用终止的瞬间：只要应用当前处于失焦/后台状态且最近 5 秒内从未发生过任何真实的窗口关闭通知，坚决撤销退出，保障 WPS Office、Chrome、微信等后台软件稳定常驻。

### ⚡ 腾讯文档等 CEF/Electron 应用关窗退出精准适配
1. **WindowServer 离屏底板精准过滤**：
   - 精准过滤腾讯文档等 CEF 应用在关闭所有文档后残留的离屏无标题缓冲底板（1366x800），修复关闭文档后应用停留在 Dock 栏不退出的问题，恢复精准优雅退出。"

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
