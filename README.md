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
  * 基于 CoreServices `MDQuery` 实现全盘文件检索，直连 macOS 系统索引，**无须自建数据库，零磁盘写入消耗**。
  * **彻底替代聚焦 (Spotlight)**：
    * 🧮 **实时计算器**：输入 `(1024 * 768) / 2`、`0x10 + 32` 回车即刻复制计算结果。
    * 📖 **离线系统词典**：调用 `DCSCopyTextDefinition`，输入单词秒出释义。
    * ⚙️ **系统极速控制**：输入 `lock`（锁屏）、`sleep`（休眠）、`trash`（清空废纸篓）、`restart`（重启）等。

* 🛡️ **双全局快捷键与原子互斥调度**：
  * 采用 Carbon 原生多热键注册，**完全不需要辅助功能 (Accessibility) 权限**，零能耗监听。
  * `PanelCoordinator` 集中调度：两面板之间原子切换，**绝不发生窗口重叠与闪烁**，统一外部点击失焦退让。
* 🍃 **极致轻量**：
  * 原生 Swift 实现，安装包体积轻巧；
  * 面板关闭后 3 秒内自动执行堆内存脏页回收（`malloc_zone_pressure_relief`），常驻内存极低。

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
3. **关键：解除 macOS Gatekeeper 隔离（首次打开必须）**：
   开源应用未购买苹果昂贵的商业开发者证书，macOS 默认会拦截并提示“已损坏”或“无法确认开发者”。打开终端运行以下一行命令即可永久解除：
   ```bash
   xattr -cr /Applications/ATools.app
   ```
4. 双击启动 `ATools` 即可顺畅使用！启动后右上角状态栏将出现 🔍 放大镜图标，常驻闲置内存仅 ~20MB。

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
> * atools 的核心优势在于 **“零自建数据库、零扫盘能耗”**，直接向系统已有的 `mds` 索取检索结果。因此只需关闭 Spotlight 的快捷键和菜单图标，保留后台索引，即可实现极致省电、0 额外开销的毫秒级全盘秒搜！

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
│   ├── SpotlightBridge.swift         // CoreServices MDQuery 流式文件检索
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
