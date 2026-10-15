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

---

### 六、专项优化：借鉴 GlassDesk 实现应用抽屉实时平滑让位、长按 350ms 起拖、Alt 快速交换、Esc 撤销还原与双指横向翻页 (2026-10-15)

- **涉及文件**：
  - `Sources/atools/UI/ShelfGridView.swift`
  - `Sources/atools/UI/ShelfPanel.swift`
  - `Sources/atools/UI/CategoryBarView.swift`
  - `Sources/atools/Storage/ConfigManager.swift`
- **优化详情**：
  1. **长按 350ms 触发浮起 + 快速拖拽双模响应（`ShelfItemButton`）**：
     - 按下图标满 `350ms` 时触发微浮起放大（`1.08x`）与触觉反馈（`.generic`），进入就绪态后移动 `1pt` 即可丝滑起拖；同时保留直接拖动 `> 4.5pt` 的桌面快速起拖路径。
     - 起拖时源图标在网格内平滑过渡为 `0.22` 透明度占位槽（Ghost Slot），拖拽浮层采用 `1.04x` 放大快照。
  2. **实时平滑让位算法与 14% 边界磁滞防抖（`ShelfGridView`）**：
     - 新增 `targetSlotIndex(at:itemCount:currentSlot:)`：纯几何反算网格行列槽位（不依赖正在动画中的按钮 `frame`），并在每个槽位外围设置 `14%` 磁滞防抖带（Hysteresis Core），彻底杜绝指针在相邻槽位边界处引发的反复横跳。
     - 在 `draggingUpdated` 中实时计算重排预览并驱动 `relayoutButtons(animated: true, duration: 0.24)`，采用 `CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)` 阻尼弹簧曲线与 `.alignment` 触觉反馈，让周围图标实时丝滑让位。
  3. **Alt (⌥) 快速交换模式（`ShelfGridView` & `ConfigManager`）**：
     - 拖拽过程中按住 `Option / Alt (⌥)` 键时，自动切换为「双图标直接对调（Quick Swap）」模式：仅将源槽位与目标槽位两个图标直接互换（其余图标保持原位不动），并在目标图标上绘制高亮强调环；松手时调用 `ConfigManager.shared.swapItems(at:and:in:)` 持久化。
  4. **Esc 撤销还原与拖出边界取消保护（`ShelfGridView`）**：
     - 起拖瞬间保存 `dragOriginalItems` 与 `dragOriginalButtons` 快照，并注册本地按键监听：拖拽途中按下 `Esc` 键、拖出网格边界（`draggingExited`）或未落盘松手时，所有图标立即通过平滑动画回弹恢复至起拖前原位，底层配置零污染。
  5. **双指横向滑动翻页与拖拽悬停分类胶囊自动切页（`ShelfGridView` & `CategoryBarView`）**：
     - 在 `ShelfGridView.scrollWheel(with:)` 中识别触控板双指左右滑动手势，联动 `CategoryBarView.moveSelection(by:)` 与 `playCategoryPageTransition(direction:)` 实现丝滑翻页；
     - 在 `CategoryBarView` 中新增拖拽悬停 `420ms` 自动切换分类（Spring-loaded Category Pill），支持跨分类拖入后继续享受实时平滑让位。

---

### 七、专项修复：跨分类拖拽后图标文字重叠与跨分类实时平滑让位补全 (2026-10-15)

- **问题根因**：
  1. **跨分类拖拽后文字与图标重叠**：当从分类 A 起拖图标并悬停切换到分类 B 时，`ShelfGridView.reloadData(items:)` 创建了分类 B 的按钮，但未清空分类 A 起拖时保存的 `dragOriginalItems` 与 `dragOriginalButtons` 快照。当拖拽结束触发 `endInternalDragPreview` 或 `restoreDragPreviewToOriginal` 时，旧分类 A 的按钮数组被回写至 `itemButtons`，导致分类 A 与分类 B 的两套 `ShelfItemButton` 同时残留在 `contentView.subviews` 的相同网格坐标上发生文字重叠。
  2. **拖入其他分类后无让位动画**：此前 `updateLiveDragReorder` 仅在被拖拽项属于当前分类（`itemButtons.first(where: { $0.item.id == sourceId }) != nil`）时才计算实时让位；当把应用拖入另一分类时，因该应用尚不在目标分类列表中而直接跳过，周围图标不会滑开让位。
- **修复详情**（`ShelfGridView.swift`、`ConfigManager.swift`、`ShelfPanel.swift`）：
  1. **彻底根除跨分类子视图残留重叠（`ShelfGridView.reloadData` & `resetDragPreviewSnapshotBeforeReload`）**：
     - 在 `reloadData(items:)` 入口立即调用 `resetDragPreviewSnapshotBeforeReload()` 清空上一分类的拖拽快照与跨分类临时占位图标；
     - 同时从 `contentView.subviews` 与 `itemButtons` 收集可复用按钮，并在构建 `newButtons` 后严格遍历 `contentView.subviews` 移除所有不在 `newButtons` 中的 `ShelfItemButton`，从根源上杜绝任何双层按钮或文字重叠。
  2. **新增跨分类拖入实时平滑让位动画（`beginCrossCategoryDragPreview` & `applyCrossCategoryLivePreview`）**：
     - 当把应用从分类 A 拖入分类 B 的网格时，自动为被拖入的应用创建 `0.22` 透明度虚影占位按钮 `crossCategoryGhostButton`；
     - 指针在分类 B 网格内移动时，实时计算插入槽位（`0 ... origItems.count`），驱动分类 B 内的周围图标丝滑滑入新位置让出空位；若移出网格或按 `Esc` 则自动移除占位并平滑回弹。
  3. **跨分类指定槽位原子落盘（`ConfigManager.moveItem(id:toCategoryId:at:)`）**：
     - 扩展 `ConfigManager.moveItem` 支持一次性从源分类移除并直接插入目标分类的指定索引 `destinationIndex`，避免二次重排导致的跳变。

---

### 八、专项修复：应用抽屉「鼠标移出面板后自动关闭」失效修复与「固定在桌面」优先级保护加固 (2026-10-15)

- **问题根因与修复要点**：
  1. **严格保障「固定在桌面」(`isShelfPinned == true`) 最高优先级保护**：
     - 当勾选「固定在桌面」时，抽屉面板完全不受「鼠标移出面板后自动关闭」(`autoCloseOnMouseExit`)、「点击启动应用后自动关闭」(`autoCloseOnLaunch`) 及外部点击失焦关闭的影响；勾选瞬间立即取消任何排队中的自动关闭任务（`cancelPendingMouseExitAutoClose()`），取消固定时若抽屉可见则立即热恢复移出监控。
  2. **彻底解决未固定时「鼠标移出面板后自动关闭」不生效问题**：
     - **视图层 `ShelfRootView.updateTrackingAreas()` + `.assumeInside`**：将 `NSTrackingArea` 下沉至 `NSView` 子类 `ShelfRootView` 的生命周期内，并在抽屉唤出到鼠标正下方时动态注入 `.assumeInside` 与 `window.acceptsMouseMovedEvents = true`；
     - **全局/本地鼠标移动监听 + `0.10s` `.common` 模式轮询双保险**：在抽屉显示期间同时挂载 `NSEvent` 本地与全局鼠标移动监听器（`.mouseMoved` / `.mouseEntered` / `.mouseExited` / `.leftMouseUp` / `.rightMouseUp`）与 `0.10s` 定时器 `evaluateMouseExitState()`，彻底解决被 `NSScrollView` 及图标按钮子视图拦截 `mouseExited` 的问题；
     - **自愈式菜单状态锁 `isEffectiveMenuOpen`**：结合 `RunLoop.main.currentMode == .eventTracking` 与时间戳校验，防止因状态栏菜单或右键菜单触发模态弹窗导致 `NSMenu.didEndTrackingNotification` 遗漏而永久卡死 `isRightClickMenuOpen` 阻塞自动关闭。
  3. **其他潜在使用 Bug 排查修复**：
     - **跨分类拖拽回源分类胶囊松手未切回源分类**：当从分类 A 拖出图标、悬停切到分类 B，随后又拖回分类 A 的胶囊上松手时，自动切回源分类 A；
     - **右键菜单切换「固定在桌面」时偏好设置开关实时同步**：在 `ConfigManager.updateIsShelfPinned` 变更时广播 `.atoolsShelfDataDidChange`，确保打开中的偏好设置窗口实时刷新开关状态。
- **修复文件**：
  - `Sources/atools/UI/ShelfPanel.swift`
  - `Sources/atools/UI/PanelCoordinator.swift`
  - `Sources/atools/Storage/ConfigManager.swift`
