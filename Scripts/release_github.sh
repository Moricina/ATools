#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

VERSION="${ATOOLS_VERSION:-1.3.39}"
BUILD_NUMBER="${ATOOLS_BUILD_NUMBER:-65}"

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

NOTES="## ATools v${VERSION} (Build ${BUILD_NUMBER}) 深度架构加固与安全闭环更新说明

### 🛡️ 数据安全与备份事务化升级 (Security & Data Integrity)
1. **备份清单路径穿越彻底防御**：
   - 引入严格单文件名白名单（禁止路径分隔符、父目录与隐藏前缀），结合 APFS Unicode NFC 规范化（\`precomposedStringWithCanonicalMapping\`）与 \`resolvingSymlinksInPath()\` 前缀校验，彻底杜绝恶意备份清单越界读写；
   - 增加目标安全校验，严禁覆盖非备份目录或包含用户文件的目录；采用隔离临时目录事务化导出与 \`.bak\` 回滚缓冲；
   - 完善自定义图标元数据映射（\`iconFileMap\`），精准支持非 PNG（\`.jpg\` / \`.icns\`）自定义图标跨机器自愈映射。
2. **配置解码类型安全强化**：
   - 解码器严格区分“旧版本缺键”与“字段存在但类型损坏”；当核心字段类型损坏时显式抛出异常并触发时间戳快照保全，坚决杜绝静默抹空持久化分类；
   - 分类删除迁移强校验目标存在性与非自身，杜绝静默丢项；失效应用清理采用精确 Bundle ID 匹配杜绝模糊误伤。
3. **Shell 启动项参数化安全改造**：
   - 严格隔离脚本文件执行（内核直接传参）与命令行执行（\`[\"-c\", cmd, \"--\"] + extraArgs\`），杜绝命令注入与路径含空格切词 bug；
   - 完整落地 \`ExecutionContext\` 的管理员提权（\`runAsAdmin\`）与终端模式（\`terminalMode\`）能力。

---

### 🚀 软件更新生命周期与伴生安全脚本 (Update Lifecycle & Hardened Script)
1. **更新代次令牌强拦截**：
   - 引入全局唯一代次令牌（\`_currentSessionToken = UUID()\`），在所有下载与解压回调首行执行强断言，用户点击取消即刻作废令牌，杜绝取消后旧任务重入安装；
   - 下载大文件拷贝解耦至独立后台操作队列（\`downloadDelegateQueue\`），彻底根除主线程 UI 冻结。
2. **伴生重启脚本安全闭环**：
   - 脚本顶部强制锁定系统安全环境（\`export PATH=\"/usr/bin:/bin:/usr/sbin:/sbin\"\`），所有工具全绝对路径调用；
   - 废除无条件裸 PID 暴力 \`kill -9\`，接入进程路径真实身份核验（必须隶属 \`ATools.app\`），防止 PID 复用误杀无辜进程；
   - Staging 目录采用目标 App 同卷隐藏工作目录 \`.atools_staging_<UUID>\`，实现系统内核 \`rename(2)\` 绝对原子替换与失败无损还原。

---

### 🔍 搜索协调员并发安全、算法与边界防御 (Search Concurrency & Algorithms)
1. **并发状态同步与漏投拦截**：
   - \`SearchCoordinator\` 采用 \`stateLock\` 保证代次递增与取消线程安全；
   - \`deliver\` 闭包首行强校验 \`currentGenerationId == generation\`，面板收起或快速键入时即刻取消待投递项，彻底消除旧结果冲刷界面；
   - 新增轻量不可变载荷 \`RawSearchResultPayload\`，严格合规 Sendable 跨隔离区传递，跨入主线程后再绑定图片与交互动作。
2. **检索算法与边界体验优化**：
   - 扩大粗排候选池至 100 项，全量计算新鲜度与路径惩罚后再最终截断，修复高热度修改文件被提前丢弃的算法缺陷；
   - 修复计算器 \`-2^2 == -4\` 负号幂运算优先级；支持 MDQuery 物理中断（\`MDQueryStop\`）；
   - 搜索排除引擎与开发者排除开关独立解耦，全量接入 NFC 规范化路径匹配；搜索结果拖拽绑定稳定 ID，杜绝异步刷新动态行号错位。

---

### ✨ 启动台交互、智能 Favorites 与多屏坐标 (Shelf & Interaction)
1. **智能 Favorites 只读投影锁定**：
   - 智能 Favorites 明确声明为只读投影（\`isReadOnlyProjection = true\`），硬拦截网格内拖拽排序与放置，彻底杜绝持久化索引污染与丢项；
   - 跨分类文件夹合并事务化原子迁移；\`reloadData\` 彻底清空拖拽快照与合并定时器；去除频次排序双重代理调用；
   - 协调器收拢面板禁用生命周期 Teardown；基于当前光标所在物理屏幕的真实高度精准计算 Quartz 翻转坐标；文件夹弹窗关闭时自动提交重命名。

---

### ⚡ 系统服务与 AutoQuit 零窗守护 (System Actions & AutoQuit)
1. **双零窗口权威校验 (Fail-Safe)**：
   - \`isConfirmedZeroWindowCount\` 实行 AX 与 WindowServer 双重权威校验，未知状态（nil）或 >0 绝对不触发退出；
   - 持锁期间仅做毫秒级内存快照，耗时 AX 属性查询与 WindowServer 扫描推送到后台并发队列异步执行，杜绝主线程卡死；
   - 彻底清除所有 \`as!\` 强制类型转换崩溃点；
2. **HUD 倒计时与进程身份绑定**：
   - 倒计时 Timer 显式挂载到 \`RunLoop.main\` 的 \`.common\` 模式，基于绝对 Deadline 驱动，保证滑块或菜单展开期间倒计时不暂停且与底层 GCD 退出绝对步调一致；支持传入解析后的真实 PID；
   - 单项全局快捷键与默认热键成对暂停/恢复，两阶段提交保障热键注册与持久化配置强一致。"

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
