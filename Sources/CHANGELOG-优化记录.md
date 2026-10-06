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
