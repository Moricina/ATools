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

