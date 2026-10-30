#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.38}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-64}"

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

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 核心体验优化与架构解耦更新说明

### 🛡️ 关窗即退与新应用自动入库架构彻底解耦 (Architecture Decoupling)
1. **关窗即退 (AutoQuit) 以用户名单为最高准绳**：
   - 白名单模式（\`onlyListed\`）：彻底解除常规窗口应用限制，无论目标是否包含菜单栏图标或属于托盘小工具，只要在用户名单内，窗口关闭确认无窗时绝对触发退出；
   - 全局退出模式（\`allApps\`）：严密维持系统常规应用守卫，杜绝误退未纳管的无窗后台守护；
   - 伴生 Helper 联动退出闭环：针对如 Google Gemini 等双进程应用（主窗口 + 独立状态栏 Launcher Helper），在主窗口终审退出时，严格基于物理宿主包含关系安全联动终止其伴生 Helper，彻底消灭状态栏孤儿托盘残留；
   - 设置界面列表清洗与权威去重：重构 \`allSelectableApps\`，彻底阻断 CoreServices 系统后台守护与纯系统底座，引入物理路径权重机制按 \`bundleId\` 权威唯一去重，彻底消除 macOS Cryptex 镜像投影导致的 Safari 重复、Siri 双份等问题。

---

### 📦 新安装应用自动入库与动态基线协同 (Auto Discovery & Dynamic Baseline)
1. **全面接纳 \`LSUIElement\` 独立菜单栏/小工具应用**：
   - 抽屉自动入库判定切换为独立的 \`isShelfEligible\`，全面支持 Paste、MonitorControl、Bob、Snipaste 等独立菜单栏工具自动入库至指定分类；
   - 保持 7 重安全防护闭环，严禁无界面纯后台守护进程（\`LSBackgroundOnly\`）、系统底座与未落地残包混入。
2. **动态基线同步修剪（Pruning 机制）**：
   - 扫描基线与物理磁盘存活实时同步，彻底解决应用卸载清理失效项后重新安装无法被感知自动入库的问题；
   - 物理磁盘持续存活但未放入抽屉的历史既有应用持续锁定在基线中，绝对保障历史旧应用不误报、不批量灌水。

---

### ✨ 原生液态水滴微缩文件夹与视觉晶体质感重构 (Folder & Crystal Architecture)
1. **1:1 复刻设置页原生液态水滴胶囊 (NativeLiquidButtonBackdrop)**：
   - 微缩文件夹重命名胶囊全面换装原生液态水滴底衬，涵盖 Apple 硬件级 \`.glassEffect\` 折射、顶部天光微弧张力反光与 0.75pt 镜面双色发丝切边高光；
   - 移除生硬蓝色外边框，编辑态交由纯粹晶体微光收口，保持与设置页一致的浑然一体纯净质感；
   - **全圆角自适应弹性胶囊**：两端呈现完美半圆，依据文字宽度动态弹性伸缩，与右侧关闭按钮保留 >=70pt 黄金护城河。
2. **像素级绝对垂直居中校准**：
   - 针对 macOS Cocoa \`NSTextField\` 基线偏移增加 \`+1.5pt\` 垂直补偿；
   - 在 Retina 屏针对中文字符（如「虚拟机」、「办公」）与英文字符（如「Chrome」、「codex」）实现 **14px 对 14px（7.0pt 对 7.0pt，差异为 0）** 的绝对物理对称，彻底消灭视觉上浮感。
3. **内联改名状态机与空白失焦自愈**：
   - 双击文件夹标题直接原地切入内联编辑，回车即时保存，Esc 撤销还原，点击空白或关闭按钮平滑收起；
   - 搭载自动去除首尾空白与防空串自愈回退机制，操作前自动收口悬挂光标，深浅色外观秒级动态跟随。
4. **浮层滚动条无槽化与对称居中重构**：
   - 彻底移除展开浮层原生灰色滑槽底衬，换装无槽化原生悬浮滑块；左右内边距绝对居中对齐。
5. **文件夹浮层全面交互隔离**：
   - 点击浮层严格拦截事件穿透至底层抽屉面板，禁止误拖拽抽屉窗口；
   - 加固多应用拖拽合并灵敏度（中心区域判定与吸附动画）、文件夹专属右键菜单与空文件夹自愈清理。

---

### 🎨 视觉深度提纯方案 B (Pure Ink Theme & Visual Contrast)
1. **浅色模式墨黑字体提纯加重**：
   - 针对浅色毛玻璃文字可读性重构，文字颜色提纯为深邃墨黑（#1A1A1A / 纯黑），消除强对比背景下的发灰发白感；
   - 分类胶囊与网格项文字粗细微调加重，配合微投影强化，在任何明亮桌面或窗口前均清晰锐利。
2. **原生液态防穿透底衬加固**：
   - 全面加固防穿透底衬与高光阴影双色切边，彻底杜绝复杂壁纸下的视觉噪点与穿透干扰。

---

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
   - 自动校验应用 Bundle 完整性与可执行路径，自动入库至指定分类；
   - 搭载 Tombstone 墓碑机制：用户手动移除某应用后，该应用 ID 立即记入墓碑，防止后续再次自动复活入库。
4. **单项全局快捷键与 ⌘1~⌘9 抽屉秒启**：
   - 深度编辑弹窗支持为任意单独应用/脚本/网址配置独占全局快捷键；
   - 抽屉激活时原生支持 \`⌘1\` ~ \`⌘9\` 直出秒启当前分类前 9 个应用。
5. **橡皮筋框选多选与批量原子操作 (Marquee Batch Actions)**：
   - 抽屉空白处按住鼠标拖拽拉出液态虚线半透明选框，支持 \`⌘\`/\`⇧\` 连续增减选；
   - 选中项呈现 Accent 蓝底白字药丸与液态底衬；支持 \`⌫\` (Delete) 快捷键或右键批量移除入墓碑、批量原子搬移至指定分类、批量新建文件夹。"

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
