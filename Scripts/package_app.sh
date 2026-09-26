#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v1.1.0")"
GIT_VER="${GIT_TAG#v}"
VERSION="${ATOOLS_VERSION:-$GIT_VER}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-2}"
SCRATCH_PATH="${ATOOLS_SCRATCH_PATH:-$DIR/.build}"

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

echo "==> Signing ATools.app bundle with ad-hoc signature..."
codesign --force --deep --sign - "$APP_BUNDLE"

BIN_SIZE=$(du -h "$MACOS/ATools" | cut -f1)
TOTAL_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ARCHS=$(lipo -archs "$MACOS/ATools")

echo "==> Creating release zip archive for GitHub Releases..."
rm -f "$DIR/ATools.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIR/ATools.zip"
ZIP_SIZE=$(du -h "$DIR/ATools.zip" | cut -f1)

echo "==> Creating ATools.dmg disk image (drag-and-drop installer)..."
DMG_STAGING="/tmp/atools_dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DIR/ATools.dmg"
hdiutil create -volname "ATools" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DIR/ATools.dmg" > /dev/null
rm -rf "$DMG_STAGING"
DMG_SIZE=$(du -h "$DIR/ATools.dmg" | cut -f1)

echo "==> Successfully packaged ATools.app!"
echo "    Binary size:  $BIN_SIZE"
echo "    Architectures: $ARCHS"
echo "    App bundle:   $TOTAL_SIZE ($APP_BUNDLE)"
echo "    Release zip:  $ZIP_SIZE ($DIR/ATools.zip)"
echo "    Release dmg:  $DMG_SIZE ($DIR/ATools.dmg)"
