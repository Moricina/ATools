#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

VERSION="${ATOOLS_VERSION:-1.3.12}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-37}"
SCRATCH_PATH="${ATOOLS_SCRATCH_PATH:-$DIR/.build}"
# 签名身份解析：
# ① 显式指定（ATOOLS_SIGNING_IDENTITY="-" 可强制 ad-hoc，见 RELEASING.md 迁移说明）
# ② 未指定 → 钥匙串里存在 "ATools Sign" 就自动使用（避免误用 ad-hoc 重签
#    导致辅助功能授权失效）
# ③ 都没有 → ad-hoc
SIGNING_IDENTITY="${ATOOLS_SIGNING_IDENTITY-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    if security find-certificate -c "ATools Sign" >/dev/null 2>&1; then
        SIGNING_IDENTITY="ATools Sign"
    else
        SIGNING_IDENTITY="-"
    fi
fi
UPDATE_SIGNING_KEY="${ATOOLS_UPDATE_SIGNING_KEY:-$HOME/.config/atools/update-signing.key}"
UPDATE_SIGNATURE_TOOL="$DIR/Scripts/update_signature.swift"

if [ ! -f "$UPDATE_SIGNING_KEY" ]; then
    echo "错误: 未找到更新签名私钥: $UPDATE_SIGNING_KEY" >&2
    echo "请先备份现有私钥，或使用 update_signature.swift keygen 生成新的密钥对。" >&2
    echo "提示: 运行 ./Scripts/key_manager.sh status 查看密钥状态" >&2
    exit 1
fi

# 预检：验证签名密钥是否在 UpdateManager.swift 中注册
CURRENT_PUBKEY=$(swift "$UPDATE_SIGNATURE_TOOL" public-key "$UPDATE_SIGNING_KEY" 2>/dev/null)
REGISTERED_KEYS=$(grep -oE '"[A-Za-z0-9+/]{43}="' "$DIR/Sources/atools/System/UpdateManager.swift" | tr -d '"')
if ! echo "$REGISTERED_KEYS" | grep -qF "$CURRENT_PUBKEY"; then
    echo "错误: 签名密钥公钥未在 UpdateManager.swift 中注册" >&2
    echo "  当前密钥公钥: $CURRENT_PUBKEY" >&2
    echo "  已注册公钥:" >&2
    echo "$REGISTERED_KEYS" | sed 's/^/    /' >&2
    echo "" >&2
    echo "请执行以下操作之一:" >&2
    echo "  1. 恢复已注册的密钥: ./Scripts/key_manager.sh restore" >&2
    echo "  2. 将当前公钥添加到 UpdateManager.swift 的 updateSigningPublicKeys 数组" >&2
    exit 1
fi
info "签名密钥验证通过 ✓ (公钥: ${CURRENT_PUBKEY:0:12}...)"

echo "==> Building ATools $VERSION ($BUILD_NUMBER) in Release mode..."
swift build -c release --disable-sandbox --scratch-path "$SCRATCH_PATH" -debug-info-format none

BIN_PATH="$SCRATCH_PATH/release/ATools"
APP_BUNDLE="$DIR/ATools.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [ ! -x "$BIN_PATH" ]; then
    echo "Build output not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Creating ATools.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BIN_PATH" "$MACOS/ATools"
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

if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "==> Signing ATools.app bundle with ad-hoc signature..."
    codesign --force --deep --sign "-" "$APP_BUNDLE"
else
    echo "==> Signing ATools.app bundle with identity: $SIGNING_IDENTITY..."
    if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
        # Developer ID：hardened runtime + 可信时间戳（后续公证的前提）
        codesign --force --deep --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
    else
        # 自签名等：不加 runtime/timestamp（自签名无 TSA，runtime 无公证也无收益）
        codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    fi
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "==> Designated requirement:"
codesign -dr - "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
if [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "    ↑ 若是 certificate leaf = H\"...\"，把它填入 UpdateManager.expectedSigningLeafHashes"
fi

BIN_SIZE=$(du -h "$MACOS/ATools" | cut -f1)
TOTAL_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ARCHS=$(lipo -archs "$MACOS/ATools")

echo "==> Creating release zip archive for GitHub Releases..."
rm -f "$DIR/ATools.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIR/ATools.zip"
ZIP_SIZE=$(du -h "$DIR/ATools.zip" | cut -f1)

echo "==> Creating ATools.dmg disk image (drag-and-drop installer)..."
DMG_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/atools_dmg_staging.XXXXXX")"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DIR/ATools.dmg"
hdiutil create -volname "ATools" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DIR/ATools.dmg" > /dev/null
rm -rf "$DMG_STAGING"
DMG_SIZE=$(du -h "$DIR/ATools.dmg" | cut -f1)

echo "==> Signing release assets with Ed25519..."
swift "$UPDATE_SIGNATURE_TOOL" sign "$UPDATE_SIGNING_KEY" "$DIR/ATools.zip" "$DIR/ATools.zip.sig" >/dev/null
swift "$UPDATE_SIGNATURE_TOOL" sign "$UPDATE_SIGNING_KEY" "$DIR/ATools.dmg" "$DIR/ATools.dmg.sig" >/dev/null

PUBLIC_KEY=$(swift "$UPDATE_SIGNATURE_TOOL" public-key "$UPDATE_SIGNING_KEY")
swift "$UPDATE_SIGNATURE_TOOL" verify "$PUBLIC_KEY" "$DIR/ATools.zip" "$DIR/ATools.zip.sig" >/dev/null
swift "$UPDATE_SIGNATURE_TOOL" verify "$PUBLIC_KEY" "$DIR/ATools.dmg" "$DIR/ATools.dmg.sig" >/dev/null

echo "==> Successfully packaged ATools.app!"
echo "    Binary size:  $BIN_SIZE"
echo "    Architectures: $ARCHS"
echo "    App bundle:   $TOTAL_SIZE ($APP_BUNDLE)"
echo "    Release zip:  $ZIP_SIZE ($DIR/ATools.zip)"
echo "    Release dmg:  $DMG_SIZE ($DIR/ATools.dmg)"
echo "    Signatures:   $DIR/ATools.zip.sig, $DIR/ATools.dmg.sig"
