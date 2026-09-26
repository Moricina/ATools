#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Building ATools (Release mode)..."
swift build -c release

BIN_PATH="$DIR/.build/release/ATools"
APP_BUNDLE="$DIR/ATools.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating ATools.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BIN_PATH" "$MACOS/ATools"
chmod +x "$MACOS/ATools"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

cat << 'EOF' > "$CONTENTS/Info.plist"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "==> Creating release zip archive for GitHub Releases..."
rm -f "$DIR/ATools.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIR/ATools.zip"
ZIP_SIZE=$(du -h "$DIR/ATools.zip" | cut -f1)

echo "==> Successfully packaged ATools.app!"
echo "    Binary size:  $BIN_SIZE"
echo "    App bundle:   $TOTAL_SIZE ($APP_BUNDLE)"
echo "    Release zip:  $ZIP_SIZE ($DIR/ATools.zip)"
