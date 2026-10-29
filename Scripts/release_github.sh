#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.36}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-62}"

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

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 综合体验大版本更新说明

### 🚀 抽屉启动器多维体验升级 (Shelf Evolution)
1. **多策略智能排序与偏好方案选择 (Multi-Policy Sorting)**：
   - 偏好设置新增「默认排序方式」：支持「手动自定义 (推荐)」、「按使用频次」、「按应用名称 (A-Z / 拼音升序)」与「按最近添加」；
   - 抽屉网格空白处、分类栏药丸与分类栏空白处右键菜单统一升级为「重新排序」二级子菜单，支持随时一键整理当前分类；
   - 启动项模型补充 \`addedAt\` 精准时间戳并兼容老版本；排序算法支持嵌套文件夹内部子项按最新活跃度联动排序；
   - **手动拖拽自愈保护**：当用户在分类内手动拖拽图标调换位置时，排序策略自动平滑置为「手动自定义 (.manual)」，捍卫用户排布心智。
2. **启动频次隐私控制开关**：
   - 偏好设置新增「记录应用启动频次」开关，关闭后本地不再统计启动计次与时间戳，彻底尊重用户隐私。
3. **新装应用静默感知与自动入库 (Auto Discovery & Tombstone)**：
   - 基于 FSEvents 深度防抖感知应用安装与变动，零额外常驻守护进程消耗；
   - 自动校验应用 Bundle 完整性与可执行路径，自动入库至工作分类；
   - 搭载 Tombstone 墓碑机制：用户手动移除某应用后，该应用 ID 立即记入墓碑，防止后续再次自动复活入库。
4. **多应用拖拽合并文件夹与液态毛玻璃浮层 (Folder Nesting)**：
   - 拖拽图标至另一图标中心区域悬停 0.45 秒即可合并建文件夹；
   - 原生液态毛玻璃弹层展示文件夹子应用，支持 2x2 四宫格微缩图、内联重命名、右键移出与空文件夹自愈清理。
5. **单项全局快捷键与 ⌘1~⌘9 抽屉秒启**：
   - 深度编辑弹窗支持为任意单独应用/脚本/网址配置独占全局快捷键；
   - 抽屉激活时原生支持 \`⌘1\` ~ \`⌘9\` 直出秒启当前分类前 9 个应用。
6. **橡皮筋框选多选与批量原子操作 (Marquee Batch Actions)**：
   - 抽屉空白处按住鼠标拖拽拉出液态虚线半透明选框，支持 \`⌘\`/\`⇧\` 连续增减选；
   - 选中项呈现 Accent 蓝底白字药丸与液态底衬；支持 \`⌫\` (Delete) 快捷键或右键批量移除入墓碑、批量原子搬移至指定分类、批量新建文件夹。

---

### 🛡️ 关窗退出 (AutoQuit) 现代化架构重构
1. **全面剥离录屏权限依赖（向 SwiftQuit 看齐）**：
   - 彻底移除 \`CGPreflightScreenCaptureAccess\`，仅需系统「辅助功能 (Accessibility)」授权即可无缝工作；
   - 权限与职责严格隔离：AX 语义负责窗口列表与角色，WindowServer 仅核验零隐私权限公开几何数据。
2. **声明式规则库与通用幽灵图层过滤引擎 (AutoQuitQuirks)**：
   - 解耦写死的硬编码名单，建立集中式规则引擎；
   - 自动化清洗系统代理视图、CEF 缓冲画布、通用设置/偏好窗口 orderOut 残余与微型光标。
3. **原生液态毛玻璃可撤销倒计时 HUD**：
   - 退出前在屏幕底部弹出轻柔倒计时胶囊与「取消」按钮，撤销后当次会话智能抑制；
   - 零按键拦截、零常驻显存，退出后即刻释放 Window Backing Store。
4. **决策诊断流水线与设置页检查器 (Trace & Inspector)**：
   - 纯值类型环形缓冲区记录最近 50 条裁决，设置页增设「诊断与决策历史」独立面板，支持一键导出排障报告。
5. **OPPO 互联等 Electron 应用 \`win.hide()\` 离屏层专项根治**：
   - 准确过滤隐藏至托盘或后台的离屏窗口残余，双向权威确诊零窗，点击红叉即刻安全退出。"

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
