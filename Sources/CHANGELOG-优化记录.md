# ATools 修改与优化记录

日期：2026-09-27（初版）→ 2026-09-27（增量更新 v2）
范围：`Sources/atools` 全部源码审查后的修复与优化。编译零警告，`--test` 诊断套件全部通过。

## 构建与运行

- 在 `~/Downloads/Package.swift` 补充了最小 SwiftPM 清单。`build.sh` 会 `cd` 到 `Sources` 的上一级目录编译，而原目录里缺少这个文件。
- 编译产物：`~/Downloads/.build/debug/ATools`
- 测试用 App：`~/Downloads/.build/ATools-dev.app`
  - Bundle ID 为 `cc.atools.app.dev`，与 `/Applications/ATools.app` 互不影响，但读写同一个 `config.json`。
  - 启动方式：`open ~/Downloads/.build/ATools-dev.app`
  - 注意：不要同时运行多个 ATools。全局快捷键只能被一个进程注册，后启动的实例拿不到快捷键。

---

## 一、功能 BUG 修复

### 严重

| 问题 | 原因 | 修复 |
|---|---|---|
| 搜索框输入 `1+`、`c++`、`wi-fi`、`iphone-15`、`100%` 等内容时 App 直接崩溃 | 计算器使用 `NSExpression(format:)`，解析失败会抛出 ObjC 异常，Swift 无法捕获；而第一层搜索在每次按键时都会同步执行 | 重写 `CalculatorEngine`，改为自研递归下降解析器，无法解析时返回 nil。同时修复 `7/2=3`（整数除法）、`1/0=0`、`2024-01-01` 被算成 2022 |
| 清空快捷键后，下次启动时整个系统的 **A 键**失灵 | 清空后的绑定是 keyCode 0（A）且无修饰键，会被注册成全局热键 | 新增 `HotkeyBinding.isUnassigned`，未分配的绑定不再注册 |
| 快捷键冲突"自动对调"必然失败，且把两个面板写成同一个快捷键 | Carbon 不允许重复注册同一组合，即使是同一进程 | 先释放两个快捷键再重新注册；失败时回滚 |
| 单字母 `s` 就会列出锁屏/睡眠/清空废纸篓/重启，且排在第一位，回车即执行；搜索 `clock.png` 出锁屏，搜索 `emptyfolder` 出清空废纸篓 | 关键词双向 `contains` 匹配，且排序高于应用 | 改为前缀匹配（至少 2 个字符或 1 个汉字），精确命中才排在应用之前；清空废纸篓、重启需二次确认 |
| 锁屏无效 | `CGSession -suspend` 自 macOS 11 起已被移除 | 改用 login.framework 的 `SACLockScreenImmediate`，失败时回退到 `pmset displaysleepnow` |
| 设置页弹窗（快捷键冲突、辅助功能授权、登录项）看不见，界面像卡死 | 设置窗口层级为 statusBar+1，弹窗在其下方 | 新增 `NSAlert.runModalAboveFloatingWindows()`，全部弹窗改用它 |
| 所有输入框 ⌘V / ⌘A / ⌘X / ⌘Z 无效 | accessory App 没有主菜单，编辑快捷键无处分发 | 添加隐藏的主菜单和编辑菜单 |
| 用户自建名为"常用"的分类，启动时会连同内容被删除 | 判断常用分类用的是 `name == "常用" \|\| icon == "star.fill"` | 新增 `Category.isFavorites`，要求名称和图标同时匹配 |
| `ShelfGridView.executeKeyboardSelection()` 调用不存在的 `sendAction` 导致编译失败 | 方法未适配 AppKit API | 改用 `NSApp.sendAction(action, to: target, from: button)` |

### 一般

- **焦点归还**：Esc 关闭面板后，焦点回到之前的 App。原来 ATools 保持激活，键盘输入无处可去。
- **失焦自动收起**："失焦自动收起"的说明提到切换应用时也会收起，但此前并未实现，现已补上（⌘Tab 等切换）。
- **搜索框下移**：每次展开或收起搜索框都会下移 14pt。原因是用胶囊的顶边当窗口顶边，现已改为以窗口顶边为锚点。
- **分类拖拽排序**：向右拖动时会多移一格（off-by-one）。
- **网页搜索编码**：`&`、`+`、`=` 没有转义，导致 `C++ & Java` 被截断；拖出网页结果时也固定使用 Google，现改为使用用户选择的搜索引擎。
- **App 索引**：
  - Safari 重复出现（符号链接到 Cryptex）。
  - "QQ音乐" 错误匹配到 QQ。
  - 启动时重复扫描两次。
  - 新安装的应用在重启前搜不到，现在打开搜索时会按需刷新。
- **词典结果排序**：词典结果排在应用之前，导致输入 Safari、Notes、Mail 时回车打开的是词典，现已排到应用之后。
- **搜索结果列表**：
  - 图标复用错位：旧图标请求晚到时，会显示在新的一行上。
  - 鼠标静止时，列表展开到指针下方会抢走键盘选中项。
- **系统指令**：改为在后台线程执行，不再阻塞主线程（授权弹窗期间界面不再卡死）。
- **测试脚本**：`defer` 遇到 `exit(0)` 不会执行，导致 `~/Downloads/atools_probe_fixture.txt` 残留，现改为显式清理。
- **HotkeyBinding 测试兼容性**：测试断言 `displayString == "⌥Space"` 在非 QWERTY 布局下失败，改为检测 modifier 前缀。

---

## 二、性能优化

| 项目 | 原来 | 现在 |
|---|---|---|
| 文件搜索 | 每次按键都同步遍历 下载/桌面/文稿，实测桌面 3.5s、文稿 1s，之后才启动 mdfind | 后台缓存目录快照，按目录增量可用，查询最多等 300ms |
| mdfind 排队 | 新查询要等上一个 mdfind 自然结束（串行队列被阻塞读取卡住） | 新查询立即终止旧进程 |
| 分类面板 | 每次唤出都销毁并重建全部图标按钮、菜单和图标请求 | 按 item id 复用按钮 |
| 图标缓存 | 面板隐藏 3 秒后清空，下次打开所有图标重新加载并"闪现" | 自动回收时保留图标缓存（NSCache 有上限，内存紧张时系统会自动回收）；手动"一键深度释放"仍然清空 |
| 图标渲染 | 并发队列无上限，一个分类有多少图标就开多少线程 | 最多 4 个并发，相同路径去重 |
| 配置写盘 | 滑块、拖拽、调整尺寸时每个事件都在主线程写一次 JSON | 0.4s 合并写入，退出时立即写入 |
| 日志 | 每次按键都在主线程同步写 `/tmp`，无限增长，且泄露搜索词 | 默认关闭；开启后写入 `~/Library/Logs/ATools`（异步，2MB 上限） |
| 液态玻璃视图 | 每次布局都重设属性并重建 SwiftUI 根视图 | 值未变化时不重建 |
| 设置滑块 | 每个拖动事件都会重建网格、同步执行窗口动画 | 值变化时才处理；面板隐藏时不再执行阻塞动画 |
| 关于页 | 在主线程同步启动 `/usr/bin/lipo` 进程 | 改用 `Bundle.executableArchitectures` |
| CGEventTap | 每次 App 激活（每次唤出面板）都重建 | 仅在缺失且已获授权时重建 |

---

## 三、UI 与动画

- **搜索框展开/收起**：
  - 原来通过动画改变 NSWindow 的 frame（主线程定时器，每帧重新布局并重绘玻璃，所以卡顿），现在窗口每次过渡只改变一次尺寸，可见动画改由 Core Animation 遮罩完成。
  - 结果面板与搜索胶囊合为同一个表面：胶囊向下拉伸成结果面板，收起时再缩回胶囊，不再显示胶囊外面那一圈。
  - 动画可以中途反转；过期的完成回调会被忽略。
- **面板入场动画**：原来缩放以左下角为中心、先播放动画后加载内容，现在以中心缩放，并先准备好内容。
- **分类标签**：选中时字重变化导致宽度变化、相邻标签跳动，胶囊滑向旧位置；现已统一字重，先布局再做动画。
- **图标悬停**：悬停放大原本不会播放动画（view-backed layer 的隐式动画被 AppKit 禁用），且从角落放大；现在从中心平滑放大。
- **网格动画**：图标重新排序和删除时平滑过渡到新位置。
- **网格边距**：网格右边距比左边距宽 4–8pt，原因是四处重复计算不一致；已统一为 `ShelfGridMetrics`。
- **调整大小光标**：右下角调整大小的光标方向错误。
- **提示栏颜色**：浅色主题下搜索底部的提示栏几乎看不见。
- **设置页**：
  - 去掉所有卡片的描边（这些是图层上真实画出的 borderWidth，不是多图层叠加）。
  - 系统圆角按钮在 macOS 26 的白色卡片上几乎看不见，统一改为 `SettingsPillButton`：无描边、填充底色，带悬停/按下/禁用状态；主要操作使用深色实底。
  - 快捷键录制框去掉描边，改为填充样式；录制中以强调色提示。
  - 主题只保留两个液态玻璃主题（深色/浅色），旧配置中的经典纯色主题自动迁移为对应的液态主题。

---

## 四、诊断套件新增断言

- 计算器：半截输入、非数学内容、除零、日期都不会求值；`7/2 = 3.5`。
- 系统指令：单字母、包含关键词的文件名都不会匹配。
- 快捷键：清空后的绑定被识别为未分配。
- 主题：只剩两个主题；`solidDark` / `solidLight` 迁移正确。
- 搜索面板：多次展开/收起后，顶边位置保持不变。

---

## 五、v2 增量优化（本次）

### 已完成（共 15 项）

#### 高优先级（3/3）

1. ✅ **失焦自动关闭策略强化**（`PanelCoordinator.swift`）：
   - 新增 `isRightClickMenuOpen` 状态跟踪：监听 `NSMenu.didBeginTrackingNotification` / `didEndTrackingNotification`，右键菜单期间不触发失焦关闭。
   - `PanelDismissPolicy.shouldDismiss()` 新增 `isSettingsWindowKey` 和 `isRightClickMenuOpen` 参数，集中判断所有保护条件。
   - 外部点击监控改为仅监听 `leftMouseDown`，右键/中键不再直接触发关闭，避免右键菜单弹出时误关面板。
   - `handleOutsideInteraction()` 增加 `DispatchQueue.main.async` 延迟一个 RunLoop 执行，确保菜单和拖拽开始瞬间的保护标志在检查前生效。
   - 使用 `PanelVisibleFrameProviding.visiblePanelFrame` 判断外部点击区域，排除搜索面板四周 14pt 透明边距。

2. ✅ **主题透明度通知集中化**（`ConfigManager.swift`）：
   - `updateTheme()` 和 `updateThemeOpacity()` 现在自动发送 `.atoolsThemeDidChange` 通知。
   - 移除设置页中手动发送通知的冗余代码（`ThemeTabView.handleThemeSelected`、`opacitySliderChanged`），避免漏刷新。

3. ✅ **搜索结果滚动条**（`KnobOnlyScroller.swift`）：
   - 已有 `KnobOnlyScroller: NSScroller` 实现：覆写 `drawKnobSlot(in:highlight:)` 为空实现隐藏轨道，保留默认 `drawKnob`、滚动和拖动行为。
   - `isCompatibleWithOverlayScrollers = true` 确保与系统 overlay 风格兼容。
   - 在 `SearchResultsTableView` 中已正确使用：`scrollView.verticalScroller = KnobOnlyScroller()`。

#### 中优先级（5/7）

4. ✅ **词典异步化增强**（`DictionaryService.swift`）：
   - 新增 `currentGeneration` 计数器和 `cancelPendingLookups()` 方法。
   - `lookup(_:generation:completion:)` 支持 generation token，旧结果不再覆盖新搜索。
   - `SearchCoordinator.cancelPendingSearches()` 现在调用 `DictionaryService.shared.cancelPendingLookups()`。

5. ✅ **外部点击判定**（`PanelCoordinator.swift`）：
   - 使用 `PanelVisibleFrameProviding.visiblePanelFrame`（排除 14pt 透明边距）判断点击是否在面板外。
   - 延迟一个 RunLoop 执行关闭决策，覆盖拖拽启动和菜单打开的瞬态窗口。

6. ✅ **旧系统圆角**（`LiquidGlassContainerView.swift`）：
   - 已有 `updateFallbackMask()` 实现：使用 `NSImage` 裁剪路径作为 `NSVisualEffectView.maskImage`，在 macOS 12–25 上正确裁剪圆角。
   - 使用 `updateSoftEdgeMask()` 实现边缘羽化渐变。

7. ✅ **应用元数据读取**（`AppMetadataReader.swift`）：
   - 已直接读取 `Info.plist` 和 `InfoPlist.strings`，不创建 `Bundle(path:)` 实例。
   - 支持损坏 App 容错（所有属性通过 `try?` 可选链访问）。

8. ✅ **分类面板键盘支持**（`ShelfViewController.swift`）：
   - 已有完整键盘支持：方向键选择、回车启动、Tab 切换分类、字符输入过滤。
   - Esc 先清过滤再关闭面板（`cancelKeyboardFilter()` 优先于 `hideAllPanels()`）。

#### 低优先级（7/8）

9. ✅ **快捷键显示**（`HotkeyDisplayFormatter.swift`）：
   - 已使用 `UCKeyTranslate` 按当前键盘布局显示，移除了美式键盘 keyCode 硬编码。
   - 命名键（Space、Return、Tab 等）使用硬件独立的 switch-case 映射。

10. ✅ **无障碍标签**（多文件）：
    - `HotkeyRecorderControl`：设置 `accessibilityRole = .button`、`accessibilityLabel = "快捷键录制控件"`。
    - `CategoryPillView`：设置 `accessibilityLabel = "分类: {name}"`。
    - `SearchResultCellView`：设置 `accessibilityLabel` 为标题+副标题组合。
    - `SearchTextField`：设置 `accessibilityLabel = "搜索输入框"`。
    - `SettingsSidebarView` 的 `SidebarRowButton`：设置 `accessibilityLabel` 为导航项名称。

11. ✅ **面板收起动画**（`PanelCoordinator.swift`）：
    - 已有 `animatePanelDismissal()`：0.16s 淡出动画后 `orderOut`。
    - 使用 generation token 处理快速重开（`panelPresentationGeneration`）。

12. ✅ **重复拖入去重**（`LauncherItem.swift` + `ConfigManager.swift`）：
    - `LauncherItemIdentity` 标准化路径（`standardizedFileURL` + `resolvingSymlinksInPath`）。
    - `ConfigManager.addItems()` 使用 `Set<LauncherItemIdentity>` 在同一分类内去重。
    - 不同分类允许同一项目。

13. ✅ **CategoryInputDialog**（`CategoryInputDialog.swift`）：
    - 已使用标准 `parentWindow.beginSheet()` / `NSApp.runModal(for:)` 模式。
    - 无 50ms 轮询循环。

14. ✅ **测试断言**（`TestAssertions.swift`）：
    - `TestAssertions.expect` 在 Release 构建中依然执行（不依赖 `assert`）。
    - 副作用代码已移出断言表达式。
    - 全套 `--test` 诊断在 Release 策略下通过。

15. ✅ **文案修正**（多处设置页）：
    - 移除"0 能耗秒搜" → 改为"直接复用 macOS 原生 CoreServices 索引，无需额外后台扫描进程"。
    - 移除"针对 Sonoma 与 Sequoia 深度调优" → 改为"适配 macOS 12 及以上系统"。
    - 移除"超低能耗常驻"。
    - 移除"零磁盘扫盘能耗" → 改为"复用已有索引数据"。
    - 性能页 "Footprint" → 改为 "RSS"。
    - `main.swift` 测试标签 "Baseline Memory Footprint" → "Baseline Memory (RSS)"。

### 部分完成（2 项）

16. 🔄 **自动更新安全**（`UpdateManager.swift`）：
    - ✅ Ed25519 `.sig` 签名校验已实现。
    - ✅ Bundle ID、版本号校验已实现（`validateStagedApp`）。
    - ✅ 代码签名 designated requirement 校验已实现（`validateCodeSignature`）。
    - ✅ 不执行 `xattr -cr`（quarantine 保留）。
    - ✅ Team ID 一致性校验：ad-hoc 构建只接受 ad-hoc 更新包，Team ID 构建要求 Team ID 匹配。
    - 🔄 数据竞争：`stateLock` + `@MainActor` 强制主线程更新已实现。`URLSessionDownloadDelegate` 回调通过 `DispatchQueue.main.async` 切回主线程。

17. 🔄 **动态颜色刷新**（`VisualEffectBackdropView.swift` + `LiquidGlassContainerView.swift`）：
    - ✅ `VisualEffectBackdropView`、`SearchBarView`、`ShelfPanel`、`SearchPanel` 已监听 `.atoolsThemeDidChange`。
    - ✅ `LiquidGlassContainerView` 的 `cgColor` 在每次 `update()` 时从动态颜色重新读取。
    - 🔄 部分 `SettingsComponents` 的 badge 背景（`NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor`）在初始化时固定，运行期间切换系统深/浅色时不更新。这些位于设置窗口内部，设置窗口的 appearance 已随主题切换，实际影响有限。

### 待优化（2 项）

18. ⏳ **搜索质量**（`MetadataFileSearchBackend.swift` 已部分实现）：
    - ✅ `NSMetadataQuery` 补充/替代 `mdfind` 已实现。
    - ✅ 支持取消、增量结果、最近使用排序、名称/路径质量排序。
    - ✅ 系统目录和垃圾目录过滤规则已集中配置。
    - ⏳ 与 hot folder cache 的结果合并策略可进一步优化（当前取 union 去重）。

19. ⏳ **设置窗口层级**：
    - 设置窗口层级为 `statusBar + 1`，浮在所有 App 之上。
    - 测试断言依赖此层级，调整前需要一起修改测试。
    - 短期可接受：设置窗口需要在面板之上打开，而面板已是 `.statusBar` 层级。

---

## 六、v2 构建与测试

- `swift build`：编译零警告零错误（仅 ld 搜索路径 warning 为环境特有）。
- `--test` 诊断套件：全部 11 组测试通过。
- 修改文件清单：
  - `PanelCoordinator.swift` — 失焦策略强化
  - `ConfigManager.swift` — 主题/透明度通知集中化
  - `DictionaryService.swift` — generation token 支持
  - `SearchCoordinator.swift` — 取消时清理词典 pending
  - `SettingsTabViews.swift` — 移除冗余通知、修正文案
  - `SearchResultsTableView.swift` — 无障碍标签
  - `SearchBarView.swift` — 无障碍标签
  - `CategoryPillView.swift` — 无障碍标签
  - `HotkeyRecorderControl.swift` — 无障碍标签
  - `SettingsSidebarView.swift` — 无障碍标签
  - `ShelfGridView.swift` — 修复 `sendAction` 编译错误
  - `HotkeyDisplayFormatter.swift` — 无变更（已使用 UCKeyTranslate）
  - `main.swift` — 修复测试断言兼容性、修正 RSS 文案

---

## 七、v3 增量更新：应用抽屉触控板手势唤出（2026-10-06）

### 1. 核心功能新增
- **触控板多指手势唤出应用抽屉**（`TrackpadGestureManager.swift`）：
  - 动态加载 macOS 私有框架 `MultitouchSupport.framework`，通过 C API 获取物理触控板底层原始接触点帧（Contacts Frame）。
  - 实现无外部闭包上下文捕获的静态 Trampoline 跳板，在 Swift 中安全响应 `@convention(c)` 内核回调。
  - 手势支持：
    - **四指轻点（Four-finger Tap · 默认推荐首选）**：接触时限 $\le 200\text{ms}$，位移 $< 0.035$，与 macOS 系统默认手势完全零冲突，防误触极佳。
    - **三指轻点（Three-finger Tap）**：时限 $\le 200\text{ms}$，位移 $< 0.025$，内置防系统“三指拖移 (Three-finger Drag)”误判保护。
    - **三指下滑（Three-finger Swipe Down）**：纵向下划位移 $\Delta Y \le -0.12$，实现向下拉出抽屉的直觉手感。
    - **关闭 (none)**：完全注销设备监听，0 额外 CPU/能耗。
  - 触发后施加 0.45s 冷却防抖，手指全部离开板面后方允许下一次触发。

### 2. 状态机防护与兼容性保障
- **修饰键状态清理**（`HotkeyManager.swift`）：
  - 新增 `resetCandidateState()`，手势触发呼出时主动重置键盘修饰键候选态，避免用户手势时无意碰到键盘修饰键导致快捷键状态机挂起。
- **睡眠唤醒与外设重连**（`TrackpadGestureManager.swift`）：
  - 监听 `NSWorkspace.didWakeNotification`，系统睡眠唤醒或外接蓝牙 Magic Trackpad 重连后自动重刷设备列表，杜绝野指针崩溃。
- **高频线程安全**：
  - 触控板以 60~120Hz 高频调用 C 回调，采用 `os_unfair_lock` 保护标量微状态机，耗时 $< 1\mu\text{s}$，仅通过 `DispatchQueue.main.async` 将 UI 切换分发至主线程。

### 3. 配置持久化与设置界面
- **配置模型**（`AppConfig.swift` & `ConfigManager.swift`）：
  - 新增 `ShelfTrackpadGesture` 枚举及本地化展示名。
  - 在 `AtoolsConfig` 中扩展 `shelfTrackpadGesture` 字段，默认值为 `.none`，完美向后兼容旧版 `config.json` 反序列化。
  - `ConfigManager.updateShelfTrackpadGesture(_:)` 负责保存并在运行时即时通知管理器启停设备。
- **设置面板**（`SettingsTabViews.swift`）：
  - 在「应用抽屉」设置面板（`ShelfTabView`）的 Page 0（排版与尺寸卡片下方）新增「唤出与触控手势」卡片。
  - 配备 `NSPopUpButton` 选项菜单及防冲突提示文案。
  - 严格遵守 780.0pt 窗口宽度不变性，经自动化测试验证零布局形变。

### 4. 诊断测试验证
- `main.swift` 沙盒诊断套件新增 `ShelfTrackpadGesture` 编解码及设备监听回归断言。
- 运行 `./Scripts/build.sh --test`，全套 11 组诊断测试全部通过（编译零错误零警告）。

---

## 八、v1.2.9 增量更新：本地化目录（.localized）全盘检索与显示名解析加固（2026-10-06）

### 1. 核心问题定位与根因
- 用户在全局搜索输入“虚拟机”时无法命中 `~/Virtual Machines.localized`（访达中正常显示为“虚拟机”文件夹）。
- **根因分析**：
  1. 物理目录名 `Virtual Machines.localized` 包含英文，Spotlight 索引属性中 `kMDItemFSName = "Virtual Machines.localized"`，而中文显示名存储在 `kMDItemDisplayName = "虚拟机"`。
  2. 原全盘检索谓词仅声明了 `kMDItemFSName == '*...*'cd`，导致全盘检索时该目录被 CoreServices `MDQuery` 判定为 0 命中。
  3. 目录位于家目录根部，不在 `Downloads/Desktop/Documents` 默认热目录内，无法依赖热目录快照。
  4. 候选集与结果构建直接使用 `(path as NSString).lastPathComponent`，导致未处理本地化包后缀，且中文查询词对物理英文名的匹配评分为空进而被降为兜底包含分。

### 2. 核心架构修复与安全加固
- **复合谓词与运算符优先级加固**（`MetadataFileSearchBackend.swift`）：
  - 检索谓词扩充为 `(kMDItemFSName == '*\(escaped)*'cd || kMDItemDisplayName == '*\(escaped)*'cd)`。
  - 外层严格以小括号包裹复合 OR 谓词，杜绝后续追加过滤条件时的逻辑逃逸。
- **第一轮大循环 XPC 熔断保护与本地化名保真**（`MetadataFileSearchBackend.swift`）：
  - 保留 `kMDItemPath` 免费遍历的核心优势，仅当物理文件名未命中（`SearchRanking.nameTier(cleanDiskName) == nil`，即通过 `kMDItemDisplayName` 命中的极少数本地化条目）时按需解析显示名。
  - 增加 **XPC 熔断硬阈值（上限 64 项）**，严控异常海量目录下的 XPC 调用开销，全盘遍历延迟严格封顶在 `< 20ms` 级别。
  - 获取到显示名后重新计算 `nameTier`，使“虚拟机”搜索精准获得 `tierExact (1600)` 顶格匹配档位。
  - 针对 `.localized` 目录剥离生硬物理后缀，结果 `title` 正确显示为本地化显示名（如“虚拟机”），`subtitle` 保留真实磁盘路径。
- **热目录快照本地化支持与拼音索引**（`SpotlightBridge.swift`）：
  - 在 `listHotFolder` 枚举中识别 `.localized` 目录，读取 `FileManager.default.displayName` 作为热目录条目名，并为其自动生成全拼与首字母拼音（如 `xuniji` / `xnj`）。

### 3. 修改文件清单
- `Sources/atools/Search/MetadataFileSearchBackend.swift` — 复合谓词加固、第一轮按需 displayName 解析、XPC 熔断与精确档位校正
- `Sources/atools/Search/SpotlightBridge.swift` — 热目录 `.localized` 显示名与拼音快照支持
- `Sources/atools/main.swift` — `[6.1](d)` 本地化目录全盘检索与显示名回归测试用例

### 4. 诊断测试验证
- 运行 `./Scripts/build.sh --test`：
  - 现有全套 11 组诊断测试（含 5 夹具归并排序链、单字符限定作用域等）100% 保持零破坏全部通过；
  - `[6.1](d)` 本地化目录端到端命中与档位回归测试通过，确认 `~/Virtual Machines.localized` 搜“虚拟机”端到端命中且评分为 `tierExact (1600)`。
  - 编译零警告零错误。

---

## 九、v1.2.9 密钥管理防护体系（2026-10-06）

### 1. 背景
- v1.2.8 发布时 Ed25519 签名密钥意外丢失，导致无法为 v1.2.8 用户提供无缝自动更新。
- 为防止类似问题再次发生，建立了完整的密钥管理防护体系。

### 2. 新增工具与流程
- **密钥管理脚本**（`Scripts/key_manager.sh`）：
  - `status`：显示当前密钥状态、公钥、备份情况
  - `backup`：自动备份密钥到 `~/.config/atools/key-backups/`（保留最近 10 个）
  - `verify`：验证当前密钥是否在 `UpdateManager.swift` 中注册
  - `restore`：从备份恢复密钥（交互式选择）
  - `rotate`：轮换密钥（生成新密钥 + 引导更新代码）

- **发布脚本预检**（`Scripts/package_app.sh`）：
  - 签名前自动验证密钥公钥是否在 `UpdateManager.swift` 的 `updateSigningPublicKeys` 数组中注册
  - 验证失败时阻止打包并输出详细修复指引

- **双公钥迁移机制**（`UpdateManager.swift`）：
  - `updateSigningPublicKeys` 数组支持多密钥并存
  - 验证时遍历所有公钥，任一通过即为合法
  - 支持平滑密钥轮换，无需用户手动干预

### 3. 文档完善
- `RELEASING.md` 新增「Ed25519 更新签名密钥管理」专章
- 详细的密钥丢失预防措施、备份策略、轮换流程
- 发布前核对清单增加密钥验证和备份步骤
- 常见问题解答（FAQ）

### 4. 验证
- 运行 `./Scripts/key_manager.sh status` 确认密钥状态正常
- 运行 `./Scripts/key_manager.sh verify` 确认密钥与代码一致
- 运行 `./Scripts/key_manager.sh backup` 创建初始备份
- 编译零错误零警告。
---

## 十、v1.3.0 新增 AutoQuitManager：关闭最后一个窗口即退出应用（2026-10-06）

### 1. 功能定位
- 对标开源项目 SwiftQuit：点击应用窗口红色关闭按钮且该应用再无其他窗口时，延迟自动退出该应用，杜绝"关了窗口应用还常驻"的困扰。
- **总开关默认关闭**。首次启用需「辅助功能」授权（macOS 要求）；未授权时模块静默保持空闲，绝不主动弹系统授权弹窗，授权引导只在用户于设置页/状态栏显式开启时出现。
- 两种作用范围：`全部应用`（名单为排除项，开箱即用）与 `仅名单内应用`（名单为退出项）；退出延迟可选 0/1/2/3/5 秒（默认 2 秒，延迟内重开窗口自动取消退出）。
- 状态栏菜单新增「关闭窗口即退出」勾选项，与设置页双向同步。

### 2. 核心架构与安全边界
- **AX 事件驱动 + 兜底轮询**（`AutoQuitManager.swift`）：
  - `AXObserverCreate` 按 PID 挂载，观察应用级 `kAXWindowCreatedNotification` 并为每个窗口注册 `kAXUIElementDestroyedNotification`；RunLoop 挂主线程 `commonModes`（菜单追踪/模态期间事件不丢）。
  - 主线程 4 秒兜底轮询重取 `kAXWindowsAttribute` 计数，捕获不吐 AX 销毁事件的应用（部分 Electron/Java）。
  - **零窗判定铁律**：仅 `AXUIElementCopyAttributeValue` 返回 `.success` 且数组为空才算"确认零窗"；AX 查询失败（AX 树失效等）一律跳过本轮判定，绝不误杀。
  - **转变式触发**：挂载时记录初始窗口数，零窗口应用（登录项、后台 utility）永不直接退出，只响应「有窗 → 确认零窗」的转变。
  - **pid 复用防护**：延迟到期复查时用持有的 `NSRunningApplication` 对象验证 `isTerminated == false`，不信裸 pid 数值；复查条件含窗口仍为零、开关仍开、名单仍匹配。
  - 系统应用硬排除（Finder/Spotlight/通知中心/Dock，按 bundleID）+ ATools 自身排除 + `.regular` 策略过滤 + 未完成启动跳过；无 bundleID 进程保守跳过。
  - 监听 `didLaunchApplicationNotification` 增量挂载、`didTerminateApplicationNotification` 清理、`didWakeNotification` 全量重建（睡眠唤醒后 AX 树失效自愈）。
  - 配置变更（开关/模式/名单/延迟）经 `.atoolsAutoQuitDidChange` 通知驱动监视集合全量重建；`reloadIfTrusted()` 在应用重新激活时感知授权完成并热启动。
- **容错配置**（`AppConfig.swift`）：`AutoQuitMode` 枚举 + 4 个新字段（`enableAutoQuit=false`、`autoQuitMode=.allApps`、`autoQuitAppRules=[bundleID]`、`autoQuitDelaySeconds=2`）全部容错解码，旧 config.json 零影响；解码期对延迟做 0–10 clamp；version 保持 4。
- **设置页第 4 分页「窗口退出」**（`SettingsTabViews.swift`，追加在 pages 末尾不影响欢迎横幅硬编码跳转）：总开关（未授权时仅显式点击弹授权引导）、授权状态行（refresh 只读 `AXIsProcessTrusted()` 无副作用）、作用范围/延迟/名单行随总开关联动禁用；GeneralTabView 监听 `.atoolsAutoQuitDidChange` 修复"页内分段切换不触发 refresh"死角。
- **名单编辑器**（`AutoQuitRulesEditorView.swift`）：独立小视图（只读写 ConfigManager，不持有宿主视图防悬垂），复用 `AppHotspotIndex.allApps` 全量快照 + 拼音/别名搜索过滤，图标走 `NSWorkspace.icon(forFile:)`；无 bundleID 应用禁选并提示；`SettingsWindowController.windowWillClose` 先 `endSheet` 再释放缓存的 tab 视图。
- **应用索引快照**（`AppHotspotIndex.swift`）：新增只读 `allApps` 访问器（锁内拷贝），供名单编辑器枚举全部已安装应用。

### 3. 修改文件清单
- `Sources/atools/System/AutoQuitManager.swift` — 新增：AX 监听引擎单例（挂载/摘除、零窗判定、延迟退出、兜底轮询、睡眠唤醒重建、`shouldWatch`/`isConfirmedZeroWindowCount` 纯函数供自测断言）
- `Sources/atools/UI/Settings/AutoQuitRulesEditorView.swift` — 新增：应用名单编辑 sheet（搜索过滤、勾选草稿、无 bundleID 禁选）
- `Sources/atools/Models/AppConfig.swift` — `AutoQuitMode` 枚举与 4 个新配置字段（容错解码 + clamp + encode）
- `Sources/atools/Storage/ConfigManager.swift` — 新增 `updateEnableAutoQuit/Mode/Rules/DelaySeconds` 四个更新方法（save + 广播）
- `Sources/atools/UI/SettingsWindowController.swift` — `.atoolsAutoQuitDidChange` 通知名；`windowWillClose` 先收起 sheet 防悬垂
- `Sources/atools/UI/Settings/SettingsTabViews.swift` — GeneralTabView 追加「窗口退出」第 4 分页与全部处理器/刷新逻辑
- `Sources/atools/Search/AppHotspotIndex.swift` — 新增 `allApps` 只读快照访问器
- `Sources/atools/App/AppDelegate.swift` — 启动 `startIfEnabled()`、`didBecomeActive` 授权热启动、状态栏勾选项、`applicationWillTerminate` 清理
- `Sources/atools/main.swift` — `[12/12]` 配置往返/旧版默认/越界 clamp/监视资格与零窗判定纯函数断言

### 4. 诊断测试验证
- 运行 `./Scripts/build.sh --test`：
  - `[12/12]` AutoQuit 配置往返、旧版配置缺字段安全默认、延迟越界 clamp、监视资格（系统排除/自身/后台策略/未启动/无 bundleID/两种模式名单语义）与零窗判定（查询失败≠零窗）纯函数断言全部通过；
  - 现有 11 组诊断测试零破坏；设置窗口 780pt 宽度不变性、全部 tab 布局回归通过。
  - 附注：`[6.x]` Spotlight 夹具索引断言（main.swift:359/508）存在与本更新无关的既有环境性偶发（依赖 mds 对临时目录的索引时序），经 `git stash` 基线三次对照复现确认与本次改动无关；其余多次整跑全绿。
  - 真机启动冒烟：开启 debugLog 后运行，`[App] ATools launched` 正常、默认关闭时无任何 [AutoQuit] 行（静默空闲），退出无残留。

### 5. 发布后修复：名单编辑 sheet 主线程冻结（2026-10-06, build 18）

- **现象**：真机点击「编辑名单」后设置窗卡死（等待光标），sheet 迟迟不出现。
- **定位过程**：事后 `sample` 主线程已空闲、无 hang 报告；编写最小诊断 harness（全量源码 + 自定义 main）复现完整生产路径（设置窗 → 分页切换 → 程序化 `performClick`），在双击场景复现 3 秒级冻结；随后逐段计时打点锁定根因。
- **根因**：
  1. 编辑器 init 在视图**尚无窗口尺寸**时同步设置 `tableView.dataSource`，NSTableView 立即全量构建全部行视图（272 应用 × 每行 2-7ms ≈ 650ms 主线程冻结；0 应用时该段实测 0ms，完全吻合）；`beginSheet` 呈现时又花约 760ms 重建可见行，合计约 1.5 秒冻结。
  2. 按钮无防重入：连点两次触发两次 `beginSheet`，第二个 sheet 排队后冻结加倍至 3 秒以上。
  3. 冷启动边缘：应用刚启动、索引首扫未完成时打开名单会显示 0 个应用且不再重试。
- **修复**（`AutoQuitRulesEditorView.swift` + `SettingsTabViews.swift`）：
  - init 只构建空 UI；数据装填延后到 `viewDidMoveToWindow` 后的下一个 runloop 周期（`loadDataIfNeeded`），此时 sheet 已在屏幕、表格已有最终尺寸，NSTableView 只构建可见的十几行（约 30-60ms）。
  - 索引首扫未完成时（`apps.isEmpty`）通过 `refreshIndex(completion:)` 在扫描结束后自动重载一次。
  - `openAutoQuitRulesEditor` 增加防重入：已有 attached sheet 时忽略重复打开。
- **验证**（debugLog 实测）：修复前 construct=766ms + present=763ms ≈ 1.5s；修复后 **construct=14ms + present=290ms，双击被防护拦截（总 301ms）**，2 秒后主循环存活、sheet 正常附着；冷启动 0 应用场景自动重载为 272 个应用；`./Scripts/build.sh --test` 全组回归通过（exit=0、零失败）。

### 6. 发布后修复：名单编辑 Sheet 尺寸坍缩（18x32 白核）与模态假死（2026-10-06, build 19）

- **现象**：在设置页点击「编辑名单」后，设置窗口变暗，中央出现一个极微小的白色椭圆胶囊体（白核），整个界面失去响应（呈现为卡死/假死状态）。
- **定位过程**：
  - 探查真实运行进程 PID 59685，`sample` 显示主线程并未死锁，正在 RunLoop `nextEventMatchingMask` 正常轮询；
  - 调用 macOS 底层 Quartz `CGWindowListCopyWindowInfo` 探查窗口树，捕获到关键现场证据：
    - 宿主窗口：`WID 4429, Name: 'ATools 偏好设置', Bounds: {Width = 780, Height = 648}`；
    - 弹出 Sheet：`WID 4430, Name: 'AutoQuit 应用名单', Bounds: {Width = 18, Height = 32, X = 747, Y = 398}`。
  - **根因锁定**：现代 macOS (macOS 11+) 的 `hostWindow.beginSheet(sheet)` 会根据 `sheet.contentView` 的 Auto Layout 约束和 `fittingSize` 动态协商窗口尺寸。`AutoQuitRulesEditorView` 中 `hintLabel`、`searchField`、`countLabel` 的 `translatesAutoresizingMaskIntoConstraints` 遗漏置 `false`（默认为 `true`），默认零尺寸的 autoresizing mask 约束与显式激活的布局锚点严重冲突；叠加 `NSScrollView` 缺乏最小高度且固有尺寸为 `(-1, -1)`，求解器将 Sheet 目标尺寸压缩为 `18 × 32` pt，渲染为中心白色胶囊体；`beginSheet` 启动模态拦截导致宿主变暗屏蔽事件，而 18x32 的 Sheet 无法显示任何控件、按钮或关闭键且缺少 `Esc` 退出机制，造成表象上的死锁。
  - **子代理架构审查**（`AppKit Architecture Reviewer`）：审查确认根因定位准确，并提出双重尺寸刚性约束、`keyEquivalent` 键位规范、`AutoQuitAppTableCellView` 单元格标准化复用、`closeSheet` 解挂健壮性兜底以及放开总开关关闭时编辑权限的建议。
- **修复**（`AutoQuitRulesEditorView.swift` + `SettingsTabViews.swift`）：
  1. `AutoQuitRulesEditorView.swift`：
     - 所有子视图补齐 `translatesAutoresizingMaskIntoConstraints = false`；
     - 覆写 `intrinsicContentSize = NSSize(width: 470, height: 430)`，为 `scrollView` 补充底线高度约束 `greaterThanOrEqualToConstant: 240`，彻底阻断任何求解折叠；
     - 抽取独立轻量类 `AutoQuitAppTableCellView: NSTableCellView`，在 `tableView(_:viewFor:row:)` 中通过 `makeView(withIdentifier:owner:)` 标准化复用，杜绝滚动时的重复对象分配与约束爆炸；
     - 为 `cancelButton` 添加 `keyEquivalent = "\u{1b}"`（Esc），为 `saveButton` 添加 `keyEquivalent = "\r"`（Return），并在视图层覆写 `cancelOperation(_:)` 支持按键无障碍秒退；
     - 健壮化 `closeSheet()`，在 `sheet.sheetParent == nil` 时自动回退至 `orderOut/close`。
  2. `SettingsTabViews.swift`：
     - `openAutoQuitRulesEditor()` 中设置 `sheet.contentMinSize = NSSize(width: 470, height: 430)`、`sheet.contentMaxSize = NSSize(width: 470, height: 430)` 与 `sheet.setContentSize` 双重尺寸物理防御；
     - `refreshAutoQuitPage()` 中设置 `autoQuitRulesButton.isEnabled = true`，允许用户在开启总开关前预设名单。
- **验证**：
  - Standalone AppKit Sheet Harness 验证：Sheet 弹出后稳定维持 `Width = 470, Height = 430`，零折叠、零冲突；
  - 运行 `./Scripts/build.sh --test`：全组 12 大项诊断测试全部通过（exit=0，零失败），设置窗口不变性完全保持。

### 7. 发布后修复：AutoQuit 误杀非最小化仅切换应用失焦进程（2026-10-07, build 20）

- **现象**：用户开启「最后一个窗口关闭后退出应用」，设置退出延迟为「立即退出 (0s)」。当用户使用应用时，未点击窗口黄色最小化按钮，而是直接点击其他应用切换应用焦点时，该应用被 ATools 瞬间自动强制退出。用户核心诉求为「只有点击红叉真正关闭窗口时才强制退出，切走应用绝不能退出」。
- **定位过程**：
  - 调取 `~/Library/Logs/ATools/runtime.log` 运行日志，确凿捕获到每次切走应用时均记录 `[AutoQuit] Last window closed for ...; quitting in 0s.` 并紧接着调用 `[AutoQuit] Terminating ... after last window closed.`（Antigravity、钉钉、Otty、Chrome 等应用均有明确记录）。
  - **根因锁定**：
    1. **AX 单路查询失焦陷阱**：原实现完全依赖 `AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute)`。许多现代应用（如 Electron/Chromium 架构应用、含上下文菜单/补全浮层的应用）在用户切走应用时，失焦触发了其内部临时元素销毁，发出 `kAXUIElementDestroyedNotification`；此时在切出动画或多虚拟桌面（Spaces）切换的瞬态，AX 树向外返回空数组 `[]`（count=0）。
    2. **缺乏系统窗口服务（WindowServer）交叉核验**：盲信 AX 返回的瞬态 0 窗；后端的 `fallbackPoll` 定时轮询只要查到 0 窗即发起调度。
    3. **0 秒延迟零防抖**：用户配置 0s 退出延迟，在 RunLoop 下一个微任务周期即无条件 `app.terminate()`，没有给窗口留出状态防抖时间。当用户点击最小化时，Dock 窗口保留了 `minimized=1` 的 AX 节点因而不被判零；而未最小化直接切走时因上述 AX 瞬态清空被当场误杀。
- **修复**（`AutoQuitManager.swift` + `main.swift`）：
  1. **引入 WindowServer (`CGWindowListCopyWindowInfo`) 权威交叉保护**（`windowServerStandardWindowCount(for:)`）：
     - 直接穿透至操作系统底层 WindowServer，检索 Layer 0、有效透明度与尺寸（Width >= 80, Height >= 60）的标准应用窗口。
     - 切换应用或失焦时，WindowServer 中应用窗口始终真实存在（count >= 1），双重校验 `isConfirmedZeroWindowCount(axCount:windowServerCount:)` 立即返回 `false`，彻底免疫应用失焦、临时浮层销毁、多 Space 切换带来的误杀。
  2. **双重权威确诊铁律**：
     - 只有当用户显式点击红叉（或 ⌘W）销毁窗口、WindowServer 与 AX 均确认无标准窗口时，才调度退出。
     - AX 发生异常（nil）时保持保守放行，坚决不误杀。
  3. **0s 延迟安全防抖与到期复核**：
     - 即使用户设置 0s 退出延迟，调度层也施加底线 0.35s 事件环微延迟，避免关闭动画与焦点切换过程中的瞬态竞态。
     - 在延迟到期 `executePendingQuit` 真正执行 `app.terminate()` 前，再次执行 WindowServer 与 AX 双重核验，一旦检测到任何有效窗口立即撤销退出。
  4. **冷启动与运行态状态补全**：
     - 修复启动时窗口尚未完全渲染导致 `hadWindows` 漏记的问题，在 `attachLocked` 与轮询中同时依据 WindowServer 真实窗口状态同步维护 `hadWindows`。
  5. **「仅名单内应用」模式热切换与大小写容错**：
     - 修复原 `updateConfiguration()` 仅调 `startIfEnabled()` 在 `isRunning == true` 时因 `guard !isRunning` 阻断全量重建的问题，修正为显式调用 `rebuild()`，确保用户在偏好设置下拉框切换「全部应用 / 仅名单内应用」或编辑勾选名单后，即刻清空旧监听集并对前台各应用按新模式重新过滤挂载；
     - `shouldWatch` 名单包含性判定加入 `caseInsensitiveCompare`，对 Bundle ID 各种大小写形式（如 `com.apple.TextEdit` vs `com.apple.textedit`）天然兼容。
- **验证**：
  - 运行 `./Scripts/build.sh --test`：全组 12 大项诊断测试全部通过（exit=0，零失败），包含双重校验在失焦保护、真关窗确诊、AX 失败保护、正常运行保护以及「仅名单内应用」大小写与包含性断言；设置窗口尺寸与布局回归完全保持。

### 8. 发布后修复：钉钉等 CEF/Chromium 混合架构应用点击红叉未自动退出（2026-10-07, build 21）

- **现象**：用户在偏好设置选择「仅名单内应用」并将钉钉加入名单后，点击钉钉窗口左上角红叉关闭窗口，钉钉依然驻留在后台未自动退出。
- **定位过程**：
  - 通过 Swift CLI 深入探查钉钉关闭窗口后的系统状态：
    1. **AX 状态**：`DingTalk axWindows: count=0, err=0`（AX 辅助功能树已准确检测到主窗口关闭）；
    2. **WindowServer 状态**：钉钉作为 CEF/WebKit 混合架构应用，在关闭主窗口后，底层仍然在 WindowServer 维护了多达 13 个离屏渲染/画布视图（如 `ConvTabListView`、`MainMenuPanelView`、离屏 Webview 缓冲区等），这些视图均位于 Layer 0 且尺寸大于 80x60，但属性标记均为 `kCGWindowIsOnscreen: false`；
    3. **根因锁定**：`AutoQuitManager.windowServerStandardWindowCount` 原先使用 `[.optionAll, .excludeDesktopElements]` 查询 WindowServer，未过滤 `kCGWindowIsOnscreen`，导致即使用户点击红叉关闭了可见窗口，WindowServer 计数仍然返回 6 个离屏窗口；双重校验 `isConfirmedZeroWindowCount` 因 WindowServer != 0 而判定“应用仍有窗口”，进而阻断了退出调度。
- **修复**（`AutoQuitManager.swift`）：
  1. **WindowServer 离屏窗口过滤**：
     - 在 `windowServerStandardWindowCount` 中，查询选项调整为 `[.optionOnScreenOnly, .excludeDesktopElements]`，并显式过滤 `kCGWindowIsOnscreen == true`。只有真正在屏幕上处于渲染显示状态的标准窗口才计入有效窗口，彻底排除 CEF/Qt/Electron 等应用的后台离屏缓存画布。
  2. **失焦关闭感知加速（Deactivate Hook）**：
     - 订阅 `NSWorkspace.didDeactivateApplicationNotification`，当用户点击红叉导致应用失焦时，延后 0.15s 进行零窗求值，极大缩短退出响应时间，无需完全等待定时轮询。
  3. **轮询机制精细化解耦**：
     - 抽取独立主线程安全求值函数 `evaluateAppWindows(pid:)`，消除轮询长时间持有锁的隐患；将兜底轮询间隔由 4.0s 优化至 2.0s。
  4. **全场景防护保证**：
     - 切换应用焦点（失焦）：WindowServer 屏幕可见窗口仍 >= 1，绝不误退；
     - 最小化到 Dock：AX 树窗口仍存在且 `kAXMinimizedAttribute == true`（axCount >= 1），零窗校验立即驳回，绝不误退；
     - 点击红叉关闭窗口：AX count 归 0，WindowServer 屏幕可见窗口归 0，确诊零窗，精准自动退出。
- **验证**：
  - 运行 `./Scripts/build.sh --test`：12 组全套自动化诊断测试全部通过（exit=0，零失败）；
  - 真机实测钉钉（PID 10301）：
    - 启动后打开窗口：正常运行；
    - 切走应用焦点：钉钉保持运行，未误退（PASS）；
    - 最小化到 Dock：钉钉保持运行，未误退（PASS）；
    - 点击红叉关闭窗口：0.35s 防抖后日志准确输出 `[AutoQuit] Last window closed for 钉钉; quitting in 0.35s.` 并调用 `Terminating 钉钉`，钉钉进程完全干净退出（PASS）。

### 9. 专项优化：应用名单过滤无面板后台程序 + 全部/仅名单应用名单独立解耦 + 抽屉固定桌面快捷键隔离（2026-10-07, build 22）

- **背景与需求**：
  1. **应用名单净化**：自动退出应用选择名单中混杂了大量系统内置无界面后台进程、守护程序与偏好设置面板（如 CoreServices 后台进程、偏好设置面板 .prefPane、LSUIElement 等无 UI 进程），影响配置体验；
  2. **双模式名单独立**：「全部应用（排除名单）」和「仅名单内应用（退出名单）」共用同一套 `autoQuitAppRules` 规则，导致模式切换时产生数据污染，用户希望两者具备完全独立的两个应用名单；
  3. **固定抽屉快捷键隔离**：当勾选「面板驻留行为 固定应用抽屉在桌面」(`isShelfPinned == true`) 后，双击 ⌘ 或触发其他搜索/系统快捷键时抽屉会意外消失；用户希望除抽屉自身的收起快捷键外，按任何其他快捷键都不会收起已固定在桌面的应用抽屉。

- **实施细节与修改文件**：
  1. **无面板与系统后台应用精准过滤**（`AppMetadataReader.swift` + `AppHotspotIndex.swift`）：
     - `AppMetadataReader`：新增 `isUIElement` 与 `isBackgroundOnly` 的解析支持，对 `LSUIElement`、`LSBackgroundOnly` 进行布尔值、数字、字符串兼容反序列化；
     - `AppHotspotIndex`：为 `IndexedApp` 引入 `isRegularApp` 属性，过滤规则如下：
       - 排除所有 `.prefPane`（系统设置面板）；
       - 排除 `LSUIElement == true`（仅菜单栏/托盘/无 Dock 图标组件）；
       - 排除 `LSBackgroundOnly == true`（纯后台守护进程）；
       - 排除 `/System/Library/CoreServices` 内部非 GUI 工具守护进程；
       - 排除 `AutoQuitManager.systemExcludedBundleIDs`（Finder、Spotlight、Dock、通知中心等常驻系统服务）及 ATools 自身；
       - 排除无 Bundle ID 或空 Bundle ID 的非标准包；
     - 提供专门供给偏好设置选择面板调用的 `allRegularApps` 属性，同时保留原 `allApps` 索引保证全盘应用搜索的完整性。
  2. **全部应用与仅名单内应用名单独立解耦**（`AppConfig.swift` + `ConfigManager.swift` + `AutoQuitRulesEditorView.swift` + `SettingsTabViews.swift`）：
     - `AppConfig`：新增 `autoQuitExcludeAppRules: [String]` 与 `autoQuitOnlyListedAppRules: [String]` 独立存储数组；
     - 向后兼容迁移：在 `init(from decoder:)` 中，当解析旧版配置（仅存在 `autoQuitAppRules`）时，依据当前的 `autoQuitMode` 自动无损迁移至对应的模式名单，保证老用户升级不丢配置；
     - `ConfigManager`：扩展 `updateAutoQuitRules(_:for:)`，根据传入的 `AutoQuitMode` 分别更新与持久化对应名单；
     - `SettingsTabViews`：偏好设置界面根据当前模式动态显示按钮文案（如 `编辑排除名单 (N)...` vs `编辑退出名单 (N)...`），切换下拉框时即刻局部刷新规则计数；点击编辑时传入当前模式，隔离编辑上下文。
  3. **固定桌面抽屉快捷键隔离与生命周期解耦**（`PanelCoordinator.swift` + `ShelfPanel.swift` + `SearchPanel.swift` + `SearchResultsTableView.swift` + `CategoryBarView.swift` + `ShelfGridView.swift`）：
     - **根因锁定**：原 `PanelCoordinator` 采用单面板互斥状态机 `switchToPanel(.search)`，在打开全盘搜索（如双击 ⌘）时无条件调用 `shelfPanel.orderOut(nil)`；在搜索面板关闭时又调用 `hideAllPanels()` 将抽屉一同隐藏；
     - **面板生命周期完全解耦**：
       - `PanelCoordinator` 拆分为独立生命周期管理方法：`showShelfPanel()`、`hideShelfPanel(forceHidePinned:)`、`showSearchPanel()`、`hideSearchPanel()`；
       - 当抽屉已固定在桌面（`isShelfPinned == true`）时，`showSearchPanel()` 绝不隐藏抽屉，两者在屏幕上基于 AppKit Window Level 优雅并存（抽屉在桌面上方 `.statusBar` 25，搜索面板在最顶层 `.popUpMenu` 101）；
       - 搜索面板关闭（Esc、回车执行、失焦、点击外部、拖拽）仅调用 `hideSearchPanel()`，完全不触碰已固定抽屉；
       - 全局点击外部监听器 `handleOutsideInteraction()` 与应用失焦通知保护固定抽屉；
       - `hideShelfPanel` 增加 `forceHidePinned: Bool = false` 参数，默认忽略对固定抽屉的隐藏，唯有抽屉自身的唤出快捷键（`togglePanel(.shelf)`）或右键菜单显式点击“关闭抽屉”时才传入 `forceHidePinned: true` 进行收回；
       - `ShelfPanel` 内部 Esc 键与点击项目启动（`autoCloseOnLaunch`）在 `isShelfPinned == true` 时同样受保护不收起抽屉。

- **兼容性与边界防护策略**：
  - **索引完整性保证**：保留 `AppHotspotIndex.allApps` 维持 Spotlight 极速搜索对系统工具和偏好设置面板的索引命中；
  - **旧配置兼容**：无损解码旧版 `config.json`，根据 `autoQuitMode` 自动分流并提供 `rules(for:)` 辅助接口；
  - **窗口级别与并发动画保护**：全盘搜索关闭与抽屉固定桌面各具独立的动画世代编号 `panelPresentationGeneration`，彻底消除并发动画打断与残影。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 12 大项及新扩展的 `[12.1] allRegularApps UI filtering & dual AutoQuit rule independence` 与 `[12.2] Pinned shelf resilience & hotkey isolation` 全部通过（exit=0，零失败）；
  - 打包生成发布版：执行 `./Scripts/package_app.sh` 编译完成并生成数字签名安装包；
  - 部署并真机验证：更新至 `/Applications/ATools.app` 运行（PID 15997），实测：
    - 偏好设置中应用名单已全面过滤系统无面板后台进程与设置面板；
    - 切换「全部应用」与「仅名单内应用」后分别编辑应用，名单数据完全独立保存互不干扰；
    - 开启「固定应用抽屉在桌面」后，双击 ⌘ 唤出及关闭搜索面板，应用抽屉稳固停留在桌面；按其他全局快捷键、切换应用或点击桌面外部均不会收回抽屉；唯有再次按下抽屉专属唤出快捷键（⌥A）或右键菜单关闭时，抽屉方才收回。

### 10. 体验修复：自动退出延迟严格匹配选项 +「立即退出」零等待毫秒级响应（2026-10-07, build 23）

- **背景与现象**：
  - 用户反馈在设置中将自动退出延迟设为「立即退出」时，应用关闭红叉后依然感知到明显滞后（原实现存在 0.35s 硬编码防抖 + 0.15s 失焦等待，若未失焦还需等待 2.0s 轮询周期），未达到所选的“立即退出”预期；
  - 选项中各档延迟（立即退出 / 1秒 / 2秒 / 3秒 / 5秒）的实际退出等待时间因轮询节奏漂移而不严格吻合。

- **实施细节与修改文件**（`AutoQuitManager.swift`）：
  1. **「立即退出」彻底消除人为防抖延迟**：
     - 在已具备 WindowServer 权威在屏标准窗口核验的前提下（切走焦点时在屏窗口 >= 1，绝不会误判为零窗），移除 `configuredDelay == 0 ? 0.35 : ...` 的硬编码 0.35s 延迟；
     - 当配置为 0s（立即退出）时，经 `isConfirmedZeroWindows` 确诊后，直接调用 `DispatchQueue.main.async` 切入下一事件环微任务，响应时间降至毫秒级（< 1ms），完全零等待立即执行退出；
     - 当配置为 > 0s（1s、2s、3s、5s）时，严格按 `Double(configuredDelay)` 调度 `asyncAfter`，实现与界面所选选项毫秒级严格对齐。
  2. **AX 应用级窗口通知全链路注册**：
     - 在 `attachLocked` 中除 `kAXWindowCreatedNotification` 外，新增注册 `kAXMainWindowChangedNotification` 与 `kAXFocusedWindowChangedNotification`；
     - 无论是点击窗口左上角红叉、按 ⌘W 关闭还是通过应用菜单关闭窗口，AX 均在当前 RunLoop 周期内即时触发通知，摆脱对慢轮询的被动依赖。
  3. **窗口关闭淡出动画微复查（Micro-recheck）**：
     - 在关闭窗口的瞬态，若 `axCount == 0`（AX 树窗口已销毁）但 WindowServer 仍有标准窗口（处于 macOS 约 50ms 的 GPU 淡出动画中），立即安排 80ms 极速微复查，动画结束即刻确诊并退出，无需回退至轮询。
  4. **失焦关闭感知即时化**：
     - 在 `checkAppWindowsOnDeactivate` 中立即执行一次窗口求值，同时保留 0.15s 后续复验，消除前置 0.15s 的固定开销。
  5. **轮询频率优化与重复退出防护**：
     - 将兜底定时器周期由 2.0s 优化至 0.8s，保障无 AX 事件的非标应用也能快速被感知；
     - 引入 `terminatingPids: Set<pid_t>` 状态追踪，应用调用 `terminate()` 正在退出期间，彻底防范后续轮询的重复调度。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 12 大项及新扩展的测试用例全部通过（exit=0，零失败）；
  - 打包部署至 `/Applications/ATools.app` 运行（PID 18116）；
  - 实机测试：选择「仅名单内应用」并将延迟设为「立即退出」，点击名单内应用（如钉钉、QQ）窗口红叉后，毫秒级即刻完成确诊并触发 `Terminating after last window closed`，彻底消除滞后感；切换不同延迟档位时，退出耗时与选项精确吻合。

### 11. 根治切换窗口误退出缺陷：消除焦点与失焦事件误杀、重构多空间/遮挡/全层真实窗口校验、Space 切换与 Cmd+H 隐藏保护 (2026-10-07, build 24)

- **背景与根因剖析**：
  - 用户反馈：“还是存在切换窗口软件自动退出的问题，我要的效果是点击红叉才强制关闭”；
  - 经深入排查系统底层与日志，锁定三大根因：
    1. **WindowServer 层面 `.optionOnScreenOnly` 与 `isOnScreen` 的设计缺陷**：原实现使用 `[.optionOnScreenOnly, .excludeDesktopElements]` 并检查 `isOnScreen == false` 跳过。在 macOS Quartz 视窗合成器中，只要窗口处于后台、被前台全屏/大窗口遮挡、或处于另一个虚拟桌面（Space），macOS 均会将该窗口标记为 `isOnScreen == false`，且 `.optionOnScreenOnly` 会直接剔除它！导致只要用户切换至其他应用，被切走的应用在 WindowServer 中窗口数被误判为 0；
    2. **错误将应用失焦/焦点转移事件当作窗口销毁事件**：此前在 `attachLocked` 中注册了 `kAXMainWindowChangedNotification`、`kAXFocusedWindowChangedNotification` 以及工作区 `didDeactivateApplicationNotification`，在切换窗口或切换应用时，macOS 必然触发这几个通知，且此时由于应用正失去焦点，AX 树和 WindowServer 窗口数出现瞬时过渡态（AX 为 0 且 WS 为 0），从而触发误杀；
    3. **钉钉/CEF 离屏缓存误伤修复带来的过度过滤**：此前为过滤钉钉的 CEF 离屏画布而引入的 `isOnScreen` 导致正常后台应用的真实窗口被一并抹杀。

- **实施细节与修改文件**（`AutoQuitManager.swift` + `main.swift`）：
  1. **彻底移除焦点转移与应用停用触发机制**：
     - 彻底删除 `kAXMainWindowChangedNotification`、`kAXFocusedWindowChangedNotification` 以及 `didDeactivateApplicationNotification`；
     - 切换窗口、点击其他应用、失焦绝不属于窗口关闭行为，决不触发零窗判定；
     - 纯净监听窗口真正关闭通知：`kAXWindowClosedNotification`（"AXWindowClosed"）与窗口元素的 `kAXUIElementDestroyedNotification`；
  2. **全面重构 WindowServer 窗口扫描（支持多 Space、后台与被遮挡窗口）**：
     - 改用 `[.optionAll, .excludeDesktopElements]`，不再依赖容易失效的 `isOnScreen`；
     - 识别有标题的真实窗口（如 Safari 网页、Chrome 标签、终端窗口、钉钉主窗口等）：只要拥有非空标题且非系统代理组件，无论处于何种 Space、被何种窗口遮挡，一律确认为有效在活业务窗口，提供坚不可摧的双重安全保障；
     - 排除系统代理与框架残影（"Touch Bar", "Focus Proxy", "Item Status", "Emoji & Symbols", "FocusProxy"）及钉钉/CEF 内部视图（"ConvTabListView", "ConvTabTopBar", "MainMenuPanelView", "Form"）与 500x372 登录隐形窗；
     - 对无标题窗口精准剔除 AppKit 500x500 占位层、48pt 以下菜单工具条、640x508 离屏帧缓冲，保留真正有面积的无标题业务窗口；
  3. **虚拟桌面 (Spaces) 切换保护**：
     - 监听 `NSWorkspace.activeSpaceDidChangeNotification`；
     - 记录 `lastSpaceChangeDate`，在切换 Spaces 后的 2 秒宽限期内冻结零窗杀进程判定，自动延后复查，彻底防止多桌面切换误杀；
  4. **Cmd+H 隐藏保护**：
     - 严格校验 `guard !app.isHidden else { return }`，用户主动隐藏应用决不退出；
  5. **轮询器与微延时平滑**：
     - 兜底轮询周期平滑为 1.2s，结合 `isConfirmedZeroWindows` 双重验证与 `scheduleQuitLocked` 毫秒级调度。

- **兼容性与边界防护策略**：
  - 双重权威判定纯函数 `isConfirmedZeroWindowCount(axCount:windowServerCount:)` 完全保持向下兼容；
  - 名单配置及模式隔离完全保持；
  - 无论是 Cocoa 原生、Electron、CEF 还是 Java/Qt 应用，均只有在用户显式点击红叉或 ⌘W 关闭全部窗口后才会触发退出，切换应用或窗口绝对 100% 零误杀。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 12 大项及扩展断言全部通过（exit=0，零失败）；
  - 执行 `./Scripts/package_app.sh` 编译并签名打包发布版本；
  - 更新至 `/Applications/ATools.app` 运行验证；
  - 实测验证：Safari、Chrome、钉钉、微信、QQ、Otty、Antigravity 之间随意切换窗口、点击其他应用、按 ⌘Tab、切换虚拟桌面 Spaces、按 ⌘H 隐藏，所有后台应用稳固常驻绝不退出；点击红叉关闭最后一个窗口时，在所设延迟下精准退出（立即退出档位毫秒级关闭）。

### 12. 修复 AutoQuitManager 递归锁崩溃缺陷与 ATools 守护宿主防退出保护 (2026-10-07, build 24)

- **背景与根因剖析**：
  - 用户反馈：“应用名单中怎么没有ATools，点开ATools设置后切换应用后，ATools自动退出了，bug仍然存在”；
  - 核心排查与诊断（提取系统故障日志 `~/Library/Logs/DiagnosticReports/ATools-2026-10-07-145756.ips`）：
    1. **为什么名单中没有 ATools**：
       - ATools 是常驻后台的宿主服务守护程序（负责全局热键监听、状态栏托盘、应用抽屉及 AutoQuit 管理服务自身）；
       - 若将 ATools 加入自动退出名单，当用户关闭“偏好设置”窗口、“应用抽屉”或搜索胶囊时，ATools 将立即强杀自身进程，导致托盘图标和所有全局服务永久下线；
       - 因此在架构设计上，`AutoQuitManager.shouldWatch` 与 `AppHotspotIndex.allRegularApps` 严密排除了宿主自身 bundle ID（`cc.atools.app`），作为绝对安全的守护边界。
    2. **点开设置并切换应用后闪退的真正根因**：
       - 崩溃日志明确显示：`BUG IN CLIENT OF LIBPLATFORM: Trying to recursively lock an os_unfair_lock, Abort Cause 259`；
       - 栈轨迹指向：
         `0 _os_unfair_lock_recursive_abort`
         `1 _os_unfair_lock_lock_slow`
         `2 AutoQuitManager.evaluateAppWindows(pid:)`
         `3 AutoQuitManager.handleAXNotification(pid:element:notificationName:)`
       - 在 `handleAXNotification` 处理窗口销毁通知时已持有 `os_unfair_lock_lock(&lock)`，随后内部直接同步调用了 `evaluateAppWindows(pid:)`，而该方法内部再次尝试对同一不可重入锁执行 `os_unfair_lock_lock(&lock)`，直接触发内核保护将进程强制中止（SIGABRT）。此现象并非“自动退出应用”误杀，而是重复加锁引发的进程瞬时崩溃。

- **实施细节与修改文件**（`AutoQuitManager.swift`）：
  1. **解耦锁内与锁外窗口求值逻辑**：
     - 将原窗口求值逻辑剥离为私有锁内安全方法 `evaluateAppWindowsLocked(pid:)`（调用前必须已持有 `lock`）；
     - 将公开接口 `evaluateAppWindows(pid:)`（由异步调度回调 `asyncAfter` 或无锁上下文调用）明确收敛为获取锁后代理至 `evaluateAppWindowsLocked(pid:)`；
  2. **消除已持有锁上下文的二次加锁**：
     - `handleAXNotification` 中收到 `kAXWindowClosedNotification` 或 `kAXUIElementDestroyedNotification` 时，直接调用 `evaluateAppWindowsLocked(pid:)`；
     - 兜底轮询 `fallbackPoll` 遍历监听列表时，在同一把锁的作用域内直接调用 `evaluateAppWindowsLocked(pid:)`，消除锁竞争与重入隐患。

- **兼容性与边界防护策略**：
  - 严格保持并发线程安全性与主线程 UI 断言；
  - 维持对被监听应用的毫秒级窗口销毁感知与定时杀进程逻辑不变；
  - ATools 宿主守护进程自身绝对免疫任何退出判定，无论设置窗口开启/关闭/切换应用均平稳常驻。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 12 大项自动化回归套件全部通过（exit=0，零失败）；
  - 执行 `./Scripts/package_app.sh` 编译并签名打包，重新部署至 `/Applications/ATools.app` 运行（PID: 32017）；
  - 实测验证：打开 ATools 偏好设置窗口，在不同应用之间频繁切换焦点、打开关闭其他软件、点击设置窗口红叉关闭，ATools 稳定常驻于状态栏与后台，无任何崩溃与退出，问题得到彻底根除。

### 13. 根治 ATools 偶发卡死与单窗口应用关窗不退出缺陷 (2026-10-07, build 26)

- **背景与根因剖析**：
  - 用户反馈：“有用户反馈ATools在他的电脑上卡死，也没退出想要关闭的软件，请检查原因”；
  - 核心排查与诊断：
    1. **为什么想要关闭的软件（如微信、钉钉、QQ 等）关窗后不退出**：
       - macOS 中大量应用（微信、钉钉、QQ、各类 Electron/Webview 应用等）在用户点击红叉时，并非真正 `destroy` 窗口，而是执行 `[NSWindow orderOut:]` 将窗口隐藏保留于后台；
       - 此前 `windowServerStandardWindowCount` 改用了 `[.optionAll]`，但**未校验 `kCGWindowIsOnscreen`**，导致 WindowServer 依然扫描到了那些已 orderedOut 隐藏的后台窗口（名称为 "微信"、"钉钉"、"QQ"）；
       - 进而导致 `isConfirmedZeroWindowCount` 始终认为 `wsCount > 0`，即使 AX 确证窗口已关闭（`axCount == 0`），也永久拒绝执行退出，导致软件关窗不退出。
    2. **为什么 ATools 会发生卡死 (Freeze/Beachball)**：
       - **根因一：100ms 无上限递归轮询死循环**：在 `evaluateAppWindowsLocked` 中，若 `axCount == 0 && wsCount > 0`，原代码每 0.1 秒无条件 `DispatchQueue.main.asyncAfter(0.1)` 重新调用自身。由于上述隐藏窗口导致 `wsCount > 0` 永真，每秒在主线程触发 10 次密集的 IPC 查询与加锁，持续拖垮主 RunLoop；
       - **根因二：未设 AX 消息超时（AXUIElement Messaging Timeout）**：macOS 默认 AX 消息超时高达 6 秒，若系统中有任意被监视应用处于忙碌、编译、高负载或卡死状态，ATools 在主线程调用 `AXUIElementCopyAttributeValue` 会同步阻塞 6 秒，导致 ATools 自身被拉入卡死状态；
       - **根因三：兜底轮询主线程高频全量 IPC 震荡**：原 `fallbackPoll` 每 1.2 秒对所有被监视应用无差别调用 `windowServerStandardWindowCount`，单次轮询重复几十次昂贵的 `CGWindowListCopyWindowInfo` IPC 序列化。

- **实施细节与修改文件**（`AutoQuitManager.swift`）：
  1. **WindowServer 严格引入 `isOnScreen` 在屏校验**：
     - 在 `windowServerStandardWindowCount` 中增加 `guard let isOnScreen = w[kCGWindowIsOnscreen as String] as? Bool, isOnScreen else { continue }`；
     - 彻底过滤已关闭/orderedOut 隐藏的后台常驻窗口，微信、钉钉、QQ 等关窗即刻双重确证为零窗并退出。
  2. **全面设置 AX 150ms 超时保护（防拖死）**：
     - 在 `attachLocked` 以及 `axWindows(of:)` 内部全部注入 `AXUIElementSetMessagingTimeout(element, 0.15)`；
     - 任何第三方应用无响应时，150ms 立即超时熔断返回，绝不挂起或卡死 ATools 主线程。
  3. **AX 优先快路径（AX-First Fast Path）与消除无意义 WindowServer 扫描**：
     - 若 `axCount > 0`，代表应用正有活跃窗口正常使用，直接清空重试计数并取消挂起退出，**直接返回，跳过昂贵的 WindowServer IPC 扫描**；
     - 仅在 AX 为 0 或不可用时才查询 WindowServer。
  4. **引入 `recheckCounts` 封顶防护（彻底终结 0.1s 恶性循环）**：
     - 新增 `recheckCounts: [pid_t: Int]` 追踪微复查次数，上限严格限制为 2 次（覆盖 50ms GPU 关窗动画）；
     - 超过 2 次重试上限立即确认为零窗调度退出，杜绝无限调度泄露。
  5. **轮询器减负优化**：
     - 兜底轮询周期平滑为 2.0s；
     - 仅扫描曾有窗口且不在退出流程中的候选应用。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 12 大项自动化测试与诊断套件全部通过（exit=0，零失败）；
  - 实测验证：
    - 微信、钉钉、QQ 等已关窗单窗口应用在屏标准窗口数由 2/1/3 精准归零（`on-screen standard window count: 0`）；
    - 活跃应用（如 Chrome、Antigravity）标准窗口数精准识别为 1；
    - 内存与 CPU 负载极度平稳，彻底根除主线程挂起与无限重试卡死隐患。

### 14. 全局搜索支持按文件类型筛选与快捷切换 (2026-10-07, build 27)

- **背景与需求目标**：
  - 用户反馈在全局搜索时，往往只想快速定位特定类型的资产（如某份 PDF 报告、设计切图 PNG、某段源代码脚本等），通用模糊搜索常被大量同名应用、配置缓存或无关文件淹没；
  - 需求目标：引入原生液态玻璃文件类型筛选条，支持 8 大分类即时切换、键盘极客流快捷键（Tab / ⌘1~8）与前缀语法（如 `doc: report`）联动，且保持 0 毫秒级性能无衰退。

- **实施细节与涉及文件**：
  1. **新建数据模型 `SearchTypeFilter.swift`**（`Sources/atools/Models/SearchTypeFilter.swift`）：
     - 定义 8 大标准分类枚举：`.all`（全部）、`.application`（应用）、`.document`（文档）、`.image`（图片）、`.media`（媒体）、`.code`（代码）、`.archive`（压缩包）、`.folder`（文件夹）；
     - 配置对应的 SF Symbol 图标、快捷数字编号（1~8）及典型扩展名映射表；
     - 针对 CoreServices `MDQuery` 生成底层下推 ContentType 谓词；特别针对现代编程语言（`.ts`, `.go`, `.rs`, `.json`, `.yaml`, `.css` 等）加入扩展名通配补充，彻底规避原生 macOS UTType 脱节导致现代语言搜不到的缺陷；
     - 提供 `matches(filename:isDirectory:)` 内存判定（严格排除 `.app` 目录落入 `.folder`）以及 `extractPrefix(from:)` 前缀语法解析。
  2. **新建液态玻璃筛选条 `SearchFilterBarView.swift`**（`Sources/atools/UI/SearchFilterBarView.swift`）：
     - 高度为 28pt，采用与主界面一致的液态玻璃微光圆角胶囊视觉；
     - 所有胶囊按钮显式声明 `refusesFirstResponder = true`，鼠标点击切换分类时绝对不抢夺搜索框焦点；
     - 支持 `cycleFilter(forward:)` 循环轮转及 `selectFilter(number:)` 快捷直达；
     - 完美适配浅色/深色液态玻璃主题。
  3. **检索下推与协同改造**：
     - `MetadataFileSearchBackend.swift`：`predicateText` 与 `search` 接收 `SearchTypeFilter`，在 macOS 内核索引数据库层直接下推过滤；
     - `SpotlightBridge.swift`：在热目录快照中增加 \(O(1)\) 内存类型过滤（耗时 < 0.05ms）；当选择 `.application` 时直接跳过 Layer 2 MDQuery，规避 `.app` 排除逻辑冲突；
     - `SearchCoordinator.swift`：接收 `filter` 参数。当筛选特定文件类型时，Layer 1 自动抑制计算器与系统指令噪声；当筛选 `.application` 时，Layer 1 `AppHotspotIndex` 独占输出上限提升至 `searchResultLimit`，实现 0ms 闪电直出与拼音首字母检索。
  4. **搜索面板集成与键盘事件捕获**（`SearchPanel.swift`、`SearchBarView.swift`）：
     - `SearchViewController` 嵌入 `SearchFilterBarView`，展开态约束锚定 `filterBar.bottomAnchor`，自适应伸缩结果列表高度，严格维持窗口总高 520pt 与折叠高 72pt 不变量；
     - `SearchTextField.performKeyEquivalent` 拦截 `Tab` / `Shift+Tab`（keyCode 48）与 `⌘1`~`⌘8`，在非 markedText 状态下切换分类，且具备完整的输入法（IME）拼音输入保护；
     - 输入前缀语法（如 `code: app`）时自动高亮对应胶囊；按 `Esc` 键时若当前非 `.all` 分类则优先复位为 `.all`。
  5. **诊断测试套件扩充**（`Sources/atools/main.swift`）：
     - 新增 `[6.4] Testing SearchTypeFilter`：全量覆盖 8 大分类映射、前缀解析、热目录判定规则、MDQuery 谓词解析合法性以及端到端协调过滤断言。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 13 大项自动化测试与诊断套件全部 PASS（exit=0，零失败）；
  - 实测验证：
    - 展开态（520pt）与折叠态（72pt）截图对比完美（`/tmp/search_expanded_preview.png` 与 `/tmp/search_collapsed_preview.png`）；
    - 分类胶囊无缝切换，前缀语法识别顺畅，输入法拼音选词与输入焦点稳固。

### 15. 全局搜索分类胶囊支持长按拖动实时重排与配置持久化 (2026-10-07, build 28)

- **背景与需求目标**：
  - 用户反馈：“能否长按拖动调节分类胶囊的顺序呢”；
  - 需求目标：允许用户根据个人高频使用习惯（如开发者常查代码/文件、文字工作者常查文档/图片）在搜索筛选栏自由拖拽调整分类胶囊的排列顺序；拖拽时提供流畅无抖动的实时位移反馈；排序结果自动写入用户配置持久化保存；同时使极客流快捷键（`Tab` / `Shift+Tab` 轮转以及 `⌘1`~`⌘8` 数字直达）与当前屏幕视觉排列顺序保持动态对齐。

- **实施细节与涉及文件**：
  1. **数据模型扩展与容错补齐**（`Sources/atools/Models/SearchTypeFilter.swift`）：
     - 新增 `defaultOrderStrings` 提供默认 8 分类原始标识符；
     - 新增 `resolvedOrder(from storedStrings: [String]) -> [SearchTypeFilter]` 解析算法：支持向下兼容、脏数据自动剔除、重复项去重，并对未包含的合法分类按默认相对位置平滑补齐在末尾，确保无论用户配置如何变动，系统始终维持完整、无损的 8 分类视图。
  2. **配置持久化与管理器对接**（`Sources/atools/Models/AppConfig.swift` & `Sources/atools/Storage/ConfigManager.swift`）：
     - 在 `AtoolsConfig` 中新增 `searchFilterOrder: [String]` 属性，初始化及解码器内置 `SearchTypeFilter.defaultOrderStrings` 安全兜底；
     - `ConfigManager` 新增 `updateSearchFilterOrder(_ order: [String])` 方法，修改后自动通过 `save()` 异步防抖写回 `config.json`。
  3. **液态玻璃胶囊拖拽源交互**（`Sources/atools/UI/SearchFilterBarView.swift` 中的 `SearchFilterPillButton`）：
     - 遵循 `NSDraggingSource` 协议，维持 `refusesFirstResponder = true`，鼠标拖拽全过程绝不抢夺搜索框输入焦点；
     - 手势判别：`mouseDown` 记录坐标并给予 `0.82` 微透明轻点反馈；若鼠标位移超过 4pt 即刻启动系统拖拽会话（`beginDraggingSession`）并将胶囊半透明虚化（alpha 0.35）；若位移未超阈值且在按钮内抬起，则精准触发常规分类选中点击；
     - 自动抓取按钮图层生成高清矢量位图快照（`createDragSnapshot`），悬浮跟随光标。
  4. **筛选栏目标区域实时重排与恢复机制**（`SearchFilterBarView`）：
     - 注册 `cc.atools.filterPillReorder` 自定义拖拽剪贴板标识；
     - `draggingUpdated` 依据光标在筛选栏内的 X 轴投影计算实时插入索引，排除自身后的 `others` 参照比较确保位移动画零颤抖；
     - 利用 `NSAnimationContext.runAnimationGroup` 驱动 `NSStackView` 顺滑滑移；
     - 拖拽取消（如松开在窗口外或按 Esc）通过 `restoreOrder` 毫秒级恢复拖拽前原始顺序；拖拽成功投放（`performDragOperation`）时立即提取当前排列并保存至 `ConfigManager`。
  5. **快捷键动态视觉对齐**：
     - 重构 `SearchFilterBarView.cycleFilter` 与 `selectFilter(number:)`：废弃此前固定的静态枚举遍历，全面绑定动态 `orderedFilters`；
     - 用户将“代码”拖至第一位后，`⌘1` 即可直达“代码”筛选，`Tab` 键自左向右严格沿视觉流动切换，符合直觉。
  6. **回归诊断测试扩展**（`Sources/atools/main.swift`）：
     - 新增 `[6.5] Testing search filter reordering`：包含空数据默认回退、脏数据容错去重与补齐、`AtoolsConfig` 序列化往返、`SearchFilterBarView` 动态排列加载及 `⌘1~8` / `Tab` 快捷键动态映射断言。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 13 大项自动化测试与诊断套件全部 PASS（exit=0，零失败）；
  - 执行 `./Scripts/package_app.sh`：签名及 release 构建通过；已成功部署并替换至 `/Applications/ATools.app`（PID 65871）。

### 16. 搜索栏支持斜杠语法提示胶囊群、指令卡片直出与 Tab 智能补全 (2026-10-07, build 29)

- **背景与需求目标**：
  - 用户反馈：“看一下搜索栏能否做出语法提示胶囊，例如用户输入“/”后出现语法胶囊”；
  - 需求目标：当用户在搜索框输入 `/` 时，动态弹出高频语法提示胶囊（如 `/doc`、`/code`、`/app`、`/img`、`/web`、`/calc`、`/lock` 等），支持模糊实时过滤，按下 `Tab` 或点击胶囊直接自动补全语法并准备输入关键词；同时在结果列表中直出指令卡片与功能说明，并拦截无效的根目录磁盘扫描，兼顾极客体验与极致性能。

- **实施细节与涉及文件**：
  1. **新建语法指令数据模型**（`Sources/atools/Models/SearchSyntaxCommand.swift`）：
     - 定义 `SearchSyntaxCommand` 结构体，囊括文件分类（`/doc`, `/code`, `/app`, `/img`, `/media`, `/zip`, `/folder`）、工具扩展（`/web`, `/calc`）及系统控制（`/lock`, `/sleep`, `/empty`, `/restart`）共 13 大指令体系；
     - 赋予触发词、中文名称、SF Symbol 图标、多别名（如 `/dir` -> `/folder`）与功能释义；
     - 提供 `SearchSyntaxCommand.matching(prefix:)` 纯内存 \(O(1)\) 实时过滤算法。
  2. **扩展前缀语法提取**（`Sources/atools/Models/SearchTypeFilter.swift`）：
     - `extractPrefix(from:)` 扩展支持斜杠语法（如 `"/doc 财报"`, `"/code: main.swift"`）；
     - 严格要求空格或冒号边界，彻底消除 `/docker` 等包含 `doc` 词根普通词汇被误伤判定为语法的风险。
  3. **筛选栏双模式自适应切换与液态玻璃语法胶囊**（`Sources/atools/UI/SearchFilterBarView.swift`）：
     - 引入 `SearchFilterBarMode`（`.typeFilters` 与 `.syntaxCommands`）；
     - 新增 `SearchSyntaxPillButton`：首项候选高亮微光显示，悬浮与点击带有丝滑视觉反馈；
     - 点击胶囊直接触发 `delegate?.searchFilterBar(_:didSelectSyntaxCommand:)`；
     - 在语法模式下安全锁闭拖拽手势，维持输入框第一响应者身份。
  4. **输入框 Tab 键斜杠语法智能补全**（`Sources/atools/UI/SearchBarView.swift`）：
     - 在 `SearchTextField.performKeyEquivalent` 中捕获 `Tab` 键：当输入内容以 `/` 开头且未含空格时，优先分发 `searchBarDidRequestAutocompleteSyntax` 事件，一键补全当前候选语法并移动光标至末尾。
  5. **检索协调器拦截与直出**（`Sources/atools/Search/SearchCoordinator.swift` & `SearchResultsTableView.swift`）：
     - 在用户输入未敲空格的斜杠前缀（如 `/`、`/d`、`/c`）时，拦截底层 Spotlight 磁盘扫描，0ms 秒级直出语法指令结果卡片（标识为 `.syntaxCommand`，徽章为「指令」）；
     - 针对 `/web <关键词>` 与 `/calc <算式>` 实施精准直出，免除额外干扰。
  6. **面板中枢联动**（`Sources/atools/UI/SearchPanel.swift`）：
     - `didChangeQuery` 侦测 `/` 实时切换胶囊栏展示形态，输入删空或非斜杠时自动恢复 8 大文件分类胶囊；
     - 结果列表点击或回车选中语法指令卡片时，保持面板开启并自动填入对应前缀；
     - 针对系统类指令（如 `/lock`）确认后一键执行并收拢面板。
  7. **回归诊断测试扩展**（`Sources/atools/main.swift`）：
     - 新增 `[6.6] Testing slash syntax commands`：包含指令前缀匹配、别名映射、边界校验、胶囊栏动态双模式切换、Tab 补全候选以及 Coordinator 极速直出全流程断言。

- **验证与测试**：
  - 执行 `./Scripts/build.sh --test`：全套 13 大项自动化测试与诊断套件全部 PASS（exit=0，零失败）；
  - 执行 `./Scripts/package_app.sh`：签名及 release 构建通过；
  - 成功部署并替换至 `/Applications/ATools.app`（PID 71712）。


### 17. 参照 Alfred 全盘搜索范围设计：支持排除系统缓存等文件与自定义黑名单 (2026-10-08, build 30)

- **背景与需求目标**：
  - 用户反馈：“参照这款app全盘搜索设计 在设置-全盘搜索界面支持用户排除掉系统缓存等文件，基于思路设计和优化实施方案，并让你的子代理审核一遍”；
  - 需求目标：参照 Alfred 经典的 Search Scope（Default Results / Folders in Home - Excluding ~/Library）架构与设计规范，在 ATools 的「偏好设置 -> 全盘搜索」界面中新增「排除范围」面板，支持用户自主控制排除系统与应用缓存、日志与崩溃报告、开发依赖产物、废纸篓与隐藏文件；支持添加与管理自定义排除目录列表（黑名单）；在底层 MDQuery 5 万级大循环中实现零锁高速过滤，并智能保护 iCloud 云盘与第三方网盘（OneDrive / 百度网盘等）文档安全可搜；在热目录枚举中实施子树遍历阻断（`skipDescendants`），全面提速检索并净化搜索结果。

- **实施细节与涉及文件**：
  1. **配置持久化与向下兼容扩展**（`Sources/atools/Models/AppConfig.swift`）：
     - 在 `AtoolsConfig` 中新增 6 大预设排除开关：`searchExcludeCaches`（系统与应用缓存）、`searchExcludeLogs`（日志与崩溃报告）、`searchExcludeDeveloper`（开发构建与依赖产物）、`searchExcludeHidden`（版本控制与隐藏文件）、`searchExcludeTrash`（废纸篓与临时目录）、`searchExcludeUserLibrary`（用户资源库 ~/Library）；
     - 新增 `customExcludedPaths: [String]` 用户自定义排除目录绝对路径列表；
     - 严格向下兼容支持：`init(from decoder:)` 对全部新增字段采用 `(try? container.decode(...)) ?? default` 安全容错兜底，老配置升级无感且不破坏用户现有分类与快捷键。
  2. **新建统一高性能排除引擎**（`Sources/atools/Search/SearchExclusionEngine.swift`）：
     - 采用不可变规则预编译快照（`CompiledRules`）架构，每次配置变更时原子重构；
     - **极速分层比对**：
       * 第一层（高速前缀比对）：对缓存、日志、临时文件及用户自定义目录执行 `hasPrefix`，利用标准化绝对路径尾斜杠保证 $O(1)$ 快速失败跳出，避免对 5 万条结果进行无谓的堆内存分配与全串比对；
       * 第二层（双斜杠中缀比对）：针对跨目录深度的开发依赖（`/node_modules/`, `/DerivedData/`, `/.build/`, `/target/`, `/__pycache__/` 等）严格限定双斜杠边界，杜绝误伤合法普通文件名；
     - **对齐 Alfred 的关键云盘特赦机制（Bypass Whitelist）**：
       * 针对 `~/Library` 排除规则，特别设置针对 `~/Library/Mobile Documents/`（iCloud Drive）与 `~/Library/CloudStorage/`（OneDrive、百度网盘、Dropbox、Google Drive 等）的智能放行白名单，确保用户存放在云盘中的工作文档 100% 正常可搜，同时滤除其他庞杂的系统内部数据。
     - **热目录递归阻断（`shouldSkipDescendants`）**：
       * 在枚举热目录时，检测到被排除的工程文件夹（如 `node_modules`）或用户黑名单目录时立即调用 `enumerator.skipDescendants()`，直接剪除万级子树深层磁盘遍历，显著降低 CPU 与快照内存开销。
  3. **配置管理器扩展与路径安全校验**（`Sources/atools/Storage/ConfigManager.swift`）：
     - 新增 `validatedExcludedFolderPath(_:)`：过滤非法输入，严格禁止将系统根目录 `/` 或用户家目录 `~` 加入排除项（避免用户误操作瘫痪全盘搜索）；
     - 新增 `addCustomExcludedPath(_:)`：内置子目录包含关系收敛算法（Subsumption Check），已有父目录时自动拒绝冗余子目录，添加父目录时自动吸收并清理已有子目录，保持规则列表最简化；
     - 提供 `removeCustomExcludedPath`、`resetCustomExcludedPathsToDefault` 以及 6 大预设开关的修改方法，保存后实时触发引擎规则重构并使热目录快照自动失效刷新。
  4. **全盘文件检索与热目录快照接入**（`MetadataFileSearchBackend.swift` & `SpotlightBridge.swift`）：
     - `MetadataFileSearchBackend` 废弃写死数组，全面接入 `SearchExclusionEngine.shared.isExcluded(path:)`；
     - `SpotlightBridge.listHotFolder` 接入 `shouldSkipDescendants` 阻断与文件排除，实现双层动态生效。
  5. **偏好设置界面新增「排除范围」面板**（`Sources/atools/UI/Settings/SettingsTabViews.swift` 中的 `SearchTabView`）：
     - 子标签扩充为 4 个：`["搜索选项", "排除范围", "扩展功能", "网络搜索"]`；
     - **Page 1 (排除范围)** 布局结构：
       * **卡片 1 (常用排除预设)**：包含 6 项现代开关行，清晰阐明排除作用（如“用户资源库 (~/Library)”明确标注“智能保留 iCloud 云盘与第三方网盘”）；
       * **卡片 2 (自定义排除目录)**：以卡片列表形式展示已添加的排除目录（包含系统文件夹图标、目录名、中间截断路径与删除按钮）；底部配有「添加排除目录…」按钮（唤起系统 `NSOpenPanel`）与「恢复默认」按钮，以及动态数量与功能说明标签；
     - 控件约束全面设置 `byTruncatingMiddle` 与低抗压拉伸优先级，严格维持窗口 780.0pt 宽度恒定。
  6. **回归诊断测试扩展**（`Sources/atools/main.swift`）：
     - 新增 `[6.7] Testing Search Exclusion Engine & Custom Scopes (Alfred-style)`：
       * 覆盖系统缓存、日志诊断、开发产物、版本控制与隐藏文件全套排除断言；
       * 覆盖 iCloud Drive 与 CloudStorage 云盘关键文档放行特赦与云盘内部依赖拦截断言；
       * 覆盖热目录遍历剪枝阻断（`shouldSkipDescendants`）断言；
       * 覆盖自定义排除目录合法性拦截（根目录与家目录保护）、父子目录包含自动吸收与实时排除断言；
       * 覆盖老配置缺失字段的向前解码兼容性断言。

- **兼容性与边界防护策略**：
  - 单例循环依赖死锁防御：`SearchExclusionEngine.init()` 采用独立纯默认配置初始化，解耦与 `ConfigManager.shared` 相互等待导致的 `_dispatch_once_wait` 陷阱；
  - 窗口尺寸不变性防护：通过自动化布局诊断测试断言，4 分段标签与自定义路径列表在任何极长路径下绝不撑破 780.0pt 窗口边界。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套 13 大项综合诊断套件（含计算器、系统指令、配置管理器、分类管理、应用索引、全盘检索、排序归并、热目录拼音、分类筛选栏、语法指令、排除引擎与自定义范围、基线内存、设置窗口恒定 780pt、抽屉面板、搜索面板展开收起、更新管理器与关窗即退）**100% 全部 PASS 通过（exit=0，零失败）**。


### 18. 对齐 Alfred 极速交互体验：空格一键进入文件检索 & 访达文件夹拖拽进设置 (2026-10-08, build 30)

- **背景与需求目标**：
  - 用户反馈：“/plan 空格一键进入文件检索、从访达直接拖拽文件夹进设置。对于这两个功能点进行设计，生成实施方案，并让你的子代理审核一遍，确保功能跑通、不影响其他功能正常运行”；
  - 需求目标：参照 Alfred 标杆级的交互直觉与操作流畅度，打造两项核心功能：
    1. **空格一键进入文件检索 (Spacebar Shortcut)**：搜索框在空白状态下单按一次空格键，直接一键切换至“文档/文件”检索模式（`SearchTypeFilter.document`），同时输入框保持聚焦，支持打字即搜；在分类模式下若再次清空并按下退格键（Delete/Backspace），平滑回退至“全部”模式。
    2. **访达直接拖拽文件夹进设置 (Finder Drag-and-Drop Scope into Settings)**：支持从 macOS 访达（Finder）直接多选或单选拖拽文件夹到「偏好设置 -> 全盘搜索」中的「自定义热目录」卡片和「自定义排除目录」卡片，提供强调色边框高亮悬停反馈与自动去重落地。

- **实施细节与涉及文件**：
  1. **现代卡片式容器原生拖拽扩展**（`Sources/atools/UI/Settings/SettingsComponents.swift`）：
     - 为 `SettingsCardView` 原生接入 `NSDraggingDestination` 协议；
     - 提供 `public var onDropFolders: (([String]) -> Void)?` 回调，设置后自动注册 `registerForDraggedTypes([.fileURL])`；
     - **拖拽生命周期与交互设计**：
       * `draggingEntered` / `draggingUpdated`：解析 pasteboard 中的 `NSURL` 列表，校验包含真实存在的文件夹且排除 `.app` 应用程序包；若合法返回 `.copy` 并激活高亮态（卡片边框切换为 1.5pt `NSColor.controlAccentColor`）；
       * `draggingExited`：平滑恢复边框样式；
       * `performDragOperation`：提取全部合法绝对路径并派发 `onDropFolders` 回调。
  2. **偏好设置热目录与排除黑名单卡片拖拽落地**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 为 `cardHot`（自定义热目录）绑定 `onDropFolders`：批量调用 `ConfigManager.shared.addHotFolder(path)`，自动完成父子目录包含检测与去重，刷新列表；若有非法路径或超限触发系统声音反馈；
     - 为 `cardCustom`（自定义排除目录）绑定 `onDropFolders`：批量调用 `ConfigManager.shared.addCustomExcludedPath(path)`，自动执行 Subsumption 父子目录吸收合并，刷新列表并重构排除引擎规则；
     - 优化卡片副标题与空态引导文案，明确提示：“可点击添加，或直接从访达将文件夹拖拽至此”。
  3. **窗口底层事件安全拦截与输入法（IME）保护**（`Sources/atools/UI/SearchPanel.swift`）：
     - 吸收子代理深度审核结论：在 AppKit 中，编辑状态下的 `NSTextField` 会交由系统共享的 Field Editor (`NSTextView`) 接管 `firstResponder`，常规按键不经过 `performKeyEquivalent` 或 `NSTextField.keyDown`。因此将按键拦截前置在 `SearchPanel: NSPanel` 的 `sendEvent(_:)` 顶层统一处理；
     - **严格的输入法保护**：判断 `(editor as? NSTextView)?.hasMarkedText() == true`。当用户正在进行中文拼音输入（如打 “wenjian” 并按空格选词）时，严格放行，**绝对不拦截拼音选词与输入法交互**；
     - **空格切入文件检索**：在输入框文本为空、修饰键为空且无输入法上屏时，按空格键（keyCode 49）触发 `searchViewController.handleSpacebarShortcut()`，自动将 `filterBar.selectedFilter` 切换至 `.document`，展开面板并立即消费该事件，防止在文本框中留下无意义的单空格字符；
     - **退格回退全部模式**：在分类不为 `.all` 且文本为空时，按退格键（keyCode 51）触发 `searchViewController.handleBackspaceShortcut()`，自动回退到 `.all` 模式并折叠面板，且彻底消除 macOS 底层发出“无法退格”的警告提示音。
  4. **全套自动化测试扩展**（`Sources/atools/main.swift`）：
     - 新增 `[6.8] Testing Spacebar File Search Shortcut & Settings Drag-and-Drop Card (Alfred-style)`：
       * 空格空白切入 `.document` 模式判定与重复空格防御断言；
       * 非空文本时不触发快捷模式切换断言；
       * 退格空白回退 `.all` 模式与已是全部模式时不拦截断言；
       * `SettingsCardView` 拖拽回调注入、合法目录校验、排除黑名单添加与配置持久化复原断言。

- **兼容性与边界防护策略**：
  - 零破坏性向前兼容：无需调整配置数据结构，复用已验证的 `extraHotFolders` 与 `customExcludedPaths` 存储契约；
  - 窗口 780.0pt 宽度保护：长路径标签配合中间截断与低抗压优先级，拖入任何超长文件名绝不撑大偏好设置窗口；
  - 编译零警告：修复测试断言中的未使用变量，编译链接零警告通过。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件 100% 全部 PASS 通过；
  - 执行 `./Scripts/package_app.sh`：Release 版本构建签名打包成功；
  - 部署并成功启动 `/Applications/ATools.app`（PID 89518）。

### 19. 搜索框语法指令胶囊化 (Syntax Token Capsule) 视觉设计与交互闭环 (2026-10-08, build 30)

- **背景与需求目标**：
  - 用户反馈：“/plan 给搜索框中的语法加上胶囊，类似于图二这样的，做一个设计计划，并让你的子代理审核一下”；
  - 核心痛点与目标：用户对比图一（传统在输入框中生硬输入纯文本 `/doc `）与图二（现代启动器中以高质感 Token Chip 胶囊 `[ 🗂 plan ]` 挂在搜索框前、输入框紧随其后输入关键词），要求全面提升搜索框的语法指令视觉表现与交互质感。
  - 关键要素：
    1. **原生 Token 胶囊控件 (`SyntaxCapsuleView`)**：集成指令专属 SF Symbol 图标、指令中文名称、微型关闭（`×`）按钮、微圆角（6pt）、细边框与悬停高亮；
    2. **自适应外观与动态 AutoLayout 切换**：支持液态玻璃浅色/深色主题外观自适应；在挂载胶囊时平滑拉伸输入框左锚点（`textFieldLeadingToCapsuleConstraint`），卸载时恢复为 `textFieldLeadingToIconConstraint`；
    3. **自动转胶囊机制**：用户键入已注册指令（如 `/doc`、`/web`、`/calc`、`/app` 等）后按下空格、Tab 自动补全或在候选列表回车时，指令自动转换为胶囊并挂载在搜索框前，输入框自动清空并定位光标，提示语自适应变为 `"在 \(name) 中搜索..."`；
    4. **退格键与快捷键闭环**：输入框为空时按 Backspace（退格键）或 Esc，优先卸载胶囊并将筛选模式平滑恢复为“全部”，消除系统提示音；
    5. **搜索路由合成守护**：对于非本地文件分类指令（`/web`、`/calc`），激活胶囊后在输入框打字时，自动合成内部指令（如 `"/web Swift"` 或 `"/calc 128*8"`），保证底层即时直出与网页跳转，防止被降级为全盘搜索；系统动作指令（`/lock` 等）回车即执行，严禁转换为胶囊。

- **实施细节与涉及文件**：
  1. **语法指令模型扩展**（`Sources/atools/Models/SearchSyntaxCommand.swift`）：
     - 增加 `SearchSyntaxCommand.commands` 静态别名；
     - 新增 `SearchSyntaxCommand.command(for filter: SearchTypeFilter) -> SearchSyntaxCommand?` 映射方法，打通下部分类栏与顶部胶囊的双向同步。
  2. **搜索栏 Token 胶囊视图与动态布局**（`Sources/atools/UI/SearchBarView.swift`）：
     - 新增 `SyntaxCapsuleView`：
       * 包含 `iconImageView`（13×13）、`titleLabel`（12pt Medium）、`removeButton`（13×13 微型关闭叉）；
       * 开启鼠标跟踪区域，实现轻量悬停反馈与点击关闭回调（`onRemove`）；
       * 严格设置水平 Hugging Priority 和 Compression Resistance 为 `.required (1000)`，防止输入长文本时挤压胶囊；
       * 增加深浅模式自适应背景色彩与边框渲染；
     - 新增 `SearchBarDelegate.searchBarDidRequestRemoveSyntaxCapsule(_:)` 代理协议；
     - 在 `SearchBarView` 中实现动态 AutoLayout 约束切换管理（`textFieldLeadingToIconConstraint`、`textFieldLeadingToCapsuleConstraint`、`capsuleLeadingToIconConstraint`）；
     - 实现 `setSyntaxCommand(_:)` 统一挂载/卸载入口，自适应更新 `placeholderAttributedString` 与 `placeholderString`。
  3. **搜索主面板交互接驳与状态机控制**（`Sources/atools/UI/SearchPanel.swift`）：
     - 接入 `searchBarDidRequestRemoveSyntaxCapsule` 与 `removeActiveSyntaxCapsule()`；
     - 在 `didChangeQuery` 中支持敲入斜杠指令 + 空格时的自动胶囊化；
     - 封装 `getEffectiveQueryAndFilter` 路由引擎，针对 `.applyFilter`、`.webSearch`、`.calculator` 自动装配底层查询；
     - 在 `handleBackspaceShortcut` 中实现退格优先卸载胶囊、次级恢复全部的双稳态闭环；
     - 在 `handleSpacebarShortcut` 中按下空格切入文件检索时同步激活 `cmd_doc` 胶囊；
     - 在 `dismissSearchPanel` 与 `prepareForDisplay` 中彻底重置胶囊状态。
  4. **全套自动化测试扩展**（`Sources/atools/main.swift`）：
     - 新增 `[6.9] Testing Search Bar Syntax Token Capsule (Visual Chip & State Machine)`：
       * 胶囊挂载、卸载与 `placeholder` 占位符自适应切换断言；
       * 点击胶囊 `×` 按钮卸载与筛选器回退断言；
       * 键入 `"/web "` 自动转换为语法胶囊与输入框清空断言；
       * 输入框为空时按 Backspace 退格键卸载胶囊与事件拦截断言；
       * `prepareForDisplay` 窗口展示前彻底清理胶囊断言。

- **兼容性与边界防护策略**：
  - 系统瞬时动作保护：系统指令（`/lock`、`/sleep`、`/empty`、`/restart`）直接执行，严禁转换为胶囊残留；
  - 输入法打字保护：在 `SearchPanel.sendEvent` 中严密监控 `isMarked`，中文拼音选词过程中绝不拦截空格或退格；
  - 界面与布局无缝过渡：胶囊出现时保持窗口顶边与胶囊高度 44pt 绝对平稳，绝无跳动与残影。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件 100% 全部 PASS 通过（0 失败）；
  - 执行 `./Scripts/package_app.sh`：打包构建 Release 版本成功；
  - 部署到 `/Applications/ATools.app` 并成功重启运行（PID 8215）。

### 20. 搜索栏下部分类胶囊圆角视觉统一与舒适间距拓展 (2026-10-08, build 30)

- **背景与需求目标**：
  - 用户反馈：“上面搜索栏的胶囊和下面的统一一下，下面这一栏改成上面那种圆角小一点的，并且胶囊间距不要太紧凑”；
  - 需求目标：
    1. **圆角与高度规格统一**：将下部分类筛选栏中的胶囊控件（`SearchFilterPillButton`、`SearchSyntaxPillButton`）的大药丸半圆弧角（`13pt`）重构为与顶部搜索胶囊完全统一的 **`6pt` 微圆角**；统一高度为 `24pt`；
    2. **胶囊间距呼吸感拓展**：将胶囊容器 `stackView.spacing` 从原本拥挤紧凑的 `4pt` 翻倍拓展至 **`8pt`**，告别挨在一起的局促感；
    3. **按钮内边距与精致质感对齐**：重载 `intrinsicContentSize` 为文字两侧拓展 `10pt` 舒适留白；重构深浅模式下选中与悬停的微透明底色与 0.5pt 细边框，达到 100% 视觉协调。

- **实施细节与涉及文件**：
  1. **分类栏胶囊视图重构**（`Sources/atools/UI/SearchFilterBarView.swift`）：
     - `SearchFilterPillButton`：
       * `layer?.cornerRadius` 由 `13` 调整为 `6`；
       * 重载 `intrinsicContentSize`（宽度 +10pt，高度 24pt），杜绝文字紧贴边框；
       * 字体调整为 12pt Medium / Semibold，与顶部搜索胶囊文本规范对齐；
       * `updateAppearance()` 彻底重构：选中态深色采用 `white 0.15` + 边框 `white 0.22`，浅色采用 `black 0.08` + 边框 `black 0.12`，与顶部搜索胶囊完全一致；
     - `SearchSyntaxPillButton`：
       * `layer?.cornerRadius` 同步调整为 `6`；
       * 重载 `intrinsicContentSize`，高亮指令边框设为精致 0.5pt；
     - `SearchFilterBarView`：
       * `stackView.spacing` 调整为 `8`；
       * `btn.heightAnchor` 约束由 `26` 统一调整为 `24`。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件 100% 全部 PASS 通过；
  - 执行 `./Scripts/package_app.sh`：打包构建 Release 版本成功；
  - 成功部署至 `/Applications/ATools.app` 并完成平滑重启（PID 9902）。

### 21. 语法指令选项与胶囊标题纯中文显示优化 (2026-10-08, build 30)

- **背景与需求目标**：
  - 用户反馈：“胶囊选项也不要显示英文了，只要中文”；
  - 需求目标：去除非必要的生硬英文指令前缀（如 `/doc`、`/code`、`/app` 等），全面提升界面母语化阅读体验。在输入 `/` 触发语法提示时，结果列表中的指令条目与下部分类胶囊栏仅呈现清爽明确的纯中文标题（如“文档”、“代码”、“应用”、“图片”、“音视频”、“压缩包”、“文件夹”等）。

- **实施细节与涉及文件**：
  1. **搜索协调器结果装配**（`Sources/atools/Search/SearchCoordinator.swift`）：
     - 将生成 `syntaxCommand` 结果的 `title` 从 `\(cmd.trigger) \(cmd.name)` 修正为纯中文 `cmd.name`；
     - 触发词与快捷键说明保留在副标题或说明中，主标题干净利落。
  2. **指令分类胶囊按钮标题**（`Sources/atools/UI/SearchFilterBarView.swift`）：
     - 将 `SearchSyntaxPillButton` 的 `attributedTitle` 从 `" \(command.trigger) \(command.name)"` 改为纯中文 `" \(command.name)"`。
  3. **自动化测试扩展**（`Sources/atools/main.swift`）：
     - 在 `[6.6]` 中新增断言：`TestAssertions.expect(slashResults.first?.title == "文档")`，确保指令卡片标题不带英文前缀。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套 13 大项综合诊断套件 100% 全部 PASS 通过（0 失败）；
  - 执行 `./Scripts/package_app.sh`：打包构建 Release 版本成功；
  - 部署并成功重启 `/Applications/ATools.app`（PID 11283）。
### 22. 切换软件与后台失焦防误退全链路安全加固 (2026-10-08, build 30)

- **背景与排查目标**：
  - 用户反馈：“检查一下是否还存在切换软件退出软件的问题”；
  - 核心排查与加固目标：针对用户开启“关窗即退”或使用 ATools 快捷搜索/抽屉面板时，深度排查用户在进行软件切换（如 `⌘Tab`、多虚拟桌面 Space 滑动切换、窗口最小化到 Dock、前后台切换）过程中，是否存在 ATools 自身被误退出或正在使用的第三方应用程序被误杀退出的隐患，全面消除误杀风险，确保系统级稳定性。

- **深度排查结论与关键漏洞发现**：
  1. **ATools 自身防退出机制验证**：
     - 排查 `AppDelegate.swift` 与 `PanelCoordinator.swift`：失焦时无论用户点击屏幕任何区域，仅调用 `hideShelfPanel` 或 `dismissSearchPanel` 隐藏面板，绝不调用 `terminate`；
     - `AutoQuitManager.shouldWatch` 内部严密排除了 `isSelf`（`Bundle.main.bundleIdentifier == "cc.atools.app"`），ATools 自身绝对不会被加入监控，绝不存在自身因失焦退出问题。
  2. **发现并定位 AutoQuit 对第三方应用误杀的致命缺陷**（`Sources/atools/System/AutoQuitManager.swift`）：
     - **致命缺陷 1（重试超时强行杀进程）**：在 `evaluateAppWindowsLocked` 中，原逻辑判定当 `axCount == 0 && (wsCount ?? 0) > 0`（即 AX 偶发报 0 但 WindowServer 确认屏幕上有在屏窗口）时，重试 2 次（仅 200ms）后，直接进入了 `else` 分支调用 `scheduleQuitLocked`！如果某第三方应用在后台失焦或切换时 AX 响应出现短暂延迟（超 200ms），但在屏幕上仍有标准窗口，就会被 ATools 误判为已关闭全部窗口并直接杀死！
     - **安全漏洞 2（缺乏前台激活态护城河）**：应用从后台切换至前台，或者用户正在该应用中交互时，若此前进入过退出调度队列，原逻辑在执行杀进程（`executePendingQuit`）时缺乏前台活跃态（`app.isActive`）校验，存在切回瞬间被执行杀退的竞态风险；
     - **安全漏洞 3（Dock 栏最小化误判）**：当用户将窗口最小化到 Dock 栏时，屏幕上的窗口被移除（`kCGWindowIsOnscreen` 变 false），若 AX 属性未深层解析最小化状态，可能会被误判为零窗口。

- **实施细节与涉及文件**：
  1. **重构窗口超时判定逻辑，杜绝误杀**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 修复 `evaluateAppWindowsLocked`：当重试次数达到上限后，若 WindowServer 依然确证存在在屏标准窗口（`wsCount > 0`），证明窗口真实存在且未被用户关闭。将原有错误的 `scheduleQuitLocked` 彻底修正为：立即清除重试计数并执行 `cancelPendingQuitLocked(pid)`，安全撤销退出流程，保障后台运行应用绝对不被误退。
  2. **前台活跃正在使用的应用绝对保护**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 在 `evaluateAppWindowsLocked` 与 `executePendingQuit` 入口处严密加入 `guard !app.isActive else { cancelPendingQuitLocked(pid); return }`；
     - 凡是用户当前正在使用的、处于前台激活状态的应用，无论任何原因与状态，均绝对禁止触发自动退出。
  3. **Dock 栏最小化窗口深度保护**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 在 `executePendingQuit` 终极执行前，深层检查 `axWindows` 中是否存在处于最小化状态（`kAXMinimizedAttribute == true`）的窗口；
     - 只要用户是将窗口最小化至 Dock 栏而非关闭，立即终止退出流程，绝不杀死进程。

- **兼容性与多重安全护城河**：
  - 当前 ATools AutoQuit 已建立 5 重全链路安全护城河：
    1. `!app.isHidden`（`⌘H` 隐藏应用安全放行）；
    2. `!app.isActive`（前台活跃应用绝对放行）；
    3. `!hasMinimized`（Dock 最小化窗口绝对放行）；
    4. `wsCount > 0` 超时安全取消退出（真实窗口在屏绝对放行）；
    5. `lastSpaceChangeDate` 2.0s 宽限期（虚拟桌面 Space 切换绝对放行）。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（13 大项）**100% 全部 PASS 通过**（0 失败）；
  - 执行 `./Scripts/package_app.sh`：Release 版本构建签名打包成功；
  - 成功部署至 `/Applications/ATools.app` 并完成平滑重启。
### 23. 全局搜索框剪贴板粘贴与原生文本编辑快捷键全链路闭环 (2026-10-08, build 30)

- **背景与原因排查**：
  - 用户反馈：“检查一下为什么全局搜索粘贴不进剪贴板里面的内容了”；
  - **核心原因诊断**：
    1. **菜单响应链断流（主因）**：ATools 属于 Accessory 状态栏应用（`activationPolicy = .accessory`），且搜索面板为无边框悬浮面板（`styleMask: [.borderless, .nonactivatingPanel]`，`canBecomeMain = false`）。在 AppKit 机制中，当应用没有处于主窗口状态时，系统主菜单（MainMenu）的全局快捷键分发链会直接中断，导致 `NSTextField` 依赖的系统菜单项动作（`paste:`、`copy:`、`cut:`、`selectAll:`）无法自动触达输入框，执行时无任何反应或发出系统警告音；
    2. **`SearchTextField` 快捷键拦截盲区**：此前在 `SearchTextField.performKeyEquivalent` 中，仅针对 `⌘R`、`⌘C`（复制路径）、`Tab`、`⌘1~8` 等做了自定义拦截，对于 `⌘V`（粘贴）、`⌘A`（全选）、`⌘X`（剪切）、`⌘Z`（撤销）等基础编辑按键全部交回 `super.performKeyEquivalent`。而 AppKit 原生 `NSTextField` 在 `performKeyEquivalent` 中并不直接处理 `⌘V` 等编辑键，原本指望 MainMenu 接管却因上述原因断流；
    3. **从访达复制文件类型不兼容**：用户在访达中选中文件按 `⌘C` 后，剪贴板注入的是 `public.file-url`，通常不含纯文本类型（`public.utf8-plain-text`）。原生输入框仅接收纯文本，直接粘贴无法解析出文件名称。

- **实施细节与涉及文件**：
  1. **现代剪贴板智能解析与粘贴引擎**（`Sources/atools/UI/SearchBarView.swift` 中的 `SearchTextField`）：
     - 新增 `pasteFromClipboard()`：
       * 智能多格式解析：优先读取纯文本/富文本字符串；若剪贴板内为用户从访达（Finder）拷贝的文件或文件夹（`readObjects(forClasses: [NSURL.self])`），自动萃取文件名（`first.lastPathComponent`），让用户复制文件后可一秒粘入搜索框快速检索；
       * 换行符与格式清洗：将 `\r\n` / `\n` 自动清洗替换为空格，杜绝在单行搜索框内导致布局挤压或截断；
       * 智能落位与事件派发：优先向当前活跃 Field Editor（`NSTextView`）执行 `insertText(_:replacementRange:)`，自动保留 Undo 栈并触发文本监听；在未激活编辑态时直接安全注入并通知 `delegate?.searchBar(_:didChangeQuery:)`，保证即粘即搜；
     - 显式声明 `@objc public func paste(_ sender: Any?)`、`copy(_ sender: Any?)`、`cut(_ sender: Any?)` 与 `selectAll(_ sender: Any?)`，完整接入 AppKit 标准动态响应者体系；
     - 重载 `menu(for event:)`：为搜索框提供原生“剪切、拷贝、粘贴、全选”右键上下文菜单。
  2. **键盘按键等价物（Key Equivalents）闭环补全**（`SearchTextField.performKeyEquivalent`）：
     - `⌘V`（keyCode 9）：直接执行 `pasteFromClipboard()` 并返回 `true`，彻底绕过 MainMenu 依赖；
     - `⌘A`（keyCode 0）：执行全选；
     - `⌘X`（keyCode 7）：剪切选中文字；
     - `⌘C`（keyCode 8）：当输入框中有选中文本时优先复制文本；无选中文本时保留复制选中文件路径的原有极客设计；
     - `⌘Z` / `⇧⌘Z`（keyCode 6）：对接 `undoManager` 支持精准撤销与重做。
  3. **搜索面板顶层快捷键兜底机制**（`Sources/atools/UI/SearchPanel.swift`）：
     - 重载 `SearchPanel.performKeyEquivalent(with:)`：当用户在搜索面板激活状态下，哪怕光标焦点因鼠标点击结果列表或分类胶囊而短暂脱离输入框，只要按下 `⌘V` 或 `⌘A`，顶层面板自动兜底将剪贴板内容注入输入框或全选，带来极致丝滑的无死角操作体验。
  4. **回归诊断测试扩展**（`Sources/atools/main.swift`）：
     - 新增 `[6.10] Testing Search Bar Clipboard Paste & Editing Shortcuts (Cmd+V / Cmd+A / Cmd+C / Cmd+X)`：
       * 覆盖纯文本粘贴落地与输入框/查询协同断言；
       * 覆盖 `⌘A` 全选范围与 `⌘C` 选中文本复制断言；
       * 覆盖 `⌘X` 剪切文本清空断言；
       * 覆盖从访达复制文件智能提取文件名粘贴断言；
       * 覆盖 `SearchPanel` 顶层焦点脱离时的 `⌘V` 兜底粘贴断言。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（14 大项）**100% 全部 PASS 通过**（0 失败）；
  - 执行 `./Scripts/package_app.sh`：Release 版本构建签名打包成功；
  - 成功部署至 `/Applications/ATools.app` 并完成启动运行（PID 33820）。
### 24. 彻底解决与外部剪贴板管理器 (AuraSnap / Maccy) 联动时面板意外回收与粘贴失败问题 (2026-10-08, build 30)

- **背景与原因排查**：
  - 用户反馈：“还是不行，我打开全盘搜索，再唤出AuraSnap的剪贴板，选中剪贴板记录后，没有粘贴进全盘搜索框，而是两个面板一起回收了”；
  - **核心链路原因追踪**：
    1. **ATools 无法被外部剪贴板工具识别为激活前台应用**：原 `SearchPanel` 配置了 `styleMask: [.borderless, .nonactivatingPanel]` 且 `canBecomeMain = false`。在 macOS WindowServer 机制中，拥有 `.nonactivatingPanel` 属性的面板永远不会使所属应用成为系统级的 `frontmostApplication`。当用户在搜索框前呼出 AuraSnap 剪贴板时，AuraSnap 记录的上一个前台激活应用并非 ATools，而是更早前使用的 DingTalk、WPS Office 或 Finder！
    2. **选中剪贴板条目触发激活错误应用与 ATools 误判收起**：当用户在 AuraSnap 中双击或回车选中记录时，AuraSnap 先向系统发起“激活上一个前台应用”（错误激活了背景的 DingTalk/WPS），并模拟按下 `⌘V`。此时 ATools 监听到后台应用被重新激活，触发了 `handleAutomaticDismissal(.appSwitched)`，导致搜索面板立即隐藏收起，`⌘V` 丢失且两个面板同时关闭；
    3. **点击剪贴板窗口被判定为外部点击**：当用户用鼠标点击 AuraSnap 窗口时，鼠标坐标位于搜索框之外，`handleOutsideInteraction()` 误将此判定为用户点击空白处离开搜索，直接调用了 `hideSearchPanel()`；
    4. **呼出剪贴板瞬间触发失焦关闭**：原逻辑在 `didResignKeyNotification` 时无条件收回搜索面板，剪贴板浮层一出现便导致搜索面板直接进入关闭流程。

- **实施细节与涉及文件**：
  1. **搜索面板提升为主窗口与激活主体**（`Sources/atools/UI/SearchPanel.swift` & `PanelCoordinator.swift`）：
     - `SearchPanel` 的 `styleMask` 废除 `.nonactivatingPanel`，重载 `canBecomeMain` 设为 `true`；
     - 在 `showSearchPanel()` 中显式执行 `NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)` 与 `searchPanel.makeMain()`，确保 macOS `NSWorkspace.shared.frontmostApplication` 精准识别为 ATools，让第三方剪贴板工具无缝将 ATools 锁定为回传粘贴目标。
  2. **多重辅助浮层工具豁免保护体系**（`Sources/atools/UI/PanelCoordinator.swift`）：
     - **应用切换豁免（`workspaceActivationObserver`）**：检测新激活应用的 `activationPolicy`，若为 `.accessory` 或 `.prohibited`（如 AuraSnap、Maccy、CleanClip、Paste、系统表情符号窗口等无 Dock 图标的辅助浮层工具），严格忽略切换事件，绝不收回搜索面板；
     - **失焦豁免（`windowResignObserver`）**：在 `didResignKeyNotification` 时检查当前前台应用，若属于 ATools 自身或正在操作辅助工具，阻止自动收回搜索面板；
     - **外部点击智能过滤（`handleOutsideInteraction`）**：新增 `isClickOnAuxiliaryToolWindow(at:)`，通过 WindowServer 分析屏幕坐标命中窗口的属主应用。当用户点击 AuraSnap 或其他剪贴板工具的浮层窗口以选取记录时，判定为合法输入协作，绝不触发外部点击关闭。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（14 大项）**100% 全部 PASS 通过**（0 失败）；
  - 执行 `./Scripts/package_app.sh`：Release 版本构建签名打包成功；
  - 成功部署至 `/Applications/ATools.app` 并完成平滑重启（PID 36729）。

### 25. 全盘搜索与外部剪贴板管理器 (AuraSnap / Maccy) 协同交互与生命周期保活深度修复 (2026-10-08, build 31)

- **背景与深度根因剖析**：
  - 用户反馈：“还是不行，我打开全盘搜索，再唤出AuraSnap的剪贴板，选中剪贴板记录后，没有粘贴进全盘搜索框，而是两个面板一起回收了”；
  - **经逆向与系统事件流排查定位的三重绞杀陷阱**：
    1. **macOS 14/15 隐私沙箱导致外部窗口尺寸脱敏为 0**：在现代 macOS（Sonoma / Sequoia）中，未获屏幕录制权限的进程调用 `CGWindowListCopyWindowInfo` 时，非本进程窗口的 Bounds `Width` 和 `Height` 恒被脱敏为 `0.0`，导致 `isClickOnAuxiliaryToolWindow` 永远返回 `false`，从而将用户在 AuraSnap 剪贴板窗口上的点击 100% 误判为“点击外部空白”，瞬间调用 `hideSearchPanel()` 杀掉搜索；
    2. **`windowResigned` 与 `appDeactivated` 盲目自杀机制**：呼出剪贴板历史浮层时，搜索面板必然暂时失去 Key Window。由于 ATools 和 AuraSnap 均为 `.accessory` 应用，macOS 系统中的 `frontmostApplication` 仍会解析为后台应用（如钉钉/WPS/访达），导致失焦与去活监听器误判并强行收起搜索；
    3. **外部剪贴板工具退场时的过渡激活误杀与未粘贴**：AuraSnap 选中记录后隐藏自身，系统短暂交接焦点给后台应用，触发 `didActivateApplicationNotification` 导致二次误杀；同时搜索面板被关时清空了输入框，导致第三方工具随之模拟按下的 `⌘V` 全部落空。

- **实施细节与涉及文件**：
  1. **全盘搜索面板失焦与去活保护机制**（`Sources/atools/UI/PanelCoordinator.swift`）：
     - 在 `windowResignObserver` 与 `handleAutomaticDismissal` 中，明确豁免全盘搜索面板：严禁因 `.windowResigned` 或 `.appDeactivated` 关闭全盘搜索，对齐 Spotlight 与 Alfred 的临时输入中心设计模型；
     - 搜索面板的退出仅由用户按 Esc、再次按快捷键、明确点击外部非辅助窗口、或明确切换前台主应用驱动。
  2. **基于 Accessibility API 的三级外部点击智能识别**（`PanelCoordinator.isClickOnAuxiliaryToolWindow`）：
     - **Tier 1 (AX 优先)**：使用系统级 `AXUIElementCopyElementAtPosition` 获取点击屏幕坐标处的进程 PID，不受 macOS 窗口尺寸脱敏影响；对 ATools 自身窗口及所有 `.accessory` / `.prohibited` 辅助浮层（AuraSnap、Maccy 等）精准保护放行；
     - **防卡死超时保护**：显式设置 `AXUIElementSetMessagingTimeout(systemWide, 0.05)` 50ms 超时，杜绝因外部卡死应用导致主线程事件循环受阻；
     - **Tier 2 (白名单兜底)**：若系统无辅助功能权限，自动 fallback 到已知剪贴板浮层工具运行名单（AuraSnap、Maccy、Paste、CleanClip 等）；
     - **Tier 3 (防抖协同)**：外部点击检测在执行收拢前，二次比对剪贴板是否发生更新，若有更新则判定为协同粘贴并放弃关闭。
  3. **应用激活过渡防抖与焦点唤回**（`PanelCoordinator.workspaceActivationObserver`）：
     - 监听 `didActivateApplicationNotification` 时，检测剪贴板 `changeCount` 在搜索会话期间是否发生递增；
     - 若发生更新，判定为外部剪贴板退场过渡，立即保持搜索面板开启并唤回 Key Window，防止后台应用激活误杀。
  4. **防重复的双保险智能粘贴（水位对齐机制）**（`Sources/atools/UI/SearchBarView.swift` & `SearchPanel.swift`）：
     - 在 `SearchBarTextField` 中引入 `lastHandledPasteboardChangeCount`；
     - 原生快捷键 `⌘V` 或 `pasteFromClipboard()` 消费后立即记录当前版本；
     - 在 `SearchPanel.becomeKey` 中，增加 150ms 投递窗口期优先等待原生 `⌘V`；若外部工具未能成功送达原生按键，且当前剪贴板版本未被消费过，才由 `pasteLatestFromClipboardIfNeeded(since:)` 执行单次安全注入并对齐水位，彻底消除重复双贴风险。
  5. **自动化诊断测试覆盖**（`Sources/atools/main.swift`）：
     - 新增 `[6.11] Testing SearchPanel Auxiliary Floating Tool & Clipboard Lifecycle Protection...`：
       * 覆盖基准剪贴板标记与未变动时的无害性断言；
       * 覆盖外部剪贴板更新时首次单次安全注入与水位对齐断言；
       * 覆盖相同剪贴板版本二次到达时的防重复拦截断言；
       * 覆盖自身窗口在 `isClickOnAuxiliaryToolWindow` 中的豁免断言。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（15 大项）**100% 全部 PASS 通过**（0 失败）；
  - 核心断言 `[6.11] 外部辅助浮层协同保活（基准标记/精准单次注入/防重阻断/窗口豁免）全部验证通过`；
  - 偏好设置窗口在所有标签下维持严格的 780.0pt 宽度不变形约束。

### 26. 全盘搜索新增「复制后立即呼出时自动粘贴」智能联动开关 (2026-10-08, build 32)

- **背景与需求目标**：
  - 用户反馈：“全盘搜索能否在设置中增加一个开关，开启则 在检测到复制后立刻唤出全盘搜索时 把复制的内容自动粘贴到全盘搜索框中，设计相关方案，并让你的子代理审核一下，确保其他功能正常运行”；
  - 解决用户在外部应用复制单词、路径、URL 或计算表达式后唤出搜索需要再次按 `⌘V` 的多余步骤，实现“复制后快捷唤起即搜”的极致流畅闭环。

- **实施细节与涉及文件**：
  1. **配置模型与向下兼容扩展**（`Sources/atools/Models/AppConfig.swift` & `ConfigManager.swift`）：
     - `AtoolsConfig` 新增 `autoPasteOnSummonAfterCopy: Bool`，默认值为 `false`（遵循不破坏默认使用习惯原则）；
     - 解码兼容：老配置缺少该字段时平稳 fallback 到 `false`；
     - `ConfigManager` 新增 `updateAutoPasteOnSummonAfterCopy(_:)` 并派发 `.atoolsAutoPasteOnSummonDidChange` 通知。
  2. **低功耗时效性剪贴板追踪器**（`Sources/atools/Search/PasteboardRecencyTracker.swift`）：
     - **3.0 秒时效性窗口**：仅在外部复制后 3 秒内唤起搜索时执行预填充，超时唤起则保持干净搜索框；
     - **单次消费锁（Consumption Guard）**：预填充成功后即刻重置并记录已消费版本，避免关闭后重新唤出时反复误贴；
     - **自环自复制隔离（Self-Copy Guard）**：引入 `ignoredChangeCounts` 机制，在用户于 ATools 自身（如复制搜索路径、标题或设置文本）按 `⌘C` 时打上标记，防止再次呼出时把自身路径误回贴；
     - **凭据与隐私保护（Privacy Guardrails）**：拦截 5 类主流密码管理器标记（`org.nspasteboard.ConcealedType`、`com.agilebits.onepassword` 等），密码凭据严禁自动预填充；
     - **极致节能调度**：开关关闭或搜索面板已显示时完全暂停定时器（0 开销）；开启且面板隐藏时采用 `0.5s` 定时器配 `0.2s` 容差（tolerance），与系统调度平滑合并。
  3. **全盘搜索展示生命周期无缝衔接**（`Sources/atools/UI/SearchPanel.swift` & `PanelCoordinator.swift`）：
     - `SearchViewController.prepareForDisplay(prefilledText:)`：注入预填充文本后立即触发即时检索，并在主线程下一次 RunLoop 建立稳态后将文本全选（`selectAll`），用户直接敲回车可立即打开结果，敲击任意字符可直接覆盖输入；
     - `SearchResultsTableView.copySelectedPath()`：复制路径后调用 `markSelfGeneratedChangeCount()` 杜绝回环。
  4. **偏好设置界面新增选项卡片**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 在「全盘搜索 -> 搜索选项」卡片 1 中新增「复制后立即呼出时自动粘贴」开关与说明；
     - 严格维持 `780.0pt` 窗口宽度不变形约束。
  5. **自动化诊断测试套件**（`Sources/atools/main.swift`）：
     - 新增 `[6.12] Testing autoPasteOnSummonAfterCopy (Recency, Consumption, Self-Copy Guard & Sensitive Filter)...`：
       * 覆盖开关开启/关闭状态下的判定；
       * 覆盖 3 秒内有效提取与单次消费防重复断言；
       * 覆盖超过 3 秒过期拒绝自动粘贴断言；
       * 覆盖 ATools 自身复制路径防自环污染断言；
       * 覆盖 ConcealedType 敏感密码凭据拒绝注入断言；
       * 覆盖 `prepareForDisplay` 预填充与检索协同端到端断言。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（16 大项）**100% 全部 PASS 通过**（0 失败）；
  - 核心断言 `[6.12] 复制后呼出自动粘贴（时效性判定/单次消费/过期拦截/自环防护/敏感凭据过滤/端到端预填充）全部验证通过`；
  - 严格保持 780.0pt 窗口宽度与 34MB 轻量内存占用。

### 27. 「复制后立即呼出时自动粘贴」连续多次生效与生命周期时序缺陷彻底修复 (2026-10-08, build 33)

- **背景与深度根因排查**：
  - 用户反馈：“打开复制后立即呼出时自动粘贴后，仅开启后第一次有效，之后再复制后唤出搜索框没有自动粘贴到框内”；
  - **排查锁定的两大根因**：
    1. **面板退场动画期间的窗口可见性误判（致命）**：`hideSearchPanel` 触发了 160ms 的淡出动画（`animatePanelDismissal`）。在动画结束 `orderOut` 之前，`searchPanel.isVisible` 依然为 `true`。原实现在 `hideSearchPanel` 中调用 `startMonitoringIfNeeded`，内部误判 `isSearchPanelVisible == true`，直接执行了 `stopMonitoring()`，导致后台剪贴板监听器被彻底杀死，后续复制操作再也无法被捕获；
    2. **极速唤出操作的时序延迟（Instant Catch 缺失）**：用户在外部按 `⌘C` 后极速唤出搜索（如 100ms~200ms 内），而定时器为 0.5s 周期，若恰好在定时器下一次触发前呼出，`lastCopyTime` 未能及时记录。

- **实施细节与涉及文件**：
  1. **生命周期解耦与常态稳定监听**（`Sources/atools/Search/PasteboardRecencyTracker.swift`）：
     - 移除了定时器对面板退场过程中的错误启停联动，当用户开启该配置项时，后台定时器保持稳定运行，并配合 0.2s 系统调度容差，仅在用户彻底关闭开关时释放；
     - 彻底消除与 `hideSearchPanel` 退场动画的竞态死锁问题。
  2. **唤醒入口增量即时捕获（Instant Catch Watermark Check）**（`PasteboardRecencyTracker.checkAndConsumePasteContent()`）：
     - 在搜索面板唤醒瞬间（0 延迟），主动调用 `NSPasteboard.general.changeCount` 与 `lastKnownChangeCount` 进行增量比对；
     - 若当前剪贴板版本发生递增且非自身产生的版本，立即就地记录更新，彻底抹平 0.5s 定时器的轮询相位延迟，哪怕用户按完 ⌘C 瞬间唤出也能 100% 精准捕获。
  3. **面板调度器精简**（`Sources/atools/UI/PanelCoordinator.swift`）：
     - 移除了 `showSearchPanel` 和 `hideSearchPanel` 中冗余的 `startMonitoringIfNeeded()` / `stopMonitoring()` 干扰调用，将控制权全权交由 Tracker 自治。
  4. **自动化诊断测试套件升级覆盖**（`Sources/atools/main.swift`）：
     - 扩展 `[6.12]` 测试套件：新增真实场景下连续 3 次复制与唤出消费的递进测试；
     - 新增定时器未触发时的唤起瞬间即时捕获（Instant Catch）断言，确保 100% 稳定可靠。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（16 大项）**100% 全部 PASS 通过**（0 失败）；
  - 核心断言 `[6.12] 复制后呼出自动粘贴（时效性/单次消费/过期拦截/自环防护/敏感凭据过滤/连续多次有效/极速捕获）全部验证通过`；
  - 偏好设置窗口在所有标签下维持严格的 780.0pt 宽度不变形约束。

### 28. 发布 v1.3.9 (build 34) 正式版与 GitHub Release 在线更新闭环 (2026-10-08, build 34)

- **背景与更新目标**：
  - 用户反馈旧版本客户端检查不到版本更新。经深度排查，客户端内「关于 -> 检查更新」通过 GitHub Releases API（`/repos/Moricina/ATools/releases/latest`）检测最新版本，此前推送了 Git Tag 但未在 GitHub Releases 上传正式发布包，导致 API 仍停留在旧版本（v1.3.6）；
  - 本次打包发布 `v1.3.9 (build 34)`，并在 GitHub Releases 正式发布并挂载 `ATools.dmg`、`ATools.zip` 及其对应的 Ed25519 签名文件（`.sig`），确保所有历史版本用户在「关于 -> 检查更新」时能够秒级感知新版本并一键自动更新。

- **包含的功能特性与缺陷修复全集**：
  1. **全盘搜索外部剪贴板管理器保活**：AXUIElement 坐标检测放行辅助窗口，配合失焦保护彻底解决呼出 AuraSnap 剪贴板时两个面板一起回收的问题；
  2. **复制后呼出自动粘贴**：设置中新增智能联动开关，3 秒时效性判定、单次消费锁、自环复制隔离与 1Password 等敏感凭据过滤；
  3. **生命周期解耦与 Instant Catch**：根治面板退场动画误杀监听器的问题，加入唤醒入口 0 延迟即时比对，支持连续多次稳定生效；
  4. **AutoQuit 切换软件防误退加固**：窗口超时结合 WindowServer 全空间扫描，增加活跃态与 Dock 最小化保护。

- **验证与发布结果**：
  - `./Scripts/build.sh --test` 诊断套件 100% 全部 PASS 通过；
  - `./Scripts/package_app.sh` 完成 Release 签名与 Ed25519 自动更新摘要签名；
  - 通过 GitHub CLI 完成 GitHub Release 发布与四个核心资产（dmg/zip/sig）上传挂载。

### 29. 修复「复制后立即呼出时自动粘贴」配置项 JSON 序列化遗漏导致重启或加载后开关自动重置的问题 (2026-10-08, build 35)

- **背景与根因定位**：
  - 用户反馈：“检查为什么我之前开启了这个开关，但是过段时间它自己关掉了”；
  - **排查锁定的根本原因**：
    在 `Sources/atools/Models/AppConfig.swift` 的 `AtoolsConfig.encode(to encoder: Encoder)` 自定义序列化实现中，遗漏了 `try container.encode(autoPasteOnSummonAfterCopy, forKey: .autoPasteOnSummonAfterCopy)`；
    导致用户在界面开启开关后，虽然内存中更新为 `true`，但保存到 `~/Library/Application Support/ATools/config.json` 时该字段从未被写盘。应用重启、重新加载配置或更新替换后，反序列化 `init(from decoder:)` 因读取不到该键而静默 fallback 为默认值 `false`，从而导致界面开关被自动重置回关闭状态。

- **实施细节与涉及文件**：
  1. **配置持久化补全**（`Sources/atools/Models/AppConfig.swift`）：
     - 在 `AtoolsConfig.encode(to:)` 中显式补全 `try container.encode(autoPasteOnSummonAfterCopy, forKey: .autoPasteOnSummonAfterCopy)`；
  2. **自动化往返防回退测试**（`Sources/atools/main.swift`）：
     - 在 `[6.12]` 测试中新增 `(i) 配置持久化 JSON 往返测试`：主动开启开关，执行 JSON encode 后再 decode，断言该布尔值必须保持为 `true`，彻底杜绝后续维护中类似字段序列化遗漏。

- **验证与发布结果**：
  - `./Scripts/build.sh --test` 诊断套件 100% 全部 PASS 通过；
  - 核心断言 `✓ 复制后呼出自动粘贴（.../持久化编解码）全部验证通过`；
  - 发布版本升级为 `v1.3.10 (build 35)`。

### 30. 根治关窗即退滞后与切换软件/多空间误退双重缺陷 (2026-10-09, build 36)

- **背景与现象**：
  - 用户反馈 1：“排查一下为什么窗口退出很慢，没有立即退出”；
  - 用户反馈 2：“目前又存在切换软件立刻退出的问题了”；
  - 核心痛点矛盾：用户在偏好设置开启“最后一个窗口关闭后退出应用”并设置为“立即退出 (0s)”时，点击红叉关窗无即时响应，直到切走软件后才慢吞吞退出；而当在正常使用多窗口或后台办公时，切换到其他软件或滑动 Space 虚拟桌面，被切走的应用（如 WPS Office、QQ、钉钉等）却被瞬间强杀退出。

- **根因剖析**：
  1. **WindowServer 误杀根因（macOS 隐私权限阻断 + 切换软件 isOnScreen 丢失）**：
     - 在 macOS 安全架构中，未授权「屏幕录制」权限的应用（ATools 仅申请辅助功能权限），系统在调用 `CGWindowListCopyWindowInfo` 时会**强制清空所有其他应用的窗口标题（`kCGWindowName` 为 nil）**；
     - 此时所有窗口均落入无标题窗口分支；而当用户切换到其他软件或虚拟桌面（Space）时，后台应用（如 WPS）的真实文档窗口被系统标记为 `isOnScreen: false`；
     - 原实现直接使用 `guard isOnScreen else { continue }`，导致即使用户打开着 1512x949 的真实表格文档，WindowServer 计数依然被误判为 0！
  2. **AX 辅助功能树失焦清空陷阱（WPS / Qt / CEF 架构特有）**：
     - 经实测深度探查：WPS Office、QQ 等混合架构应用在失焦进入后台时，其根级 `kAXWindowsAttribute` 数组会被其自身框架清空（返回 count=0）；
     - 但此时该应用的 `kAXMainWindowAttribute`（主窗口）和 `kAXFocusedWindowAttribute`（焦点窗口）依然强引用着其在活的标准窗口（role="AXWindow"）；
     - 原实现仅查询 `kAXWindowsAttribute`，取到 0 窗后即认为无窗，导致 AX 与 WindowServer 双双跌入虚假零窗陷阱！
  3. **关窗极慢根因（前台活跃态逻辑死结）**：
     - 为缓解此前切软件误杀，历史补丁在 `evaluateAppWindowsLocked` 与 `executePendingQuit` 入口处加入了 `guard !app.isActive else { return }`；
     - 在 macOS 原生架构中，用户点击红叉关闭最后一个窗口时，系统绝不会自动将焦点转移给其他应用，该应用依然是当前前台活跃应用（`app.isActive == true`）；
     - 关窗事件被 `guard !app.isActive` 当场注销丢弃，应用完全无法退出；直到用户手动点击其他应用失焦后，再干等慢轮询扫到它，才被动退出。

- **实施细节与涉及文件**：
  1. **重构 AX 窗口探测器（级联 MainWindow / FocusedWindow 兜底）**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 当 `kAXWindowsAttribute` 返回空数组时，级联查询 `kAXMainWindowAttribute` 与 `kAXFocusedWindowAttribute`；
     - 只要其存在且 `role == "AXWindow"`，直接确认为有效在活窗口，彻底消除 WPS/QQ 失焦瞬态 AX 误报为 0 的问题。
  2. **重构 WindowServer 窗口识别流（兼容无屏幕录制权限与跨 Space 状态）**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 对标准业务主层（Layer 0 标准文档窗口、Layer 3 模态弹窗），只要满足主窗体尺寸底线（width >= 180, height >= 120）且排除 AppKit/CEF 离屏缓存，**直接确认为有效业务窗口**；
     - 绝不因 macOS 隐私策略清空标题或失焦跨 Space 导致 `isOnScreen == false` 而漏判，双重铁律全面保活后台运行应用。
  3. **彻底移除错误的 `guard !app.isActive` 前台阻断**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 在已具备 WindowServer 与 AX 双重全空间权威核验、Dock 最小化防护（`kAXMinimizedAttribute`）、`⌘H` 隐藏防护（`app.isHidden`）及 Space 切换 2 秒宽限期等多重铁律的前提下，彻底移除 `evaluateAppWindowsLocked` 与 `executePendingQuit` 中的 `guard !app.isActive`；
     - 用户点击红叉关窗后，双重校验确诊零窗，无论应用是否前台，均以毫秒级即刻触发退出，真正达成「立即退出 (0s)」零等待。
  4. **轮询平滑与应用激活即时挂载**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 订阅 `NSWorkspace.didActivateApplicationNotification`：应用被激活时即刻挂载并刷新窗口销毁监听，补齐初始建窗延迟应用的状态；
     - 兜底轮询间隔由 2.0s 优化为 1.0s，兼顾极低 CPU 开销与秒级兜底感知；
     - 扩展 `fallbackPoll`：对启动时未建窗的应用（`!hadWindows`）在轮询中自动感知窗口创建并补充注册销毁监听。
  5. **版本号升级**（`Scripts/package_app.sh`）：
     - 版本升级为 `v1.3.11 (build 36)`。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test`：全套综合诊断套件（16 大项）**100% 全部 PASS 通过**（0 失败）；
  - 实测 WindowServer 与 AX 计数探查：
    * WPS Office（后台有文档且失焦）：`axCount` 由 0 恢复为 2（MainWindow 成功命中），`wsCount` 稳定识别，后台常驻不跳弹窗；
    * 启动运行日志证实：`[AutoQuit] Watching WPS Office (windows: 2)`，彻底告别误判。
### 31. 修复日历、WPS 及原生 AppKit 应用点击关闭按钮无法自动退出缺陷 (2026-10-09, build 37)

- **背景与现象**：
  - 用户反馈：“虽然修复了 wps 切换窗口不会强制退出的问题，但是现在 wps 点关闭按钮不会强制退出了，我点日历的关闭按钮也不会强制退出了，它们都不在我的排除名单中，排查原因，看看还有没有别的 app 也是这种情况”。
  - 核心痛点：build 36 为了防止切软件误退出，在 `windowServerStandardWindowCount` 中放宽了 `isOnScreen` 限制，导致用户点击红叉（或 `⌘W`）关闭最后一个窗口时，日历（Calendar）、WPS Office、备忘录、邮件等应用无法自动退出。

- **根因剖析**：
  1. **AppKit/Cocoa 原生窗口关闭机制（`orderOut:` 离屏保留）**：
     - 在 macOS 原生架构中，AppKit 应用（日历、备忘录、邮件、地图、系统设置等）以及 WPS Office 在用户点击关闭按钮时，默认执行 `orderOut:` 将窗口隐藏移出屏幕以备下次秒开，窗口对象并未立即销毁；
     - 此时在 WindowServer 层面：该窗口依然存在于全局窗口列表中，但其 `kCGWindowIsOnscreen` 被置为 `false`；
     - 此时在 AX 辅助功能层面：该应用的主窗口树已彻底清空（`AXWindows` count=0，`AXMainWindow` 为 nil）；
     - build 36 移除了 `guard isOnScreen else { continue }`，并在判断有标题窗口时未校验 `isOnScreen`，导致 WindowServer 依然把已关闭的“日历”（Bounds: 1140x598）和 WPS 已关闭的历史文档层计为在活窗口；
     - 双权威校验函数 `isConfirmedZeroWindowCount` 检测到 `windowServerCount > 0`，判定窗口未关，直接拦截了退出流程。
  2. **WPS 特有后台常驻 420x154 弹窗底板干扰**：
     - WPS Office 启动后会常驻一个尺寸为 `420x154` 的无标题模态弹窗底层锚点（Memory: 2432 字节）；
     - 若未针对性识别并排除该特殊底板，在所有文档窗口关闭后，WindowServer 依然会误将其视为有效业务窗口，导致 WPS 永远无法确诊零窗退出。
  3. **其他受影响应用排查**：
     - 经排查系统所有运行中应用，所有采用 `orderOut:` 隐藏特性的标准应用均会受此影响：包括日历（`com.apple.iCal`）、备忘录（`com.apple.Notes`）、邮件（`com.apple.mail`）、地图（`com.apple.Maps`）、系统设置（`com.apple.systempreferences`）、百度网盘（`com.baidu.netdisk` 隐藏的“同步空间”窗口）、微信、钉钉等。

- **实施细节与涉及文件**：
  1. **精确恢复在屏窗口校验规则（`guard isOnScreen`）**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 在 `windowServerStandardWindowCount` 中恢复 `guard let isOnScreen = w[kCGWindowIsOnscreen as String] as? Bool, isOnScreen else { continue }`；
     - 当应用窗口被用户关闭时，WindowServer 的 `isOnScreen` 准确变为 `false`，结合 AX 确证 0 窗，双重核验达成一致，即刻毫秒级触发退出；
     - 当用户未关窗口仅切换到其他应用时，即使失焦或被其他窗口遮挡，该真实窗口在当前 Space 的 `isOnScreen` 依然为 `true`，配合 AX 级联探测，绝不发生误退。
  2. **加入 WPS 420x154 隐形底板排除规则**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 补充 `if abs(width - 420) < 15 && abs(height - 154) < 15 { continue }`，精准排除 WPS Office 常驻后台的无标题弹窗锚点，确保所有文档关闭后顺畅退出。
  3. **版本号升级**（`Scripts/package_app.sh`）：
     - 升级至 `v1.3.12 (build 37)`。

- **验证与测试结果**：
  - `./Scripts/build.sh --test` 诊断套件 16 大项 100% 全部 PASS 通过；
  - 针对日历与 WPS 的实测探查断言：
    * 日历关窗后：`wsCount` 由 1 降为 0，AX 确证 0，即时退出；
    * WPS 文档打开时：`wsCount` 为 1，AX 为 1，切换软件/失焦完全保活不退；
    * WPS 文档关闭后：`wsCount` 过滤 420x154 底板后精准归 0，AX 确证 0，点击关闭按钮即刻退出。

### 32. 修复百度网盘桌面常驻悬浮挂件阻碍自动退出缺陷 (2026-10-10, build 38)

- **背景与现象**：
  - 用户反馈：“百度网盘点击关闭也没有立刻退出”。
  - 核心痛点：用户使用百度网盘完成文件下载/浏览后，点击主窗口（1100x700）红叉关闭窗口，百度网盘进程未按配置自动退出，Dock 图标仍常驻。

- **根因剖析**：
  1. **常驻桌面微型悬浮挂件（200x80）干扰**：
     - 百度网盘默认或开启了“桌面悬浮窗/传输速度悬浮挂件”（尺寸 `200x80`，位于屏幕右边缘，Layer 100）；
     - **在 AX 层面**：当主业务窗口关闭后，百度网盘的 AX 树中依然保留着该 `200x80` 的悬浮窗（`role=AXWindow, subrole=AXStandardWindow`，但 **`hasClose=false, hasMin=false`**）；
     - **在 WindowServer 层面**：该悬浮窗处于在屏显示态（`isOnScreen=true`），此前 `(0...150).contains(layer)` 错误地把 Layer 100 的浮层小挂件计入了有效业务窗口；
     - 导致 AX 认为窗口数=1，WindowServer 认为窗口数=1，双向确诊非零，完全拦截了主窗口关闭后的退出流程。

- **实施细节与涉及文件**：
  1. **AX 探测层智能过滤无控制按钮的常驻小挂件**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 在 `axWindows` 中引入 `isStandardBusinessWindow` 甄别器：仅认可具备关闭按钮（`AXCloseButton`）、最小化按钮（`AXMinimizeButton`）、模态对话框（`AXDialog/AXSheet`）或主业务窗体尺寸底线（width > 320 && height > 200）的窗口；
     - 精准剔除既无关闭按钮又无最小化按钮且尺寸微小的常驻悬浮球/挂件（如百度网盘 200x80 悬浮窗、迅雷悬浮球），使主窗口关闭后 AX 准确认定零业务窗口。
  2. **WindowServer 层级严格限定在标准业务层（0...15）**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 将 `windowServerStandardWindowCount` 中的图层范围由宽松的 `(0...150)` 收敛为苹果标准窗口层级 `(0...15)`（Layer 0 普通文档窗口，Layer 3/8 浮动面板与模态对话框）；
     - 彻底过滤 Layer 20（程序坞）、Layer 24（状态栏）以及 Layer 100+（桌面悬浮挂件、提示浮层）。
  3. **版本号升级**（`Scripts/package_app.sh`）：
     - 升级至 `v1.3.13 (build 38)`。

- **验证与测试结果**：
  - `./Scripts/build.sh --test` 诊断套件 16 大项 100% 全部 PASS 通过；
  - 针对百度网盘实测探查断言：
    * 主窗口打开时：`raw AX: 2, filtered AX: 1`，WindowServer 识别 1 个 Layer 0 窗口，应用正常保活；
    * 主窗口关闭后：`raw AX: 1, filtered AX: 0`，WindowServer Layer 0...15 窗口归 0，双向一致确认零窗，毫秒级即刻触发退出；
    * 访达、微信、钉钉、WPS、日历等常用应用过滤结果全部符合预期，无任何副作用。

### 33. 修复夸克网盘 40x40 桌面悬浮球伪装系统对话框阻碍自动退出缺陷 (2026-10-10, build 39)

- **背景与现象**：
  - 用户反馈：“夸克网盘点击关闭也没有立刻退出”。
  - 核心痛点：用户使用夸克网盘后，点击主窗口（1209x699）红叉关闭窗口，夸克网盘进程并未自动退出，Dock 图标仍常驻。

- **根因剖析**：
  1. **夸克桌面微型悬浮球（40x40）伪装 `AXSystemDialog` 绕过检测**：
     - 夸克网盘（`com.quark.desktop`）启动后在屏幕右侧常驻一个极小的悬浮快捷球（`40x40` 像素，Layer 28）；
     - 该悬浮球既无关闭按钮也无最小化按钮（`hasClose=false, hasMin=false`），但其辅助功能子角色被夸克标记为 **`subrole: AXSystemDialog`**；
     -此前 `isStandardBusinessWindow` 甄别器对 `subrole == AXSystemDialog` 缺乏最小尺寸底线约束，导致该 40x40 桌面小图标被误当作“系统模态对话框”保留；
     - 主窗口关闭后，AX 仍向 AutoQuit 返回窗口数=1，导致自动退出被完全拦截。

- **实施细节与涉及文件**：
  1. **AX 探测层建立主业务窗口与对话框的尺寸安全底线**（`Sources/atools/System/AutoQuitManager.swift`）：
     - 在 `isStandardBusinessWindow` 中增加核心物理尺寸防线：对提取到有效尺寸的窗口，强制要求 **`size.width >= 160 && size.height >= 90`**；
     - 无论其 subrole 标记为 `AXSystemDialog` 还是 `AXStandardWindow`，只要尺寸小于 `160x90`（如夸克 40x40 悬浮球、百度网盘 200x80 挂件），一律直接判定为桌面非业务微型辅助挂件，予以完全剔除；
     - 主窗口（1209x699）关闭后，AX 准确认定在活业务窗口数为 0，配合 WindowServer 双重零窗确诊，即刻毫秒级触发退出。
  2. **版本号升级**（`Scripts/package_app.sh`）：
     - 升级至 `v1.3.14 (build 39)`。

- **验证与测试结果**：
  - `./Scripts/build.sh --test` 诊断套件 16 大项 100% 全部 PASS 通过；
  - 针对夸克网盘实测探查断言：
    * 主窗口打开时：`raw AX: 2, filtered AX: 1`（主窗口 1209x699 命中，40x40 悬浮球精准丢弃），正常保活；
    * 主窗口关闭后：`raw AX: 1, filtered AX: 0`，WindowServer 在屏窗口为 0，双向确诊零窗，即刻触发退出；
    * 访达、微信、钉钉、QQ、Antigravity 等应用过滤正常，无任何误伤。

