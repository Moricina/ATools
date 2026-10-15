# ATools 优化与版本记录 (OPTIMIZATION_LOG)

## [基线快照] Commit: `9f9f956` (2026-10-15 00:37:49)
- **改动内容**：
  1. 原生液态主题（深色/浅色）默认透明度调整为 `40%`（0.40）。
  2. 修复 `/calc` 穿透、剪贴板自环、语法胶囊残留、触控板手势锁及抽屉拖拽边界问题。
- **一键回退命令（回退至 P0 实施前基线）**：
  ```bash
  git reset --hard 9f9f956
  ```

---

## [实施计划备份快照] Commit: `aeff411` (2026-10-15 01:30:00)
- **改动内容**：
  1. 完成 GlassDesk v1.3.1 核心源码对标分析与 P0 详细实施计划制定。
  2. 完成子代理架构与可用性审查并同步至优化记录文档。
- **一键回退命令（仅保留文档、回退代码）**：
  ```bash
  git reset --hard aeff411
  ```

---

## [P0 核心功能落地与验证] 对标 GlassDesk v1.3.1 核心工程设计 (2026-10-15)

### 一、P0 功能落地总览与对应文件

| 优先级 | 功能模块 | 借鉴自 GlassDesk v1.3.1 核心设计 | 实际落点文件 |
| :--- | :--- | :--- | :--- |
| **P0-1** | 启动项深度编辑器（自定义图标/参数/工作目录/搜索别名） | `AppEntry.cs` / `AppEntryEditor.cs`：支持可视化修改名称、启动参数、工作目录、替换自定义图标及添加多音字搜索别名 | `LauncherItem.swift`、`ThumbnailPipeline.swift`、`LauncherExecutor.swift`、`LauncherItemEditorDialog.swift` (新增)、`ShelfGridView.swift`、`ShelfPanel.swift`、`SearchResult.swift`、`SearchResultsTableView.swift`、`SearchCoordinator.swift`、`ConfigManager.swift` |
| **P0-2** | 失效项目检测、角标提示与一键重定位/清理 | `IsTargetMissing` / `LibraryMaintenance.cs`：应用移动或卸载后不静默失效，显示半透明灰阶+右上角黄色感叹号微标，支持重新定位或一键清理 | `LauncherItem.swift`、`ThumbnailPipeline.swift`、`ShelfGridView.swift`、`ShelfPanel.swift`、`ConfigManager.swift`、`SettingsTabViews.swift` |
| **P0-3** | 配置与自定义图标全量备份、干跑预校验及快照回滚 | `BackupService.cs`：打包导出 `config.json` + `icons/` + `manifest.json`，恢复前全量内存干跑校验 SHA256/JSON，自动拍 `pre-restore-*` 快照并自愈跨机图标路径 | `BackupService.swift` (新增)、`ConfigManager.swift`、`SettingsTabViews.swift` |

---

### 二、已完成的详细改动内容

1. **P0-1：启动项属性编辑器与自定义图标/别名 (`AppEntryEditor`)**：
   - **右键菜单与可视化属性编辑器 (`ShelfGridView.swift` + `LauncherItemEditorDialog.swift`)**：
     - 在应用抽屉图标右键菜单中新增 **「编辑项目属性...」**；
     - 弹窗支持修改 **显示名称**、**目标路径（含重定位按钮）**、**启动参数 (`arguments`)**、**工作目录 (`workingDirectory`)** 与 **搜索别名标签 (`tags`)**；
     - 支持点击「更换图标...」选择本地 `.png` / `.icns` / `.jpg` / `.tiff` / `.app`，自动通过 `ThumbnailPipeline.normalizedCustomIconPNGData` 等比居中缩放归一化为 `256×256` PNG 并托管拷贝至 `~/Library/Application Support/ATools/icons/<itemId>.png`，同时支持一键「恢复默认图标」。
   - **缩略图管线与缓存保护 (`ThumbnailPipeline.swift`)**：
     - 新增 `icon(forItem:completion:)` 与 `icon(forPath:customIconPath:completion:)`，优先读取 `customIconPath`，若文件不存在自动平滑回退至原生图标；
     - 在 `clearTransientSearchCache()` 中同时保留 `customIconPath` 缓存键，防止内存退火时误清自定义图标。
   - **带参执行与全局/抽屉别名检索闭环 (`LauncherExecutor.swift` + `ShelfGridView.swift` + `SearchCoordinator.swift`)**：
     - `LauncherExecutor.open(item:)` 完整读取 `executionContext`（`arguments`、`workingDirectory`、`environmentVars`）并注入 `NSWorkspace.OpenConfiguration` 或 `Process`；
     - 抽屉内键盘过滤 (`ShelfGridView.applyFilter`) 与全盘搜索 Layer 1 (`SearchCoordinator`) 均支持匹配 `tags` 搜索别名及其全拼/首字母。

2. **P0-2：失效启动项检测、视觉标记与一键维护 (`IsTargetMissing` & `LibraryMaintenance`)**：
   - **异步存活检测与灰阶+黄色感叹号微标 (`ShelfGridView.swift` + `ThumbnailPipeline.swift`)**：
     - 抽屉加载时通过 `validateItemTargetsAsynchronously` 在后台异步校验 `FileManager.default.fileExists(atPath:)`；
     - 对路径不存在的图标通过 `ThumbnailPipeline.grayscaleImage(for:)` 渲染保留透明通道的半透明灰阶图标，并在右上角叠加绘制 `MissingTargetBadgeView`（黄色感叹号微标 `!`）。
   - **保持原位重新定位与一键清理 (`ShelfPanel.swift` + `ConfigManager.swift` + `SettingsTabViews.swift`)**：
     - 右键菜单新增 **「重新定位目标...」**，左键点击失效图标时弹出「重新定位目标... / 从分类中移除 / 取消」引导弹窗；
     - `ConfigManager.relocateItem` 在更新目标路径时严格保持原有 `id`、排序位置、自定义名称、自定义图标、启动参数与 `tags` 不变；
     - 在「常规」设置页与「应用抽屉 -> 分类与视觉排版」设置页均提供 **「一键清理全部失效项目」** 按钮，并自动清理孤立的自定义图标文件。

3. **P0-3：自描述配置备份、恢复前预校验与自动快照回滚 (`BackupService`)**：
   - **全量打包导出 (`BackupService.exportBackup`)**：将 `config.json`、托管图标目录 `icons/` 与包含版本号、创建时间、源机器家目录及 SHA-256 校验信息的 `manifest.json` 打包导出至 `.atoolsbackup` 归档目录。
   - **恢复前内存干跑预校验 (`BackupService.validateBackup`)**：导入恢复前先在内存中完整解析校验 JSON 语法、核心字段、版本兼容性与所有文件的 SHA-256 摘要；若文件损坏则立即拒绝覆盖并提示具体错误，现有配置零改动。
   - **自动安全快照与跨机路径自愈 (`BackupService.restoreBackup` & `rollbackToLatestSnapshot`)**：
     - 执行恢复前自动将当前配置与图标完整快照至 `~/Library/Application Support/ATools/backups/pre-restore-时间戳/`（自动保留最近 10 份），并在设置页支持 **「回滚快照」**；
     - 自动将归档中的 `customIconPath` 与跨机家目录路径修复映射为当前机器的 `~/Library/Application Support/ATools/icons/` 与当前用户主目录。

---

### 三、编译与自动化诊断验证结果

- **编译验证**：`./Scripts/build.sh debug` 与 `./Scripts/build.sh release` 均 **零错误、零源码警告** 通过。
- **自动化诊断套件 (`--test`)**：
  - `[3/7]` 主题切换与默认透明度（40% / 90%）联动测试通过；
  - `[8/8]` 偏好设置窗口全标签页 **780.0pt 几何宽度不变性** 严格通过；
  - `[13]` P0 新增专项诊断测试（参数/标签分词解析、自定义图标归一化托管与加载、失效项扫描/重定位保序/一键清理、备份导出/干跑防损坏拦截/跨机路径自愈/pre-restore 快照回滚）**100% 全部通过**。

---

### 四、专项修复：AutoQuit 关窗动画期间多通知并发防重入与 TextEdit 零窗识别优化 (2026-10-15)

- **修复文件**：`Sources/atools/System/AutoQuitManager.swift`
- **修复内容**：
  1. **新增 `pendingRechecks` 延迟复查防重入锁**：点击红叉关闭窗口时，`kAXWindowClosedNotification` 与应用级/窗口级 `kAXUIElementDestroyedNotification` 往往在同一毫秒内并发到达。新增 `pendingRechecks: [pid_t: DispatchWorkItem]` 队列去重保护：若当前 `pid` 已有排队中的关闭动画复查任务，后续并发通知直接合并忽略，不再重复递增 `recheckCounts[pid]`。
  2. **扩展关闭淡出动画复查窗口期**：将 `axCount == 0 && wsCount > 0`（AX 已确认无窗但 WindowServer 仍处于 macOS 250ms～350ms 关窗淡出动画中）的重试配额调整为最多 `5` 次 × `0.12s`（覆盖 `600ms` 动画期），并在确认零窗、新建窗口或取消退出时联动清理 `pendingRechecks`。
  3. **补全 `hadWindows` 状态与 `.noValue` 零窗判定**：
     - 在 `kAXWindowCreatedNotification` 收到标准业务窗口元素，或收到明确 `kAXWindowClosedNotification` / 已注册窗口销毁通知时，确保 `entry.hadWindows = true` 被可靠标记；
     - 在 `axWindows(of:)` 中兼容原生 Cocoa 应用（如 `TextEdit`）在关闭最后一个窗口或打开面板后 `kAXWindowsAttribute` 返回 `AXError.noValue` 的情况：只要应用级 `kAXRoleAttribute` 正常响应，即确认为空窗口列表 `[]`（0 窗），避免误判为 AX 故障（`nil`）而漏退。

---

### 五、专项优化：应用抽屉空白区域右键菜单新增「新建项目...」与「一键清理失效项」 (2026-10-15)

- **涉及文件**：
  - `Sources/atools/UI/ShelfGridView.swift`
  - `Sources/atools/UI/ShelfPanel.swift`
  - `Sources/atools/UI/LauncherItemEditorDialog.swift`
- **优化详情**：
  1. **抽屉空白区域右键菜单扩展（`ShelfGridView.swift`）**：
     - 在右键抽屉空白面板弹出的 `ShelfGridMenu` 顶部新增 **「新建项目...」**（图标 `plus.app`）与 **「一键清理失效项」**（图标 `trash`，当存在失效项目时动态显示数量 `一键清理失效项 (N)`）。
  2. **复用深度属性编辑器创建新启动项（`LauncherItemEditorDialog.swift` & `ShelfPanel.swift`）**：
     - 新增 `LauncherItemEditorDialog.presentCreateNew(in:onCreated:)`，点击「新建项目...」直接弹出「编辑启动项属性」窗口；
     - 支持点击右侧「选择目标...」选取 `.app` / 文件 / 文件夹或手动输入路径，若「显示名称」为空则自动提取本地化显示名称并实时刷新图标预览，保存时直接追加至当前激活分类。
  3. **抽屉内一键清理全部失效项目并回收孤立托管图标（`ShelfPanel.swift`）**：
     - 点击「一键清理失效项」时调用与设置页完全一致的 `ConfigManager.shared.scanMissingItems()` 预览确认弹窗及 `ConfigManager.shared.removeAllMissingItems()`，一键移除所有分类中的失效启动项、自动回收孤立的托管自定义图标并即时刷新抽屉面板。
