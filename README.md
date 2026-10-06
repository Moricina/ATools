# atools for macOS 🚀

> 拒绝臃肿，回归纯粹。专为 macOS 打造的双独立面板生产力神器：  
> • 🗂️ **应用分类工作台**（对标 Windows 极简启动器 **Maye Nano**）  
> • 🔎 **毫秒级全盘搜索中枢**（对标 macOS 原生 **聚焦 Spotlight / Raycast**）

---

## ✨ 核心亮点与重构升级

* 🎨 **高质感磨砂与 90%+ 遮光阻尼（告别虚透发灰）**：
  * 彻底摒弃粗糙的 `.hudWindow`，改用行业顶级的三重自适应磨砂底模：
    - **底层**：大散射卷积核 `.popover` 毛玻璃，彻底弥散背景高频图文；
    - **夹层**：自适应阻尼色漆（深色模式 88% 石墨黑、浅色模式 85% 柔白），杜绝任何文字穿透与重影；
    - **表层**：0.5pt 物理像素微高光描边（Rim Light），呈现精致轻拟物轮廓。
* 🗂️ **面板 A：Maye Nano 风格分类工作台 (`⌥A`)**：
  * **三段式高级胶囊标签 (CategoryPillView)**：融合 SF Symbol 图标 + 分类名 + 数量角标 (Badge)，自适应深浅色高光描边、微阴影浮雕与 Hover 悬停动效。
  * **完备分类管理与安全删减 (CRUD)**：
    - **右键上下文菜单**：支持在任意标签上右键快速「✏️ 重命名分类」、「🗑️ 删除分类」、「➕ 新建分类」；
    - **安全底线保护**：至少保留一个分类，禁止删空；
    - **非空级联保护**：分类内若包含应用/文件，支持「无损移交合并至邻近分类」或「连同项目一并删除」；
    - **配置自动持久化**：原子写入 `config.json`，重启不丢失。
  * **支持从访达 (Finder) 批量拖拽添加** 应用、文件夹、文件与 Shell 脚本。
  * 右键快捷项目可在访达定位、修改参数或删除。
* 🔎 **面板 B：Spotlight 风格全盘搜索中枢 (`⌥Space` 或接管 `⌘Space`)**：
  * **独立 680 x 480 流线型搜索窗口**，居中大输入条与光标秒级捕获。
  * **彻底消除闪退与停留**：UI 跨线程刷新保护，主线程重定向与监听器生命周期严密闭环，彻底根除 Option+Space 退出 Bug。
  * **原生中文拼音输入法 (IME) 深度兼容**：打拼音组字阶段（Marked Text）不截断回车与上下选词。
  * **0 毫秒** 匹配全盘核心应用（支持中文拼音简拼/全拼）。
  * 基于 CoreServices `MDQuery` 实现全盘文件秒级检索，直连 macOS Spotlight 索引，**无须自建数据库，减少额外磁盘扫描**；完美支持 `.localized` 本地化文件夹（如“虚拟机”/“文稿”/“下载”）显示名与拼音双向检索。
  * **彻底替代聚焦 (Spotlight)**：
    * 🧮 **实时计算器**：输入 `(1024 * 768) / 2`、`0x10 + 32` 回车即刻复制计算结果。
    * 📖 **离线系统词典**：调用 `DCSCopyTextDefinition`，输入单词秒出释义。
    * ⚙️ **系统极速控制**：输入 `lock`（锁屏）、`sleep`（休眠）、`trash`（清空废纸篓）、`restart`（重启）等。

* 🛡️ **双全局快捷键与原子互斥调度**：
  * 采用 Carbon 原生多热键注册，**完全不需要辅助功能 (Accessibility) 权限**，零能耗监听。
  * `PanelCoordinator` 集中调度：两面板之间原子切换，**绝不发生窗口重叠与闪烁**，统一外部点击失焦退让。
* 🚪 **关闭最后一个窗口即退出应用（对标 SwiftQuit）**：
  * 点击窗口红色关闭按钮且该应用再无其他窗口时，延迟自动退出该应用，告别“关了窗口应用还常驻”的困扰；
  * 支持「全部应用（名单为排除项）」与「仅名单内应用（名单为退出项）」双作用范围，0–5 秒延迟可调；
  * 具备未保存文档保护、最小化/隐藏窗口不误判，Finder 与 ATools 自身永久排除；内置独立应用名单搜索与编辑界面。
* 🍃 **极致轻量**：
  * 原生 Swift 实现，安装包体积轻巧；
  * 面板关闭后自动执行堆内存脏页回收（`malloc_zone_pressure_relief`），常驻物理内存极低（实测 Footprint 仅约 20–40MB，采用 Apple 官方 `task_vm_info.phys_footprint` 物理足迹真实口径）。

---

## ⌨️ 快捷键与操作速查

| 功能面板 | 默认快捷键 | 操作说明 |
| :--- | :--- | :--- |
| **应用分类面板 (Maye Nano)** | `Option + A` (`⌥A`) | 呼出分类工作台，点击或回车启动，支持拖拽外部文件加入 |
| **全盘搜索面板 (Spotlight)** | `Option + Space` (`⌥Space`) | 呼出全局搜索，直接打字秒搜，`↑`/`↓` 选择，`⏎` 打开，`⌘⏎` 在访达定位 |
| **退出 / 取消** | `Esc` 或 点击外部 | 瞬时关闭当前激活的面板，并优雅归还工作区光标 |

---

## 📥 快速开始与安装指南

### 方式 A：直接下载使用（面向普通 Mac 用户）
1. 从 GitHub 的 **Releases** 页面下载最新发布的 **`ATools.dmg`**（或 `ATools.zip`）；
2. 双击打开 `ATools.dmg`，将 **`ATools`** 直接拖入 **Applications (应用程序)** 文件夹；
3. 首次打开时按 macOS Gatekeeper 提示确认来源；不要使用 `xattr -cr` 清除隔离属性。正式发布应使用 Apple Developer ID 签名并完成公证。
4. 双击启动 `ATools` 即可顺畅使用！启动后右上角状态栏将出现 🔍 放大镜图标，常驻闲置内存约 20MB（RSS，非 Footprint）。

---

### 方式 B：从源码一键构建与打包（面向开发者）
项目基于纯原生 Swift Package Manager 构建，无需任何外部第三方依赖：
```bash
# 运行自动化打包脚本（生成 Release 版 ATools.app、ATools.zip 及 ATools.dmg）
./Scripts/package_app.sh

# 运行自动化沙盒诊断自检（Debug 构建才会启用 assert；安全隔离测试，零污染个人配置）
swift build -c debug --debug-info-format none
./.build/debug/ATools --test

# 启动应用
open ./ATools.app
```

---

## 🛑 彻底关闭与替换系统聚焦 (Spotlight) 的详细步骤

在 macOS 上，“彻底替换聚焦”包含两个层面：**关闭 Spotlight 前台入口（快捷键 + 菜单栏图标）**，以及**让 atools 完美接管全局调用**。

### 步骤 1：禁用系统聚焦的快捷键（释放 Cmd + Space）
1. 打开 macOS **「系统设置」** (System Settings)；
2. 在左侧栏找到并点击 **「键盘」** (Keyboard)；
3. 点击右侧的 **「键盘快捷键...」** (Keyboard Shortcuts...) 按钮；
4. 在弹出窗口左侧导航选择 **「聚焦」** (Spotlight)；
5. **取消勾选** 以下两项：
   - ☑️ **显示“聚焦”搜索**（原快捷键为 `⌘ Space`）
   - ☑️ **显示“访达”搜索窗口**（原快捷键为 `⌥⌘ Space`）
6. 点击「完成」保存。此时 `Cmd + Space` 已完全被系统释放，不再有任何冲突！

### 步骤 2：从右上角菜单栏移除聚焦放大镜图标
1. 再次打开 **「系统设置」** -> 左侧点击 **「控制中心」** (Control Center)；
2. 向下滚动找到 **「聚焦」** (Spotlight) 模块；
3. 将下拉选项从「在菜单栏中显示」改为 **「不在菜单栏中显示」**；
4. 此时 macOS 顶栏右侧的系统聚焦放大镜图标将彻底消失，桌面干净清爽。

### 步骤 3：让 atools 接管日常（推荐做法）
* 启动 atools 后，点击右上角菜单栏 🔍 放大镜状态图标，选择 **「彻底关闭/替换聚焦 (Spotlight) 指南...」**，可一键直达上述系统设置页面；
* 此时日常使用 `⌥A` 唤出分类工作台，使用 `⌥Space`（或接管后的 `⌘Space`）唤出全局搜索，全面替代并超越原生体验。

> [!CAUTION]
> **重要技术提醒：为什么不建议使用终端命令 `sudo mdutil -a -i off` 强行杀死后台索引？**
> * 很多网上教程会建议执行 `sudo mdutil -a -i off`。这会彻底关闭 macOS 内核的 `mds` 元数据守护进程。
> * **千万不要这样做！** 因为 `mds` 索引不仅供原生聚焦使用，macOS 系统的访达搜索、邮件检索、Xcode 索引以及第三方高效搜索工具（包括 atools 的 `MDQuery` 接口、Raycast、Alfred）都依赖该底层索引。
> * atools 的核心优势在于 **“零自建数据库、减少额外扫盘”**，直接向系统已有的 `mds` 索取检索结果。因此只需关闭 Spotlight 的快捷键和菜单图标，保留后台索引，即可获得低开销的全盘搜索体验。

---

## 📝 最近更新记录

### v1.3.0 (Build 19)：新增「关窗即退出」与设置页名单交互加固

* 🚪 **新增 AutoQuitManager（关窗即退出应用）**：
  * 对标开源 SwiftQuit：感知最后一个窗口关闭并延迟自动退出该应用；
  * 支持「全部应用（排除名单）」与「仅名单内应用（退出名单）」双模式，延迟 0–5 秒可调；
  * AX 事件驱动 + 4 秒兜底轮询，系统硬排除 + 转变式触发 + pid 复用防护，零杀错。
* 🛠️ **名单编辑器（AutoQuitRulesEditorView）Auto Layout 防坍缩与单元格复用**：
  * 彻底修复 Sheet 窗口因 Auto Layout 求解折叠导致的 18x32 白核及模态假死 Bug；
  * 引入 `AutoQuitAppTableCellView` 专用复用单元格，滚动 270+ 应用无卡顿；
  * 完善 `Esc` / `Return` 键位支持与解挂兜底保护；总开关关闭时亦开放预设名单。
* 📊 **内存口径说明**：
  * 设置页「运行与性能」全面采用 Apple 官方 `task_vm_info.phys_footprint` 真实物理足迹，与活动监视器完全吻合（杜绝 RSS 共享框架虚高）。

### v1.2.9：应用抽屉 (Shelf) 选中与动效打磨

* 🖱️ **选中高亮跟随鼠标**（`ShelfGridView.swift`）：
  * 新增 `ShelfItemButton.onHoverChanged` 回调，悬停到哪个图标，选中背景就跟随到哪个；
  * 引入 `pinnedSelectionID` 区分「悬停临时选中」与「键盘/点击固定选中」，鼠标移出图标或面板后高亮自动清除，不再残留阴影；
  * 面板打开时不再默认选中第一个图标（`applyFilter` 不强制回落首项，显示前经 `clearKeyboardSelection()` 清空残留）。
* 🌫️ **残留阴影治理**：
  * `baseLayer` 样式变更全部包入显式 `CATransaction`（0.10s easeOut），消除独立 CALayer 默认 0.25s 隐式动画导致的阴影拖尾；
  * 新增 `resetInteractionStates()`：快捷键收起面板时鼠标下方的图标收不到 `mouseExited`，hover 状态会卡死，下次打开残留阴影，现于每次显示前统一重置。
* ⚡ **收起面板闪烁与提速**（`PanelCoordinator.swift`）：
  * 收起时不再提前移除入场动画（`sublayerTransform` 0.96→1.0 跳变会闪一帧），改为淡出完成后在回调中清理；
  * 调整 `orderOut` 与 `alphaValue` 复位顺序，避免淡出完成瞬间闪现全亮一帧；
  * 收起动画 160ms → 90ms，曲线改为陡降 `(0.4, 0, 1.0, 1.0)`，回收更利落。
* 🔎 **搜索面板视觉优化**（`SearchPanel.swift` / `SearchResultsTableView.swift`）：
  * 搜索栏与结果列表间距 10pt → 2pt，结果紧贴搜索文字，不再有空荡荡的空白带；
  * 新增滚动边缘渐变遮罩：滚动时行在视口上/下边缘柔和溶解，不再被硬线切断；静止时渐变关闭，首尾行保持清晰。
* 🧠 **物理内存占用优化与泄漏排查**：
  * `leaks` 工具全量扫描：仅剩系统框架的 NSXPCConnection 内部循环（~19KB），业务代码零泄漏；
  * 搜索繁忙后内存不再堆积：每次搜索清理上一代结果缓存，搜索静默 3s 后自动调度退火（`scheduleAnneal`）归还 malloc 空闲页——实测 30 次连续搜索后占用从 45MB 降至 31MB；
  * 词典缓存加上 512 条上限（原先每个按键前缀都永久缓存）；
  * 热文件夹快照：面板关闭时释放（下次打开本来就会重建），并加上单目录 25k 条上限防止超大下载目录占用；
  * 设置页关闭时释放 7 个缓存 Tab 视图（下次打开懒重建），回收数百个视图与 AutoLayout 对象。
* ⚡️ **全盘搜索打字卡顿修复**（`MetadataFileSearchBackend.swift` / `SpotlightBridge.swift`）：
  * 根因：旧实现用 `NSMetadataQuery` 在主线程逐项读取属性，每次读取都是到 mds 守护进程的同步 XPC，外加逐项 stat；像 `how` 这种常见子串命中数万文件名，输入即冻结（采样：主线程 70% 时间耗在这里）；
  * 重写为 CoreServices `MDQuery`：后台串行队列同步执行、属性随结果批量预取（内存内读取）、按需只为 Top-N 构造结果对象；
  * 热文件夹快照与合并也移出主线程，结果回投主线程；单字符查询只走热目录+应用索引（全盘检索从 2 字符起）；
  * 修复后同样输入场景采样：主线程 99.8% 空闲等待事件，metadata 相关 0 样本。

---

## 🏗️ 架构设计图景

```
atools/
├── App/
│   ├── AppDelegate.swift             // 状态栏图标与托盘事件调度
│   ├── HotkeyManager.swift           // Carbon 原生多热键注册 (零权限)
│   └── MemoryGuardian.swift          // 面板隐藏时三级内存退火与脏页回收
├── Search/
│   ├── AppHotspotIndex.swift         // 0ms 内存 App 索引 (拼音/简拼/多路径覆盖)
│   ├── SpotlightBridge.swift         // NSMetadataQuery 系统索引文件检索
│   ├── CalculatorEngine.swift        // 离线数学表达式即时计算
│   ├── DictionaryService.swift       // DCSCopyTextDefinition 系统离线词典
│   ├── ThumbnailPipeline.swift       // 64px 像素限制缩略图 + UTI 共享单例 (6MB 上限)
│   └── SearchCoordinator.swift       // 多层级搜索聚合与流式分发
├── Storage/
│   └── ConfigManager.swift           // 强类型 HotkeyBinding、分类与启动项持久化
├── System/
│   └── SystemActions.swift           // 锁屏、休眠、废纸篓等系统原生指令
└── UI/
    ├── VisualEffectBackdropView.swift // 90%+ 遮光阻尼高质感磨砂底模
    ├── PanelCoordinator.swift        // 双面板原子互斥调度器 & 黄金视线居中
    ├── ShelfPanel.swift              // 面板 A: Maye Nano 风格分类工作台
    ├── SearchPanel.swift             // 面板 B: Spotlight 风格全盘搜索中枢
    ├── CategoryBarView.swift         // 分类标签胶囊栏
    ├── ShelfGridView.swift           // 自适应拖拽网格视图
    ├── SearchBarView.swift           // 原生大搜索输入框 (完美拼音候选框)
    └── SearchResultsTableView.swift  // 虚拟化复用搜索结果表
```
