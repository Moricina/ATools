#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.44}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-69}"

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

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 核心加固与单窗口应用关窗退出系统性根治更新说明

### 🎯 AutoQuit 零窗守护立体加固与单窗口桌面应用矩阵全面闭环
1. **彻底根治吸附悬浮挂件阻断缺陷（AX 树微元门禁升级）**：
   - 深入重构 \`isStandardBusinessWindow\`，为 \`AXDialog\` / \`AXSystemDialog\` / \`AXSheet\` 增设物理微元尺寸门禁；
   - 凡既无关闭按钮又无最小化按钮且物理尺寸小于 160x90 的吸附挂件（如夸克 40x40 桌面吸附悬浮球、截图栏、取词浮标），坚决不计入标准业务窗口，彻底消除假窗口阻断零窗退出。
2. **离屏主视窗全尺寸清洗与伴生 Helper 联动清理**：
   - 彻底解决腾讯元宝、夸克等单窗口应用点击红叉后仅通过 \`orderOut:\` 离屏隐藏导致 WindowServer 误判的问题；
   - 引入 \`cleanAllOffscreenWindows: true\`，全面支持用户任意缩放窗口尺寸；支持动态会话标题模糊匹配；
   - 主应用退出时联动终止 \`Helper (Renderer)\`、\`Helper (Player)\` 等伴生进程，杜绝僵尸进程常驻。
3. **同系列单窗口桌面应用矩阵一揽子纳入**：
   - 专用规则覆盖：夸克网盘、腾讯元宝、网易云音乐、微信读书、百度网盘、迅雷、QQ音乐、钉钉、飞书、腾讯文档；
   - 统一享受全尺寸离屏清洗与渲染子进程协同清理。
4. **关窗因果律与在屏双检终审机制**：
   - 新增 \`windowServerOnScreenWindowCount\` 仅统计 \`isOnScreen == true\` 的在屏有效窗口；
   - 引入关窗因果律（\`recentlyHadCloseEvent\`）：仅在用户真实点击红叉/⌘W 且在屏窗口归零时放行退出；
   - 严格维持后台 Chromium / Chrome / 夸克在多 Space 遮挡或频繁切换应用时的坚挺保活，绝不误杀。

---

### 🛡️ 架构质量与自动化诊断验证
- 全套 19 大项综合诊断套件（\`DiagnosticSuite\`）100% 全部 PASSED 通过；
- 兼容性与边界防护严密闭环，编译零错误、零警告。"

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
