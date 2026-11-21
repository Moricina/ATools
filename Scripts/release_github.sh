#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.60}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-87}"

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

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 关窗退出新装应用智能引导、沙盒跨进程伴生面板纳管与 HUD 快捷排除

### 🚀 核心优化与功能亮点
1. **新装应用关窗退出名单智能询问与引导浮层（AutoQuitNewAppPromptController）**：
   - 设计非抢焦轻量级原生毛玻璃胶囊卡片，在屏幕右上角舒适区域浮现，支持 8 秒倒计时自动淡出与悬停驻留；
   - 支持智能多应用并发安装防抖聚合（「发现 N 个新安装应用」），点击一键展开规则设置列表；
   - 关窗退出规则编辑器支持传入新安装应用高亮集合（\`highlightedBundleIDs\`），渲染专属高亮徽标并自动置顶排列；
   - 解耦应用抽屉自动入库与关窗退出名单询问，即使用户关闭抽屉入库，仍能独立捕获新安装应用并触发关窗退出引导。
2. **文本编辑等沙盒应用跨进程打开/保存伴生面板（NSOpenPanel）精准纳管**：
   - 深入 macOS 沙盒 XPC 架构，解析 \`com.apple.appkit.xpc.openAndSavePanelService\` 及 \`QuickLookUIService\` 伴生服务；
   - 建立进程级关联与窗口计数联动，修复用户在文本编辑（TextEdit）等应用打开/保存文件期间被误判为 0 窗口触发退出的问题。
3. **VPN、网络代理及内网零信任客户端特征智能识别与免杀/引导优化**：
   - 构建涵盖 40+ 款主流网络工具特征库（Clash、Verge、Surge、Sing-box、Tailscale、WireGuard、EasyConnect、aTrust、奇安信等）；
   - 扫描 App 内部 SystemExtensions 与 PlugIns 扩展，即使无常规 Dock 图标的后台网络守护工具也能精准捕捉并弹窗引导，避免网络连接被意外截断。
4. **关窗退出撤销 HUD 支持一键加入排除名单**：
   - 在退出倒计时原生胶囊 HUD 中新增快捷加入排除名单操作；
   - 遇到不希望退出的应用，倒计时内点击一次即可直接加入排除名单，无需手动进入偏好设置逐层查找。

---

### 🛡️ 架构质量与系统性加固
1. **全套自动化测试回归与诊断套件扩容**：
   - 综合诊断套件（\`DiagnosticSuite\`）扩容至 **全套 20 大项 120+ 个测试用例，100% 全部 PASSED 通过**；
   - 新增 \`--test-autoquit\` 命令行参数，支持关窗退出专项自检；
2. **Ed25519 签名与安全更新保障**：
   - 发布资产经由专属 Ed25519 私钥签名，支持客户端安全自检与防篡改热更新。"

echo "==> Publishing GitHub Release v${VERSION} to Moricina/ATools..."

if [ -x "$GH_BIN" ]; then
    if "$GH_BIN" release view "v${VERSION}" --repo Moricina/ATools >/dev/null 2>&1; then
        "$GH_BIN" release upload "v${VERSION}" --repo Moricina/ATools \
            "$DIR/ATools.dmg" "$DIR/ATools.zip" "$DIR/ATools.dmg.sig" "$DIR/ATools.zip.sig" --clobber
    else
        "$GH_BIN" release create "v${VERSION}" --repo Moricina/ATools \
            --title "ATools v${VERSION}" \
            --notes "$NOTES" \
            "$DIR/ATools.dmg" "$DIR/ATools.zip" "$DIR/ATools.dmg.sig" "$DIR/ATools.zip.sig"
    fi
else
    echo "==> gh CLI not found, using GitHub REST API via curl..."
    if [ -z "${GH_TOKEN:-}" ]; then
        echo "Error: GH_TOKEN is required when gh CLI is unavailable." >&2
        exit 1
    fi

    # 1. 查找或创建 Release
    RELEASE_DATA=$(curl -s -H "Authorization: token $GH_TOKEN" "https://api.github.com/repos/Moricina/ATools/releases/tags/v${VERSION}")
    RELEASE_ID=$(echo "$RELEASE_DATA" | jq -r '.id // empty')

    if [ -z "$RELEASE_ID" ]; then
        echo "==> Creating release v${VERSION}..."
        PAYLOAD=$(jq -n \
            --arg tag "v${VERSION}" \
            --arg name "ATools v${VERSION}" \
            --arg body "$NOTES" \
            '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: false}')
        CREATE_RESP=$(curl -s -X POST \
            -H "Authorization: token $GH_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "https://api.github.com/repos/Moricina/ATools/releases")
        RELEASE_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty')
        if [ -z "$RELEASE_ID" ]; then
            echo "Failed to create release: $CREATE_RESP" >&2
            exit 1
        fi
    else
        echo "==> Found existing release v${VERSION} (ID: $RELEASE_ID), updating assets..."
    fi

    # 2. 上传 Release Assets
    UPLOAD_URL="https://uploads.github.com/repos/Moricina/ATools/releases/${RELEASE_ID}/assets"
    EXISTING_ASSETS=$(curl -s -H "Authorization: token $GH_TOKEN" "https://api.github.com/repos/Moricina/ATools/releases/${RELEASE_ID}/assets")

    upload_asset() {
        local file_path="$1"
        local asset_name="$(basename "$file_path")"
        local content_type="$2"

        # 若已存在同名资产，先删除
        local existing_id=$(echo "$EXISTING_ASSETS" | jq -r ".[] | select(.name == \"$asset_name\") | .id // empty")
        if [ -n "$existing_id" ]; then
            echo "==> Deleting existing asset $asset_name (ID: $existing_id)..."
            curl -s -X DELETE -H "Authorization: token $GH_TOKEN" "https://api.github.com/repos/Moricina/ATools/releases/assets/${existing_id}" >/dev/null
        fi

        echo "==> Uploading $asset_name..."
        curl -s -X POST \
            -H "Authorization: token $GH_TOKEN" \
            -H "Content-Type: $content_type" \
            --data-binary "@$file_path" \
            "${UPLOAD_URL}?name=${asset_name}" >/dev/null
        echo "    $asset_name uploaded ✓"
    }

    upload_asset "$DIR/ATools.dmg" "application/octet-stream"
    upload_asset "$DIR/ATools.zip" "application/zip"
    upload_asset "$DIR/ATools.dmg.sig" "text/plain"
    upload_asset "$DIR/ATools.zip.sig" "text/plain"
fi

echo "==> GitHub Release v${VERSION} 发布成功！"
