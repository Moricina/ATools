# ATools 优化与版本记录 (OPTIMIZATION_LOG)

## [基线快照] Commit: `9f9f956` (2026-10-15 00:37:49)
- **改动内容**：
  1. 原生液态主题（深色/浅色）默认透明度调整为 `40%`（0.40）。
  2. 修复 `/calc` 穿透、剪贴板自环、语法胶囊残留、触控板手势锁及抽屉拖拽边界问题。
- **一键回退命令**：
  ```bash
  git reset --hard 9f9f956
  ```

---

## [P0 功能详细实施计划与架构审查记录] 对标 GlassDesk v1.3.1 核心工程设计 (2026-10-15)

### 一、P0 待增加功能总览与落点映射

| 优先级 | 功能模块 | 借鉴自 GlassDesk v1.3.1 核心设计 | 对应 ATools 落点文件 |
| :--- | :--- | :--- | :--- |
| **P0-1** | 启动项深度编辑器（自定义图标/参数/工作目录/搜索别名） | `AppEntry.cs` / `AppEntryEditor.cs`：可视化修改显示名、启动参数、工作目录、替换托管自定义图标及多音字/缩写搜索别名 | `LauncherItem.swift`、`ThumbnailPipeline.swift`、`LauncherExecutor.swift`、`LauncherItemEditorDialog.swift` (新增)、`ShelfGridView.swift`、`ShelfPanel.swift`、`SearchCoordinator.swift`、`ConfigManager.swift` |
| **P0-2** | 失效项目检测、角标提示与一键重定位/清理 | `IsTargetMissing` / `LibraryMaintenance.cs`：应用卸载或文件移动后不静默失效，渲染灰阶+黄色感叹号角标，支持保持原位重新定位及一键清理 | `LauncherItem.swift`、`ThumbnailPipeline.swift`、`ShelfGridView.swift`、`ShelfPanel.swift`、`ConfigManager.swift`、`SettingsTabViews.swift` |
| **P0-3** | 配置与自定义图标全量备份、干跑预校验及快照回滚 | `BackupService.cs`：打包导出 `config.json` + `icons/` + `manifest.json`，恢复前全量内存干跑校验 SHA256/JSON，自动拍 `pre-restore-*` 快照并自愈跨机路径 | `BackupService.swift` (新增)、`ConfigManager.swift`、`SettingsTabViews.swift` |

---

### 二、P0 各模块详细实施方案

#### 1. P0-1：启动项属性编辑器与自定义图标/别名 (`AppEntryEditor`)
1. **模型与等价性升级 (`LauncherItem.swift`)**：
   - 为 `ExecutionContext` 与 `LauncherItem` 实现 `Equatable`，确保 `ShelfGridView.reloadData` 复用按钮时能精准感知 `customIconPath`、`executionContext`、`tags` 的变更并刷新视图与右键菜单上下文。
   - 新增命令行参数解析与格式化辅助方法：`ExecutionContext.parseArguments(_ raw: String) -> [String]`（支持双引号/单引号包裹含空格参数）与 `formattedArgumentsString`。
2. **自定义图标托管与缩略图管线升级 (`ConfigManager.swift` + `ThumbnailPipeline.swift`)**：
   - 在 `ConfigManager` 中管理托管图标目录 `~/Library/Application Support/ATools/icons/`（沙盒测试环境下自动隔离至临时测试目录 `icons/`）。
   - 新增 `ConfigManager.importCustomIcon(from sourceURL: URL, for itemId: UUID) -> String?`：支持选择 `.png` / `.icns` / `.jpg` / `.tiff` 或直接点选 `.app` 提取应用图标，通过线程安全 `CGContext` 归一化缩放为 `256×256` PNG 并拷贝托管至 `icons/<itemId>.png`。
   - 升级 `ThumbnailPipeline.icon(forItem:completion:)` 与 `icon(forPath:customIconPath:completion:)`：当 `customIconPath` 存在且文件可读时，优先加载自定义图标并缓存；若自定义图标文件丢失，自动回退至 `target` 原生图标。
   - 升级 `ThumbnailPipeline.clearTransientSearchCache()`：同时保留抽屉项目的 `target` 与 `customIconPath` 缓存键，防止内存退火误清自定义图标。
3. **可视化属性编辑器弹窗 (`LauncherItemEditorDialog.swift`)**：
   - 采用固定尺寸 (`480 × 430`) AppKit 模态/Sheet 窗口，全子视图禁用 `translatesAutoresizingMaskIntoConstraints`，支持 `Esc` 取消、`Return` 保存，窗口层级置于 `.popUpMenu + 2` 防止被浮动抽屉遮挡。
   - 支持编辑：
     - **自定义图标预览与替换**：64×64 图标预览 +「更换图标...」（支持 `.png`/`.icns`/`.app`）+「恢复默认图标」；
     - **显示名称 (`name`)**；
     - **目标路径 (`target`)** +「重新定位...」浏览按钮；
     - **启动参数 (`executionContext.arguments`)**；
     - **工作目录 (`executionContext.workingDirectory`)** +「选择目录...」按钮；
     - **搜索别名标签 (`tags`)**：逗号或空格分隔，用于生僻字、多音字或自定义英文缩写检索。
4. **启动参数执行与全局/抽屉别名检索闭环 (`LauncherExecutor.swift` + `ShelfGridView.swift` + `SearchCoordinator.swift`)**：
   - `LauncherExecutor.open(item:completion:)`：读取 `item.executionContext`，对 `.application` 设置 `NSWorkspace.OpenConfiguration` 的 `arguments` 与 `environment`，对脚本/命令设置 `Process.currentDirectoryURL` 与 `arguments`。
   - `ShelfGridView.applyFilter(_:)`：支持匹配 `name`、`target`、`tags` 及其全拼与拼音首字母。
   - `SearchCoordinator` Layer 1：检索抽屉启动项的自定义名称与 `tags`（含拼音/首字母），命中时展示自定义名称与自定义图标，并按 `LauncherExecutor.open(item:)` 带参启动。

#### 2. P0-2：失效启动项检测、视觉标记与一键维护 (`IsTargetMissing` & `LibraryMaintenance`)
1. **目标路径存活检测 (`LauncherItem.swift` & `ShelfGridView.swift`)**：
   - `LauncherItem.checkTargetMissing()`：对 `.application` 与 `.fileOrFolder` 检查 `FileManager.default.fileExists(atPath: target)`；在抽屉加载与面板展示时后台异步批量校验并主线程无阻塞刷新按钮状态。
2. **半透明灰阶 + 右上角黄色感叹号微标 (`ShelfItemButton` & `ThumbnailPipeline`)**：
   - `ThumbnailPipeline.grayscaleImage(for:)`：基于 `CGColorSpaceCreateDeviceGray` 保留 Alpha 通道渲染高保真灰阶图标。
   - `ShelfItemButton.isTargetMissing`：为 `true` 时切换灰阶图标、透明度降至 `0.55`，并在图标右上角渲染黄色感叹号微标（`exclamationmark.triangle.fill`），悬停 ToolTip 显示失效原因与原路径。
3. **右键「重新定位目标...」与一键清理 (`ShelfGridView.swift` & `ConfigManager.swift` & `SettingsTabViews.swift`)**：
   - 右键菜单新增「重新定位目标...」；左键点击失效项目时主动弹出「重新定位目标 / 从分类中移除 / 取消」引导框。
   - `ConfigManager.relocateItem(id:in:newTarget:)`：**严格保持原有 `id`、排序位置、自定义名称、自定义图标、启动参数与 `tags` 不变**，仅更新 `target` 并刷新状态。
   - `ConfigManager.removeAllMissingItems()` 及设置页（`GeneralTabView` 与 `ShelfTabView`）「一键清理全部失效项目」按钮：实时展示失效项计数，支持一键清理全部失效项及孤立自定义图标。

#### 3. P0-3：自描述配置备份、恢复前预校验与自动快照回滚 (`BackupService`)
1. **自描述归档结构 (`BackupService.swift`)**：
   - 导出 `.atoolsbackup` 归档目录（或文件夹），内含：
     - `manifest.json`（含 `formatVersion`、`appVersion`、`createdAt`、`sourceUserHomePath`、`configSHA256`、`categoriesCount`、`totalItemsCount`、`customIcons` SHA256 映射）；
     - `config.json`（完整配置）；
     - `icons/`（全量托管自定义图标文件）。
2. **恢复前内存干跑预校验 (`validateBackup(at:)`)**：
   - 导入恢复前先在内存完整解析 `manifest.json` 与 `config.json`，核对 SHA-256 完整性、版本兼容性与 JSON Schema；若损坏则拒绝覆盖并弹窗提示具体错误。
3. **自动安全快照 (`backups/pre-restore-时间戳/`) 与跨机路径自愈 (`restoreBackup`)**：
   - 恢复前自动将当前配置与图标完整快照至 `~/Library/Application Support/ATools/backups/pre-restore-yyyyMMdd-HHmmss/`（自动保留最近 10 份快照），支持在设置页一键回滚至恢复前快照；
   - 自动将归档中的 `customIconPath` 重映射至本机 `~/Library/Application Support/ATools/icons/`，并对跨机用户主目录路径（`/Users/<oldUser>/...` -> `NSHomeDirectory()`）执行智能存活探测与自愈替换。
4. **「常规」设置页「备份与恢复数据」卡片 (`SettingsTabViews.swift`)**：
   - 在 `GeneralTabView` 新增「备份与恢复数据」卡片，提供「导出备份...」「导入恢复...」「回滚快照...」以及「一键清理失效项」可视化操作入口。

---

### 三、子代理架构与可用性审查结论 (Sub-Agent Architecture & Usability Review)

1. **浮动面板与模态弹窗防冲突验证**：
   - **风险点**：`ShelfPanel` 位于 `.statusBar` 级别且开启了失焦自动收起，若属性编辑器或 `NSOpenPanel` 以普通层级弹出，会导致抽屉自动关闭或弹窗被遮挡。
   - **加固措施**：新增 `PanelCoordinator.shared.isModalDialogOpen` 保护锁；在打开属性编辑器或「重新定位目标」文件选择面板期间置为 `true`，并将弹窗/面板层级提升至 `.popUpMenu + 2`，确保弹窗始终位于最前且抽屉稳固驻留。
2. **按钮复用缓存一致性验证**：
   - **风险点**：`ShelfGridView.reloadData` 原本仅比对 `name` 和 `target`，修改自定义图标或别名后不会刷新现有按钮。
   - **加固措施**：`LauncherItem` 实现完整 `Equatable`，属性变更后自动刷新图标纹理、ToolTip 与右键菜单 `representedObject`。
3. **跨机备份恢复与沙盒测试隔离验证**：
   - **风险点**：诊断测试 `--test` 运行时不能污染真实用户的 `~/Library/Application Support/ATools/` 目录。
   - **加固措施**：`ConfigManager` 的 `iconsDirectoryURL` 与 `backupsDirectoryURL` 动态跟随 `configURL.deletingLastPathComponent()`，在 `--test` 隔离环境下全部读写临时沙盒目录，生产环境与测试环境 100% 物理隔离。
4. **设置窗 780.0pt 几何宽度不变性验证**：
   - **风险点**：新增设置卡片若按钮过宽可能破坏 `780.0pt` 宽度不变性测试断言。
   - **加固措施**：使用紧凑型水平按钮栈（`NSStackView` spacing 8pt）与自适应换行副标题，确保在 580pt 右侧内容区内留有充足余量。
