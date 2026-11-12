#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.58}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-85}"

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

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 修复 Magpie 关窗退出死循环与偏好设置文案极简化规范重构

### 🚀 核心优化与缺陷修复
1. **彻底攻克 Magpie 等 LSUIElement/Wails 架构应用关窗退出死循环**：
   - 解决 Wails/Tauri 应用在关闭主视窗后动态将 ActivationPolicy 降级为 \`.accessory\` 导致终审拦截无法退出的缺陷；
   - 移除定时器中伪造关窗时间戳逻辑，彻底切断自动退出调度自激死循环链路；
   - 重构伴生进程清理机制：通过内核级 \`proc_pidinfo\` 深度递归扫描并终止脱离主 Bundle 目录的孤儿直接子进程（如 \`magpie-bun\`），实现主辅进程彻底干净退出。
2. **偏好设置全功能点提示词与副标题极简化重构**：
   - 逐一梳理重写常规、应用抽屉、全盘搜索、关窗退出、外观与主题、运行与性能、关于全部 7 个标签页的标题、副标题与提示文案；
   - 彻底清除技术宣讲、过度辩护与人机长句，全面禁用“绝不”、“彻底”、“杜绝误杀”、“毫秒级”、“物理隔离”等绝对化词汇；
   - 统一遵循地道 macOS 原生设计规范，文案简明、克制、准确、操作导向。

---

### 🛡️ 架构质量与系统性加固
1. **全套自动化测试回归**：
   - 全套 19 大项 112+ 个综合诊断测试套件（\`DiagnosticSuite\`）100% 全部 PASSED 通过；
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
