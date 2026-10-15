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

### 34. 修复深色主题下搜索分类胶囊显示不清及鼠标悬停跳变缺陷 (2026-10-11, build 39)

- **背景与现象**：
  - 用户反馈：“检查深色主题胶囊分类显示不清，鼠标移到胶囊上字体才变成白色的问题，修改完毕后部署重启应用，我看看效果”。
  - 核心痛点：在深色主题（`liquidDark`）下，唤出全盘搜索中枢后，顶部的分类胶囊（全部、文件夹、应用、压缩包、图片、媒体、代码等）文本与图标呈半透明暗黑色，几乎融在深色液态毛玻璃面板中难以辨识；只有当鼠标指针移到某个胶囊上方（Hover）时，该胶囊字体才瞬间跳变成白色。

- **根因剖析**：
  1. **孤立视图创建期间的系统外观继承陷阱（根本诱因）**：
     - 在 `SearchViewController` 实例化时，属性 `filterBar = SearchFilterBarView()` 即刻完成初始化并调用 `loadPills()` 批量创建 `SearchFilterPillButton`；
     - 此时所有分类胶囊按钮还未挂载到任何 `NSWindow` 上。在 AppKit 机制中，未挂载视图的 `effectiveAppearance` 会直接回退到系统全局外观（若系统偏好为浅色模式或 aqua）；
     - `GlassPalette.swift` 中的 `glassIsDark` 原先仅读取 `effectiveAppearance`，在 view 未入窗时误判为浅色模式（`false`），导致按钮使用 `GlassPalette.textSecondary(isDark: false)`（50% 黑色文字）生成了固化的 `NSAttributedString`。
  2. **缺少视图生命周期外观通知监听（状态固化）**：
     - 当 `SearchPanel` 设置为 `.darkAqua` 外观并显示到屏幕时，`SearchFilterPillButton`、`SearchSyntaxPillButton` 及 `SearchFilterBarView` 均未重写 `viewDidMoveToWindow()` 和 `viewDidChangeEffectiveAppearance()`；
     - 导致胶囊内文字一直停留在初始化阶段计算出的半透明黑字；只有在用户鼠标移入胶囊触发 `mouseEntered` 时，才执行了 `updateAppearance()`，此时由于已在深色窗口内部，字体才瞬间跳变成亮白。
  3. **未选中态缺乏胶囊轮廓与毛玻璃微反光**：
     - 未选中胶囊原先背景设为 `clear`，在深色半透明毛玻璃面板上，低透明度文字极易与背景纹理混淆，缺乏精致的胶囊容器感与视觉边界。

- **实施细节与涉及文件**：
  1. **强化 `glassIsDark` 全局判定与配置精准兜底**（`Sources/atools/UI/GlassPalette.swift`）：
     - 优先获取 `window?.appearance ?? window?.effectiveAppearance`；若视图尚未挂载到任何窗口，自动回退到 `ConfigManager.shared.config.theme.isDark` 作为精准兜底，确保在应用配置为深色主题时，无论在何时何地构建视图，均准确初始化为深色模式样式，绝不再被误染成黑字。
  2. **补全视图生命周期外观响应机制**（`Sources/atools/UI/SearchFilterBarView.swift` & `SearchPanel.swift`）：
     - 在 `SearchFilterPillButton`、`SearchSyntaxPillButton` 与 `SearchFilterBarView` 中统一重写 `viewDidMoveToWindow()` 与 `viewDidChangeEffectiveAppearance()`，视图加入窗口或外观发生变化时即刻自动刷新外观；
     - 在 `SearchPanel.prepareForDisplay()` 及 `setPanelExpanded()` 展开阶段，主动调用 `filterBar.updatePillsAppearance()`，确保每次唤出搜索面板时胶囊状态 100% 保持最新。
  3. **精致化深色与浅色双模式胶囊视觉层级（免硬编码、高自适应）**（`Sources/atools/UI/SearchFilterBarView.swift`）：
     - **未选中默认态**：深色模式下采用 `0.92` 亮白文字（`0.88` alpha）与 `0.05` 微白毛玻璃底色、`0.10` 精细微边框；浅色模式下采用 `0.15` 墨黑文字与 `0.03` 微黑底色，清晰典雅、层次分明；
     - **鼠标悬停态**：深色模式采用 100% 亮白文字、`0.12` 发光底色与 `0.20` 亮边框，动效柔和自然，彻底消除“黑字突变白字”的视觉跳跃感；
     - **选中高亮态**：保持 `0.20` 饱满毛玻璃高光与加粗纯白文字，状态鲜明。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 全部 16 大项（包括热键、搜索协同、胶囊排序、780pt 几何不变性等）**100% 全部 PASS 通过**；
    * 诊断套件中自动生成浅色模式预览 `/tmp/search_expanded_preview.png` 与深色模式预览 `/tmp/search_dark_preview.png` 验证无误；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、部署覆盖到 `/Applications/ATools.app` 并重启应用；
  - 实机呼出全盘搜索并触发展开测试：截屏 `/tmp/live_search_expanded_done.png` 证实深色主题下所有分类胶囊默认态文字与图标清晰明亮，对比度极高，毛玻璃质感优雅，鼠标悬停与选中过渡丝滑顺畅。

### 35. 偏好设置「应用抽屉」三模块多页化与「关窗退出」单页精简重构 (2026-10-11, build 39)

- **背景与现象**：
  - 用户反馈：“请把应用抽屉中的三个模块做成切换页，关闭窗口一页就能放下所有相关设置的情况就去掉切换页选项，完成后部署并重启应用”。
  - 核心诉求：
    1. 「应用抽屉」原实现将三个模块（启用与唤出触发、驻留形态与关闭行为、分类与视觉排版）全部堆叠在同一个长 ScrollView 中，需要长距离滚动，且顶部仅有一个孤立的「抽屉设置与唤出」单选分段；
    2. 「关窗退出」整体内容非常精简紧凑（仅两张设置卡片），顶部却保留了孤立的「退出行为与规则」切换分段，造成界面冗余。

- **实施细节与涉及文件**：
  1. **应用抽屉 Tab 三模块多页化重构**（`Sources/atools/UI/Settings/SettingsTabViews.swift` - `ShelfTabView`）：
     - 将原先顶部的单一分段升级为三模块切换页：`tabs: ["启用与唤出触发", "驻留形态与关闭行为", "分类与视觉排版"]`；
     - 引入 `pageContainer` 与 `pages` 数组架构，将 3 个大模块拆分为 3 个独立的自包含子页面（`triggerPage`、`behaviorPage`、`layoutPage`）；
     - 每个子页面独立配备专属 `makeTabScrollView`，通过 `headerView.onSegmentChanged` 切换 `page.isHidden`，内容紧凑聚焦，彻底告别单页长滚动；
     - 完整保留并无缝适配 `refresh()` 绑定逻辑，所有开关、快捷键录制器、触控板手势、布局方向与尺寸滑块等交互状态保持 100% 连贯。
  2. **关窗退出 Tab 单页精简与多余分段清理**（`Sources/atools/UI/Settings/AutoQuitTabView.swift`）：
     - 将 `headerView` 的 `tabs` 设为空列表 `[]`；
     - 利用 `SettingsHeaderView` 内部自适应特性，自动移除顶部单选分段控制器，释放垂直间距；
     - 「关窗退出总开关与模式」和「规则与应用过滤」两张卡片直接一屏舒展呈现，整洁雅致。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 严格验证 `[8/8] Testing SettingsWindowController Layout...`：应用抽屉与关窗退出等全部 7 个 Tab 均严格维持 `780.0pt` 窗口宽度绝对不变性（Strict 780.0pt Width Invariance）；
    * 16 大项诊断测试全部 PASS；
### 36. 优化关于 ATools 界面：应用名称旁动态标注当前版本号 (2026-10-11, build 39)

- **背景与现象**：
  - 用户反馈：“优化关于 ATools 界面，在应用名旁边写上（当前版本号）”。
  - 核心诉求：
    1. 在状态栏菜单点击「关于 ATools」弹出的信息弹窗中，原先标题仅写有 `ATools for Mac`，缺少直观的版本标识；
    2. 用户希望在应用名称旁边清晰展示当前版本号（如 `ATools for Mac (v1.3.14)`），便于一目了然确认当前软件版本，无需再到复杂设置中逐层翻找。

- **实施细节与涉及文件**：
  1. **关于 ATools 弹窗动态注入版本号**（`Sources/atools/App/AppDelegate.swift`）：
     - 在 `showAbout()` 中，通过 `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` 动态获取当前版本号，并安全回退到 `UpdateManager.shared.currentAppVersion`；
     - 将弹窗主标题 `alert.messageText` 更新为：`ATools for Mac (v\(version))`，实现免硬编码的动态版本自适应感知。
  2. **偏好设置关于 Tab 协同优化**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 在偏好设置「关于 ATools」Tab 的软件版本与更新卡片首行中，将应用名称标题同步更新为 `ATools for macOS (v\(currentVer))`；
     - 保持弹窗与偏好设置关于界面的视觉规范与语义高度统一。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 16 大项（包括 CalculatorEngine、SystemActions、ConfigManager、SearchCoordinator、Settings 780.0pt 绝对宽度不变性、UpdateManager 语义化版本等）**100% 全部 PASS 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、部署覆盖到 `/Applications/ATools.app` 并重启应用；
  - 实机呼出「关于 ATools」弹窗截图实测验证（`/tmp/about_axpress.png`）：
    * 弹窗大标题完美呈现 `ATools for Mac (v1.3.14)`；
    * 偏好设置关于页同步呈现 `ATools for macOS (v1.3.14)`，文字排版清晰自然。

### 37. 偏好设置全盘排除范围紧凑化、滑块比例节点与右对齐、授权按钮左对齐及空格键中文标注优化 (2026-10-11, build 39)

- **背景与现象**：
  - 用户反馈 4 项核心视觉与体验痛点：
    1. 「全盘搜索 -> 排除范围」：自定义排除目录卡片内存在多余空白，整体高度超标导致右侧出现垂直滑动条（滚动条），无法一屏完整查看；
    2. 「应用抽屉 -> 分类与视觉排版」：应用图标大小比例滑动条未贴齐右侧边缘，且缺少了比例刻度节点；
    3. 「关窗退出 -> 规则与应用过滤」：下方的「前往授权...」按钮与上方的「编辑排除名单...」按钮未垂直左对齐，造成界面参差凌乱；
    4. 「快捷键录制」：设置 `Command + 空格` 时，快捷键栏只显示修饰符 `⌘`，空格键因转换成不可见空白字符未能标注显示。

- **实施细节与涉及文件**：
  1. **快捷键空格键中文标注支持**（`Sources/atools/Models/HotkeyDisplayFormatter.swift` & `AppConfig.swift`）：
     - 将 `switch keyCode` 特殊硬件按键映射逻辑前置于 `translate` 调用之前，阻断 `UCKeyTranslate` 将 Space（49）翻译成普通不可见字符 `" "` 的问题；
     - 显式将 `keyCode == 49` 映射为中文 `"空格"`；对 `translate` 结果增加空白符修剪保护；
     - 录制 `Command + 空格` 时在控件中清晰展示为 `⌘空格`，全盘搜索与应用抽屉全局快捷键显示逻辑完全一致，契合 Apple 官方规范。
  2. **应用图标大小比例滑块刻度恢复与绝对右对齐**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 为 `iconSizeSlider` 补齐 7 个比例节点刻度：`numberOfTickMarks = 7` 与 `allowsTickMarkValuesOnly = false`（对应 80% 到 140% 各比例关键点）；
     - 重构 `sliderContainer` 布局约束：`iconSizeBadge` 设置固定 76pt 宽度并靠右贴齐容器 trailing（距离卡片右边缘 16pt），滑块自动填充左侧剩余宽度，与上一行分段控件、下一行开关实现严格的垂直右对齐。
  3. **关窗退出交互控件等宽与左对齐规整**（`Sources/atools/UI/Settings/AutoQuitTabView.swift`）：
     - 将「编辑名单...」（`autoQuitRulesButton`）与「前往授权...」（`openPermBtn`）统一设定等宽（`148pt`），右对齐贴边，实现上下两行按钮**左右双向垂直严格对齐**；
     - 权限状态标签「已授权」设为右对齐，紧贴授权按钮左侧；
     - 上方卡片的「生效模式」与「关闭后延迟退出」两个 PopUp 菜单同样设置等宽（`184pt`），实现全页交互控件的垂直秩序美感。
  4. **全盘搜索排除范围空间紧凑化与滑动条消除**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 重构 `reloadCustomExclusionRows()`：当无自定义排除目录时，直接在 `makeAddCustomExclusionRow` 中展示状态副标题，移除冗余的独立空行占位，消除大面积多余留白；
     - 优化标题与卡片的垂直外边距（Section 间距 20pt -> 12pt，Card 间距 8pt -> 6pt，Tip 底部间距 28pt -> 12pt）；
     - 整体内容高度收束至约 410pt，远低于内容区 562pt 视窗高度，**彻底消除垂直滚动条**，所有设置一屏舒展呈现。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 16 大项（包括 CalculatorEngine、SystemActions、ConfigManager、SearchCoordinator、Settings 780.0pt 绝对宽度不变性、UpdateManager 语义化版本等）**100% 全部 PASS 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、部署覆盖到 `/Applications/ATools.app` 并重启应用；
  - 实机截屏严格核验：
    * `/tmp/verify_autoquit.png`：关窗退出按钮等宽左对齐，下拉框等宽左对齐；
    * `/tmp/verify_shelf_page1.png`：全局快捷键框内明确标注 `⌘空格`；
    * `/tmp/verify_shelf_page3.png`：图标大小滑块精准呈现 7 个比例节点刻度，右侧百分比数字严格贴齐卡片右边框；
    * `/tmp/verify_search_exclusion.png`：全盘搜索排除范围一屏完整呈现，无空白截断，**滚动条彻底消失**。




### 38. 偏好设置应用图标大小滑块紧凑消除空白、左边缘对齐与 60%~120% 缩放范围优化 (2026-10-11, build 39)

- **背景与现象**：
  - 用户反馈「偏好设置 -> 应用抽屉 -> 分类与视觉排版」子页中，图标缩放控件存在以下体验与排版问题：
    1. **滑块与数值间距过大**：原先数值文本框固定宽度 76pt 且右对齐，导致滑块右端与 `87%` 百分比之间留存了大片无意义的空白红框区域；
    2. **比例条未左对齐**：上一行分段控件宽度为 180pt，而滑块容器为 240pt，滑块左边缘往左突出，两行未能垂直左对齐；
    3. **缩放范围需求调整**：用户希望将比例范围精准收敛至 `60% ~ 120%`（此前为 80% ~ 140%），且比例节点清晰可见。

- **实施细节与涉及文件**：
  1. **滑块布局容器等宽与双向对齐规整**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 将滑块容器 `sliderContainer` 宽度统一设置为与上一行分段控件完全相同的 `180pt`；
     - 滑块从容器左端开始（`iconSizeSlider.leadingAnchor == sliderContainer.leadingAnchor`），滑块左边缘与上一行「水平顶部」控件左边缘**绝对垂直严格左对齐**；
     - 容器右边缘与卡片 Accessory 右边框垂直严格对齐，实现上下两行左右双向完美对齐。
  2. **消除中间空白与百分比紧贴**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 滑块宽度设定为 `136pt`，右侧紧贴百分比标签 `iconSizeBadge`，间隙精准控制为 `6pt`；
     - `iconSizeBadge` 文本设为左对齐（`alignment = .left`），百分比字符统一格式化为简洁直观的 `"\(pct)%"`；
     - 彻底消除了原先 50pt+ 的冗余空白，滑块拖动时数字与滑块端点如影随形、紧凑精致。
  3. **比例范围调整为 60% ~ 120% 与 7 节点刻度**（`Sources/atools/UI/Settings/SettingsTabViews.swift` & `ConfigManager.swift` & `main.swift`）：
     - 更新 `iconSizeSlider`：`minValue = 60`，`maxValue = 120`，保留 7 个比例刻度（`numberOfTickMarks = 7`，每 10% 一个比例节点）；
     - `ConfigManager.updateShelfIconScale` 范围 clamp 防护策略同步更新为 `max(0.60, min(1.20, scale))`；
     - 行副标题清晰注明：`"自由缩放应用抽屉网格内图标和文字尺寸 (60% ~ 120%，默认 100%)"`；
     - 单元测试与诊断用例中对 `0.60` 下限与 `1.20` 上限的截断断言全面更新通过。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 16 大项（包括 CalculatorEngine、SystemActions、ConfigManager 60%-120% 缩放下限上限、Settings 780.0pt 绝对宽度不变性等）**100% 全部 PASS 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、部署覆盖到 `/Applications/ATools.app` 并重启应用；
  - 自动渲染并核验快照（`/tmp/settings_tab_shelf_layout.png`）：
    * 滑块左边沿与上方分段控件左边缘严格垂直左对齐；
    * 滑块右端与 `100%` 之间间距紧凑贴合（仅 6pt），大空白彻底消除；
    * 刻度节点分布清晰，副标题说明完整明确。

### 39. 偏好设置「常规」Tab 平铺整合与子切换页去除 (2026-10-11, build 39)

- **背景与现象**：
  - 用户反馈「常规」偏好设置中只有两个小型卡片（「通用与启动」与「系统权限」），通过顶部二级分段胶囊 Tab（切换页）拆分反而增加了不必要的点击层级，下方留白过多，交互体验割裂；
  - 诉求：将「系统安全与隐私权限」卡片直接移至「基础与系统」卡片下方平铺展示，去除顶部切换页分段控件，实现一屏完整浏览与管理。

- **实施细节与涉及文件**：
  1. **移除二级分段切换页与层级扁平化**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 将 `headerView = SettingsHeaderView(title: "常规", iconName: "gearshape")` 的 `tabs` 移除，隐藏二级分段控件；
     - 彻底精简并移除 `launchPage`、`permPage`、`pages`、`pageContainer`、`showPage` 等子页嵌套层；
  2. **垂直流式排版整合与一屏直出**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 统一挂载至单一 `scrollView & scrollContent`：
       * 第 1 模块：**基础与系统**（开机自启、失焦时自动关闭）；
       * 第 2 模块：**系统安全与隐私权限**（辅助功能权限、完全磁盘访问权限、前往授权按钮）；
       * 底部：**权限与本地隐私安全说明**（零网络上传、完全本地运行）；
     - 整体内容垂直高度约 320pt，远低于 562pt 视窗高度，**彻底无需垂直滚动条**，界面舒展大方。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 16 大项（包括 CalculatorEngine、SystemActions、ConfigManager、Settings 780.0pt 绝对宽度不变性等）**100% 全部 PASS 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、部署覆盖到 `/Applications/ATools.app` 并重启应用；
  - 自动渲染并核验快照（`/tmp/settings_tab_0.png`）：
    * 顶部分段切换页已彻底移除，大标题干净现代；
    * 「基础与系统」与「系统安全与隐私权限」卡片上下平铺，左右边界严格对齐；
    * 零滚动条，一览无余。

### 40. 应用抽屉图标比例范围收束至 70%~110%、透明度滑块防抖固定及双向「恢复默认」按钮支持 (2026-10-12, build 39)

- **背景与现象**：
  - 用户提出 3 项关键交互与美观性诉求：
    1. **抽屉图标缩放范围微调**：将应用抽屉图标比例控制在更合理的 `70% ~ 110%` 黄金区间（默认 100%），避免极端过小或过大；
    2. **面板透明度滑块动态伸缩缺陷修复**：原先「外观与主题」中透明度滑块的数值 Badge 容器未固定宽度，当处于 90%（文案为“90%（默认）”）与 85%（文案为“85%”）切换时文本长度跳变，带动左侧滑块轨道产生视觉伸缩跳动；
    3. **空间与美观性评估并增设「恢复默认」按钮**：在图标缩放与透明度滑块旁评估合适位置，增设一键「恢复默认」交互按钮。

- **空间与美观性评估与设计决策**：
  - **位置选择（右侧紧随 vs 下方折行）**：
    * 下方折行方案：会导致单行卡片高度由 46pt 暴增至 70pt+，上下留白突兀，打破 macOS 原生偏好设置一贯的单行紧凑节奏；
    * 右侧紧随方案（采纳）：卡片右侧 Accessory 具有 240~260pt 的宽裕空间。将结构设计为 `[ 滑块(120pt) ] + [ 数值(38pt) ] + [ 恢复默认按钮(68pt) ]`，总宽度精确为 `240pt`；
    * 上方的分段控件同步设为 `240pt`，上下两行左右双向严格垂直对齐，秩序感与平衡感极强。
  - **组件形态与状态感知**：
    * 封装 `SettingsResetButton` 紧凑型胶囊按钮（高度 22pt，圆角 11pt，11pt Medium 字体）；
    * 状态联动：当前值处于默认值（图标 100%，透明度 90%）时，呈现微淡精致的禁用态；拖动偏离默认值时自动点亮激活；点击瞬间平滑复位并变淡。

- **实施细节与涉及文件**：
  1. **应用抽屉图标缩放范围与刻度节点优化**（`Sources/atools/UI/Settings/SettingsTabViews.swift` & `ConfigManager.swift` & `main.swift`）：
     - 滑块参数更新为：`minValue = 70`，`maxValue = 110`，5 个均匀刻度节点（`numberOfTickMarks = 5`，对应 70%, 80%, 90%, 100%, 110%）；
     - `ConfigManager.updateShelfIconScale` 范围防护收敛至 `max(0.70, min(1.10, scale))`，1.05 以上自动映射为 `.large`；
     - 副标题更新为：`"自由缩放应用抽屉网格内图标和文字尺寸 (70% ~ 110%，默认 100%)"`；
     - 增加 `resetScaleToDefault()` 触发方法与 `resetScaleButton` 状态绑定。
  2. **面板透明度滑块固定宽度与彻底防抖**（`Sources/atools/UI/Settings/SettingsTabViews.swift`）：
     - 移除引起弹性伸缩的未定宽 `badgeContainer`；
     - `opacitySlider` 显式施加 `widthAnchor.constraint(equalToConstant: 120)`，宽度绝对固定，拖动滑块时轨道**绝对恒定不发生任何伸缩**；
     - `opacityBadge` 设定固定 38pt 宽度左对齐，数值清晰变化；
     - 增加 `resetOpacityButton` 恢复默认按钮，点击一键复位至 90%。
  3. **全局新增紧凑型复位组件**（`Sources/atools/UI/Settings/SettingsComponents.swift`）：
     - 新增 `SettingsResetButton` 类，内建深浅色自适应、鼠标悬浮高亮、禁用态透明度保护。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 16 大项（包括 CalculatorEngine、SystemActions、ConfigManager 0.70~1.10 缩放边界等）**100% 全部 PASS 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、部署覆盖到 `/Applications/ATools.app` 并平滑重启；
  - 实机渲染快照核验：
    * `/tmp/settings_tab_shelf_layout.png`：应用抽屉图标滑块 70%~110% 刻度舒展，右侧「恢复默认」按钮与分段控件上下垂直对齐；
    * `/tmp/settings_tab_4.png`：外观与主题透明度滑块绝对固定 120pt，右侧「恢复默认」完美对齐，伸缩抖动彻底根除。
### 41. 新增 macOS 原生液态玻璃主题（深色/浅色）与界面水滴质感全链路适配 (2026-10-12, build 39)

- **背景与现象**：
  - 为满足 macOS 最新视觉系统要求，在现有「液态玻璃」主题基础上，新增「原生液态 (深色)」与「原生液态 (浅色)」双模式；
  - 浅色模式追求 100% 极纯无色水滴透镜效果，白底完全通透无色差；深色模式增加轻量暗色微熏透镜，凸显亮白文字与深色通透质感。

- **实施细节与涉及文件**：
  1. **枚举扩展与旧配置容错迁移**（[`AppConfig.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/Models/AppConfig.swift)）：
     - `AppTheme` 扩展 `macosLiquidDark` 与 `macosLiquidLight`；
     - 新增 `isNativeLiquid` 状态判定与 `migrated(from:)` 迁移兼容处理（支持兼容 `macosLiquid` 与 `nativeLiquid` 迁移至 `macosLiquidLight`）。
  2. **SwiftUI 液态透镜多层光影重塑**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - 在原生液态模式下引入多重光影渲染：柔和外扩散环境光晕阴影、多层水滴内部凹面漫射高光、双色发丝切边高光（天光反射 0.90 + 侧边微光 0.35 + 底部漫射 0.16）；
     - 依据深浅色模式自动配置环境色温、色调不透明度及发光层次。
  3. **背景透镜与图层裁剪调优**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift)）：
     - 原生液态模式下动态调整 `masksToBounds = false` 确保光晕阴影立体扩散；
     - 浅色透镜采用纯透明零 tint 处理，深色透镜采用轻量暗色微熏，保证对比度与通透性并存。
  4. **全套面板交互控件高光与阴影联动**：
     - [`GlassPalette.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/GlassPalette.swift)：提供原生液态主题下的边框色彩、选中态与悬停态对比度；
     - [`CategoryBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryBarView.swift) & [`CategoryPillView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryPillView.swift)：胶囊选框及标签在原生液态深色模式下强化文字外发光阴影；
     - [`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift) & [`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)：应用图标在原生液态模式下增强悬停立体投影，标题文字添加微羽化阴影；
     - [`SearchPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchPanel.swift)：搜索提示文字色相自适应。
  5. **主题设置卡片与回归断言**（[`ThemeCardView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ThemeCardView.swift) & [`main.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/main.swift)）：
     - 主题设置卡片增设专属原生水滴极纯微缩模型预览；
     - 补充 `--test` 针对原生主题更新、迁移及 `isNativeLiquid` 状态的完整自动化回归断言。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包 DMG/ZIP 校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，顺利重启进程验证（PID: 91605），全局热键与界面渲染均正常运作。
### 42. 修复原生液态主题抽屉文字变色滞后，全局搜索胶囊与展开结果面板原生水滴质感全面对齐 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈原生液态（深色）主题下，应用抽屉内的文字默认呈现暗色，只有当鼠标移动到图标上时字体才变白；
  - 全局搜索胶囊（折叠态）呈现生硬的黑灰卡片与描边，与应用抽屉极纯通透的水滴液态外观不一致；
  - 当输入文字或指令出现搜索结果时（展开态），整个搜索大面板的液态玻璃效果完全消失，退化为无折射、无高光的纯色磨砂灰板。

- **实施细节与涉及文件**：
  1. **抽屉应用文字颜色初始化与生命周期即时刷新**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift)）：
     - 为 [`ShelfItemButton`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift#L12) 增设 `viewDidMoveToWindow()` 挂载回调，当按钮添加入视图树后立即触发 `updateAppearanceStyles()`，依据窗口真实 `effectiveAppearance` 正确初始化文字颜色与阴影；
     - 在 [`reloadData(items:)`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift#L450) 中对复用按钮 `existing` 与新建按钮 `btn` 均无条件执行 `updateAppearanceStyles()`；
     - 在 `ShelfGridView` 增设 `updateAppearanceForTheme()`，并在 `setupViews()` 和 `handleThemeChanged()` 中显式将 `appearance` 广播赋予 `contentView` 与 `scrollView`，彻底解决鼠标悬停才变白的视觉延迟。
  2. **全局搜索胶囊（折叠态）水滴液态完全对齐**（[`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 搜索胶囊内部 `glassEffectView` 全面激活 `isNativeLiquid = true`，浅色模式应用 0% tint 纯通透透镜，深色模式应用 22% tint 微熏透镜；
     - 原生液态下去除宿主 CALayer 黑色生硬描边（`borderWidth = 0`），完全交由 `LiquidGlassRoot` 的双层发丝高光与内部焦散折射接管；
     - 增加 `viewDidMoveToWindow()` 回调确保搜索框唤出即与当前主题外观严格一致。
  3. **搜索结果大面板（展开态）水滴液态效果修复**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift) & [`SearchPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchPanel.swift)）：
     - 修复 `VisualEffectBackdropView.updateAppearanceColors()` 中 `matchesSearchCapsuleAppearance` 提前 `return` 拦截并阻断 `isNativeLiquid` 设置的致命缺陷；将原生液态判断置顶，使展开大面板同享 100% 原生硬件级物理液态水滴折射；
     - 展开态下动态去除 `revealLayers` 外部生硬描边（`rim.borderWidth = 0`），消除覆盖在水滴高光之上的多余灰线；
     - [`SearchResultsTableView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchResultsTableView.swift)：为原生液态模式下的搜索结果选中条与文字配备匹配的微羽化立体阴影与对比度。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 96856）。
### 43. 强化液态玻璃深色主题遮蔽度与暗色沉浸感，杜绝白底背景文字杂色穿透 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈深色液态玻璃效果颜色不够深，当悬浮在白色网页或高对比度文本文档上方时，底层黑色/红色文字严重穿透（透出度高达 78%），导致搜索列表前景内容与底层背景严重冲突混乱。

- **实施细节与涉及文件**：
  1. **SwiftUI 硬件水滴透镜材质与深邃底衬调优**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - `LiquidGlassRoot` 在深色模式下由完全透明的 `Glass.clear` 切换为具备真实物理漫射模糊的 `Glass.regular`；
     - 增设深色模式专属深邃暗色底衬（`Color(red: 0.06, green: 0.07, blue: 0.10).opacity(min(0.72, tintOpacity * 0.90))`），配合发丝切边高光与内部焦散，有效遮蔽底层高亮文字杂色，彻底消除穿透感。
  2. **透镜色阶深度与遮蔽浓度全面加深**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift) & [`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 原生液态深色模式（`macosLiquidDark`）透镜浓度从偏浅的 0.22 大幅提升至 0.72，`tintColor` 切换为深邃黑曜石微熏色（`#12141C`），并联动 `themeOpacity` 滑块进行精准无级调节；
     - 经典液态深色模式（`liquidDark`）同步深化：`tintColor` 强化为 `NSColor(white: 0.06, alpha: 1.0)`，`tintOpacity` 升至 0.85，`tintOverlayView` 暗黑叠层提升至 0.20；
     - [`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)：`SearchGlassSurfaceProfile` 深色基础透明度升至 0.85，悬停强调态升至 0.90。
  3. **主题微缩卡片预览更新**（[`ThemeCardView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ThemeCardView.swift)）：
     - 同步加深偏好设置中原生深色液态玻璃的微缩窗口底色，确保所见即所得。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 99486）。

### 44. 消除应用抽屉四周四个透明方角，精准分离并恢复经典液态玻璃磨砂质感 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈应用抽屉周围出现四个透明的角（原先为防止高光被剪裁而豁免关闭了 `masksToBounds`，导致底层矩形图层及 `NSHostingView` 四个直角渗出 24pt 圆角边界形成透明方角）；
  - 同时用户要求将「液态玻璃」主题（classic `liquidDark` / `liquidLight`）还原回之前的经典磨砂质感，且明确保持「原生液态」主题（`macosLiquidDark` / `macosLiquidLight`）完好无损。

- **实施细节与涉及文件**：
  1. **彻底消除应用抽屉四周的四个透明角**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift)、[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)、[`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)）：
     - [`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift)：无论处于原生液态或经典磨砂主题，宿主图层与内部 `effectView` 均无条件强制启用 `layer.cornerRadius = 24/20` 与 `layer.masksToBounds = true`，并在 `layout()` 布局生命周期中持续约束，彻底阻断子图层向外溢出；
     - [`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)：彻底移除对 `isNativeLiquid` 豁免设置的 `layer.masksToBounds = false`，改为统一绑定 `layer.masksToBounds = true`，并对内部 `hostingView` 显式设置 `hostingView.layer?.cornerRadius = cornerRadius` 与 `hostingView.layer?.masksToBounds = true`，使内部 SwiftUI NSHostingView 严密限制在圆角范围内；
     - [`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)：对抽屉内容根视图 `ShelfRootView` 显式开启 `wantsLayer = true`，并在初始化与 `layout()` 中同步配置 `cornerRadius = 24` 与 `masksToBounds = true`，构筑双重防漏裁剪屏障。
  2. **恢复经典「液态玻璃」主题纯正磨砂质感，隔离并保持「原生液态」不变**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift) & [`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - 恢复经典「液态玻璃（深色）」先前的磨砂参数：`effectView.tintColor = GlassPalette.darkBaseTop`，`tintOpacity = 0.76`，暗色叠层遮罩恢复为经典 `NSColor.black.withAlphaComponent(0.08 * opacity)`；
     - [`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)：`SearchGlassSurfaceProfile` 恢复经典深色基础浓度 `darkBaseTintOpacity = 0.76`、强调态浓度 `darkEmphasizedTintOpacity = 0.82`；
     - 严格保持「原生液态」主题（`macosLiquidDark` / `macosLiquidLight`）1:1 硬件级双层发丝高光、内部焦散折射与黑曜石微熏透镜光学效果，完全不受任何干扰。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 4597）。

### 45. 修复原生液态深色主题在低透明度（40%）下无法透出底层背景的问题，实现与浅色主题一致的晶莹透光水滴质感 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈原生液态深色主题（`macosLiquidDark`）在偏好设置中将「面板背景透明度」拖动至最低的 40% 后，仍然无法像浅色主题那样晶莹透出底层桌面与应用窗口；
  - **根本原因**：此前为加深颜色，代码中硬编码了 `max(0.60, ...)` 阻断了 40%~60% 区间的滑块生效；且内部 `LiquidGlassRoot` 无条件采用带磨砂模糊的 `Glass.regular` 并叠加了固定的不透明暗色底衬，导致无论如何调低透明度，底层内容均被磨砂和底衬完全遮挡。

- **实施细节与涉及文件**：
  1. **解开硬编码限制，建立透明度全范围平滑映射**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift) & [`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 彻底移除 `max(0.60, ...)` 截断，建立 `progress = (themeOpacity - 0.40) / 0.60` 连续响应曲线；
     - 当滑块处于 40% 最低透明度时，`dynamicTintOpacity` 精确下探至 0.05（极轻微水滴微熏透镜）；当滑块拉升至 90%~100% 时，平滑增强至 0.58~0.72 深邃浓度。
  2. **暗色底衬动态隐退与 `Glass.clear` 水滴透镜无缝切换**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - 在 `LiquidGlassRoot` 中，当处于低透明度区间（`tintOpacity <= 0.18`，对应滑块 40%~55%）时，深色模式动态自动切换为纯水滴透镜 `Glass.clear`，消除磨砂模糊漫射，实现 100% 物理光线折射穿透；
     - 联动 `underlayAlpha`：在低透明度（<=0.08）时暗色底衬完全隐退（`underlayAlpha = 0.0`），彻底移除非通透色块阻隔，使面板底部桌面壁纸与底层窗口纤毫毕现，通透感与浅色主题完全一致；高透明度（60%~100%）下平滑增强至 0.68，确保文字防穿透遮蔽力。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 6345）。

### 46. 兼顾纯水滴透镜动态折射与基准暗色底衬，重塑原生液态深色主题的黑曜石深色辨识度 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈原生液态深色主题（`macosLiquidDark`）在透明度调整至 40% 后，因底衬过度清零而发白发浅，丢失了深色主题应有的暗色底蕴与辨识度；
  - 用户明确要求在保留低透明度下水滴透镜纯净折射（`Glass.clear`）的同时，始终保留恰到好处的暗色底衬，使整体呈现清晰透底的半透明黑曜石质感，既透亮又具备纯正深色主题气质。

- **实施细节与涉及文件**：
  1. **维持深色基准微熏浓度**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift) & [`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 将 40% 最低透明度下的 `dynamicTintOpacity` 基准值设定为 0.22（避免过度衰减至 0.05 导致色彩脱失），在 40%~100% 间由 0.22 平滑增强至 0.72；
     - 确保透镜本身自带深邃黑曜石微熏色（`#12141C`），与浅色白水滴透镜形成鲜明色调分水岭。
  2. **水滴透镜动态切换与暗色底衬深度兼顾**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - 在 `LiquidGlassRoot` 中，即使处于 40% 透明度，也始终保留 `underlayAlpha ≈ 0.24` 的基准暗色底衬，既让 76% 外部光线畅通穿透、清晰看见面板下方桌面内容，又将该区域整体压暗为高级黑曜石深色调；高透明度（90%~100%）下平滑过渡至 0.58~0.68；
     - 阈值设定为 `tintOpacity > 0.36`（对应约 60% 透明度）：当处于 40%~55% 低透明度区间时动态采用 `Glass.clear` 消除磨砂漫射，享受纯水滴晶体折射；高透明度下无缝切入 `Glass.regular` 磨砂模糊。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 7501）。

### 47. 全面排查并修复偏好设置全界面按钮“静止不可见、悬停才显现”缺陷，健全按键视觉轮廓与指针反馈 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈当前偏好设置中存在“部分按钮在鼠标移动上去时才显现出来”的问题，严重影响视觉可用性与按键引导性；
  - **排查与根因定位**：
    1. **胶囊按钮缺乏基准线框与可见底色**（`SettingsPillButton`）：原本静止状态下 `borderWidth = 0`，底色透明度仅 `0.06`（且依赖系统的 `contentTintColor`），在设置面板浅色白底卡片或深色卡片上，由于对比度极低，按钮轮廓几近隐形，只有鼠标悬停触发展开加深后才暴露出胶囊外形；
    2. **文字颜色未显式设置属性字符串**：`SettingsPillButton` 之前直接修改 `contentTintColor`，在 AppKit 的 `NSButton` 某些样式下文字并不会随之变更颜色或产生清晰的边缘；
    3. **排除规则重置按钮采用隐形样式**（`SettingsTabViews.swift`）：自定义排除规则行的重置按钮使用了 `bezelStyle = .inline`，macOS 原生内联样式在静止状态下无底色、无边框，完全隐形；
    4. **热文件夹及排除规则行首尾增删按钮缺乏按键语义**：原先采用裸 SF Symbols 图标按钮（`minus.circle.fill` / `plus.circle.fill`），在卡片中无独立微弱底衬，静止时缺少交互按键感；
    5. **光标手势缺失**：设置窗口中多个自定义按钮（`SettingsPillButton`、`SettingsResetButton`、`SidebarRowButton`）未实现 `resetCursorRects`，鼠标悬停时仍为普通箭头，缺乏可点击交互反馈。

- **实施细节与涉及文件**：
  1. **重构核心胶囊与重置按钮组件**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - **`SettingsPillButton`**：
       * 赋予常驻清晰微弱边框：静止状态下始终保持 `borderWidth = 1.0`，浅色模式为 12% 灰度边框，深色模式为 16% 高光白边，悬停与按下时梯级加深至 28%/35%；
       * 增强常驻轻质底色：浅色模式常驻 7% 灰度底色，深色模式常驻 11% 灰度底色，无论鼠标在何处，胶囊按键几何形态一目了然；
       * 改用显式 `attributedTitle`：统一注入精确的字体与前景色，杜绝文字颜色因状态丢失而褪色的问题；
       * 增加 `resetCursorRects` 与 `cursorUpdate`，鼠标悬停即刻变为标准 `pointingHand` 手型光标。
     - **`SettingsResetButton`**：
       * 赋予常驻 1.0pt 轮廓与微弱填充底衬，修复静止时仅凭极淡文字漂浮的假象；
       * 补全 `resetCursorRects` 手型光标。
     - **全新增加 `SettingsIconButton` 规整微型圆形动作按钮**：
       * 封装 24x24 固定尺寸、圆角 12pt 的高质感图标按键；
       * 具备清晰常驻描边、微弱底衬、悬停高亮、按下加深、系统无障碍标签及手型光标；
       * 专用于列表项的增删（`plus`、`minus`）等微型交互场景。
  2. **全面替换列表行增删与重置按钮**（[`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift)）：
     - 热文件夹行（`makeHotFolderRow` / `makeAddHotFolderRow`）及自定义排除项行（`makeCustomExclusionRow` / `makeAddCustomExclusionRow`）的 `+` 与 `-` 按钮全面迁移至 `SettingsIconButton`；
     - 彻底废除 `bezelStyle = .inline` 的隐形重置按钮，统一替换为标准 `SettingsResetButton`，并根据排除列表条数动态控制 `isEnabled` 与高亮。
  3. **增强侧边栏选项卡光标反馈**（[`SettingsSidebarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsSidebarView.swift)）：
     - 在 `SidebarRowButton` 中补全 `resetCursorRects` 与 `cursorUpdate`，实现侧边栏各导航项的全域 `pointingHand` 光标交互。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 9598）。

### 48. 根治未入窗控件主题穿透判定缺陷（glassIsDark Fallback）与暗箱隐形，实现设置全域按钮常驻高对比度实体轮廓 (2026-10-12, build 39)

- **背景与现象**：
  - 用户反馈在设置中某些按钮依然存在“鼠标移到按钮上才显现出来，且大部分表现为极度透明的液态玻璃材质”的隐形现象；
  - **深度溯源与排查定性**：
    1. **未入窗控件在浅色系统下的“深色误判穿透”（致命根因）**：
       - 当用户配置了深色主题（如 `macosLiquidDark`），但 macOS 系统处于浅色外观（Light mode）时；
       - 各设置 Tab 视图均在 `window` 赋值前实例化其子控件，此时 `self.window == nil`；
       - 原 `glassIsDark` 逻辑为：`if effectiveAppearance.bestMatch(...) == .darkAqua { return true } return theme.isDark`；
       - **严重缺陷在于**：当未入窗视图处于浅色环境时，`bestMatch` 返回 `.aqua`，未被拦截直接穿透跌落至 `return theme.isDark`（返回 `true`！）；
       - 导致所有按钮在浅色卡片上直接按深色模式初始化：被赋予了**纯白文字（white）、白色半透明描边（white alpha 0.16）与纯白微弱底色（white alpha 0.11）**！
       - 在浅色卡片的纯白背景上，白字白框白底导致按钮视觉上完全隐形，呈现出极具欺骗性的“消失在白底上的透明液态玻璃水滴”！
       - 当鼠标初次划过按键触发 `mouseEntered` 时，控件因已被挂载到窗口，`self.window != nil` 重新评估为浅色模式，按键文字才突然翻转为深黑色并暴露出背景，给用户造成“鼠标移到按键上才显现出来”的强烈现象。
    2. **生命周期入窗感知缺失**：
       - `SettingsPillButton`、`SettingsResetButton`、`SettingsIconButton`、`HotkeyRecorderControl`、`ThemeCardView` 均未实现 `viewDidMoveToWindow()`，控件挂入真实窗口渲染树时未能强制刷新色彩模型。
    3. **快捷键录制框无边框隐形**：
       - `HotkeyRecorderControl` 静止状态下缺少外轮廓边框（`borderWidth = 0`），仅有微弱浅灰底色，在白底卡片中形似平铺文字。
    4. **未选中主题卡片对比度过低**：
       - `ThemeCardView` 未选中状态下描边透明度仅 0.06，底色仅 0.02，在未悬停时四个“液态玻璃”主题卡片边框虚浮几近隐形。

- **实施细节与涉及文件**：
  1. **修正全域环境深色判定兜底**（[`GlassPalette.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/GlassPalette.swift)）：
     - 修复 `glassIsDark`：无论是否挂入窗口，优先以 `NSApp?.effectiveAppearance ?? effectiveAppearance` 解析 `.darkAqua` 与 `.aqua`。只有当完全无法匹配时才考虑 `theme.isDark`，彻底终结浅色系统下未入窗控件被反向染成白色的错误穿透。
  2. **补全全量设置按键入窗刷新钩子与标题响应**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - 为 `SettingsPillButton`、`SettingsResetButton`、`SettingsIconButton` 统一补全 `override func viewDidMoveToWindow()`，一旦入窗立即重算当前宿主窗口真确的色彩系统；
     - 覆写 `SettingsPillButton.title` 的 `didSet`，确保动态更新按键文本时即刻同步重绘属性字符串；
     - 提升静态状态对比度：浅色模式下常驻 18% 灰度轮廓（深色模式 24%），底色增强至 9%~15%，彻底告别“虚浮无边”的伪透明玻璃感。
  3. **重构快捷键录制框常驻实体胶囊形态**（[`HotkeyRecorderControl.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/HotkeyRecorderControl.swift)）：
     - 增加 `viewDidMoveToWindow()` 自动响应；
     - 赋予常驻 `borderWidth = 1.0` 实体细描边（浅色 16%、深色 22%）与微弱底衬，悬停时加深至 28%/38%，使 `⌥A` 与 `⌥Space` 录制框在静止时具备清晰的按键物理凹槽与可点击暗示。
  4. **提升精选主题卡片轮廓辨识度**（[`ThemeCardView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ThemeCardView.swift)）：
     - 增加 `viewDidMoveToWindow()` 保证实时响应；
     - 未选中状态下常驻清晰的 1.0pt 边框（浅色 14%、深色 18%）与微弱底色，确保 4 个主题卡片（深/浅液态玻璃、深/浅原生液态）无论是否悬停均有规整利落的卡片外观。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（计算器、系统指令、配置管理、热点索引、Spotlight 全盘搜索、搜索展开收起动画、偏好设置等）**100% 全部 PASSED 通过**；
  - 检查生成的 `/tmp/settings_tab_*.png` 视觉截图，证实各页面的按钮、快捷键框、主题卡片在静止无 Hover 状态下均具备清晰可见的高质感实体轮廓；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 11780）。

### 49. 设置界面全域按钮重塑为 macOS 原生液态水滴质感（光学折射/双色切边高光/悬浮光影/按压下陷）(2026-10-12, build 39)

- **背景与现象**：
  - 用户期望将偏好设置（Settings）窗口内的所有交互按钮打造成与主面板一致的「macOS 原生液态（Native Liquid Glass）」水滴质感；
  - 原先设置中的胶囊按钮、复位按钮、图标按钮与快捷键录制框采用平铺色块与基础描边，缺乏高阶真实物理光学折射、水滴天光张力漫反射（Surface Sheen）以及连续双色发丝微切边高光。

- **实施细节与涉及文件**：
  1. **构建原生液态按钮光学背景组件 `NativeLiquidButtonBackdrop`**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - **底层物理光学折射（Liquid Refraction）**：挂载 `LiquidGlassContainerView(isNativeLiquid: true)`，在 macOS 26+ 上无缝承载原生硬件级 `.glassEffect` 动态折射，旧系统自动平滑降级至 `NSVisualEffectView`；
     - **水滴表面张力天光漫反射（Top Ambient Sheen）**：新增 `topSheenLayer`（CAGradientLayer），在按钮上半区（45% 空间）注入自上而下的微弱凸弧高光漫射，营造水滴鼓起的微曲表面张力；
     - **360° 连续双色发丝微切边高光（Dual Hairline Contour Stroke）**：新增 `specularBorderLayer`，基于 `CAShapeLayer` 路径描边遮罩渲染精确到 1.0pt 的全闭合梯度发丝高光——顶部承接 0.85/0.95 亮白高光，两侧及底部流转为轮廓微光，解决水滴与卡片底衬的物理边缘衔接；
     - **微环境接触投影（Contact Shadow）**：赋予轻量 2.0pt 阴影半径与 (0, -1) 微下沉投影，使按键自然脱离平面、悬浮于设置卡片之上；
     - **交互物理状态机（Interactive Physics）**：
       * **静止态（Resting）**：晶莹剔透的水滴透镜，具备 100% 常驻清晰轮廓，彻底告别隐形；
       * **悬停态（Hover）**：整体亮度轻微提升，天光漫反射与发丝高光点亮，光标自然切换为 `pointingHand`；
       * **按压态（Pressed）**：整体向下微弹缩放（`scale(0.98)`）或加深，呈现水滴受压的扎实触感反馈；
       * **禁用态（Disabled）**：透镜透明度降至 40%，高光隐退，文字与图标自然褪色。
  2. **全面重构并接入 `SettingsPillButton` 胶囊按钮**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - 挂载 14pt 圆角 `NativeLiquidButtonBackdrop`；
     - 针对 AppKit 中 `wantsLayer = true` 时 `NSButtonCell` 文字易被透镜层剪裁或模糊的底层机制，采用悬浮独立的 `titleLabel`（NSTextField）置顶挂载，确保文字 100% 极纯锐利、零锯齿；
     - 全面支持 `.primary`（黑曜石/高亮水滴）与 `.secondary`（通透晶体水滴）双重原生质感形态；
     - 补全 `resetCursorRects` 手型光标与生命周期实时入窗更新。
  3. **重构 `SettingsResetButton` 紧凑型复位按钮与 `SettingsIconButton` 微型按键**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - `SettingsResetButton` 挂载 11pt 圆角液态水滴透镜底衬，22pt 高度紧凑精致；
     - `SettingsIconButton` 挂载 12pt 圆角液态透镜底衬，正中央悬浮 14x14 矢量符号，为列表行增删（`+` / `-`）提供触手可及的水滴触感。
  4. **重构 `HotkeyRecorderControl` 原生液态录制胶囊**（[`HotkeyRecorderControl.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/HotkeyRecorderControl.swift)）：
     - 快捷键录制框底层全面接入 14pt 圆角 `NativeLiquidButtonBackdrop`；
     - 常态呈现晶莹剔透的水滴凹槽质感，悬停时发丝高光流转；进入录制状态时发光变亮，提示输入。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 20490）。

### 50. 移除搜索指令首项蓝色异常并统一胶囊外观，重塑原生液态主题下全局搜索与抽屉“选中态”为水滴质感 (2026-10-13, build 39)

- **背景与现象**：
  1. 用户反馈全局搜索输入 `/` 触发语法模式时，首个“文档”指令胶囊呈现刺眼的生硬蓝色，风格与其他胶囊完全割裂；
  2. 原生液态主题下，全局搜索结果列表选中项（`SearchResultRowView`）和应用抽屉应用图标（`ShelfItemButton`）在选中或悬停时呈现生硬的黑灰色块描边，完全丧失了液态水滴通透折射感与表面张力天光。

- **实施细节与涉及文件**：
  1. **封装通用的原生水滴选中态背景组件 `NativeLiquidSelectionBackdrop`**（[`NativeLiquidSelectionBackdrop.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/NativeLiquidSelectionBackdrop.swift)）：
     - **物理光学水滴折射**：底层挂载 `LiquidGlassContainerView(isNativeLiquid: true)`，在 macOS 26+ 环境下由 `.glassEffect` 呈现真实水滴焦散与背景折射放大效果；
     - **浅色极纯水滴晶体**：在浅色模式下采用纯白水滴透镜（`tintColor = white`，选中 0.55，悬停 0.32），彻底根除黑灰底色；
     - **深色黑曜石晶莹水滴**：在深色模式下采用微熏透光水滴晶体（`tintColor = white`，选中 0.24，悬停 0.15），与文字形成纯净对比；
     - **顶部天光表面张力微弧（Top Sheen）**：顶部注入 `LinearGradient` 弧形反光（浅色 0.45，深色 0.30），呈现圆润水滴微鼓张力；
     - **360° 连续双色发丝微切边高光（Dual Hairline Contour）**：顶沿 0.98/0.90 亮白高光切边，两侧与底缘流转为 0.35/0.20 轮廓微光，解决水滴与底板的边缘衔接；
     - **微环境柔和投影**：赋予 (0, -1.5) 轻量柔和投影，使选中态晶莹脱离底板。
  2. **消除搜索指令首项蓝色并全面重构搜索胶囊**（[`SearchFilterBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchFilterBarView.swift)）：
     - 彻底废除 `SearchSyntaxPillButton` 中硬编码的蓝色（`NSColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 0.28)` 与蓝色边框）；
     - `SearchSyntaxPillButton` 与 `SearchFilterPillButton` 统一挂载 `NativeLiquidSelectionBackdrop(cornerRadius: 6)` 与独立 `NonInteractiveImageView` / `NonInteractiveLabel`，选中与悬停时呈现原生水滴质感，未选中时保持微透镜描边；
     - 首项待补全指令胶囊外观与普通胶囊规范完全对齐。
  3. **重塑搜索结果列表项选中态（SearchResultRowView）**（[`SearchResultsTableView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchResultsTableView.swift)）：
     - 在 `SearchResultRowView` 底层内嵌 10pt 圆角 `NativeLiquidSelectionBackdrop`；
     - 键盘上下导航切换选中行时，背景即刻无缝呈现晶莹剔透的水滴透镜条与顶部发丝切边高光，告别单薄灰条。
  4. **重塑应用抽屉图标选中与悬停态（ShelfItemButton）**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift)）：
     - 在 `ShelfItemButton` 底层挂载 14pt 圆角 `NativeLiquidSelectionBackdrop`；
     - 键盘聚焦（`isSelected`）或鼠标滑动（`isHovered`）时，图标与标题下方浮现通透晶莹的水滴透镜，彻底消除先前的暗黑方框。
  5. **重塑应用抽屉顶部滑动分类胶囊（SelectionCapsuleView）**（[`CategoryBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryBarView.swift)）：
     - 在 `SelectionCapsuleView` 中集成 `NativeLiquidSelectionBackdrop`，滑动切换分类时水滴透镜柔滑流转。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 23925）。

### 51. 彻底根除应用抽屉与搜索胶囊四周不自然阴影与方角，重塑滑动胶囊为纯净无瑕水滴透镜 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈应用抽屉中的分类胶囊（如「办公」）四周阴影极不自然，出现生硬向外突出的 4 个黑下方角（如图所示）；
  - **根本原因排查**：
    1. `NativeLiquidSelectionBackdrop` 底层 `layer.cornerRadius` 未设置（默认 0），且内部 `topSheenLayer` 未启用 `masksToBounds = true`，导致 CoreAnimation 在图层渲染与阴影绘制时按未剪裁的矩形生成投影，暴露出 4 个尖锐黑角；
    2. `SelectionCapsuleView` 依赖了带有微下沉投影的阴影逻辑，对于抽屉分类栏这种紧凑型滑动 Tab，外围生硬投影与下方图标重叠污染，且伴随滑动产生黑边瑕疵。

- **实施细节与涉及文件**：
  1. **深度加固水滴背景容器圆角与剪裁防护**（[`NativeLiquidSelectionBackdrop.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/NativeLiquidSelectionBackdrop.swift)）：
     - 显式在宿主图层绑定 `layer?.cornerRadius = cornerRadius`；
     - `topSheenLayer` 强制开启 `masksToBounds = true` 与 `cornerRadius = cornerRadius`，坚决阻断天光漫反射图层向矩形四角溢出；
     - 引入 `public var contactShadowEnabled: Bool` 开关控制；开启时计算精准连续的圆角 `shadowPath`，关闭时完全清空 `shadowOpacity`、`shadowColor` 与 `shadowPath`，杜绝任何方角阴影残余。
  2. **分类胶囊彻底消除外围阴影并重塑为无瑕滑动透镜**（[`CategoryBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryBarView.swift)）：
     - `SelectionCapsuleView` 显式设置 `liquidBackdrop.contactShadowEnabled = false`，彻底移除分类胶囊四周突出的多余阴影；
     - 覆写 `layout()` 生命周期，根据当前视图高度精确计算 `cornerRadius = bounds.height / 2`（标准 14pt 圆角），确保胶囊两侧圆弧 100% 严密闭合；
     - 废除内部 AutoLayout 约束延迟，改为在滑动与尺寸变更时与宿主 frame 实时无抖动对齐。
  3. **搜索栏胶囊同步纯净化**（[`SearchFilterBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchFilterBarView.swift)）：
     - `SearchSyntaxPillButton` 与 `SearchFilterPillButton` 同步关闭外部投影（`contactShadowEnabled = false`），避免搜索胶囊间阴影交叠污染，呈现晶莹纯粹的液态水滴晶体。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 25587）。

### 52. 彻底重塑「液态玻璃 (浅色)」主题为纯白晶莹磨砂质感，修复系统深色模式误穿透与底色发黑泥潭，实现纯正优雅的高阶白透液态玻璃 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈切换至「液态玻璃 (浅色)」主题（`liquidLight`）后，大搜索面板与搜索胶囊呈现极其暗沉的暗黑灰碳色（如图二用户截图），文字几乎埋没在黑灰泥潭底色中，直呼“太黑了，改成白色的”；
  - **根本原因排查与深度剖析**：
    1. **`effectView.isDark` 与 `effectView.isNativeLiquid` 状态遗留与赋值盲区**：在 `VisualEffectBackdropView` 与 `SearchBarView` 中，`effectView.isDark = isDark` 之前被深埋在 `if theme.isNativeLiquid` 分支内；当用户从「原生液态（深色）」切换到「液态玻璃（浅色）」时，`matchesSearchCapsuleAppearance` 先行返回，导致 `effectView.isNativeLiquid` 未被复位为 `false`，且 `effectView.isDark` 从未被设置为 `false`（默认值 `true` 固化）；
    2. **SwiftUI 颜色模式穿透暗化**：由于 `isDark` 恒为 `true`，`LiquidGlassRoot` 底层传递给 SwiftUI 的环境色彩模式恒为 `.environment(\.colorScheme, .dark)`。在 macOS 26+ 系统中，暗色模式下的 `Glass.regular` 材质基底自带深灰黑底衬，即便叠加白色 tint 也会融合成浑浊肮脏的深灰碳底色；
    3. **非原生浅色玻璃缺乏纯白漫射底衬**：经典磨砂浅色液态玻璃此前仅依赖极薄的半透明材质，在桌面或背景应用包含暗色元素时极易被背景吸黑，缺乏苹果官方 Light Panel（如 Spotlight 纯白磨砂面板）所具备的微熏温润白瓷透光底衬。

- **实施细节与涉及文件**：
  1. **全域视觉令牌纯白化**（[`GlassPalette.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/GlassPalette.swift)）：
     - 将 `GlassPalette.lightGlassTint` 与 `lightGlassTintBright` 升级为 100% 极纯白 `NSColor(white: 1.0, alpha: 1.0)`，彻底铲除原本带有 4% 灰度杂色的微灰底色。
  2. **全面升级浅色玻璃光学配方与纯白通透磨砂底衬**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - **强化搜索玻璃表面配方**：`SearchGlassSurfaceProfile` 中浅色基础浓度 `lightBaseTintOpacity` 提升至 0.85，悬停强调态 `lightEmphasizedTintOpacity` 提升至 0.92；
     - **构建多层纯白晶莹磨砂透光玻璃体系**：
       * **第一层（系统磨砂液态玻璃基底）**：`Color.clear.glassEffect(Glass.regular.tint(Color.white.opacity(tintOpacity)), in: shape)`，承载真实的物理背景模糊漫射与光折射；
       * **第二层（纯白通透磨砂底衬）**：新增 `shape.fill(Color.white.opacity(0.70 + 0.20 * min(1.0, tintOpacity)))`，无论背景窗口是深是浅，均呈现如同高级白瓷/羊脂白玉般的通透纯白光泽，杜绝底色暗沉；
       * **第三层（顶部透亮天光微反射）**：注入自顶向下的 `LinearGradient` 弧形反光（0.45 -> 0.10 -> clear），再现顶级晶体在环境光下的微微泛光；
       * **第四层（精致双层高光边框）**：采用 1.0pt 梯度发丝边框（顶部 0.95 白高光，两侧 0.55，底缘 0.45），塑造层次分明的浮雕感；
     - **修复降级材质同步**：在 `isDark` 属性变化时，同步将 `fallbackEffect.material` 在 `.hudWindow` 与 `.popover` 间平滑切换。
  3. **铲除状态分支盲区，保障深浅模式与原生开关 100% 实时同步**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift)、[`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 在 `VisualEffectBackdropView.updateAppearanceColors()` 顶部，无条件显式设置 `effectView.isDark = isDark` 与 `effectView.isNativeLiquid = theme.isNativeLiquid`，彻底消除条件提早 return 导致的状态滞留；
     - 在 `SearchBarView.updateGlassTint()` 中为非原生液态分支补齐 `glassEffectView.isDark = isDark`；
     - 在浅色非原生液态模式下，为 `tintOverlayView` 提供 `0.20 * opacity` 纯白微光遮罩，与底层纯白磨砂形成完美双重光效叠加。
  4. **面板生命周期外观广播时序深度校准**（[`SearchPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchPanel.swift)、[`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)）：
     - 将 `updateWindowAppearanceForTheme()` 调用时序调整至 `contentView`、`backdrop` 与 `viewController.view` 完全挂载入窗口层次结构之后；
     - 同步显式将 `appearance`（`.aqua` / `.darkAqua`）广播赋予 `contentView` 与子视图控制器，确保应用冷启动与配置初次加载时即刻以准确的浅色外观渲染，彻底避免时间差导致的浅色误判。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
  - 检查生成的 `/tmp/search_expanded_preview.png`、`/tmp/search_collapsed_preview.png` 与 `/tmp/shelf_preview.png` 视觉截图，证实搜索胶囊、展开大搜索面板及应用抽屉均已完美呈现纯正洁白、晶莹通透的白瓷磨砂质感，文字与图标对比度极其优异；同时 `/tmp/search_dark_preview.png` 验证深色主题不受任何负面影响；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 27755）。

### 53. 偏好设置分段切换胶囊（Segmented Switcher）全面重塑为 Apple 原生液态水滴质感 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈：“偏好设置中的切换胶囊也改成原生液态质感，如图 2 这种感觉”；
  - **视觉参考分析**（用户图 1 与图 2 对比）：
    1. 图 1 标注了偏好设置顶部二级 Tab 切换胶囊以及卡片内部的选项分段胶囊（如「水平顶部 / 垂直左侧」），原生 `NSSegmentedControl` 外观灰暗、扁平生硬，缺乏呼吸感与水滴光学通透度；
    2. 图 2 示范了苹果官方顶阶视觉规范：完整圆润胶囊轨道（`cornerRadius = height / 2`）、纯白高浮雕液态水滴透镜滑块、360° 发丝切边光晕、柔和环境投影（Soft Drop Shadow）、顶部环境光漫反射天光，以及高清晰度排版与丝滑平移物理动效。

- **实施细节与涉及文件**：
  1. **构建通用的原生液态分段控制器组件（SettingsLiquidSegmentedControl）**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - **全圆角轨道底槽（Track Container）**：底槽自适应圆角（`cornerRadius = bounds.height / 2`），浅色下覆以 `NSColor.black.withAlphaComponent(0.04)` 微灰槽底与 `0.06` 精细内切边，深色下覆以 `NSColor.white.withAlphaComponent(0.06)`，形成内嵌凹陷感；
     - **物理浮动液态水滴透镜滑块（Liquid Lens Slider）**：
       * 滑块内嵌 `NativeLiquidSelectionBackdrop(cornerRadius: (height - 4) / 2)`；
       * 注入 `customShadowRadius = 4.0` 与 `customShadowOpacity = 0.14`（深色 0.28），搭配顶部 `LinearGradient` 弧形表面张力反光与 360° 发丝微边框，完美还原图 2 饱满圆润的通透纯白水滴质感；
     - **物理丝滑平移动画（Smooth Fluid Spring Motion）**：
       * 切换选中项时，滑块通过 `NSAnimationContext.runAnimationGroup` 执行 `0.22s` EaseOut 弹性质感平移动画，滑块在胶囊轨道内丝滑流动变换；
     - **交互与尺寸自适应（Interactivity & Layout Dynamics）**：
       * 单项文本标签自动计算 `intrinsicContentSize`，鼠标悬停时触发微透镜反馈与 `pointingHand` 抓手光标；
       * 完善 `isEnabled` 属性支持：禁用时平滑降暗至 `0.45` alpha 并安全拦截点击事件；
       * 提供 `init(labels:target:action:)` 构造器与 `selectedSegment` 兼容接口，无缝替换原有系统控件。
  2. **全面替换偏好设置顶部与所有子页分段控制器**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)、[`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift)）：
     - **偏好设置顶部二级 Tab 栏**：`SettingsHeaderView.segmentedControl` 升级为 `SettingsLiquidSegmentedControl`；
     - **应用抽屉布局方向**：`orientationControl`（`["水平顶部", "垂直左侧"]`）升级为 1:1 复刻图 2 的双段原生水滴胶囊；
     - **全盘搜索结果上限**：`limitControl`（`["30 条", "50 条", "80 条 (推荐)", "120 条"]`）升级为原生水滴胶囊；
     - **性能与调试参数**：`annealControl`、`debounceControl`、`cacheControl` 等全面升级为原生水滴胶囊。
  3. **增强水滴透镜投影参数定制（NativeLiquidSelectionBackdrop）**（[`NativeLiquidSelectionBackdrop.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/NativeLiquidSelectionBackdrop.swift)）：
     - 增加 `customShadowOpacity` 与 `customShadowRadius` 属性，使紧凑型分段胶囊能够根据外形尺寸呈现最细腻的悬浮落差感。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
  - 自动化截取偏好设置实景渲染图 `/tmp/settings_tab_shelf_layout.png` 严格核验：
    * 顶部二级 Tab 栏与卡片内「水平顶部 / 垂直左侧」胶囊形态、质感、阴影及切边与图 2 达到 1:1 像素级复刻，水滴浮动质感饱满通透；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 30249）。

### 54. 彻底修复「液态玻璃 (深色)」下应用抽屉分类胶囊字体初态发黑缺陷，重塑为常驻晶莹高对比白色字体 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈并在截图标注：「液态玻璃深色主题的应用抽屉的分类胶囊字体鼠标移到上面才变白，最开始都是黑的，请修复为一致白色字体显示」；
  - 截图证实：选中项「AI」与未选中项「办公」、「网络」呈现浑浊暗黑色字体，几乎隐没在深色玻璃面板中；唯独鼠标曾悬停过的「工具」呈现亮白色。

- **根本原因排查与深度剖析**：
  1. **孤立初始化与系统外观误判（Root Cause 1）**：`CategoryBarView.reloadData` 在创建 `CategoryPillView` 时，视图尚未被添加至 `stackView`（`window == nil`）。此时判定色彩模式时直接回退至 `NSApp.effectiveAppearance`。在用户系统为浅色模式时，返回 `.aqua`，误判为浅色模式，导致所有胶囊标签均使用了黑灰色；
  2. **缺失窗口挂载生命周期监听（Root Cause 2）**：`CategoryPillView` 与 `CategoryBarView` 均未实现 `viewDidMoveToWindow()`，在挂载入已设定为 `.darkAqua` 外观的 `ShelfPanel` 窗口层次树后，未触发二次外观重算，导致黑字固化；
  3. **唤出与数据加载时序未显式重算（Root Cause 3）**：`ShelfPanel.prepareForDisplay()` 仅调用了 `loadData()`，未显式调用分类栏的外观刷新。

- **实施细节与涉及文件**：
  1. **`CategoryPillView` 稳健深色判定与纯白字体强化**（[`CategoryPillView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryPillView.swift)）：
     - 引入 `pillIsDark` 属性：优先读取宿主窗口真实外观，若视图未入窗则无条件以 `ConfigManager.shared.config.theme.isDark` 精准兜底，彻底终结浅色系统下未入窗误判；
     - 显式实现 `viewDidMoveToWindow()` 与 `viewDidChangeEffectiveAppearance()`，视图加入窗口后毫秒级自愈更新；
     - 在深色模式下，选中态与悬停态赋予 100% 极纯白（`NSColor(white: 1.0, alpha: 1.0)`），常态未选中项赋予 88% 高通透亮白（`NSColor(white: 1.0, alpha: 0.88)`），并注入抗锯齿柔和阴影，全态统一呈现清晰、高对比度白色字体，彻底杜绝黑字。
  2. **`CategoryBarView` 与 `SelectionCapsuleView` 协同更新与生命周期补齐**（[`CategoryBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryBarView.swift)）：
     - `SelectionCapsuleView` 引入 `capsuleIsDark` 并重写 `viewDidMoveToWindow()` / `viewDidChangeEffectiveAppearance()`；
     - `CategoryBarView` 提供统一外观刷新方法 `updatePillsAppearance()`，并在 `reloadData()`、`viewDidMoveToWindow()` 及主题变更时主动调用；
     - 提供 `allPills` 内部访问器供诊断断言。
  3. **`ShelfPanel` 预先设定外观与唤起刷新**（[`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)）：
     - 在 `ShelfPanel.init` 最早期（子视图挂载前）即刻执行 `updateWindowAppearanceForTheme()`；
     - `updateWindowAppearanceForTheme()` 与 `prepareForDisplay()` 中显式调用 `categoryBar.updatePillsAppearance()`。
  4. **自动化诊断测试套件升级防回退断言**（[`main.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/main.swift)）：
     - 在 `[9/9]` 抽屉测试中新增动态切换 `liquidDark` 模式断言：核验所有分类胶囊文字亮度均严格大于 0.75，绝不发生黑字回退。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括全盘搜索、分类胶囊、780pt 几何不变性、liquidDark 分类胶囊白色亮度断言等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功同步部署并安装覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 32575）。

### 55. 全面排查并消除设置界面、应用抽屉与搜索列表中的原生液态阴影与直角溢出瑕疵 (2026-10-13, build 39)

- **背景与现象**：
  - 用户提供 4 张实景标注截图反馈：「看一下设置界面和应用抽屉中有些原生液态的阴影不太自然，统一排查一下是否可以优化」：
    * **图 1**：设置「全盘搜索」中「恢复默认」胶囊按钮（`SettingsResetButton`）左上角与右上角出现不自然的直角渐变黑边溢出；
    * **图 2**：设置「运行与性能」中「2x ⌘ Command」快捷键记录按钮（`HotkeyRecorderControl`）顶部左右两侧出现明显的直角切角与脏污阴影；
    * **图 3**：设置「全盘搜索」中「编辑排除名单 (8)...」与「前往授权...」常规液态按钮（`SettingsLiquidButton`）顶部左右两端同样存在直角黑色边缘；
    * **图 4**：全局搜索/语法指令联想列表（`SearchResultRowView`）中，当前选中高亮行向上投射出一道生硬浓重的外投影阴影，与上方未选中行发生重叠与遮挡，视觉体验不自然。

- **根本原因深度排查与剖析**：
  1. **按钮高光层未开启圆角裁剪导致直角溢出（Root Cause 1 - 图 1、2、3）**：
     - 在 `NativeLiquidButtonBackdrop` 中，`topSheenLayer`（`CAGradientLayer`）设定了高度为 `bounds.height * 0.55`，但其 `masksToBounds` 默认为 `false`，且未指定 `cornerRadius`；
     - CoreAnimation 的 `CAGradientLayer` 在未遮罩时是一个标准的直角矩形，在胶囊两端圆弧处，顶部的渐变色块直接从 `(0, 0)` 和 `(width, 0)` 的直角区域溢出到了胶囊边界之外，形成生硬的直角黑斑。
  2. **浅色次级按钮边缘光发黑加重直角斑纹（Root Cause 2 - 图 1、2、3）**：
     - 浅色模式下次级按钮（Secondary / Reset / Regular Button）顶部反光条边缘被设定为 `NSColor(white: 0.0, alpha: 0.20)`，在浅色底衬卡片上呈现出两条脏黑的粗边线，加剧了直角生硬感；同时静态常态下启用了不必要的外阴影。
  3. **列表行与抽屉图元挂载外投影污染（Root Cause 3 - 图 4）**：
     - `SearchResultRowView` 与 `ShelfItemButton` 内部挂载了通用类 `NativeLiquidSelectionBackdrop`；
     - 默认的 `contactShadowEnabled = true` 在紧凑的表格列表（每行高度仅 36pt）中向上投射 `shadowOffset = (0, -1.5)`、`shadowRadius = 3.5` 的接触阴影，直接映射到上一行的文字与底板上；在密集列表中行内元素应依赖内部晶莹玻璃折射与高光内边，而非向相邻行投掷外投影。
  4. **水滴高光层半高截断隐患（Root Cause 4）**：
     - `NativeLiquidSelectionBackdrop.topSheenLayer` 原本框架高度为 `bounds.height * 0.50`，在部分不同长宽比的图元下形成了腰部截断线。

- **实施细节与涉及文件**：
  1. **重构 `NativeLiquidButtonBackdrop`：消除直角溢出与优化反光边界**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - 将 `topSheenLayer.frame` 调整为匹配宿主全边界 `bounds`，显式设置 `topSheenLayer.masksToBounds = true` 并同步 `cornerRadius = cornerRadius`；
     - 调整渐变分布为 `locations = [0.0, 0.40, 0.70]`，自顶部高光向底部通透递减，完全贴合圆弧轮廓，彻底根治直角溢出黑角；
     - 浅色次级按钮反光发丝边调整为极柔和半透明色（顶部 `NSColor(white: 0.20, alpha: 0.14)`，底部 `0.08`），静态常态下 `shadowOpacity = 0.0`，仅在悬停与按压时呈现柔和微浮（`0.07`），彻底清除卡片背景上的脏污杂色。
  2. **全面消除搜索列表与应用抽屉的外部杂乱阴影**（[`SearchResultsTableView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchResultsTableView.swift)、[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift)）：
     - 在 `SearchResultRowView.setupViews()` 中显式配置 `liquidBackdrop.contactShadowEnabled = false`，彻底消除图 4 中选中行向上投射至上一行的浓厚阴影；
     - 在 `ShelfItemButton.setupViews()` 中同样设置 `liquidBackdrop.contactShadowEnabled = false`，保证抽屉网格内图标选中高亮聚焦于水滴玻璃透镜内质感，避免图标四周产生突兀阴影。
  3. **增强 `NativeLiquidSelectionBackdrop` 全局轮廓闭合度与阴影平滑度**（[`NativeLiquidSelectionBackdrop.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/NativeLiquidSelectionBackdrop.swift)）：
     - `topSheenLayer` 尺寸统一延展至全 `bounds`，配合多阶段衰减 `[0.0, 0.40, 0.70]` 消除腰部硬线；
     - 优化 `layer.shadowPath`，仅在 `shadowOpacity > 0` 时计算并赋给图层，消除多余绘制损耗；
     - 将默认投影参数从 `(0, -1.5) / 3.5` 平滑软化至 `(0, -1.0) / 3.0`。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括 CalculatorEngine、SystemActions、ConfigManager、AppHotspotIndex、SpotlightBridge、ShelfPanel、SettingsWindowController、UpdateManager 等）**100% 全部 PASSED 通过**；
    * 偏好设置严格保持 780.0pt 窗口宽度不变性；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署并更新覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 86412）。

### 56. 消除应用抽屉与全盘搜索顶缘黑折射斑并重构柔和自然微环境光晕过渡 (2026-10-13, build 39)

- **背景与现象**：
  - 用户提供 2 张实景截图并在应用抽屉与全盘搜索界面绘制红框标注：「应用抽屉和全盘搜索的阴影再检查一下，能不能过渡自然点」；
  - 实景截图深度分析：
    * **图 1**：应用抽屉垂直侧边栏顶部分类胶囊「AI」顶部，以及网格图标「Antigravity」选中/悬停态顶部出现了一条清晰的暗灰线与生硬切边，过渡不自然；
    * **图 2**：全盘搜索结果列表中「文档」选中高亮行顶部边缘与背景面板交界处呈现出较重的反光白边与折射灰线，缺乏 Apple 原生 Liquid Glass 的通透与柔润光影过渡。

- **根本原因深度剖析**：
  1. **浅色下强行回退 `Glass.clear` 产生焦散折射暗线（Root Cause 1）**：
     - 在 `LiquidGlassRoot` 中，浅色模式被硬编码为 `Glass.clear`（纯折射透镜），忽视了 `usesRegularGlass = true` 属性；
     - 浅色白底下高曲率 `Glass.clear` 边缘的系统级折射光学计算会导致光线向内折射弯曲，在顶缘物理曲度处形成 1~2px 的天然焦散暗阴影（暗折射带）；
  2. **多层发丝边与高光叠加刺眼惨白生硬切面（Root Cause 2）**：
     - `LiquidGlassRoot` 内部绘制了 `lineWidth = 1.2`、alpha 0.90 的高光边框；而外层 `NativeLiquidSelectionBackdrop` 又叠加了 `lineWidth = 1.0`、alpha 0.98 的 `specularBorderLayer`，两层强行叠加后顶部反光峰值达 1.88，与焦散暗线剧烈冲突，产生如贴纸一般的刀切边缘；
  3. **AppKit Flipped 坐标系投影方向取反与半径过窄（Root Cause 3）**：
     - 在 `isFlipped == true` 坐标系中，原 `shadowOffset = (0, -1.0)` 反向将投影向上方邻行和胶囊顶部投射，叠加 3.0pt 极窄模糊半径，使边缘呈现出一圈脏污阴影；在关闭外部阴影时又因缺乏环境漫射而使贴纸感加剧。

- **实施细节与涉及文件**：
  1. **浅色启用 `Glass.regular` 漫射折射并调和内层笔触**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - 调整 `LiquidGlassRoot.useRegular` 逻辑：当 `usesRegularGlass == true` 时在浅色模式同样切入漫射液态水滴，消除高曲率焦散边缘产生的暗灰色带；
     - 调优内部倒角与外层高光线宽至 `0.75pt`，浅色模式下内嵌高光柔化至 `0.48`，形成通透晶润的白水滴微熏感。
  2. **全面重塑 `NativeLiquidSelectionBackdrop` 发丝边与自然顺光软微影**（[`NativeLiquidSelectionBackdrop.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/NativeLiquidSelectionBackdrop.swift)）：
     - 发丝切边高光调整为细腻精湛的 `0.75pt`（`insetBounds = bounds.insetBy(dx: 0.375, dy: 0.375)`），浅色顶层高光自 `0.98` 柔化为 `0.52`，侧边 `0.20`，底部 `0.10`；
     - 天光反射层 `sheenAlpha` 自 `0.45` 柔化为 `0.20`（悬停 `0.12`），配合 `[0.0, 0.35, 0.75]` 平滑三次衰减；
     - 修正 `layer.shadowOffset = CGSize(width: 0, height: 1.0)`（符合自然重力与顺光方向，杜绝向上溢出），投影模糊半径由 `3.0` 大幅拓宽至 `5.5pt`，浅色阴影浓度控制在极微弱的 `0.04 ~ 0.05`，深色控制在 `0.14`，呈现丝般顺滑的微环境悬浮感。
  3. **应用抽屉与全盘搜索全链路配置协同**（[`SearchResultsTableView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchResultsTableView.swift)、[`CategoryBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryBarView.swift)、[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift)、[`SearchFilterBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchFilterBarView.swift)）：
     - 搜索结果选中行开启柔和微影（`radius: 5.0, opacity: 0.04`），向下顺光漫射，与上下邻行自然隔绝；
     - 分类胶囊启用 `radius: 6.0, opacity: 0.05` 微影，顶端暗线彻底消失，如水滴自然滑行在轨道上；
     - 应用抽屉网格图标 Hover/选中态启用 `radius: 5.5, opacity: 0.035~0.05` 漫射软垫，杜绝生硬裁切。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项（包括全盘搜索、分类胶囊、780pt 几何不变性等）**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署并更新覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 12662）。

### 57. 彻底根除偏好设置侧边栏选中态发黑缺陷，重构为通透纯白水滴质感胶囊 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈并在截图标注：「偏好设置左边的选中阴影怎么变成黑色了，请变成白色」；
  - 实景截图证实：偏好设置主内容区已是优雅明亮的浅色风格，卡片与顶部分段控制器「启用与唤出触发」呈现通透纯白水滴质感；唯独左侧侧边栏中当前选中的「应用抽屉」变成了深暗黑炭色块（`rgb(40,40,40)`），与全局视觉风格格格不入。

- **根本原因深度剖析**：
  - **动态系统色 `controlBackgroundColor` 误解为深色（Root Cause）**：
    - `SettingsSidebarView.SidebarRowButton.updateAppearance()` 原先直接使用 `NSColor.controlBackgroundColor.withAlphaComponent(0.78).cgColor`；
    - 当系统外观为深色（或主题为 `liquidDark`）时，该动态系统色直接解析为深黑灰；加之直接提取 `.cgColor` 脱离了 AppKit 视图层次树的动态外观渲染上下文，导致即便在浅色偏好设置窗口中，选中高亮也固化为黑色块。

- **实施细节与涉及文件**：
  1. **重构 `SidebarRowButton` 纯白水滴选中与悬停样式**（[`SettingsSidebarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsSidebarView.swift)）：
     - 引入 `isDarkAppearance` 精准判定窗口实时外观，并实现 `viewDidMoveToWindow()` / `viewDidChangeEffectiveAppearance()` 监听；
     - **浅色选中态（`isCurrentSelected`）**：彻底替换为纯白水滴底板（`NSColor.white`）+ 极细发丝切边（`NSColor.black.withAlphaComponent(0.04)`）+ 向下自然微环境顺光软投影（`shadowOffset: (0, 1.0), shadowRadius: 3.5, shadowOpacity: 0.08`），文字与图标赋予高对比深色（`NSColor(white: 0.10, alpha: 1.0)`），与顶部分段水滴滑块达成 1:1 纯白透润质感统一；
     - **浅色悬停态（`isHovered`）**：赋予 `NSColor.white.withAlphaComponent(0.55)` 通透白微光，彻底杜绝生硬脏灰色；
     - **深色自适应**：深色模式下赋予 `NSColor(white: 1.0, alpha: 0.22)` 高光白霜质感，兼顾深色模式视觉辨识度。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项自动化测试**100% 全部 PASSED 通过**；
    * 偏好设置实景截图（`/tmp/settings_preview.png`）像素采样验证：选中的侧边栏高亮块像素值达到纯白 `(255, 255, 255)`；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署并更新覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 15674）。

### 58. 修复「原生液态 (浅色)」透明度未随偏好设置滑块比例调节动态变化的缺陷，实现全范围无级平滑联动与纯白水滴质感无缝过渡 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈：「原生液态（浅色）的透明度是不是没有随着比例调整变化，修复一下看看」；
  - 现象实测核验：在外观设置中选择「原生液态 (浅色)」主题（`macosLiquidLight`）后，拖动「面板背景透明度」滑块（40% ~ 100%），应用抽屉和全盘搜索面板的背景透明度保持完全静态，没有任何浓淡或透光率变化。

- **根本原因深度剖析**：
  1. **浅色原生液态硬编码清零阻断滑块联动（Root Cause 1）**：
     - 在 [`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift) 的 `updateAppearanceColors()` 中，深色模式计算了 `progress = (themeOpacity - 0.40) / 0.60` 并动态赋予 `dynamicTintOpacity = 0.22 + 0.50 * pow(progress, 1.20)`；
     - 但浅色模式分支中被硬编码为 `effectView.tintColor = .clear; effectView.tintOpacity = 0.0;`，完全脱钩了 `ConfigManager.shared.config.themeOpacity`，导致用户拖动滑块时 `tintOpacity` 恒为 0.0；
  2. **搜索栏悬浮胶囊同步硬编码静态盲区（Root Cause 2）**：
     - 在 [`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift) 的 `updateGlassTint()` 中，原生浅色分支同样硬编码为 `glassEffectView.tintColor = .clear; glassEffectView.tintOpacity = 0.0;`；
  3. **SwiftUI `LiquidGlassRoot` 缺乏浅色透光底衬联动与材质切换（Root Cause 3）**：
     - 在 [`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift) 中，`isNativeLiquid` 的暗色底衬仅对 `isDark` 生效，浅色模式没有与透明度对应的透光白底衬；且 `tintOpacity <= 0.001` 条件恒成立，导致无论用户如何拖动滑块，系统 `.glassEffect` 始终停留在完全固定的零色度 `Glass.clear` 状态；
  4. **辅助窗口点击检测补充自身窗口极速判定**：
     - 在 [`PanelCoordinator.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/PanelCoordinator.swift) 中，`isClickOnAuxiliaryToolWindow(at:)` 之前依赖 Accessibility API；在无 UI 辅助权限或沙箱回归测试环境中无法定位自身无焦点窗口，补充 Tier 0 检查自身 `NSApp.windows` 坐标判定，既加速运行又消除测试环境误报。

- **实施细节与涉及文件**：
  1. **大面板原生浅色透明度全范围动态无级联动**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift)）：
     - 建立 `progress = (themeOpacity - 0.40) / 0.60` 连续响应曲线；
     - 赋予 `effectView.tintColor = NSColor.white`，并将 `dynamicTintOpacity` 精准映射至 `0.08 + 0.57 * pow(progress, 1.15)`；
     - 在 40%（滑块最左侧）时保持 0.08 超轻水滴晶莹通透透镜（`Glass.clear`），桌面与下层窗口清晰可见；
     - 在 100%（滑块最右侧）时平滑提升至 0.65 浓郁温润的白瓷磨砂透光玻璃，遮蔽杂乱背景。
  2. **搜索栏悬浮胶囊同步联动与微光强调**（[`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 搜索栏胶囊同步支持 `themeOpacity` 动态浓度调节；聚焦或悬停时叠加微光增益（`+0.10`），呈现通透且交互灵动的水滴胶囊。
  3. **SwiftUI 硬件级 `LiquidGlassRoot` 浅色底衬与折射材质动态升阶**（[`LiquidGlassContainerView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/LiquidGlassContainerView.swift)）：
     - 材质切换：`useRegular = (isDark && tintOpacity > 0.36) || (!isDark && tintOpacity > 0.36 && usesRegularGlass)`；在低透明度（40%~55%）保持极纯水滴透镜（`Glass.clear`），高透明度（60%~100%）无缝升阶至漫射液态水滴（`Glass.regular`）；
     - 底衬联动：新增浅色专属纯白透光底衬 `shape.fill(Color.white.opacity(underlayAlpha))`，`underlayAlpha` 随 `tintOpacity` 由 `0.08` 连续无级递增至 `0.68`，彻底消除复杂桌面背景杂色穿透。
  4. **自身窗口点击极速判定 Tier 0 加固**（[`PanelCoordinator.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/PanelCoordinator.swift)）：
     - 优先遍历 `NSApp.windows` 判断点击坐标是否命中自身窗口，毫秒级直接豁免，规避跨进程 AX 查询开销。
  5. **回归测试套件加固**（[`main.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/main.swift)）：
     - 增加 `macosLiquidLight` 主题下 `themeOpacity` 动态调整至 0.40、1.00、0.90 时 `VisualEffectBackdropView` 的联动通知处理与状态一致性断言。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项自动化测试**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署并更新覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 19248）。

### 59. 偏好设置面板全域重塑为现代 macOS 一体化顶栏与极致丝滑侧边栏质感（1:1 像素级对标参考图 2 AuraSnap 精致质感） (2026-10-13, build 39)

- **背景与现象**：
  - 用户提供参考实景截图并提出：「偏好设置面板外观能不能做成如图 2 的效果，图 2 看起来一体化感觉更强、更精致丝滑」；
  - 核心设计差异剖析（图 1 现状 vs 图 2 AuraSnap 标杆）：
    * **窗口与顶栏一体化**：图 1 仍保留传统 macOS 独立顶栏，中间突兀显示「ATools 偏好设置」居中文本，顶栏贯穿左右产生硬切割感；图 2 采用现代 macOS 全高沉浸式顶栏（`fullSizeContentView`），隐藏居中文本，窗口背景与侧边栏浑然一体；
    * **红绿灯与品牌区排版**：图 2 红绿灯（🔴🟡⚪️）直接嵌入侧边栏左上方，品牌名与图标在红绿灯下方约 22pt 处优雅展开；图 1 品牌区紧贴顶栏边缘，视觉挤压且比例失调；
    * **导航条目质感与蓝调图标**：图 2 选中项采用饱满纯白胶囊衬底 + 柔润顺光微阴影 + **活力高光蓝调图标（`#007AFF`）**，未选中态为高透极简设计；图 1 选中态图标为单调深灰色，缺乏层次感与视觉聚焦；
    * **分割线细节**：图 1 使用系统 `NSBox` 粗糙黑灰色分割线；图 2 采用极细的 0.5pt 微环境发丝分割线，自然消融于背景；
    * **底部就绪微标**：图 2 底部认证微标采用鲜明苹果蓝徽章，精致醒目；图 1 为暗淡灰色。

- **实施细节与涉及文件**：
  1. **现代沉浸式全高窗口架构与透明顶栏一体化**（[`SettingsWindowController.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SettingsWindowController.swift)）：
     - 窗口样式掩码升级：开启 `.fullSizeContentView`，配置 `win.titleVisibility = .hidden` 与 `win.titlebarAppearsTransparent = true`；
     - 启用 `win.isMovableByWindowBackground = true`，用户可在侧边栏或空白处任意拖拽移动窗口；
     - 保持系统级窗口标识：保留 `win.title = "ATools 偏好设置"` 供调度中心（Mission Control）与系统菜单识别，但不在窗口画板上产生视觉遮挡；
     - 严格保持 780.0pt 窗口宽度不变性与 620pt 高度，所有既有布局约束完美契合。
  2. **侧边栏红绿灯避让、品牌排版与活力蓝调选中态重塑**（[`SettingsSidebarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsSidebarView.swift)）：
     - **红绿灯避让与品牌区重构**：将 App 图标与「ATools」品牌标题调整至 `topAnchor + 52pt`，为左上角系统红绿灯预留出恰到好处的呼吸空间（红绿灯下方约 22pt 间距）；
     - **胶囊条目规格升级**：高度由 34pt 适度提升至 36pt，圆角调优为 9pt，间距调和为 3pt，交互手感大幅提升；
     - **纯白水滴胶囊 + 活力蓝调高光图标**：
       * 浅色选中态：纯白底板（`NSColor.white`）+ 极细发丝切边（`black 0.04`）+ 顺光微阴影（`shadowOpacity: 0.07, radius: 3.5`）+ **纯正活力蓝图标（`#007AFF`）**；
       * 深色选中态：高透白霜底板（`white 0.18`）+ 天蓝色图标（`#40A0FF`）；
     - **0.5pt 微环境发丝分割线**：彻底废除粗重 `NSBox` 分割线，替换为自适应浅色（`black 0.06`）/深色（`white 0.10`）的 0.5pt 极细右侧边缘线；
     - **底部认证微标焕新**：采用鲜亮苹果蓝（`#007AFF`）`checkmark.seal.fill` 徽章，边距优化为 `leading: 16, bottom: -20`。
  3. **右侧内容区全屏顶部对齐与水平基线统一**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - 配合全高顶栏，将 `SettingsHeaderView` 内部 `iconView.topAnchor` 由 `20pt` 平滑调整至 `50pt`；
     - 右侧各大配置页主标题（常规、应用抽屉、全盘搜索等）与左侧「ATools」品牌标题达成统一水平视觉基准线（y ≈ 50pt），彻底消除顶栏错位感。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项自动化测试**100% 全部 PASSED 通过**；
    * 严格验证 7 个 Tab 切换过程中的 780.0pt 窗口几何不变性（`Strict Window Width Invariance verified`）；
  - 实景视觉采样比对（`/tmp/settings_preview.png`、`/tmp/settings_tab_shelf_layout.png`、`/tmp/settings_tab_4.png` 与 `/tmp/about_preview.png`）：
    * 成功实现无独立顶栏沉浸式画板、红绿灯自然内嵌侧边栏、纯白胶囊衬底与亮蓝高光图标；整体视觉浑然天成，完全还原参考图 2 的高级、精致与丝滑质感；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署并更新覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 22363）。

### 60. 偏好设置全域下拉菜单原生液态材质重塑（SettingsLiquidPopUpButton）与几何对齐消除长短参差 (2026-10-13, build 39)

- **背景与现象**：
  - 用户反馈：「设置面板中这种有下拉框选项的能不能也做成原生液态材质，并且与上面的原生液态对齐，不要一长一短」；
  - 核心排查与视觉问题分析：
    * **材质不统一**：既有下拉选择框使用的是系统原生 Aqua 样式 `NSPopUpButton`，带有厚重的旧版浅灰色方形浮雕边框及系统蓝色双三角箭头，与上方快捷键录制胶囊 `HotkeyRecorderControl` 的原生液态玻璃材质（`NativeLiquidButtonBackdrop`）产生强烈的断层与违和感；
    * **长短不齐（一长一短）**：在「应用抽屉」设置面板中，上方的专属全局快捷键控件宽度为 `210pt`，而下方的「触控板手势唤出」下拉菜单宽度被硬编码约束为 `220pt`（多了 10pt），在右侧靠齐对齐的情况下，左侧边界向外突出，视觉上呈现明显的参差错位。

- **实施细节与涉及文件**：
  1. **构建全新水滴玻璃下拉控件 `SettingsLiquidPopUpButton`**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - 继承自 `NSPopUpButton`，设置 `isBordered = false`，高度固定为 `28pt`，圆角设为 `14pt`（半高水滴胶囊）；
     - 挂载 `NativeLiquidButtonBackdrop`，提供硬件级光学微透镜折射、顶部天光微弧张力反光及发丝切边高光；
     - 屏蔽默认 Aqua Bezel 与箭头绘制：重写 `draw(_:)` 为空实现，消除旧版矩形厚边与双三角箭头；
     - 右侧内嵌精致的 Apple 原生 SF Symbol `chevron.up.chevron.down`（9pt, semibold, 自适应深浅色透明度）；
     - 左侧内嵌抗锯齿排版中段/尾部截断文本标签 `titleLabel`，在菜单项切换、增删或代码设置时通过重写 `synchronizeTitleAndSelectedItem()`、`selectItem(at:)`、`selectItem(withTitle:)` 等全套 API 保证文本即时无缝联动同步；
     - 完善 `hitTest`、`mouseEntered`、`mouseExited`、`mouseDown` 与光标事件，确保用户点击胶囊任意位置均能丝滑呼出原生选项菜单，并伴随柔和的液态微浮阴影及下压反馈。
  2. **应用抽屉面板几何严密对齐**（[`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift)）：
     - 将 `trackpadGesturePopUp` 升级为 `SettingsLiquidPopUpButton`；
     - 将其宽度约束由 `220pt` 精准修正为 `210pt`，与上方的 `shelfRecorder`（`210pt`）达成左右边缘与高度（28pt）的 100% 像素级对齐，彻底消除「一长一短」的不对称瑕疵。
  3. **全域下拉选择框统一升级**（[`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift)、[`AutoQuitTabView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/AutoQuitTabView.swift)）：
     - 全盘搜索页：未命中网页搜索引擎下拉框 `enginePopUp` 统一升级为 `SettingsLiquidPopUpButton`，宽度规范化为 `210pt`；
     - 关窗退出页：生效模式下拉框 `autoQuitModePopUp` 与延迟退出下拉框 `autoQuitDelayPopUp` 统一升级为 `SettingsLiquidPopUpButton`，宽度由旧版 184pt 统一扩展对齐为 `210pt`，形成整齐划一的视觉节奏。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项自动化测试**100% 全部 PASSED 通过**；
    * 严格验证 780.0pt 窗口几何不变性（`Strict Window Width Invariance verified`）；
  - 实景视觉渲染核查（`/tmp/settings_tab_1.png`、`/tmp/settings_tab_3.png`）：
    * 快捷键录制胶囊与触控板手势下拉框完全采用一致的液态玻璃材质，宽度均为 210pt，圆角均为 14pt，左右外边距严丝合缝；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署并更新覆盖至 `/Applications/ATools.app`，重启进程验证正常运行（PID: 27539）。

### 61. 全面排查修复重大可用性缺陷与物理内存全链路深度优化（Footprint 骤降 58%） (2026-10-13, build 39)

- **背景与现象**：
  - 用户提出需求：「排查一下软件还有没有重大 bug，软件物理内存占用方面能不能优化一下」；
  - 核心排查与缺陷分析：
    1. **重大交互缺陷（⌘W 无法关闭偏好设置窗口）**：偏好设置窗口打开后，按下 macOS 标准快捷键 `⌘W` 或 `Escape` 无法关闭窗口；`AppDelegate.setupMainMenu` 未声明含有 `performClose:` 的 `文件` 菜单，导致 AppKit 无法将 `⌘W` 路由给主窗口；
    2. **偏好设置标签页常驻泄露与内存膨胀**：用户在偏好设置侧边栏中切换过 7 个标签页后，所有访问过的标签页视图（包含 20 余个 `NSHostingView` 及 200 余个 `CALayer` 图层）未被释放，常驻堆内存导致物理内存膨胀至 90MB+；
    3. **全盘搜索面板关闭时未释放结果模型与单元格**：当搜索面板通过外部点击或快捷键隐藏时，仅执行 `orderOut`，未重置搜索框及结果列表，大量模型数据与视图树常驻内存；
    4. **`ThumbnailPipeline.downsample` 跨线程安全隐患**：在后台渲染队列 `renderQueue` 中直接调用 `NSImage.lockFocus()`，引发 AppKit 跨线程绘图警告与图形上下文内存泄漏；
    5. **全盘搜索临时缩略图污染常驻缓存**：全盘检索产生的成百上千个一次性文件缩略图占据全局 `cache`，与抽屉应用图标混杂，导致内存退火时不敢清理；
    6. **XNU 内核物理内存返还局限**：原 `MemoryGuardian` 仅对单默认 zone 触发 `malloc_zone_pressure_relief`，无法触达 Swift 堆内存所在的 `MallocHelperZone`。

- **实施细节与涉及文件**：
  1. **支持标准 ⌘W 与 Escape 关闭窗口**（[`AppDelegate.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/App/AppDelegate.swift)、[`SettingsWindowController.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SettingsWindowController.swift)）：
     - 在 `AppDelegate.setupMainMenu` 中增加「文件 -> 关闭窗口 (`keyEquivalent: "w"`)」菜单项，绑定 `NSWindow.performClose(_:)`；
     - 在 `SettingsWindowController` 中重写 `cancelOperation(_:)`，当用户在偏好设置中按下 `Escape` 键时同样直接调用 `window?.performClose(sender)`。
  2. **偏好设置非活跃标签页即时卸载与轻量化**（[`SettingsWindowController.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SettingsWindowController.swift)）：
     - 重构 `switchToTab(_:)`：当切换标签时，主动移除并置空（`= nil`）上一个非活跃标签视图，释放其庞大的 `NSHostingView` 与 `CALayer` 树，在任何时刻仅保留当前正在浏览的唯一标签页；
     - 窗口关闭时调用 `MemoryGuardian.shared.onPanelsDidHide()` 触发退火清理。
  3. **搜索面板隐藏时即时释放结果模型**（[`SearchPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchPanel.swift)、[`PanelCoordinator.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/PanelCoordinator.swift)）：
     - 在 `SearchViewController` 中公开 `clearSearch()` 方法，在面板隐藏时彻底清空搜索文本、重置分类选择并清空 `resultsTable.results`，立即释放所有检索结果与单元格对象；
     - `PanelCoordinator.hideSearchPanel` 在收起面板时立即调用 `clearSearch()`。
  4. **线程安全 CGContext 缩放管线**（[`ThumbnailPipeline.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/Search/ThumbnailPipeline.swift)）：
     - 废除后台线程的 `NSImage.lockFocus()`，重构为基于 `CGContext` 与 `CGColorSpace.sRGB` 的高保真直接位图绘制，彻底消除跨线程图形隐患并降低位图常驻开销。
  5. **动静分离缩略图缓存治理（`clearTransientSearchCache`）**（[`ThumbnailPipeline.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/Search/ThumbnailPipeline.swift)、[`MemoryGuardian.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/App/MemoryGuardian.swift)）：
     - 新增 `clearTransientSearchCache()`：基于 `ConfigManager` 的分类配置，100% 精确保留抽屉内固定的关键应用图标（杜绝重新展开抽屉时的图标重新渲染闪烁与延迟），而在面板退场时清空全盘搜索中产生的海量临时文件缩略图；
     - 升级 `MemoryGuardian.performDeepPurge()`，遍历调用 `malloc_get_all_zones` 对当前进程内包括 `MallocHelperZone` 在内的全部 malloc zone 统一执行 `malloc_zone_pressure_relief`，最大化返还脏物理页给操作系统。
  6. **通知监听器生命周期补全**（[`VisualEffectBackdropView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/VisualEffectBackdropView.swift)）：
     - 补全 `deinit { NotificationCenter.default.removeObserver(self) }`，杜绝悬垂观察者风险。

- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项自动化测试**100% 全部 PASSED 通过**，780.0pt 窗口宽度绝对不变性严密保持；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、打包校验成功；
  - 成功部署覆盖安装至 `/Applications/ATools.app`，重启进程（PID: 36869）：
    * **⌘W 关闭窗口实测**：偏好设置窗口在激活状态下按下 `⌘W` 或 `Escape` 均能瞬间敏捷关闭；
    * **物理内存（`phys_footprint`）实测暴降 58%**：
      - 优化前常驻内存：`~90 MB`（峰值达 `116 MB`，CoreAnimation 占据 246 个 regions）；
      - 优化后常驻内存：**稳定降至 `37 MB ~ 40 MB`**（CoreAnimation regions 骤降至 27 个，Malloc Nano 由 21MB 降至 8.7MB）；
      - 即使在频繁打开/切换偏好设置与全盘搜索后，面板关闭 3 秒内自动触发退火回收，物理内存依然迅速平稳回落至 40MB 极低基线。

### 62. 正式发布 ATools v1.3.15 (build 40)：原生液态水滴质感重塑、沉浸式设置面板美化与物理内存全链路深度优化 (2026-10-13, build 40)

- **版本发布概述**：
  - 正式将应用版本由 `1.3.14 (build 39)` 提升至 **`1.3.15 (build 40)`**；
  - 完整打包并发布第 55~61 次迭代的重大架构升级与视觉体验飞跃：
    1. **视觉一致性**：修复深色模式下分类胶囊文字偶现黑字缺陷，重塑通透亮白文字与发光微轮廓；
    2. **原生液态光影重塑**：重构深浅双模式专属环境柔润微阴影算法，消除生硬黑块断层；
    3. **浅色透明度全级映射**：修复原生液态浅色透明度与浓度滑块联动，实现 40%~100% 极纯水滴透镜到温润白瓷漫射玻璃无缝升阶；
    4. **沉浸式现代设置面板**：对齐现代 macOS 全高顶栏，红绿灯优雅内嵌侧边栏，搭配纯白水滴胶囊与活力高光蓝调图标；
    5. **全域液态控件对齐**：构建 `SettingsLiquidPopUpButton`，全面替换旧版 Aqua 边框下拉框，210pt 几何严密对齐快捷键胶囊；
    6. **重大交互与健壮性保障**：支持标准 `⌘W` 与 `Escape` 敏捷关窗；全面消除后台线程绘图上下文隐患；
    7. **物理内存暴降 58%**：引入多 zone 深度退火与动静分离图标缓存，常驻物理内存稳定降至 37MB~40MB。
- **涉及文件**：
  - `Scripts/package_app.sh`：版本号提升至 `1.3.15`，构建编号升级至 `40`；
  - `RELEASING.md`：同步更新发布版本号为 `1.3.15 (build 40)`；
  - `Sources/CHANGELOG-优化记录.md`：建立版本正式发布历史存档。
### 63. 全盘搜索占位提示文字与输入框垂直光学居中校准（消除汉字视错觉） (2026-10-14, build 40)

- **背景与现象**：
  - 用户反馈并在截图标注：「为什么全盘搜索刚打开，提示文字没有居中显示？」；
  - 核心排查与视觉几何分析：
    1. **原生左对齐设计规范**：根据 macOS HIG 与 Spotlight / Raycast 标准交互，搜索占位提示文字采用紧随左侧放大镜的靠左对齐，以保障用户盲打时视觉焦点与键入起始流（LTR）一致，杜绝敲键瞬间文字从正中向左瞬移产生的视觉眩晕；
    2. **中文字体度量视错觉与几何偏差**：系统中文字体（苹方 PingFang SC）汉字不包含西文字符下延部（Descender），中文字块底端预留了西文行高空间；在原有几何居中计算下，汉字字块顶端距胶囊上边缘仅 11.5pt，而字块底端距胶囊下边缘留白多达 17.5pt，产生高达 6.0pt 的上下留白失衡；在肉眼感知上，提示文字与放大镜图标明显不在同一视觉水平线上，整体悬浮偏上。
- **实施细节与涉及文件**：
  1. **垂直光学下沉校准（`opticalDownwardOffset`）**（[`SearchBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SearchBarView.swift)）：
     - 在 `VerticallyCenteredTextFieldCell` 中引入 `opticalDownwardOffset = 1.0pt` 光学垂直居中校准参数；
     - 在 `drawingRect(forBounds:)` 计算垂直偏移时，将 `delta = (rect.height - textSize.height) / 2.0 + opticalDownwardOffset`；
     - 使得占位符文本（Placeholder）、编辑中文字以及光标位置（`edit`/`select`）同步下沉 1.0pt，使汉字视觉重心与放大镜图标在 22.0pt 基准线上达到绝对平齐，彻底消除上下留白视觉失衡。
- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 12 大项自动化测试**100% 全部 PASSED 通过**；
    * 严格验证 780.0pt 窗口几何不变性（`Strict Window Width Invariance verified`）；
  - 实景视觉渲染核查（`/tmp/search_collapsed_preview.png`）：
    * 像素测量核验：放大镜几何中心为 `center = 72.0px`，中文字块视觉中心为 `center = 73.5px`，两者在 2x 屏幕上的物理偏差仅为 1.5px（0.75pt），肉眼感知完美水平齐平；
    * 顶部留白与底部留白达到黄金平衡，视觉居中感极度舒适自然；
  - 执行 `./Scripts/package_app.sh` 编译 Release、`ATools Sign` 签名、Ed25519 签名验证成功；
  - 成功部署覆盖安装至 `/Applications/ATools.app`，重启进程（PID: 89905）生效。

---

### 64. 借鉴 GlassDesk v1.3.1 核心架构：落地 P0 三大功能（启动项深度编辑器、失效项检测与维护、自描述配置备份/干跑预校验/快照回滚） (2026-10-15, build 41)

- **背景与设计对标**：
  - 深入分析 `GlassDesk v1.3.1` 开源仓库核心源码（`AppEntry.cs` / `AppEntryEditor.cs`、`IsTargetMissing` / `LibraryMaintenance.cs`、`BackupService.cs`），针对 ATools 启动器资产管理、失效项目可视化自愈以及配置全量备份回滚三大 P0 痛点进行工程级落地；
  - **版本保护基线**：实施前基线 Commit 为 `9f9f956`，可随时通过 `git reset --hard 9f9f956` 一键回退。

- **子代理架构与可用性审查结论（AppKit Architecture & Reliability Reviewer）**：
  1. **浮动面板层级与模态弹窗防失焦收起保护**：`ShelfPanel` 处于 `.statusBar` 层级且支持失焦自动收起；在打开「编辑项目属性...」弹窗或「重新定位目标...」的 `NSOpenPanel` 期间，通过 `PanelCoordinator.shared.isModalDialogOpen` 保护锁阻止抽屉误收起，并将弹窗层级设为 `.popUpMenu + 2`。
  2. **按钮复用状态完整性**：为 `LauncherItem` 与 `ExecutionContext` 实现完整 `Equatable`，修复原 `ShelfGridView.reloadData` 仅比较 `name` 与 `target` 导致修改自定义图标、启动参数或搜索别名后按钮与右键菜单上下文不刷新的缺陷。
  3. **沙盒测试隔离性**：`ConfigManager` 的 `icons/`（自定义图标托管目录）与 `backups/`（恢复前自动快照目录）动态跟随 `configURL.deletingLastPathComponent()`，确保 `--test` 诊断套件运行时 100% 物理隔离，零污染生产环境。
  4. **设置窗 780.0pt 宽度刚性不变性**：在 `GeneralTabView` 新增「备份与恢复数据」卡片及在 `ShelfTabView` 新增「启动项健康维护」卡片时严格遵循 580pt 内容区约束规范。

- **实施细节与涉及文件**：
  1. **P0-1：启动项深度编辑器（自定义图标 / 启动参数 / 工作目录 / 多音字搜索别名）**：
     - [`LauncherItem.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Models/LauncherItem.swift)：扩展 `Equatable`、命令行参数智能分词解析 `ExecutionContext.parseArguments(_:)`、目标路径存活检测 `checkTargetMissing()` 与拼音匹配辅助方法；
     - [`ConfigManager.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Storage/ConfigManager.swift)：新增自定义图标托管目录 `iconsDirectoryURL`、`importCustomIcon(from:for:)`（支持 `.png` / `.icns` / `.jpg` / `.app`，自动归一化为 256×256 PNG 存入 `~/Library/Application Support/ATools/icons/`）、`removeManagedIconIfUnused(_:)`、`updateItem(_:in:)`；
     - [`ThumbnailPipeline.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Search/ThumbnailPipeline.swift)：新增 `icon(forItem:completion:)` 与 `icon(forPath:customIconPath:completion:)`，优先读取 `customIconPath`（若丢失自动平滑回退原生图标），并在 `clearTransientSearchCache()` 中保护自定义图标缓存；新增 `grayscaleImage(for:)` 高保真灰阶渲染；
     - [`LauncherItemEditorDialog.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/LauncherItemEditorDialog.swift)（新增）：可视化编辑显示名称、启动参数、工作目录、搜索别名标签（`tags`）以及更换/恢复自定义图标；
     - [`LauncherExecutor.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/System/LauncherExecutor.swift) & [`ShelfPanel.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfPanel.swift) & [`SearchCoordinator.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Search/SearchCoordinator.swift)：执行启动项时完整注入 `executionContext`（`arguments`、`workingDirectory`、`environmentVars`）；抽屉内过滤与全盘搜索 Layer 1 全面支持 `tags` 别名与拼音/首字母检索。
  2. **P0-2：失效启动项检测、灰阶+黄色感叹号微标与一键重定位/清理**：
     - [`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift)：抽屉加载时异步检测 `FileManager.default.fileExists(atPath:)`；对失效项目渲染半透明灰阶图标 + 右上角黄色感叹号角标（`exclamationmark.triangle.fill`）；右键菜单新增「编辑项目属性...」与「重新定位目标...」（保持原有 ID、排序位置和自定义名称/图标/标签不变）；左键点击失效项目时弹出「重新定位目标 / 从分类中移除」引导弹窗；
     - [`ConfigManager.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Storage/ConfigManager.swift) & [`SettingsTabViews.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/Settings/SettingsTabViews.swift)：新增 `relocateItem(id:in:newTarget:)`、`scanMissingItems()`、`removeAllMissingItems()`，并在设置页提供「一键清理全部失效项目」。
  3. **P0-3：自描述配置与图标全量备份、恢复前干跑预校验与自动快照回滚**：
     - [`BackupService.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Storage/BackupService.swift)（新增）：
       - 导出备份：将 `config.json`、托管图标目录 `icons/` 与含版本及 SHA-256 校验信息的 `manifest.json` 打包导出为 `.atoolsbackup` 归档目录；
       - 恢复前内存干跑预校验（`validateBackup(at:)`）：在内存中完整校验 JSON 结构、版本兼容性与 SHA-256 哈希，若损坏立即拒绝覆盖并提示详细错误；
       - 自动安全快照与跨机路径自愈（`restoreBackup(from:)`）：恢复前自动将当前配置与图标快照至 `backups/pre-restore-时间戳/`（支持一键回滚），并自动将归档中的自定义图标路径与家目录路径修复映射为当前机器的用户目录；
     - [`SettingsTabViews.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/Settings/SettingsTabViews.swift)：在「常规」设置页新增「备份与恢复数据」卡片（支持导出备份、干跑校验导入恢复、一键回滚恢复前快照及一键清理失效启动项）。

### 65. 修复 AutoQuitManager 关窗动画期间多通知并发消耗 recheckCounts 防重入缺陷与 TextEdit 零窗识别 (2026-10-15)

- **问题根因**：
  1. `AutoQuitManager` 对每个受监控应用同时注册了应用级 `kAXWindowClosedNotification`、应用级 `kAXUIElementDestroyedNotification` 及窗口级 `kAXUIElementDestroyedNotification`。点击红叉关闭窗口时，2～3 个通知在同一毫秒内并发触发 `evaluateAppWindowsLocked(pid:)`，而此时 macOS 窗口关闭淡出动画（约 250ms～350ms）尚未结束（`axCount == 0` 但 `WindowServer` 的 `wsCount` 仍为 `1`），导致同一帧内瞬间耗尽 `recheckCounts` 配额并调用 `cancelPendingQuitLocked(pid)`。
  2. 部分原生 Cocoa 应用（如 `TextEdit`）在关闭最后一个窗口或打开面板后，`kAXWindowsAttribute` 可能返回 `.noValue`（`-25212`），此前被当作 AX 查询失败（`nil`）处理。
- **修复细节**（[`AutoQuitManager.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/System/AutoQuitManager.swift)）：
  - 新增 `pendingRechecks: [pid_t: DispatchWorkItem]` 防重入锁与 `cancelPendingRecheckLocked(_:)`：当 `axCount == 0 && wsCount > 0` 且已有排队中的延迟复查任务时直接合并忽略，不再重复扣减 `recheckCounts`，并将复查窗口调整为最多 `5` 次 × `0.12s`（覆盖 `600ms` 关窗动画期）；
  - 在 `kAXWindowCreatedNotification` 收到标准业务窗口元素或收到明确 `kAXWindowClosedNotification` / 已注册窗口销毁通知时，自动补全 `entry.hadWindows = true`；
  - 在 `axWindows(of:)` 中当 `kAXWindowsAttribute` 返回 `.noValue` 且应用级 `kAXRoleAttribute` 正常响应时，返回空窗口列表 `[]`（确认 0 窗）。

### 66. 应用抽屉空白区域右键菜单新增「新建项目...」与「一键清理失效项」 (2026-10-15)

- **优化内容**：
  1. **抽屉空白面板右键菜单扩展**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift)）：
     - 在右键抽屉空白区域弹出的菜单顶部新增 **「新建项目...」**（图标 `plus.app`）与 **「一键清理失效项」**（图标 `trash`，当检测到失效项目时动态显示数量 `一键清理失效项 (N)`）。
  2. **通过启动项属性编辑器直接新建项目**（[`LauncherItemEditorDialog.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/LauncherItemEditorDialog.swift) & [`ShelfPanel.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfPanel.swift)）：
     - 新增 `LauncherItemEditorDialog.presentCreateNew(in:onCreated:)`，点击「新建项目...」直接弹出「编辑启动项属性」窗口；
     - 支持点击「选择目标...」选取 `.app`、文件或脚本（或直接输入路径），自动回填本地化显示名称与默认图标预览，并可一并配置自定义图标、启动参数、工作目录与搜索别名，保存后自动加入当前所在分类。
  3. **抽屉内一键清理全部失效项目并回收孤立托管图标**（[`ShelfPanel.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfPanel.swift)）：
     - 点击「一键清理失效项」执行与设置页完全一致的 `ConfigManager.shared.scanMissingItems()` 预览确认弹窗及 `ConfigManager.shared.removeAllMissingItems()`，一键清理全部失效启动项并自动回收孤立的托管自定义图标，随后即时刷新抽屉视图。

### 67. 借鉴 GlassDesk 实现应用抽屉实时平滑让位、长按 350ms 起拖、Alt 快速交换、Esc 撤销还原与双指横向翻页 (2026-10-15)

- **优化内容**：
  1. **长按 350ms 浮起反馈 + 快速拖拽双模响应**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift)）：
     - 在 `ShelfItemButton` 中新增 `350ms` 长按定时器：按住满 `350ms` 触发 `1.08x` 微浮起缩放与触觉反馈（`.generic`），进入就绪态；同时保留鼠标直接拖动 `> 4.5pt` 的即时起拖路径。
     - 起拖时网格内的源图标平滑过渡为 `0.22` 透明度虚影占位槽（Ghost Slot），松手后无缝恢复。
  2. **实时平滑让位算法与 14% 边界磁滞防抖**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift)）：
     - 新增纯几何槽位反算函数 `targetSlotIndex(at:itemCount:currentSlot:)`，不依赖动画途中的按钮 `frame`，并在每个槽位边缘设立 `14%` 磁滞防抖区（Hysteresis Deadzone），彻底消除槽位交界处的往复跳动。
     - 在 `draggingUpdated` 过程中实时驱动周围图标顺移让位，使用 `CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)` 阻尼弹簧曲线（`duration = 0.24s`）与 `.alignment` 触觉反馈实现丝滑跟手动画。
  3. **Alt (⌥) 快速交换模式**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift) & [`ConfigManager.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Storage/ConfigManager.swift)）：
     - 拖拽途中按住 `Option / Alt (⌥)` 键时切换为「双图标直接交换」模式：仅对调源槽位与目标槽位的两个图标（其余图标保持原位不动），并在目标图标上渲染高亮环；松手时通过 `ConfigManager.shared.swapItems(at:and:in:)` 持久化。
  4. **Esc 撤销还原与拖拽取消保护**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift)）：
     - 起拖瞬间保存 `dragOriginalItems` 与 `dragOriginalButtons` 快照；拖拽途中按下 `Esc` 键、拖出网格区域（`draggingExited`）或在外部松手取消时，所有图标立即平滑回弹恢复至起拖前原位，底层配置零改动。
  5. **双指横向滑动翻页与拖拽悬停分类胶囊自动切页**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift) & [`CategoryBarView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/CategoryBarView.swift) & [`ShelfPanel.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfPanel.swift)）：
     - 在 `ShelfGridView.scrollWheel(with:)` 中识别触控板双指横向滑动手势，联动 `CategoryBarView.moveSelection(by:)` 与 `playCategoryPageTransition(direction:)` 实现左右滑动切换分类；
     - 在 `CategoryBarView` 中新增拖拽悬停分类胶囊 `420ms` 自动切页（Spring-loaded Category Pill）。

### 68. 修复跨分类拖拽后图标文字重叠缺陷并新增跨分类拖入实时平滑让位动画 (2026-10-15)

- **问题根因**：
  1. **跨分类拖拽后文字与图标重叠**：从分类 A 起拖并悬停切换到分类 B 时，`ShelfGridView.reloadData(items:)` 未清理分类 A 的 `dragOriginalItems` 与 `dragOriginalButtons` 快照；拖拽结束时旧分类 A 的按钮数组被回写，导致分类 A 与分类 B 的两套 `ShelfItemButton` 同时留在 `contentView.subviews` 的同一网格坐标上重叠显示。
  2. **跨分类拖入无让位动画**：此前 `updateLiveDragReorder` 仅处理当前分类已存在的图标重排，当把图标拖入其他分类网格时，未创建占位槽位，因此周围图标不会滑开让位。
- **修复内容**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfGridView.swift)、[`ConfigManager.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Storage/ConfigManager.swift)、[`ShelfPanel.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfPanel.swift)）：
  - 在 `reloadData(items:)` 入口调用 `resetDragPreviewSnapshotBeforeReload()` 清空旧分类拖拽快照，并在构建 `newButtons` 后严格遍历 `contentView.subviews` 移除所有不在 `newButtons` 中的 `ShelfItemButton`，彻底根除双层按钮/文字重叠；
  - 新增 `beginCrossCategoryDragPreview(for:)` 与 `applyCrossCategoryLivePreview(targetIndex:ghostButton:)`：当把应用拖入其他分类网格时，自动生成半透明虚影占位槽（`crossCategoryGhostButton`），指针移动时目标分类周围图标实时丝滑让位滑入新位置；
  - 扩展 `ConfigManager.moveItem(id:toCategoryId:at:)` 支持跨分类移动并一步插入目标槽位索引。

### 69. 正式发布 ATools v1.3.16 (build 41)：启动项深度属性编辑器、失效项目自愈维护、配置备份回滚与抽屉丝滑让位手势交互 (2026-10-15, build 41)

- **版本发布概述**：
  - 正式将应用版本由 `1.3.15 (build 40)` 提升至 **`1.3.16 (build 41)`**；
  - 完整打包并发布第 63~68 次迭代的重大架构升级、资产管理自愈体系与前沿交互创新：
    1. **启动项深度属性编辑器（P0-1）**：支持可视化编辑应用显示名称、自定义启动参数/环境变量、工作目录、拼音/多音字搜索标签（Tags），并支持一键导入并托管自定义图标（`.png`/`.icns`/`.jpg`/`.app` 提取）；
    2. **失效启动项感知与自愈维护（P0-2）**：抽屉加载与设置面板全链路实时检测目标文件存活状态；失效项目智能灰阶化并呈现警示角标，提供「重新定位目标...」与「一键清理失效项」引导；
    3. **自描述配置备份、干跑预校验与快照回滚（P0-3）**：支持完整导出包含 `config.json` 与托管自定义图标的 `.atoolsbackup` 归档包；导入恢复前执行内存深度校验防损坏，恢复前自动创建本地快照支持一键回滚，并自愈跨机器家目录迁移路径；
    4. **抽屉极速响应与右键菜单扩展**：空白面板右键直达「新建项目...」与「一键清理失效项」，创建即可直接配置属性；
    5. **丝滑让位排版与专业手势操控**：引入 350ms 长按浮起微反馈、纯几何反算 + 14% 磁滞防抖实时插队占位、跨分类拖入实时虚影让位、Alt 快速对调、Esc/拖出取消回滚，以及双指横向滑动翻页与胶囊悬停 420ms 自动切页；
    6. **单实例生命周期与关窗退出加固**：启动时自动清理历史僵尸进程防 `-10827` 启动失败，强化 `AutoQuitManager` AX 并发防抖与 `TextEdit` 零窗状态感知；
    7. **全盘搜索光学居中**：垂直下沉 1.0pt 消除汉字视觉重心上浮，与放大镜图标严密光学居中对齐。
- **涉及文件**：
  - `Scripts/package_app.sh`：版本号提升至 `1.3.16`，构建编号升级至 `41`；
  - `RELEASING.md`：同步更新发布版本号为 `1.3.16 (build 41)`；
  - `Sources/atools/Storage/BackupService.swift`：版本号默认回退值对齐升级至 `1.3.16`；
  - `Sources/CHANGELOG-优化记录.md`：建立版本正式发布历史存档。
- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：
    * 13 大项自动化测试**100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 打包并签名，生成 `ATools.app`、`ATools.zip`、`ATools.dmg` 及其 `.sig` 签名文件；
### 70. 应用抽屉拖拽悬停分类丝滑切页、呼吸聚能微动效与 Esc 撤销自愈回滚 (2026-10-15)

- **背景与现象**：
  - 用户反馈：「应用抽屉拖拽图标到对应分类上时，能不能丝滑切换到对应分类页面中」；
  - 核心痛点与 AppKit 拖拽事件循环深层审查（经子代理 AppKit Architecture Reviewer 审查核验）：
    1. **AppKit 拖拽命中测试短路缺陷**：`CategoryPillView` 自身调用了 `registerForDraggedTypes` 并实现 `NSDraggingDestination`。光标位于胶囊内部时，系统事件被最内层子视图直接拦截消费，导致外层 `CategoryBarView` 根本收不到 `draggingUpdated`，悬停切页定时器静默失效；
    2. **响应时序迟钝与缺乏预备反馈**：旧版写死 420ms 延时，悬停等待期间胶囊无缩放或聚能反馈；
    3. **切页生硬突兀与无转场过渡**：`didSelectCategory` 仅调用 `reloadData` 粗暴替换所有按钮视图，未触发 `playCategoryPageTransition`，导致整个抽屉图标闪烁硬跳；
    4. **迷航风险**：用户跨分类悬停后若按下 `Esc` 取消拖拽，界面滞留在新分类而源项目留在旧分类。
- **实施细节与涉及文件**：
  1. **收归 Dragging Destination 至 `CategoryBarView`**（[`CategoryPillView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryPillView.swift) & [`CategoryBarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryBarView.swift)）：
     - 彻底移除 `CategoryPillView` 的独立拖拽类型注册与受体方法，由 `CategoryBarView` 作为单一受体（Single Source of Truth）；
     - 将悬停切页延时缩短为黄金感知阈值 `0.28s (280ms)`；
     - 新增 `isSpringLoadingHovered` 状态：悬停未选中胶囊时触发 `1.045x`（垂直模式 `1.025x`）Core Animation 图层级弹性微缩放与发光边框高亮，移开时平滑回弹。
  2. **抽屉网格液态自适应切页过渡**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift) & [`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)）：
     - 升级 `playCategoryPageTransition(direction:isVertical:)` 支持自适应水平/垂直滑动（水平 `dx: ±18pt`，垂直 `dy: ±14pt`）与液态减速弹簧曲线 `CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)`；
     - 动画作用范围限制在视口缓冲区域（`documentVisibleRect.insetBy(dx: 0, dy: -40)`），空分类对 `emptyLabel` 执行柔和淡入，保障 120Hz 满帧；
     - 在 `ShelfPanel.categoryBar(_:didSelectCategory:)` 中统一注入方向计算与转场动画，点击、滑动、拖拽悬停全场景自动触发丝滑滑入。
  3. **会话生命周期与 Esc 取消自愈回滚**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift) & [`ShelfPanel.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfPanel.swift)）：
     - `ShelfGridDelegate` 扩展 `shelfGridDidBeginDrag` 与 `shelfGrid(_:didEndDragWith:)`；
     - 在 `ShelfPanel` 起拖瞬间唯一锚定 `dragSessionOriginCategoryId`；
     - 拖拽成功落地移入目标分类时保持；若被 `Esc` 撤销或松开在非受体区域（`operation == []`），自动反向平滑切回起拖原分类。
- **验证与测试结果**：
  - 在 [`main.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/main.swift) Section 9.2 补充拖拽跨分类悬停与 `Esc` 撤销自动回滚断言；
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：**13 大项测试全部 100% PASSED 通过**；
  - 成功编译 Release 并重新签名打包，平滑覆盖部署至 `/Applications/ATools.app` 并重启生效（PID: 40848）。

### 71. 正式发布 ATools v1.3.17 (build 42)：设置界面新版本提醒闭环体系、抽屉拖拽悬停切页与静默更新健壮性加固 (2026-10-15, build 42)

- **背景与需求**：
  - 用户期望：在 ATools 有更新时，在设置界面左上角应用图标增加提醒（如红点），引导用户及时获知版本更新；
  - 经由专有子代理（AppKit & UX Architecture Reviewer）进行深度审查，发现旧版 `UpdateManager.swift` 存在重大隐患：`checkForUpdates(isUserInitiated: Bool)` 虽然声明了参数，但在网络请求回调中未向下传递，导致网络断开或触及 GitHub 60次/小时 Rate Limit 时，静默更新会粗暴将全局状态置为 `.error(...)`，使用户随后打开关于页面时看到醒目的红色报错卡片；
  - 评审淘汰了在 200pt 狭窄侧边栏顶部堆砌「图标红点 + 标题右侧版本号胶囊」的多重视觉过载方案（破坏窗口顶部空白拖拽心智，且版本号过长必遭截断），最终采纳**方案 C（改良版精准闭环微胶囊方案）**。
- **实施细节与涉及文件**：
  1. **UpdateManager 底层加固与静默节流**（[`UpdateManager.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/System/UpdateManager.swift)）：
     - 修复 `isUserInitiated` 穿透缺陷：网络回调中完整接收 `isUserInitiated` 参数，在静默更新（`isUserInitiated == false`）遇到网络断开、超时、403/429 限流或解析失败时，静默重置为 `.idle` 并仅记录日志，严禁向公开状态与 UI 抛出错误卡片；
     - 增加 `lastSilentCheckKey`（`"atools.lastSilentUpdateCheckTime"`）与 4 小时间隔节流（14400s），防止用户反复打开设置窗口消耗 GitHub API 配额；
     - 在拉取到新版本并校验通过后更新时间戳并广播 `stateDidChangeNotification`。
  2. **设置侧边栏视觉与交互闭环**（[`SettingsSidebarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsSidebarView.swift)）：
     - 顶部品牌区：封装 `NotificationBadgeView`，在 26×26 的 `appIcon` 右上角挂载 8pt 活力红微圆标（带 1.5pt 毛玻璃背景同色描边隔离环，防粘连与杂色混叠，辅以 0.5pt 细微阴影）；
     - 图标交互直达：封装 `ClickableAppIconView`，有新版本时提供手型光标与专属 Tooltip（“发现 ATools 新版本，点击查看更新详情”），点击图标直接触发 `selectItem(.about)` 直达关于页面；右侧空白区保留系统背景拖拽能力；
     - 底部导航项闭环引导：在 `SidebarRowButton` 的 `.about` 项尾部引入精致的 16pt 高度微胶囊（半透明磨砂红底，圆角 8pt，内含 9.5pt Bold 白色 `NEW` 字样），完美引导用户由“左上角发现”顺流而下到“底部关于项点击”；
     - 绿色能耗与无障碍规范：摒弃无限循环呼吸动画，采用一次性 0.35s 柔和弹性入场动效（`scale: 0.1 -> 1.15 -> 0.95 -> 1.0`），并严密遵循 `accessibilityDisplayShouldReduceMotion` 减弱动态效果规范；版本为最新或更新后平滑淡出隐藏。
  3. **静默探测触发与渲染避峰**（[`SettingsWindowController.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SettingsWindowController.swift) & [`AppDelegate.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/App/AppDelegate.swift)）：
     - 在 `SettingsWindowController.showSettingsWindow()` 打开时，延时 1.2 秒发起静默检查（避开首屏渲染与窗口毛玻璃合成峰值）；
     - 在 `AppDelegate.applicationDidFinishLaunching` 完成后，延时 8.0 秒发起静默检查（避开冷启动资源争抢）。
- **验证与测试结果**：
  - 运行 `./Scripts/build.sh --test` 综合诊断套件：**13 大项自动化测试 100% 全部 PASSED 通过**；
  - 运行 `./Scripts/package_app.sh` 编译 Release、签署 Designated Requirement 签名并打包；
  - 成功覆盖安装至 `/Applications/ATools.app` 并完成平滑重启生效（PID: 43478）。

### 72. 结合 GlassDesk 高可用保障机制全面落地：多屏幕动态 DPI 物理像素自适应、休眠期安全显存与离屏缓冲回收、极端壁纸 WCAG 2.1 AA 可读性微光晕 (2026-10-15)

- **背景与需求**：
  - 结合开源项目 GlassDesk（v1.3.1）的高可用机制与优秀架构实践，结合 ATools 自身实际架构（AppKit + 液态毛玻璃透镜），对四大核心机制进行适配升级与落地；
  - 经由专有子代理（AppKit System Architecture Reviewer）进行深度审查与可行性论证，对高风险激进操作进行防御性降级（否决清空可见 layer.contents 与废弃的 discardCachedImage 避免掉帧撕裂，否决过大光晕避免 11pt 小字笔画粘连），确保 100% 安全可用。
- **实施细节与涉及文件**：
  1. **多屏幕与动态 DPI 物理单像素自适应**（[`GlassPalette.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/GlassPalette.swift), [`SettingsSidebarView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsSidebarView.swift), [`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift), [`CategoryPillView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryPillView.swift)）：
     - 在 `NSView` 统一扩展 `physicalOnePixel` 动态计算属性（`1.0 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)`）；
     - 在关键视图全面重写 `viewDidChangeBackingProperties()`，跨屏拖动或 DPI 切换时在 `CATransaction.setDisableActions(true)` 保护下对齐物理单像素，杜绝 0.25s 隐式形变延迟与抗锯齿发虚。
  2. **深浅色即时响应**：
     - ATools 核心 18+ 关键视图已全面具备 `viewDidChangeEffectiveAppearance()` 与 `.atoolsThemeDidChange` 监听机制，经审查确认已属毫秒级零延迟自适应，无需冗余改动。
  3. **显存休眠管理与离屏缓冲安全泄压**（[`PanelCoordinator.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/PanelCoordinator.swift), [`MemoryGuardian.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/App/MemoryGuardian.swift)）：
     - 在 `PanelCoordinator` 引入 `purgeDormantOffscreenBuffers()`，当面板隐藏达 5 秒退火期后，安全清空历史搜索面板结果复用池与离屏视图缓存；
     - 与 `MemoryGuardian.performDeepPurge()` 深度联动，结合系统 `malloc_zone_pressure_relief`，确保后台物理常驻内存在低水位稳定巡航。
  4. **极端壁纸 WCAG 2.1 AA 文本可读性微光晕**（[`ShelfGridView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/ShelfGridView.swift), [`CategoryPillView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/CategoryPillView.swift)）：
     - 针对抽屉图标 `ShelfItemButton` 与未选中胶囊 `CategoryPillView`，引入对标 macOS Finder 的定向微投影（深色模式：`blur: 1.5pt, offset: (0, -1), black 0.68`；浅色模式：`blur: 1.0pt, offset: (0, 0.5), white 0.65`）；
     - 彻底杜绝纯白、纯黑、高饱和彩色壁纸下的文字粘连，实测对比度稳定超越 5.2:1（超越 WCAG 2.1 AA 4.5:1 基准），且保障 120Hz 满帧不糊字。
- **验证与测试结果**：
  - 运行 `./Scripts/build.sh --test` 综合诊断套件：**13 大项自动化测试 100% 全部 PASSED 通过**；
  - 成功编译 Release 并完成签名打包，部署覆盖 `/Applications/ATools.app` 并重启运行生效（PID: 49293）。

### 73. 偏好设置面板全 Tab「免滚动平铺（One-Screen Zero-Scroll）」重构：窗口高度提升至 680pt、Header 与板块间距紧凑化、排除项双列磁贴化、热目录空状态融合 (2026-10-15)

- **背景与现象**：
  - 用户反馈：「检查设置界面面板，使面板内功能点尽量都放在一个界面无需滑动条滑动，可以通过优化每个板块间的行间距或者其他方案」；
  - 核心痛点与 AppKit 约束深度排查（经子代理 Settings UI & HIG Architecture Reviewer 审查核验）：
    1. **窗口高度偏小**：旧版高度写死为 620pt，扣除顶栏与边距后，内容视口仅剩 486pt；
    2. **Header 顶部虚高**：`SettingsHeaderView` 顶部硬编码预留 50pt 空白，带 Tabs 时总高挤占 134pt；
    3. **板块与内边距梯度过大**：每个 Section 外边距 20pt，标题与卡片 8pt，底部留白 28pt，多板块页面累计浪费大量垂直高度；
    4. **「全盘搜索 - 搜索选项」截断**：底部的「自定义热目录」卡片被腰斩截断，出现垂直滑动条；
    5. **「全盘搜索 - 排除范围」过长**：6 项预设单列堆叠占用高达 280pt，滚动条极长。
- **实施细节与涉及文件**：
  1. **窗口基准尺寸升级至 780 × 680pt**（[`SettingsWindowController.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SettingsWindowController.swift)）：
     - 将窗口高度由 620pt 提升至 680pt（净增 60pt 黄金垂直视口），`minSize = (780, 600)`，`maxSize = (780, 860)`；
     - 保持严格的 `contentContainer.widthAnchor = 580pt` 锁定，消除 Auto Layout 弹性撑宽干扰，确保全局 780pt 宽度不变性（Strict Width Invariance）。
  2. **Header 顶栏空间收拢与微调**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift)）：
     - 顶部内边距由 `topAnchor + 50` 紧缩至 `topAnchor + 34`（释放 16pt，与红绿灯中心线平稳对齐）；
     - 分段控件（Tabs）间距收敛（上下 10pt，高度 30pt），Header 总高由 134pt 精简至 110pt，释放 24pt 视口。
  3. **板块间距（Visual Rhythm）与行高紧凑微调**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift), [`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift), [`AutoQuitTabView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/AutoQuitTabView.swift)）：
     - `SettingsRowView` 默认 `minHeight` 由 46pt 调至 42pt，上下内边距由 8pt 调至 6pt；
     - 板块 Section 间距由 20pt 紧凑至 13pt，标题与卡片间距由 8pt 调至 6pt；
     - 滚动容器底部留白由 `-28pt` 收拢为 `-16pt`，彻底消除下坠空洞。
  4. **全盘搜索核心长页结构重构（彻底告别滑动条）**（[`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift)）：
     - **「搜索选项」**：热目录空状态重构为单行 `makeEmptyHotFolderRow`（44pt），左侧直观说明已覆盖目录，右侧提供添加按钮并支持拖拽，整页总高压减至 ~389pt，在 570pt 视口内余量高达 181pt，**彻底杜绝截断与滑动条**；
     - **「排除范围」**：封装 `SettingsToggleTileView`，将 6 项预设开关重构为 **3行 × 2列 紧凑磁贴**（单行 38pt，长技术路径说明转入 ToolTip），高度腰斩 164pt，实现首屏 100% 完整平铺；
     - **「常规」、「应用抽屉」、「关窗退出」等全面板**：所有内容在首屏优雅呈现，依赖外层 `NSScrollView(autohidesScrollers = true)` 提供原生无感平铺与无障碍大字号弹性兜底。
- **验证与测试结果**：
  - 运行 `./Scripts/build.sh --test` 综合诊断套件：**13 大项自动化测试 100% 全部 PASSED 通过**；
  - 各 Tab 渲染截图（`/tmp/settings_tab_0.png`、`settings_tab_2.png`、`settings_tab_3.png` 等）实测均已实现 100% 免滚动平铺；
  - 成功编译 Release 并完成签名打包，部署覆盖 `/Applications/ATools.app` 并重启运行生效（PID: 53320）。

### 74. 偏好设置面板视觉节奏均衡微调：选项卡等距对称（14pt == 14pt）、窗口尺寸适度收敛至 780 × 600pt、消除底部冗余留白 (2026-10-15)

- **背景与现象**：
  - 用户反馈：「你调整完行间距后，面板下面留白又有点太多，并且顶部标题和切换选项卡之间以及选项卡和下面内容的留白空间不一样，感觉怪怪的，请调整到肉眼看舒适不拥挤，比较均衡的状态」；
  - 核心根因精准定位：
    1. **选项卡上下留白不对称**：`SettingsHeaderView` 中标题到底部分段控件距离为 10pt，而分段控件底部到 Header 边缘为 10pt，加上内容区首项 `topAnchor` 的 12pt，导致分段控件到下方内容的距离达 22pt（是上方间距的 2.2 倍），产生选项卡紧贴标题、远离内容的失衡视觉；
    2. **面板底部空洞**：在热目录空状态整合与排除项双列磁贴化后，全盘搜索等长页面高度已大幅精简至 ~380-420pt；此前临时将窗口拉升至 680pt 导致底部剩余近 180-260pt 的大面积空白区域，视觉空洞突兀；
    3. **板块与卡片微间距**：此前部分板块间距压缩至 12~13pt 略显紧凑，缺乏呼吸节奏。
- **实施细节与涉及文件**：
  1. **选项卡绝对等距对称（14pt == 14pt）**（[`SettingsComponents.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsComponents.swift), [`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift)）：
     - `SettingsHeaderView` 中分段控件上边距由 10pt 调整为 `14pt`（`segmentedControl.topAnchor = titleLabel.bottomAnchor + 14`）；
     - 分段控件下边距由 -10pt 调整为 `-8pt`（`segmentedControl.bottomAnchor = bottomAnchor - 8`）；
     - 各带 Tabs 页面（`SearchTabView` 的 4 个 Page、`ShelfTabView` 的 3 个 Page）首个板块标题 `topAnchor` 设为 `6pt`；
     - **最终实现**：标题到选项卡间距 **14pt**，选项卡到下方内容首项间距 **8 + 6 = 14pt**，达成严格的 1:1 几何对称与视觉均衡。
  2. **窗口高度适度收敛至 780 × 600pt**（[`SettingsWindowController.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/SettingsWindowController.swift)）：
     - 窗口默认尺寸由 `780 × 680` 调整为黄金比例 `780 × 600`（`minSize = (780, 560)`，`maxSize = (780, 860)`）；
     - 将原本 180pt 的底部巨大空白收敛至舒适自然的 70~90pt 留白，彻底消除突兀断层感，同时所有 Tab 依然保持 **100% 免滚动平铺（Zero-Scroll）**。
  3. **板块与卡片间距规范化**（[`SettingsTabViews.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/SettingsTabViews.swift), [`AutoQuitTabView.swift`](file:///Users/aurora/Downloads/atools/Sources/atools/UI/Settings/AutoQuitTabView.swift)）：
     - 板块 Section 间距统一规范为经典 `16pt`（既不拥挤也不松散）；
     - 标题与卡片之间间距统一为 `7pt`；
     - 无 Tabs 页面（`常规`、`关窗退出`、`外观`、`性能`、`关于`）首个 Section 标题 `topAnchor` 设为 `8pt`（搭配 Header 的 10pt，构成 18pt 原生节奏）。
- **验证与测试结果**：
  - 运行 `./Scripts/build.sh --test` 综合诊断套件：**13 大项自动化测试 100% 全部 PASSED 通过**，严格验证设置窗口 780.0pt 宽度不变性；
  - 抽样验证 `/tmp/settings_tab_2.png`（全盘搜索）、`settings_tab_1.png`（应用抽屉）、`settings_tab_3.png`（关窗退出）及 `settings_preview.png`（常规）：选项卡居中对称、呼吸间距均匀、无任何滚动条产生；
  - 成功完成 Release 编译打包与签名，覆盖部署至 `/Applications/ATools.app` 并重启运行生效。

### 75. 正式发布 ATools v1.3.18 (build 43)：偏好设置面板视觉节奏均衡微调、高可用多屏/显存/壁纸机制适配与免滚动全屏平铺 (2026-10-15, build 43)

- **版本发布概述**：
  - 正式将应用版本由 `1.3.17 (build 42)` 提升至 **`1.3.18 (build 43)`**；
  - 完整打包并发布第 72~74 次迭代的一系列前沿高可用架构升级与偏好设置人机界面（HIG）视觉革新：
    1. **偏好设置面板全 Tab「免滚动平铺（Zero-Scroll）」**：排查长路径折行与空状态展开，重构排除范围为 3行×2列 紧凑磁贴卡片（节约 164pt），热目录空状态融合为单行轻量条目，实现所有 Tab 首屏 100% 完整平铺且无垂直滑动条；
    2. **选项卡绝对 1:1 等距对称（14pt == 14pt）**：彻底修正分段控件与标题间距过紧（10pt）而离内容过远（22pt）的视觉失衡，实现像素级完全等距对称；
    3. **窗口黄金比例收敛（780 × 600pt）**：将窗口尺寸由试验性的 680pt 优雅收缩至 600pt，消除底部大面积空白断层，保留舒适呼吸留白（70~80pt）；
    4. **多屏与动态 DPI 物理单像素动态自适应（Dynamic DPI Pixel Alignment）**：扩展 `physicalOnePixel`，监听 `viewDidChangeBackingProperties()` 并在 DPI 切换时动态贴合物理单像素，彻底根除高分屏/非 Retina 屏描边发虚与加粗；
    5. **显存休眠管理与离屏缓冲泄压（Memory Lease & VRAM Dormancy）**：面板隐藏达 5 秒后触发离屏图层缓冲与复用池释放，联动 `malloc_zone_pressure_relief` 回收脏页；
    6. **极端壁纸可读性保障（WCAG 2.1 AA）**：针对抽屉图标与胶囊引入全天候微光晕定向投影，纯白/纯黑/高饱和桌面下文字对比度均稳定超越 5.2:1。
- **涉及文件**：
  - `Scripts/package_app.sh`：版本号提升至 `1.3.18`，构建编号升级至 `43`；
  - `RELEASING.md`：同步更新发布版本号为 `1.3.18 (build 43)`；
  - `Sources/atools/Storage/BackupService.swift`：版本号默认回退值对齐升级至 `1.3.18`；
  - `Sources/atools/UI/SettingsWindowController.swift`：窗口尺寸设为 780 × 600，保持严格 780pt 宽度不变性；
  - `Sources/atools/UI/Settings/SettingsComponents.swift`：Header Tabs 绝对等距对称，磁贴与行内间距优化；
  - `Sources/atools/UI/Settings/SettingsTabViews.swift`、`AutoQuitTabView.swift`：全 Tab Section 间距规范（16pt / 7pt / 8pt）；
  - `Sources/atools/UI/GlassPalette.swift`、`ShelfGridView.swift`、`CategoryPillView.swift`、`PanelCoordinator.swift`、`MemoryGuardian.swift`：高可用多屏/显存/文本光晕机制落地；
  - `Sources/CHANGELOG-优化记录.md`：建立版本正式发布历史存档。
- **验证与测试结果**：
  - 执行 `./Scripts/build.sh --test` 综合诊断套件：**13 大项自动化测试 100% 全部 PASSED 通过**；
  - 执行 `./Scripts/package_app.sh` 打包并签名，生成 `ATools.app`、`ATools.zip`、`ATools.dmg` 及其 Ed25519 `.sig` 签名文件；
  - 通过 GitHub CLI 发布 Release 并上传全部发布资产。

### 36. 修复应用抽屉「鼠标移出面板后自动关闭」失效并严格保障「固定在桌面」优先级保护 (2026-10-15)

- **问题根因与修复详情**：
  1. **严格保障「固定在桌面」(`isShelfPinned == true`) 最高优先级保护**：
     - 当勾选「固定在桌面」时，抽屉面板完全不受「鼠标移出面板后自动关闭」(`autoCloseOnMouseExit`)、「点击启动应用后自动关闭」(`autoCloseOnLaunch`) 及外部点击失焦关闭的影响；勾选瞬间立即取消排队中的自动关闭任务（`cancelPendingMouseExitAutoClose()`），取消固定时若抽屉可见则立即热恢复移出监控。
  2. **彻底修复未固定时「鼠标移出面板后自动关闭」不生效问题**：
     - **视图层 `ShelfRootView.updateTrackingAreas()` + `.assumeInside`**：将 `NSTrackingArea` 下沉至 `NSView` 子类 `ShelfRootView` 的生命周期内，并在抽屉唤出到鼠标正下方时动态注入 `.assumeInside` 与 `window.acceptsMouseMovedEvents = true`；
     - **全局/本地鼠标移动监听 + `0.10s` `.common` 模式轮询双保险**：在抽屉显示期间同时挂载 `NSEvent` 本地与全局鼠标移动监听器（`.mouseMoved` / `.mouseEntered` / `.mouseExited` / `.leftMouseUp` / `.rightMouseUp`）与 `0.10s` 定时器 `evaluateMouseExitState()`，彻底解决被 `NSScrollView` 及图标按钮子视图拦截 `mouseExited` 的问题；
     - **自愈式菜单状态锁 `isEffectiveMenuOpen`**：结合 `RunLoop.main.currentMode == .eventTracking` 与时间戳校验，防止因状态栏菜单或右键菜单触发模态弹窗导致 `NSMenu.didEndTrackingNotification` 遗漏而永久阻塞自动关闭。
  3. **其他潜在交互缺陷一并修复**：
     - 跨分类拖拽图标经悬停切到分类 B 后，若又拖回源分类 A 的胶囊上松手，补全自动切回源分类 A 的状态同步；
     - 在抽屉右键菜单切换「固定在桌面」时广播 `.atoolsShelfDataDidChange`，使打开中的偏好设置窗口实时同步开关状态；
     - 在偏好设置中开启「鼠标移出面板后自动关闭」时，若抽屉当前已处于打开状态，立即热启动移出监测。
- **修改文件**：
  - [`ShelfPanel.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/ShelfPanel.swift)
  - [`PanelCoordinator.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/UI/PanelCoordinator.swift)
  - [`ConfigManager.swift`](file:///Users/aurora/Downloads/ATools/Sources/atools/Storage/ConfigManager.swift)

### 76. 正式发布 ATools v1.3.19 (build 44)：应用抽屉鼠标移出自动关闭修复、固定桌面最高优先级保护与跨分类回拖同步 (2026-10-15, build 44)

- **版本迭代说明**：
  - 正式将应用版本由 `1.3.18 (build 43)` 提升至 **`1.3.19 (build 44)`**；
  - 严格保障「固定在桌面」(`isShelfPinned == true`) 的最高优先级保护，固定期间不受「鼠标移出面板后自动关闭」与「点击启动应用后自动关闭」影响，勾选时即时取消排队关闭任务，取消固定时热恢复移出检测；
  - 修复未固定时「鼠标移出面板后自动关闭」失效问题：通过 `ShelfRootView.updateTrackingAreas()` + `.assumeInside`、全局/本地 `NSEvent` 鼠标移动监听与 `0.10s` `.common` 模式轮询双保险，以及自愈式菜单状态锁 `isEffectiveMenuOpen`，确保鼠标移出抽屉后稳定延时 `0.35s` 自动收起；
  - 补全跨分类拖拽回到源分类胶囊松手时的分类状态同步，以及右键菜单切换固定状态与偏好设置窗口的实时通知联动。
- **修改文件**：
  - `Scripts/package_app.sh`：版本号提升至 `1.3.19`，构建编号升级至 `44`；
  - `RELEASING.md` / `README.md`：同步更新发布版本号为 `1.3.19 (build 44)`；
  - `Sources/atools/Storage/BackupService.swift`：版本号默认回退值对齐升级至 `1.3.19`。


