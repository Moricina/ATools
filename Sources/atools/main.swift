import Foundation
import AppKit
import CoreServices

// Diagnostic expectations are deliberately kept out of Swift's assert machinery so they run
// in release builds as well as debug builds.

if CommandLine.arguments.contains("--test") {
    let tempTestDir = ConfigManager.setupIsolatedTestEnvironment()

    print("==================================================")
    print(" [ATools] Running Comprehensive Diagnostic Suite (Sandbox Mode)")
    print("==================================================")

    // 1. Test Calculator Engine
    print("[1/7] Testing CalculatorEngine...")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("1+1") == "2", "1+1 should equal 2")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("(1024 * 768) / 2") == "393216", "Math expression evaluation failed")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("0x10 + 16") == "32", "Hex math evaluation failed")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("not a math expression") == nil, "Non-math should return nil")
    // Half-typed / non-math input used to raise uncaught NSExpression exceptions.
    for input in ["1+", "c++", "wi-fi", "iphone-15", "-", "100%", "10%", "(1+2", "3*", "sin(", "a-b"] {
        TestAssertions.expect(CalculatorEngine.shared.evaluate(input) == nil, "'\(input)' must not evaluate")
    }
    TestAssertions.expect(CalculatorEngine.shared.evaluate("7/2") == "3.5", "Division must not truncate")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("1/0") == nil, "Division by zero yields no result")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("2^10") == "1024", "Power")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("10%3") == "1", "Modulo")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("sqrt(16)+1") == "5", "Functions")
    TestAssertions.expect(CalculatorEngine.shared.evaluate("2024-01-01") == nil, "Dates are not subtraction")
    print("      ✓ CalculatorEngine passed all tests.")

    // 2. Test SystemActions
    print("[2/7] Testing SystemActions...")
    let lockActions = SystemActions.shared.match("lock")
    TestAssertions.expect(!lockActions.isEmpty, "SystemAction 'lock' should match")
    let suoActions = SystemActions.shared.match("锁屏")
    TestAssertions.expect(!suoActions.isEmpty, "SystemAction '锁屏' should match")
    let sleepActions = SystemActions.shared.match("sleep")
    TestAssertions.expect(!sleepActions.isEmpty, "SystemAction 'sleep' should match")
    TestAssertions.expect(SystemActions.shared.match("s").isEmpty, "Single letters must not surface system actions")
    TestAssertions.expect(SystemActions.shared.match("clock.png").isEmpty, "File names containing a keyword must not match")
    TestAssertions.expect(SystemActions.shared.match("emptyfolder").isEmpty, "'emptyfolder' must not offer Empty Trash")
    TestAssertions.expect(HotkeyBinding(keyCode: 0, carbonModifiers: 0, displayString: "").isUnassigned, "Cleared binding is unassigned")
    TestAssertions.expect(!HotkeyBinding.defaultShelf.isUnassigned, "Default binding is assigned")
    print("      ✓ SystemActions passed all tests (matched \(SystemActions.shared.actions.count) actions).")

    // 3. Test ConfigManager & Dual Hotkeys & Resizable Shelf Dimensions & Panel Toggles
    print("[3/7] Testing ConfigManager & Resizable Shelf Dimensions & Safety Guards...")
    let config = ConfigManager.shared.config
    TestAssertions.expect(!config.categories.isEmpty, "Default categories should not be empty")
    TestAssertions.expect(config.shelfWidth >= 240, "Shelf width should be at least minSize 240")
    TestAssertions.expect(config.shelfHeight >= 180, "Shelf height should be at least minSize 180")
    ConfigManager.shared.updateShelfSize(width: 600, height: 400)
    TestAssertions.expect(ConfigManager.shared.config.shelfWidth == 600, "Shelf width should update to 600")
    TestAssertions.expect(ConfigManager.shared.config.shelfHeight == 400, "Shelf height should update to 400")

    // Test new configuration options & safety mutual exclusion
    ConfigManager.shared.updateAutoCloseOnLaunch(true)
    TestAssertions.expect(ConfigManager.shared.config.autoCloseOnLaunch == true, "autoCloseOnLaunch should be true")
    ConfigManager.shared.updateAutoCloseOnMouseExit(false)
    TestAssertions.expect(ConfigManager.shared.config.autoCloseOnMouseExit == false, "autoCloseOnMouseExit should be false")

    // Test isShelfPinned persistence & codec round-trip
    TestAssertions.expect(ConfigManager.shared.config.isShelfPinned == false, "isShelfPinned should default to false")
    ConfigManager.shared.updateIsShelfPinned(true)
    TestAssertions.expect(ConfigManager.shared.config.isShelfPinned == true, "isShelfPinned should update to true")
    let pinnedEncoded = try! JSONEncoder().encode(ConfigManager.shared.config)
    let pinnedDecoded = try! JSONDecoder().decode(AtoolsConfig.self, from: pinnedEncoded)
    TestAssertions.expect(pinnedDecoded.isShelfPinned == true, "isShelfPinned should survive encode/decode round-trip")
    ConfigManager.shared.updateIsShelfPinned(false)
    TestAssertions.expect(ConfigManager.shared.config.isShelfPinned == false, "isShelfPinned should reset to false")

    // 严格测试「常用」分类开关：关闭不保留数据，开启重新检测生成，默认保持未启用
    ConfigManager.shared.updateEnableFavoritesCategory(true)
    TestAssertions.expect(ConfigManager.shared.config.enableFavoritesCategory == true, "enableFavoritesCategory should be true when enabled")
    TestAssertions.expect(ConfigManager.shared.config.categories.first?.name == "常用", "开启后应重新扫描生成常用分类并排在首位")
    TestAssertions.expect(!ConfigManager.shared.config.categories.first!.items.isEmpty, "重新生成的常用分类中应包含检测到的常用软件")

    ConfigManager.shared.updateEnableFavoritesCategory(false)
    TestAssertions.expect(ConfigManager.shared.config.enableFavoritesCategory == false, "enableFavoritesCategory should default to false")
    TestAssertions.expect(!ConfigManager.shared.config.categories.contains(where: { $0.isFavorites }), "常用分类数据在关闭后应彻底清空移除")

    // Mutual exclusion test: if search is enabled, we can disable shelf
    ConfigManager.shared.updateEnableSearchPanel(true)
    let canDisableShelf = ConfigManager.shared.updateEnableShelfPanel(false)
    TestAssertions.expect(canDisableShelf == true, "Should allow disabling shelf when search is active")
    // Now both cannot be disabled simultaneously:
    let canDisableBoth = ConfigManager.shared.updateEnableSearchPanel(false)
    TestAssertions.expect(canDisableBoth == false, "Safety guard: must NOT allow disabling both panels simultaneously")
    ConfigManager.shared.updateEnableShelfPanel(true)
    TestAssertions.expect(ConfigManager.shared.config.enableShelfPanel == true, "Shelf should be re-enabled")

    ConfigManager.shared.updateSidebarWidth(160)
    TestAssertions.expect(ConfigManager.shared.config.sidebarWidth == 160, "sidebarWidth should update to 160")
    ConfigManager.shared.updateSidebarWidth(84)
    TestAssertions.expect(ConfigManager.shared.config.sidebarWidth == 84, "sidebarWidth should reset to 84")

    // Test HotkeyBinding backwards compatibility and specialTrigger
    let legacyJSON = "{\"keyCode\": 49, \"carbonModifiers\": 2048, \"displayString\": \"⌥Space\"}".data(using: .utf8)!
    let decodedLegacy = try! JSONDecoder().decode(HotkeyBinding.self, from: legacyJSON)
    TestAssertions.expect(decodedLegacy.specialTrigger == .none, "Legacy HotkeyBinding without specialTrigger should decode as .none")
    // displayString is re-generated from the active keyboard layout via UCKeyTranslate.
    // keyCode 49 is the Space key, which is a named key; the display string includes modifier prefix + key name.
    TestAssertions.expect(decodedLegacy.displayString.hasPrefix("⌥"), "Legacy displayString should have option modifier prefix")

    let doubleCmdJSON = "{\"keyCode\": 0, \"carbonModifiers\": 0, \"displayString\": \"2× ⌘ Command\", \"specialTrigger\": \"doubleCommand\"}".data(using: .utf8)!
    let decodedDoubleCmd = try! JSONDecoder().decode(HotkeyBinding.self, from: doubleCmdJSON)
    TestAssertions.expect(decodedDoubleCmd.specialTrigger == .doubleCommand, "Decoded doubleCommand trigger correctly")

    // Test Theme switching
    ConfigManager.shared.updateTheme(.liquidDark)
    TestAssertions.expect(ConfigManager.shared.config.theme == .liquidDark, "Theme should update to .liquidDark")
    TestAssertions.expect(ConfigManager.shared.config.theme.isDark == true, "liquidDark isDark should be true")
    TestAssertions.expect(AppTheme.allCases == [.liquidDark, .liquidLight], "Only the two liquid themes remain")
    // Configs saved with the retired solid themes migrate to the matching liquid theme.
    let solidLightJSON = "{\"theme\": \"solidLight\"}".data(using: .utf8)!
    TestAssertions.expect((try! JSONDecoder().decode(AtoolsConfig.self, from: solidLightJSON)).theme == .liquidLight, "solidLight -> liquidLight")
    let solidDarkJSON = "{\"theme\": \"solidDark\"}".data(using: .utf8)!
    TestAssertions.expect((try! JSONDecoder().decode(AtoolsConfig.self, from: solidDarkJSON)).theme == .liquidDark, "solidDark -> liquidDark")
    ConfigManager.shared.updateTheme(.liquidLight)
    TestAssertions.expect(ConfigManager.shared.config.theme == .liquidLight, "Theme should update to .liquidLight")

    // Test shelfIconScale
    ConfigManager.shared.updateShelfIconScale(1.15)
    TestAssertions.expect(ConfigManager.shared.config.shelfIconScale == 1.15, "shelfIconScale should update to 1.15")
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize == .large, "Scale 1.15 should map to .large")
    ConfigManager.shared.updateShelfIconScale(0.85)
    TestAssertions.expect(ConfigManager.shared.config.shelfIconScale == 0.85, "shelfIconScale should update to 0.85")
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize == .small, "Scale 0.85 should map to .small")
    ConfigManager.shared.updateShelfIconScale(1.40) // should clamp to 1.30
    TestAssertions.expect(ConfigManager.shared.config.shelfIconScale == 1.30, "shelfIconScale clamped to 1.30")
    ConfigManager.shared.updateShelfIconScale(1.0)
    TestAssertions.expect(ConfigManager.shared.config.shelfIconScale == 1.0, "shelfIconScale should reset to 1.0")

    // Test themeOpacity
    ConfigManager.shared.updateThemeOpacity(0.85)
    TestAssertions.expect(ConfigManager.shared.config.themeOpacity == 0.85, "themeOpacity should update to 0.85")
    ConfigManager.shared.updateThemeOpacity(0.10) // should clamp to 0.40 (minimum floor)
    TestAssertions.expect(ConfigManager.shared.config.themeOpacity == 0.40, "themeOpacity should be clamped to 0.40")
    ConfigManager.shared.updateThemeOpacity(-0.5) // should clamp to 0.40
    TestAssertions.expect(ConfigManager.shared.config.themeOpacity == 0.40, "themeOpacity clamped to 0.40")
    ConfigManager.shared.updateThemeOpacity(1.50) // should clamp to 1.00
    TestAssertions.expect(ConfigManager.shared.config.themeOpacity == 1.00, "themeOpacity clamped to 1.00")
    ConfigManager.shared.updateThemeOpacity(0.90) // reset to default
    TestAssertions.expect(ConfigManager.shared.config.themeOpacity == 0.90, "themeOpacity reset to 0.90")

    // Test ShelfTrackpadGesture configuration & persistence
    TestAssertions.expect(ConfigManager.shared.config.shelfTrackpadGesture == .none, "shelfTrackpadGesture default should be .none")
    ConfigManager.shared.updateShelfTrackpadGesture(.fourFingerTap)
    TestAssertions.expect(ConfigManager.shared.config.shelfTrackpadGesture == .fourFingerTap, "shelfTrackpadGesture should update to .fourFingerTap")
    let encodedData = try JSONEncoder().encode(ConfigManager.shared.config)
    let decodedConfig = try JSONDecoder().decode(AtoolsConfig.self, from: encodedData)
    TestAssertions.expect(decodedConfig.shelfTrackpadGesture == .fourFingerTap, "shelfTrackpadGesture JSON roundtrip verified")
    ConfigManager.shared.updateShelfTrackpadGesture(.none)
    TestAssertions.expect(ConfigManager.shared.config.shelfTrackpadGesture == .none, "shelfTrackpadGesture should reset to .none")

    print("      ✓ ConfigManager loaded \(config.categories.count) categories successfully.")
    print("        - Shelf Hotkey:  [\(config.shelfHotkey.displayString)] (ID 1)")
    print("        - Search Hotkey: [\(config.searchHotkey.displayString)] (ID 2)")
    print("        - Shelf Trackpad Gesture: [\(ConfigManager.shared.config.shelfTrackpadGesture.title)]")
    print("        - Shelf Dimensions: \(ConfigManager.shared.config.shelfWidth) x \(ConfigManager.shared.config.shelfHeight)")
    print("        - Sidebar Width: \(ConfigManager.shared.config.sidebarWidth)")
    print("        - App Theme: \(ConfigManager.shared.config.theme.title)")
    print("        - Shelf Icon Scale: \(ConfigManager.shared.config.shelfIconScale)")
    print("        - Theme Opacity: \(ConfigManager.shared.config.themeOpacity)")
    print("        - Safety Guard (Dual Panel Mutual Exclusion): Verified.")

    // 4. Test Category Item Management, Batch Add & Reordering
    print("[4/8] Testing Category Item Management, Batch Add & Reordering...")
    if let firstCat = ConfigManager.shared.config.categories.first {
        let dummy1 = LauncherItem(name: "Item1", itemType: .fileOrFolder, target: "/tmp/dummy1")
        let dummy2 = LauncherItem(name: "Item2", itemType: .fileOrFolder, target: "/tmp/dummy2")
        ConfigManager.shared.addItems([dummy1, dummy2], to: firstCat.id)
        
        let catAfterAdd = ConfigManager.shared.config.categories.first(where: { $0.id == firstCat.id })!
        TestAssertions.expect(catAfterAdd.items.contains(where: { $0.id == dummy1.id }), "Batch add item 1 should exist")
        TestAssertions.expect(catAfterAdd.items.contains(where: { $0.id == dummy2.id }), "Batch add item 2 should exist")

        // Test item reordering
        let countBefore = catAfterAdd.items.count
        ConfigManager.shared.moveItem(from: countBefore - 1, to: countBefore - 2, in: firstCat.id)
        let catAfterMove = ConfigManager.shared.config.categories.first(where: { $0.id == firstCat.id })!
        TestAssertions.expect(catAfterMove.items[countBefore - 2].id == dummy2.id, "Item reordering should place dummy2 before dummy1")

        ConfigManager.shared.removeItem(id: dummy1.id, from: firstCat.id)
        ConfigManager.shared.removeItem(id: dummy2.id, from: firstCat.id)
        print("      ✓ Batch addition, item reordering and deletion verified.")
    }

    // Test Category Reordering & Orientation
    let catsCount = ConfigManager.shared.config.categories.count
    if catsCount >= 2 {
        let firstId = ConfigManager.shared.config.categories[0].id
        ConfigManager.shared.moveCategory(from: 0, to: 1)
        TestAssertions.expect(ConfigManager.shared.config.categories[1].id == firstId, "moveCategory should move category 0 to 1")
        ConfigManager.shared.moveCategory(from: 1, to: 0)
        TestAssertions.expect(ConfigManager.shared.config.categories[0].id == firstId, "moveCategory back should restore original position")
    }

    // Test cross-category item move via moveItem(id:toCategoryId:)
    do {
        let source = ConfigManager.shared.addCategory(name: "拖拽源分类")
        let dest = ConfigManager.shared.addCategory(name: "拖拽目标分类")
        let item = LauncherItem(name: "DragItem", itemType: .fileOrFolder, target: "/tmp/dragitem")
        ConfigManager.shared.addItems([item], to: source.id)

        TestAssertions.expect(ConfigManager.shared.moveItem(id: item.id, toCategoryId: dest.id) == true, "Cross-category move should succeed")
        TestAssertions.expect(!ConfigManager.shared.config.categories.first(where: { $0.id == source.id })!.items.contains(where: { $0.id == item.id }), "Source category should lose item after move")
        TestAssertions.expect(ConfigManager.shared.config.categories.first(where: { $0.id == dest.id })!.items.contains(where: { $0.id == item.id }), "Destination category should gain item after move")

        TestAssertions.expect(ConfigManager.shared.moveItem(id: item.id, toCategoryId: source.id) == true, "Move back should succeed")
        TestAssertions.expect(ConfigManager.shared.config.categories.first(where: { $0.id == source.id })!.items.contains(where: { $0.id == item.id }), "Source should regain item after move back")

        TestAssertions.expect(ConfigManager.shared.moveItem(id: item.id, toCategoryId: source.id) == false, "Same-category move should be a no-op returning false")
        TestAssertions.expect(ConfigManager.shared.moveItem(id: item.id, toCategoryId: UUID()) == false, "Missing destination should return false")
        TestAssertions.expect(ConfigManager.shared.moveItem(id: UUID(), toCategoryId: dest.id) == false, "Missing item should return false")

        ConfigManager.shared.removeItem(id: item.id, from: source.id)
        ConfigManager.shared.deleteCategory(id: source.id, migrateItemsTo: dest.id)
        ConfigManager.shared.deleteCategory(id: dest.id, migrateItemsTo: ConfigManager.shared.config.categories.first!.id)
        print("      ✓ Cross-category item move (moveItem) verified.")
    }

    ConfigManager.shared.updateCategoryOrientation(.vertical)
    TestAssertions.expect(ConfigManager.shared.config.categoryOrientation == .vertical, "Orientation should update to .vertical")
    ConfigManager.shared.updateCategoryOrientation(.horizontal)
    TestAssertions.expect(ConfigManager.shared.config.categoryOrientation == .horizontal, "Orientation should update to .horizontal")

    ConfigManager.shared.updateShelfIconSize(.small)
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize == .small, "ShelfIconSize should update to .small")
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize.itemSize == 68, "Small item size should be 68")
    ConfigManager.shared.updateShelfIconSize(.large)
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize == .large, "ShelfIconSize should update to .large")
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize.itemSize == 96, "Large item size should be 96")
    ConfigManager.shared.updateShelfIconSize(.medium)
    TestAssertions.expect(ConfigManager.shared.config.shelfIconSize == .medium, "ShelfIconSize should reset to .medium")
    print("      ✓ Category reordering, orientation & icon size switching verified.")

    // Pre-initialize PanelCoordinator to measure dual-panel memory footprint
    _ = PanelCoordinator.shared.shelfPanel
    _ = PanelCoordinator.shared.searchPanel

    // 5. Test AppHotspotIndex
    print("[5/7] Testing AppHotspotIndex...")
    let sema = DispatchSemaphore(value: 0)
    AppHotspotIndex.shared.refreshIndex {
        sema.signal()
    }
    _ = sema.wait(timeout: .now() + 2.0)
    let safariSearch = AppHotspotIndex.shared.search("safari")
    TestAssertions.expect(!safariSearch.isEmpty, "Search 'safari' should find matches")
    let finderSearch = AppHotspotIndex.shared.search("访达")
    TestAssertions.expect(!finderSearch.isEmpty, "Search '访达' should find Finder app via Chinese alias")
    let terminalSearch = AppHotspotIndex.shared.search("zd") // pinyin abbreviation for 终端
    TestAssertions.expect(!terminalSearch.isEmpty, "Search 'zd' (pinyin abbr) should find Terminal app")
    print("      ✓ AppHotspotIndex scanned apps successfully. Chinese ('访达') and Pinyin abbr ('zd') verified.")

    // 6. Test SpotlightBridge Full-Disk File Search
    print("[6/7] Testing SpotlightBridge Full-Disk File Search on Main RunLoop...")
    var foundFiles: [SearchResult] = []
    var isDone = false
    SpotlightBridge.shared.searchFiles(matching: "Package", limit: 10) { results in
        foundFiles = results
        isDone = true
    }
    let deadline = Date().addingTimeInterval(3.0)
    while !isDone && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    print("      ✓ SpotlightBridge file query returned \(foundFiles.count) file results.")
    TestAssertions.expect(!foundFiles.isEmpty, "SpotlightBridge should find files matching 'Package'")

    // Single-Digit File Search Test (e.g. "1")
    var foundDigitFiles: [SearchResult] = []
    var isDigitDone = false
    SpotlightBridge.shared.searchFiles(matching: "1", limit: 10) { results in
        foundDigitFiles = results
        isDigitDone = true
    }
    let dDeadline = Date().addingTimeInterval(3.0)
    while !isDigitDone && Date() < dDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    print("      ✓ SpotlightBridge single-digit query ('1') returned \(foundDigitFiles.count) file results.")
    TestAssertions.expect(!foundDigitFiles.isEmpty, "SpotlightBridge should support single-digit searches")

    // Deterministic File Search Test using transient test fixture in Downloads
    let downloadsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    let testFixtureURL = downloadsURL.appendingPathComponent("atools_probe_fixture.txt")
    try? "ATools Stability Probe".data(using: .utf8)?.write(to: testFixtureURL)
    SpotlightBridge.shared.warmHotFolderCache(maxAge: 0)

    var foundFixtureFiles: [SearchResult] = []
    var isFixtureDone = false
    SpotlightBridge.shared.searchFiles(matching: "atools_probe_fixture", limit: 10) { results in
        foundFixtureFiles = results
        isFixtureDone = true
    }
    let fDeadline = Date().addingTimeInterval(3.0)
    while !isFixtureDone && Date() < fDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    print("      ✓ SpotlightBridge file search returned \(foundFixtureFiles.count) results.")
    TestAssertions.expect(!foundFixtureFiles.isEmpty, "SpotlightBridge should find fixture file in user hot folders")

    // 6.1 全盘检索（MDQuery）回归：中文谓词 + 热目录之外的文件 + CJK 单字门限
    // 历史 bug：MDQueryCreate 不支持 NSPredicate 的 CONTAINS，谓词解析失败静默返回空，
    // 中文/英文文件全盘检索全部失效（测试文件恰在 Downloads 热目录，故未暴露）。
    print("[6.1] Testing full-disk MDQuery (Chinese predicate, fixture outside hot folders)...")
    do {
        // (a) 谓词必须可被 MDQuery 解析（含转义边界输入）
        for probe in ["报告", "don't", "C++*", "a?b", "报", "path with space", "测试\\",
                      "全盘检索中文", "it's a *wild* card?"] {
            let text = MetadataFileSearchBackend.predicateText(matching: probe)
            var parsed = false
            if let mq = MDQueryCreate(kCFAllocatorDefault, text as CFString,
                                      [kMDItemPath!] as CFArray, [] as CFArray) {
                MDQuerySetSearchScope(mq, [kMDQueryScopeComputer!] as CFArray, 0)
                parsed = MDQueryExecute(mq, CFOptionFlags(kMDQuerySynchronous.rawValue))
            }
            TestAssertions.expect(parsed, "MDQuery 谓词必须可解析: \(text)")
        }
        print("      ✓ MDQuery 谓词解析（中文/引号/通配符/空格）全部通过.")

        // (b) 端到端：家目录根（不在热目录列表里）的中文文件名必须能被全盘检索命中
        let homeFixture = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("atools全盘检索中文验证_毛静斐.txt")
        try? "fixture".data(using: .utf8)?.write(to: homeFixture)

        let mdimport = Process()
        mdimport.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        mdimport.arguments = [homeFixture.path]

        func fixtureIndexed() -> Bool {
            let pt = MetadataFileSearchBackend.predicateText(matching: "全盘检索中文验证")
            guard let mq = MDQueryCreate(kCFAllocatorDefault, pt as CFString,
                                         [kMDItemPath!] as CFArray, [] as CFArray) else { return false }
            MDQuerySetSearchScope(mq, [kMDQueryScopeComputer!] as CFArray, 0)
            guard MDQueryExecute(mq, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return false }
            for i in 0..<MDQueryGetResultCount(mq) {
                guard let raw = MDQueryGetResultAtIndex(mq, i) else { continue }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                if let p = MDItemCopyAttribute(item, kMDItemPath) as? String, p == homeFixture.path {
                    return true
                }
            }
            return false
        }

        var ready = false
        let indexDeadline = Date().addingTimeInterval(25)
        while Date() < indexDeadline {
            try? mdimport.run()
            mdimport.waitUntilExit()
            if fixtureIndexed() { ready = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        TestAssertions.expect(ready, "测试夹具必须被 Spotlight 索引，否则本组回归无意义")

        func fullDiskSearch(_ q: String) -> [SearchResult] {
            var out: [SearchResult] = []
            var done = false
            SpotlightBridge.shared.searchFiles(matching: q, limit: 30) { r in
                out = r
                done = true
            }
            let dl = Date().addingTimeInterval(6)
            while !done && Date() < dl {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            return out
        }

        if ready {
            let multi = fullDiskSearch("全盘检索中文")
            TestAssertions.expect(multi.contains(where: { $0.path == homeFixture.path }),
                                  "全盘检索必须命中热目录之外的中文文件（MDQuery 谓词回归）")

            let single = fullDiskSearch("验")
            TestAssertions.expect(single.contains(where: { $0.path == homeFixture.path }),
                                  "单个中文字必须放行到全盘检索并命中")
            print("      ✓ 中文全盘检索（多字 + 单字）端到端回归通过.")

            // (c) 方案 A 归并排序回归：档位 > 新鲜度；同档内新者优先；全盘可排到热目录之前
            // 档位链（同查询“全盘检索中文”）：
            //   精确(旧) ≈1591 > 前缀(新) ≈1310 > 前缀(旧) ≈1191 > 全盘包含(新) ≈920 > 热目录包含(旧) ≈791
            let fm = FileManager.default
            let now = Date()
            let old = now.addingTimeInterval(-60 * 86_400)
            let exactOld = downloadsURL.appendingPathComponent("全盘检索中文")
            let prefixNew = downloadsURL.appendingPathComponent("全盘检索中文zzz新.txt")
            let prefixOld = downloadsURL.appendingPathComponent("全盘检索中文aaa旧.txt")
            let hotContainsOld = downloadsURL.appendingPathComponent("atools旧的全盘检索中文文件.txt")
            for (url, date) in [(exactOld, old), (prefixNew, now), (prefixOld, old), (hotContainsOld, old)] {
                try? "rank".data(using: .utf8)?.write(to: url)
                try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
            SpotlightBridge.shared.warmHotFolderCache(maxAge: 0)

            let ranked = fullDiskSearch("全盘检索中文")
            let rankedPaths = ranked.map(\.path)
            for u in [exactOld, prefixNew, prefixOld, hotContainsOld] {
                TestAssertions.expect(rankedPaths.contains(u.path),
                                      "排序夹具必须出现在结果中: \(u.lastPathComponent)")
            }
            func idx(_ u: URL) -> Int? { ranked.firstIndex { $0.path == u.path } }
            if let iExact = idx(exactOld), let iPrefixNew = idx(prefixNew),
               let iPrefixOld = idx(prefixOld), let iHome = idx(homeFixture),
               let iHotOld = idx(hotContainsOld) {
                TestAssertions.expect(iExact < iPrefixNew,
                                      "精确匹配（旧）必须排在新鲜的前缀匹配之前：档位优先于新鲜度")
                TestAssertions.expect(iPrefixNew < iPrefixOld,
                                      "同档位内新文件必须排在旧文件之前")
                TestAssertions.expect(iHome < iHotOld,
                                      "全盘结果必须能排到热目录弱命中之前（归并排序，非拼接）")
                print("      ✓ 方案 A 归并排序（档位>新鲜度、同档新者优先、全局归并）通过.")
            } else {
                TestAssertions.expect(false, "排序断言所需的 5 个夹具必须全部出现在结果中")
            }
            for u in [exactOld, prefixNew, prefixOld, hotContainsOld] {
                try? fm.removeItem(at: u)
            }
        }
        try? FileManager.default.removeItem(at: homeFixture)

        // (d) 本地化目录（.localized）全盘检索与显示名回归
        let vmPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Virtual Machines.localized").path
        if FileManager.default.fileExists(atPath: vmPath) {
            let vmResults = fullDiskSearch("虚拟机")
            let hit = vmResults.first { $0.path == vmPath }
            TestAssertions.expect(hit != nil, "全盘检索'虚拟机'必须能命中本地化目录 '~/Virtual Machines.localized'")
            if let hit = hit {
                TestAssertions.expect(hit.title == "虚拟机", "检索结果 Title 必须为本地化名称'虚拟机'而非'Virtual Machines.localized'")
                TestAssertions.expect(hit.score >= SearchRanking.tierExact - 100, "精确匹配的本地化目录必须处于 tierExact (1600) 档位梯队")
            }
            print("      ✓ 本地化目录（Virtual Machines.localized -> 虚拟机）端到端命中与档位回归通过.")
        }
    }

    // 6.2 热目录拼音匹配 + 单 ASCII 字符限定作用域（快照覆盖不到的深层文件）
    print("[6.2] Testing hot-folder pinyin match & scoped single-char search...")
    do {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        // (a) 拼音首字母/全拼：文件名里不含查询串，只有拼音路径能命中
        let pinyinFixture = downloads.appendingPathComponent("热目录拼音验证报告.txt")
        try? "py".data(using: .utf8)?.write(to: pinyinFixture)

        // (b) 深度 4 的文件：热目录快照只到 3 层，只能靠单字符限定作用域的 MDQuery
        let deepDir = downloads.appendingPathComponent("atools_scope/a/b")
        try? FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        let deepFixture = deepDir.appendingPathComponent("zq 单字符作用域 fixture.txt")
        try? "deep".data(using: .utf8)?.write(to: deepFixture)

        SpotlightBridge.shared.warmHotFolderCache(maxAge: 0)

        func search(_ q: String) -> [SearchResult] {
            var out: [SearchResult] = []
            var done = false
            SpotlightBridge.shared.searchFiles(matching: q, limit: 40) { r in
                out = r
                done = true
            }
            let dl = Date().addingTimeInterval(6)
            while !done && Date() < dl {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            return out
        }

        // 拼音匹配基于内存快照，不依赖索引，立刻可验
        // 「热目录拼音验证报告」→ tokens [re,mu,lu,pin,yin,yan,zheng,bao,gao,txt]
        let abbr = search("rmlp")
        TestAssertions.expect(abbr.contains { $0.path == pinyinFixture.path },
                              "拼音首字母 rmlp 必须命中「热目录拼音验证报告.txt」")
        let full = search("remulupinyin")
        TestAssertions.expect(full.contains { $0.path == pinyinFixture.path },
                              "拼音全拼必须命中「热目录拼音验证报告.txt」")
        print("      ✓ 拼音首字母/全匹匹配通过.")

        // 深层文件需等 Spotlight 索引（单字符查询走限定作用域的 MDQuery）
        let mdimport = Process()
        mdimport.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        mdimport.arguments = [downloads.path]
        let deepNeedle = MetadataFileSearchBackend.predicateText(matching: "单字符作用域")
        func deepIndexed() -> Bool {
            guard let mq = MDQueryCreate(kCFAllocatorDefault, deepNeedle as CFString,
                                         [kMDItemPath!] as CFArray, [] as CFArray) else { return false }
            MDQuerySetSearchScope(mq, [downloads as CFURL] as CFArray, 0)
            guard MDQueryExecute(mq, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return false }
            for i in 0..<MDQueryGetResultCount(mq) {
                guard let raw = MDQueryGetResultAtIndex(mq, i) else { continue }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                if let p = MDItemCopyAttribute(item, kMDItemPath) as? String, p == deepFixture.path { return true }
            }
            return false
        }
        var ready = false
        let indexDeadline = Date().addingTimeInterval(25)
        while Date() < indexDeadline {
            try? mdimport.run()
            mdimport.waitUntilExit()
            if deepIndexed() { ready = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        TestAssertions.expect(ready, "深层夹具必须被 Spotlight 索引")

        if ready {
            let single = search("z")
            TestAssertions.expect(single.contains { $0.path == deepFixture.path },
                                  "单 ASCII 字符必须通过限定作用域的 MDQuery 命中快照之外(深度>3)的文件")
            print("      ✓ 单字符限定作用域检索通过.")
        }

        try? FileManager.default.removeItem(at: pinyinFixture)
        try? FileManager.default.removeItem(at: downloads.appendingPathComponent("atools_scope"))
    }

    // 6.3 自定义热目录：校验负例 + 配置持久化往返 + 快照即时命中
    print("[6.3] Testing custom hot folders (validation, round-trip, snapshot search)...")
    do {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let extraDir = home.appendingPathComponent("atools_extra_hot_自定义")
        try? fm.createDirectory(at: extraDir, withIntermediateDirectories: true)
        let fixture = extraDir.appendingPathComponent("自定义热目录即时命中文件.txt")
        try? "hot".data(using: .utf8)?.write(to: fixture)

        let originalFolders = ConfigManager.shared.config.extraHotFolders

        // 校验负例
        TestAssertions.expect(ConfigManager.shared.validatedHotFolderPath("/") == nil, "必须拒绝根路径")
        TestAssertions.expect(ConfigManager.shared.validatedHotFolderPath(home.path) == nil, "必须拒绝家目录本身")
        TestAssertions.expect(ConfigManager.shared.validatedHotFolderPath(home.appendingPathComponent("Downloads").path) == nil,
                              "必须拒绝默认热目录")
        TestAssertions.expect(ConfigManager.shared.validatedHotFolderPath("/不存在的目录_atools_xyz") == nil,
                              "必须拒绝不存在的目录")

        // 正例 + 重复拒绝 + 持久化往返
        TestAssertions.expect(ConfigManager.shared.addHotFolder(extraDir.path), "合法目录必须能添加")
        TestAssertions.expect(ConfigManager.shared.addHotFolder(extraDir.path) == false, "重复添加必须被拒绝")
        if let json = try? JSONEncoder().encode(ConfigManager.shared.config),
           let decoded = try? JSONDecoder().decode(AtoolsConfig.self, from: json) {
            TestAssertions.expect(decoded.extraHotFolders.contains(extraDir.path),
                                  "extraHotFolders 必须能持久化往返")
        } else {
            TestAssertions.expect(false, "配置编码/解码不得失败")
        }

        // 端到端：快照包含自定义目录，文件名匹配即时命中（不依赖 Spotlight 索引）
        var hits: [SearchResult] = []
        var done = false
        SpotlightBridge.shared.searchFiles(matching: "自定义热目录即时命中", limit: 40) { r in
            hits = r
            done = true
        }
        let dl = Date().addingTimeInterval(6)
        while !done && Date() < dl {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if hits.contains(where: { $0.path == fixture.path }) {
            print("      ✓ 自定义热目录（校验/往返/快照命中）通过.")
        } else {
            TestAssertions.expect(false, "自定义热目录中的文件必须被内存快照命中")
        }

        // 清理：恢复原配置与磁盘
        ConfigManager.shared.removeHotFolder(extraDir.path)
        TestAssertions.expect(ConfigManager.shared.config.extraHotFolders == originalFolders,
                              "清理后配置必须复原")
        try? fm.removeItem(at: extraDir)
    }

    // 6.4 按文件类型搜索（SearchTypeFilter）回归：扩展名匹配、MDQuery 谓词解析、前缀提取与端到端协同
    print("[6.4] Testing SearchTypeFilter (predicates, extensions, prefix parsing & coordinated filtering)...")
    do {
        // (a) 检查 8 类枚举与显示名称、SF Symbol
        TestAssertions.expect(SearchTypeFilter.allCases.count == 8, "SearchTypeFilter 必须包含全部 8 个分类")
        TestAssertions.expect(SearchTypeFilter.all.displayName == "全部", "全部显示名称为'全部'")
        TestAssertions.expect(SearchTypeFilter.code.displayName == "代码", "代码显示名称为'代码'")
        TestAssertions.expect(SearchTypeFilter.document.displayName == "文档", "文档显示名称为'文档'")

        // (b) 检查前缀语法解析
        let p1 = SearchTypeFilter.extractPrefix(from: "doc: 财报分析")
        TestAssertions.expect(p1?.filter == .document && p1?.query == "财报分析", "前缀 'doc: 财报分析' 必须解析为 document 和 '财报分析'")
        let p2 = SearchTypeFilter.extractPrefix(from: "#img app_icon")
        TestAssertions.expect(p2?.filter == .image && p2?.query == "app_icon", "前缀 '#img app_icon' 必须解析为 image 和 'app_icon'")
        let p3 = SearchTypeFilter.extractPrefix(from: "code: main.swift")
        TestAssertions.expect(p3?.filter == .code && p3?.query == "main.swift", "前缀 'code: main.swift' 必须解析为 code 和 'main.swift'")
        let p4 = SearchTypeFilter.extractPrefix(from: "纯文本无前缀")
        TestAssertions.expect(p4 == nil, "普通输入不得误提取为前缀")

        // (c) 检查 matches(filename:isDirectory:) 规则
        TestAssertions.expect(SearchTypeFilter.all.matches(filename: "anything.xyz", isDirectory: false), ".all 匹配任何文件")
        TestAssertions.expect(SearchTypeFilter.document.matches(filename: "report.pdf", isDirectory: false), ".document 匹配 .pdf")
        TestAssertions.expect(SearchTypeFilter.document.matches(filename: "paper.docx", isDirectory: false), ".document 匹配 .docx")
        TestAssertions.expect(SearchTypeFilter.document.matches(filename: "photo.png", isDirectory: false) == false, ".document 不匹配 .png")
        TestAssertions.expect(SearchTypeFilter.image.matches(filename: "banner.webp", isDirectory: false), ".image 匹配 .webp")
        TestAssertions.expect(SearchTypeFilter.code.matches(filename: "main.swift", isDirectory: false), ".code 匹配 .swift")
        TestAssertions.expect(SearchTypeFilter.code.matches(filename: "script.ts", isDirectory: false), ".code 匹配 .ts")
        TestAssertions.expect(SearchTypeFilter.code.matches(filename: "server.go", isDirectory: false), ".code 匹配 .go")
        TestAssertions.expect(SearchTypeFilter.code.matches(filename: "lib.rs", isDirectory: false), ".code 匹配 .rs")
        TestAssertions.expect(SearchTypeFilter.folder.matches(filename: "MyFolder", isDirectory: true), ".folder 匹配普通目录")
        TestAssertions.expect(SearchTypeFilter.folder.matches(filename: "Safari.app", isDirectory: true) == false, ".folder 严禁匹配 .app 目录")
        TestAssertions.expect(SearchTypeFilter.application.matches(filename: "Safari.app", isDirectory: true), ".application 匹配 .app")

        // (d) 检查 MDQuery 谓词合法性（所有带 filter 的谓词必须能被 MDQueryCreate 成功解析）
        for filter in SearchTypeFilter.allCases {
            let pred = MetadataFileSearchBackend.predicateText(matching: "test", filter: filter)
            var parsed = false
            if let mq = MDQueryCreate(kCFAllocatorDefault, pred as CFString,
                                      [kMDItemPath!] as CFArray, [] as CFArray) {
                MDQuerySetSearchScope(mq, [kMDQueryScopeComputer!] as CFArray, 0)
                parsed = MDQueryExecute(mq, CFOptionFlags(kMDQuerySynchronous.rawValue))
            }
            TestAssertions.expect(parsed, "带 filter '\(filter.rawValue)' 的 MDQuery 谓词必须可解析: \(pred)")
        }

        // (e) 检查 SearchCoordinator 端到端分类协同（应用直出 & 文件分类过滤）
        var appHits: [SearchResult] = []
        var appDone = false
        SearchCoordinator.shared.search(query: "Safari", filter: .application) { r in
            appHits = r
            appDone = true
        }
        let appDl = Date().addingTimeInterval(0.5)
        while !appDone && Date() < appDl {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        TestAssertions.expect(appHits.allSatisfy { $0.type == .application }, "application 筛选下的所有结果必须全为 application 类型")

        print("      ✓ SearchTypeFilter（规则/谓词/前缀/端到端协同）全部验证通过.")
    }

    // 6.5 分类胶囊拖动排序与持久化回归：缺省容错、去重补全、编码往返与快捷键动态映射
    print("[6.5] Testing search filter reordering (resolution, persistence, and shortcut alignment)...")
    do {
        // (a) 缺省解析
        let defaultFilters = SearchTypeFilter.resolvedOrder(from: [])
        TestAssertions.expect(defaultFilters.count == 8, "空输入必须平滑回退到默认 8 分类")
        TestAssertions.expect(defaultFilters.first == .all, "默认首项必须为 .all")

        // (b) 自定义顺序解析（含脏数据、重复项与未包含项补齐）
        let customOrder = ["code", "document", "invalid_garbage", "code", "image"]
        let resolved = SearchTypeFilter.resolvedOrder(from: customOrder)
        TestAssertions.expect(resolved.count == 8, "脏数据去重后仍需补齐全部 8 分类且无重复")
        TestAssertions.expect(resolved[0] == .code, "首项必须为 code")
        TestAssertions.expect(resolved[1] == .document, "第二项必须为 document")
        TestAssertions.expect(resolved[2] == .image, "第三项必须为 image")
        TestAssertions.expect(Set(resolved).count == 8, "解析后的分类集合必须完整且唯一")

        // (c) AtoolsConfig 序列化与持久化往返
        let originalOrder = ConfigManager.shared.config.searchFilterOrder
        let testOrder = ["folder", "archive", "code", "all", "document", "image", "audio", "application"]
        ConfigManager.shared.updateSearchFilterOrder(testOrder)
        TestAssertions.expect(ConfigManager.shared.config.searchFilterOrder == testOrder, "内存配置必须即时更新")

        if let data = try? JSONEncoder().encode(ConfigManager.shared.config),
           let decoded = try? JSONDecoder().decode(AtoolsConfig.self, from: data) {
            TestAssertions.expect(decoded.searchFilterOrder == testOrder, "searchFilterOrder 必须能完整 JSON 往返")
        } else {
            TestAssertions.expect(false, "配置编码/解码不得失败")
        }

        // (d) SearchFilterBarView 胶囊排列与 ⌘1~8 / Tab 视觉顺序动态对齐
        let bar = SearchFilterBarView()
        bar.loadPills(from: ["code", "document", "all"])
        TestAssertions.expect(bar.orderedFilters[0] == .code, "第一张胶囊必须为 code")
        TestAssertions.expect(bar.orderedFilters[1] == .document, "第二张胶囊必须为 document")
        TestAssertions.expect(bar.orderedFilters[2] == .all, "第三张胶囊必须为 all")

        bar.selectFilter(number: 1)
        TestAssertions.expect(bar.selectedFilter == .code, "⌘1 必须动态选中当前第一张胶囊 (code)")
        bar.selectFilter(number: 2)
        TestAssertions.expect(bar.selectedFilter == .document, "⌘2 必须动态选中当前第二张胶囊 (document)")
        bar.cycleFilter(forward: true)
        TestAssertions.expect(bar.selectedFilter == .all, "Tab 顺次切换必须选中第三张胶囊 (all)")

        // 恢复原配置
        ConfigManager.shared.updateSearchFilterOrder(originalOrder)
        print("      ✓ 分类胶囊排序（容错补齐/持久化往返/快捷键动态对齐）通过.")
    }


    var coordinatorResults: [SearchResult] = []
    var isCoordDone = false
    SearchCoordinator.shared.search(query: "999生僻词测试XYZ") { results in
        coordinatorResults = results
        isCoordDone = true
    }
    let coordDeadline = Date().addingTimeInterval(0.5)
    while !isCoordDone && Date() < coordDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    TestAssertions.expect(!coordinatorResults.isEmpty, "SearchCoordinator must always deliver web search fallback for non-empty input")
    TestAssertions.expect(coordinatorResults.last?.type == .webSearch, "Last result should be webSearch fallback")
    print("      ✓ SearchCoordinator guaranteed instant feedback verified (never empty for non-empty queries).")

    // Test SearchCoordinator for universal app keyword (Safari)
    var safariResults: [SearchResult] = []
    var gotSafari = false
    SearchCoordinator.shared.search(query: "Safari") { results in
        if results.contains(where: { $0.type == .application }) {
            gotSafari = true
            safariResults = results
        }
    }
    let safariDeadline = Date().addingTimeInterval(3.0)
    while !gotSafari && Date() < safariDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    TestAssertions.expect(gotSafari, "SearchCoordinator should find matches for 'Safari'")
    print("      ✓ SearchCoordinator found \(safariResults.count) results for keyword 'Safari'.")

    // 7. Test Memory Usage
    print("[7/7] Testing Baseline Memory (Footprint)...")
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    if kerr == KERN_SUCCESS {
        // phys_footprint matches Activity Monitor; RSS also counts pages shared
        // with every other process and reads 2-3x higher.
        let footprintMB = Double(info.phys_footprint) / (1024.0 * 1024.0)
        print(String(format: "      ✓ Physical Footprint: %.2f MB", footprintMB))
    }

    // Thumbnail cache cost limit applies to both image and generic caches without throwing.
    ThumbnailPipeline.shared.updateCostLimit(mb: ConfigManager.shared.config.thumbnailCacheLimitMB)
    ThumbnailPipeline.shared.clearCache()
    MemoryGuardian.shared.performImmediatePurge()
    print("      ✓ Thumbnail cache dual-cache limit & deep purge verified.")

    // 8. Test SettingsWindowController Layout & Render Preview
    print("[8/8] Testing SettingsWindowController Layout...")
    let settingsController = SettingsWindowController.shared
    settingsController.showSettingsWindow()
    if let win = settingsController.window, let contentView = win.contentView {
        win.displayIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        print("      ✓ Settings Window Frame: \(win.frame)")
        print("      ✓ Settings ContentView Frame: \(contentView.frame)")
        TestAssertions.expect(win.frame.width >= 500, "Window width should be at least 500")
        TestAssertions.expect(win.frame.height >= 600, "Window height should be at least 600")

        // Render to image
        if let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: "/tmp/settings_preview.png"))
                print("      ✓ Saved settings preview to /tmp/settings_preview.png")
            }
        }

        // Test switching to each tab with strict width consistency assertion
        for item in SettingsSidebarItem.allCases {
            // Find sidebar
            if let sidebar = contentView.subviews.first(where: { $0 is SettingsSidebarView }) as? SettingsSidebarView {
                sidebar.selectItem(item)
                win.displayIfNeeded()
                contentView.layoutSubtreeIfNeeded()
                print("      -> Tab [\(item.title)] Window Frame: \(win.frame), ContentView Bounds: \(contentView.bounds)")
                TestAssertions.expect(abs(win.frame.width - 780.0) < 0.5, "Tab \(item.title) caused window width jump: \(win.frame.width)")
                TestAssertions.expect(abs(contentView.bounds.width - 780.0) < 0.5, "Tab \(item.title) caused contentView width jump: \(contentView.bounds.width)")
                if let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
                    contentView.cacheDisplay(in: contentView.bounds, to: rep)
                    if let pngData = rep.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: URL(fileURLWithPath: "/tmp/settings_tab_\(item.rawValue).png"))
                    }
                }
            }
        }
        print("      ✓ Strict Window Width Invariance (780.0pt across all tabs) verified.")
    }

    // 9. Test ShelfPanel Badges Removed (Vertical & Horizontal)
    print("[9/9] Testing ShelfPanel Layout & Badge Removal...")
    let shelfPanel = PanelCoordinator.shared.shelfPanel
    ConfigManager.shared.updateCategoryOrientation(.horizontal)
    shelfPanel.prepareForDisplay()
    if let shelfContent = shelfPanel.contentView {
        shelfPanel.displayIfNeeded()
        shelfContent.layoutSubtreeIfNeeded()
        if let rep = shelfContent.bitmapImageRepForCachingDisplay(in: shelfContent.bounds) {
            shelfContent.cacheDisplay(in: shelfContent.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: "/tmp/shelf_preview.png"))
                print("      ✓ Saved horizontal shelf preview to /tmp/shelf_preview.png")
            }
        }
    }

    // Now test vertical orientation
    ConfigManager.shared.updateCategoryOrientation(.vertical)
    NotificationCenter.default.post(name: .atoolsCategoryOrientationDidChange, object: nil)
    shelfPanel.prepareForDisplay()
    if let shelfContent = shelfPanel.contentView {
        shelfPanel.displayIfNeeded()
        shelfContent.layoutSubtreeIfNeeded()
        if let rep = shelfContent.bitmapImageRepForCachingDisplay(in: shelfContent.bounds) {
            shelfContent.cacheDisplay(in: shelfContent.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: "/tmp/shelf_vertical_preview.png"))
                print("      ✓ Saved vertical shelf preview to /tmp/shelf_vertical_preview.png")
            }
        }
    }

    // 9.1 Test: Category Item Removal & Re-selection does NOT bring back removed item
    print("[9.1] Testing category item removal persistence on tab re-selection...")
    let shelfVC = shelfPanel.shelfViewController
    shelfVC.loadData()
    if let devCategory = ConfigManager.shared.config.categories.first(where: { $0.name == "开发" }) {
        let testDevItem = LauncherItem(name: "TestDevApp", itemType: .application, target: "/tmp/TestDevApp.app")
        ConfigManager.shared.addItems([testDevItem], to: devCategory.id)
        shelfVC.loadData()

        TestAssertions.expect(shelfVC.shelfGrid.items.contains(where: { $0.id == testDevItem.id }), "testDevItem should appear in shelfGrid")

        // Trigger item deletion via delegate (just like right-click '从分类中移除')
        shelfVC.shelfGrid(shelfVC.shelfGrid, didDeleteItem: testDevItem)

        // Verify item is removed from config and shelfGrid
        TestAssertions.expect(!ConfigManager.shared.config.categories.first(where: { $0.id == devCategory.id })!.items.contains(where: { $0.id == testDevItem.id }), "testDevItem should be removed from ConfigManager")
        TestAssertions.expect(!shelfVC.shelfGrid.items.contains(where: { $0.id == testDevItem.id }), "testDevItem should disappear from shelfGrid immediately")

        // Now simulate user clicking the '开发' category tab again
        shelfVC.categoryBar(shelfVC.categoryBar, didSelectCategory: devCategory)

        // Verify that re-clicking category does NOT bring back the deleted item
        TestAssertions.expect(!shelfVC.shelfGrid.items.contains(where: { $0.id == testDevItem.id }), "testDevItem MUST NOT reappear after re-selecting category tab")
        TestAssertions.expect(!(shelfVC.selectedCategory?.items.contains(where: { $0.id == testDevItem.id }) ?? false), "selectedCategory MUST NOT contain deleted item")
        print("      ✓ Category item deletion persistence on re-selection verified.")
    }

    // 9.2 Test: Drag-and-drop onto Category Tab & Auto-entering Category
    print("[9.2] Testing Drag-and-drop to Category Tab & Auto-entering Category...")
    if ConfigManager.shared.config.categories.count >= 2 {
        let catA = ConfigManager.shared.config.categories[0]
        let catB = ConfigManager.shared.config.categories[1]
        let testDragItem = LauncherItem(name: "TestDragLauncherApp", itemType: .application, target: "/tmp/TestDragLauncherApp.app")
        ConfigManager.shared.addItems([testDragItem], to: catA.id)
        shelfVC.loadData()
        shelfVC.categoryBar(shelfVC.categoryBar, didSelectCategory: catA)
        TestAssertions.expect(shelfVC.selectedCategory?.id == catA.id, "catA should be selected initially")

        // 1. Move internal item to catB by dropping onto catB's tab
        shelfVC.categoryBar(shelfVC.categoryBar, didMoveLauncherItem: testDragItem, to: catB)

        // Verify that:
        // a) Item was moved to catB in ConfigManager
        TestAssertions.expect(ConfigManager.shared.config.categories.first(where: { $0.id == catB.id })!.items.contains(where: { $0.id == testDragItem.id }), "testDragItem should now belong to catB")
        TestAssertions.expect(!ConfigManager.shared.config.categories.first(where: { $0.id == catA.id })!.items.contains(where: { $0.id == testDragItem.id }), "testDragItem should no longer belong to catA")
        // b) ShelfViewController automatically entered catB!
        TestAssertions.expect(shelfVC.selectedCategory?.id == catB.id, "ShelfViewController MUST automatically enter catB after drop!")
        TestAssertions.expect(shelfVC.shelfGrid.items.contains(where: { $0.id == testDragItem.id }), "ShelfGrid MUST display catB items including testDragItem immediately!")

        // 2. Drop external file path directly onto catA's tab
        shelfVC.categoryBar(shelfVC.categoryBar, didAddPaths: ["/tmp/ExternalDroppedApp.app"], to: catA)
        TestAssertions.expect(shelfVC.selectedCategory?.id == catA.id, "ShelfViewController MUST enter catA after external file drop!")
        TestAssertions.expect(shelfVC.shelfGrid.items.contains(where: { $0.name == "ExternalDroppedApp" }), "ShelfGrid MUST contain newly dropped external app in catA!")

        // Clean up test items
        ConfigManager.shared.removeItem(id: testDragItem.id, from: catB.id)
        if let extItem = shelfVC.shelfGrid.items.first(where: { $0.name == "ExternalDroppedApp" }) {
            ConfigManager.shared.removeItem(id: extItem.id, from: catA.id)
        }
        shelfVC.loadData()
        print("      ✓ Drag-and-drop to category tab with immediate category entrance verified.")
    }

    // 10. Test SearchPanel Spotlight Collapsed & Expanded Layout
    print("[10/10] Testing SearchPanel Spotlight Collapsed & Expanded Animation...")
    let searchPanel = PanelCoordinator.shared.searchPanel
    searchPanel.prepareForDisplay()
    let searchVC = searchPanel.searchViewController
    TestAssertions.expect(searchPanel.frame.height == 72, "SearchPanel initial height should be 72pt (collapsed)")
    TestAssertions.expect(searchVC.resultsTable.isHidden == true, "resultsTable should be hidden in collapsed state")

    // Render collapsed preview (single bar)
    if let searchContent = searchPanel.contentView {
        searchPanel.displayIfNeeded()
        searchContent.layoutSubtreeIfNeeded()
        if let rep = searchContent.bitmapImageRepForCachingDisplay(in: searchContent.bounds) {
            searchContent.cacheDisplay(in: searchContent.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: "/tmp/search_collapsed_preview.png"))
                print("      ✓ Saved collapsed search preview to /tmp/search_collapsed_preview.png")
            }
        }
    }

    // Typing then clearing the query must not walk the panel down the screen.
    let anchoredTop = searchPanel.frame.maxY
    for _ in 0..<3 {
        searchVC.updatePanelHeight(hasResults: true, resultCount: 4, animated: false)
        TestAssertions.expect(abs(searchPanel.frame.maxY - anchoredTop) < 0.5, "Expanding must keep the panel's top edge fixed")
        searchVC.updatePanelHeight(hasResults: false, resultCount: 0, animated: false)
        TestAssertions.expect(abs(searchPanel.frame.maxY - anchoredTop) < 0.5, "Collapsing must keep the panel's top edge fixed")
    }
    print("      ✓ Search panel top edge stays fixed across repeated expand/collapse.")

    // Now test expansion
    searchVC.updatePanelHeight(hasResults: true, resultCount: 4, animated: false)
    TestAssertions.expect(searchPanel.frame.height > 72, "SearchPanel height should expand when results exist")
    TestAssertions.expect(searchVC.resultsTable.isHidden == false, "resultsTable should be visible when expanded")

    // Populate dummy results for preview rendering
    let homePath = FileManager.default.homeDirectoryForCurrentUser.path
    let dummyResults = [
        SearchResult(title: "工作周报与项目规划.xlsx", subtitle: "\(homePath)/Documents/工作周报与项目规划.xlsx", path: "\(homePath)/Documents/工作周报与项目规划.xlsx", type: .file),
        SearchResult(title: "macOS生产力工具架构指南.docx", subtitle: "\(homePath)/Documents/macOS生产力工具架构指南.docx", path: "\(homePath)/Documents/macOS生产力工具架构指南.docx", type: .file),
        SearchResult(title: "开源开发项目仓库", subtitle: "\(homePath)/Developer/开源开发项目仓库", path: "\(homePath)/Developer/开源开发项目仓库", type: .folder),
        SearchResult(title: "Safari 浏览器", subtitle: "/Applications/Safari.app", path: "/Applications/Safari.app", type: .application)
    ]
    searchVC.searchBar.text = "西湖"
    searchVC.resultsTable.updateResults(dummyResults)
    searchVC.resultsTable.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    searchVC.updatePanelHeight(hasResults: true, resultCount: dummyResults.count, animated: false)
    searchPanel.makeKeyAndOrderFront(nil)

    // Render expanded preview
    if let searchContent = searchPanel.contentView {
        searchPanel.displayIfNeeded()
        searchContent.layoutSubtreeIfNeeded()
        if let rep = searchContent.bitmapImageRepForCachingDisplay(in: searchContent.bounds) {
            searchContent.cacheDisplay(in: searchContent.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: URL(fileURLWithPath: "/tmp/search_expanded_preview.png"))
                print("      ✓ Saved expanded search preview to /tmp/search_expanded_preview.png")
            }
        }
    }

    // 11. Test ShelfPanel Topmost Level & UpdateManager Semantic Versioning
    print("[11/11] Testing ShelfPanel Topmost Level, Window Hierarchies & UpdateManager...")
    TestAssertions.expect(shelfPanel.level == .statusBar, "ShelfPanel level MUST be .statusBar")
    TestAssertions.expect(shelfPanel.hidesOnDeactivate == false, "ShelfPanel hidesOnDeactivate MUST be false")

    if let settingsWin = SettingsWindowController.shared.window {
        TestAssertions.expect(settingsWin.level == .normal, "Settings window level MUST be .normal (not globally pinned)")
    }

    // Semantic Versioning Tests
    TestAssertions.expect(UpdateManager.isVersion("v1.0.1", greaterThan: "1.0.0") == true, "v1.0.1 > 1.0.0")
    TestAssertions.expect(UpdateManager.isVersion("1.0.10", greaterThan: "1.0.2") == true, "1.0.10 > 1.0.2")
    TestAssertions.expect(UpdateManager.isVersion("1.0", greaterThan: "1.0.0") == false, "1.0 should equal 1.0.0")
    TestAssertions.expect(UpdateManager.isVersion("1.0.0", greaterThan: "1.0") == false, "1.0.0 should equal 1.0")
    TestAssertions.expect(UpdateManager.isVersion("1.0.0", greaterThan: "v1.0.1") == false, "1.0.0 < 1.0.1")
    TestAssertions.expect(UpdateManager.isVersion("2.0.0", greaterThan: "1.9.99") == true, "2.0.0 > 1.9.99")
    print("      ✓ UpdateManager semantic versioning algorithm verified.")

    // 签名校验回归：ad-hoc 包的 `codesign -dr` 输出只有 cdhash，不含 identifier，
    // 必须走 -dv 的 Identifier= 兜底；否则所有 ad-hoc 正式包更新都会报
    // “更新包 designated requirement 无效”（v1.2.2 起的历史 bug）。
    let repoAppBundle = FileManager.default.currentDirectoryPath + "/ATools.app"
    if FileManager.default.fileExists(atPath: repoAppBundle) {
        do {
            try UpdateManager.validateCodeSignature(at: repoAppBundle, currentAppPath: repoAppBundle)
            print("      ✓ ad-hoc 更新包签名校验通过（DR 仅 cdhash 时走 Identifier= 兑底）")
        } catch {
            TestAssertions.expect(false, "ad-hoc 更新包必须通过签名校验，但被拒：\(error.localizedDescription)")
        }

        // 负例：非本应用的签名包必须被拒绝
        let foreignApp = "/System/Applications/Utilities/Terminal.app"
        if FileManager.default.fileExists(atPath: foreignApp) {
            var rejected = false
            do {
                try UpdateManager.validateCodeSignature(at: foreignApp, currentAppPath: repoAppBundle)
            } catch {
                rejected = true
            }
            TestAssertions.expect(rejected, "外源签名包必须被签名校验拒绝")
        }
        print("      ✓ 更新包签名校验正/反例验证完成.")

        // 签名指纹 pinning（自签名证书迁移路径的纯函数回归）
        let drCert = "designated => identifier \"cc.atools.app\" and certificate leaf = H\"AABBCC1122\""
        let drAdhoc = "# designated => cdhash H\"1ea93cbc6183c810\""
        TestAssertions.expect(UpdateManager.certificateLeafHash(in: drCert) == "AABBCC1122",
                              "必须解析出 certificate leaf 指纹")
        TestAssertions.expect(UpdateManager.certificateLeafHash(in: drAdhoc) == nil,
                              "ad-hoc DR 无 leaf，必须返回 nil")
        TestAssertions.expect(UpdateManager.certificateLeafHash(in: "garbage") == nil,
                              "无 leaf 的任意输入必须返回 nil")
        TestAssertions.expect(UpdateManager.acceptsUpdateWithoutTeam(
            stagedIsAdhoc: true, stagedTeam: nil, stagedRequirement: drAdhoc, pinnedLeafHashes: []),
            "ad-hoc 客户端必须接受 ad-hoc 包（历史行为）")
        TestAssertions.expect(!UpdateManager.acceptsUpdateWithoutTeam(
            stagedIsAdhoc: false, stagedTeam: nil, stagedRequirement: drCert, pinnedLeafHashes: []),
            "指纹未 pin 时必须拒绝证书包（与旧版一致）")
        TestAssertions.expect(UpdateManager.acceptsUpdateWithoutTeam(
            stagedIsAdhoc: false, stagedTeam: nil, stagedRequirement: drCert, pinnedLeafHashes: ["aabbcc1122"]),
            "指纹命中（忽略大小写）必须放行")
        TestAssertions.expect(UpdateManager.acceptsUpdateWithoutTeam(
            stagedIsAdhoc: false, stagedTeam: nil, stagedRequirement: drCert, pinnedLeafHashes: ["FFEEDD", "aabbcc1122"]),
            "双指纹过渡：新旧并存时命中任一项即放行")
        TestAssertions.expect(!UpdateManager.acceptsUpdateWithoutTeam(
            stagedIsAdhoc: false, stagedTeam: nil, stagedRequirement: drCert, pinnedLeafHashes: ["FFEEDD", "9988"]),
            "指纹列表全部不匹配必须拒绝")
        print("      ✓ 签名指纹 pinning（解析/放行/拒绝/双指纹过渡）回归通过.")
    }

    let releaseAssets: [[String: Any]] = [
        ["name": "ATools.zip", "browser_download_url": "https://example.com/ATools.zip"],
        ["name": "ATools.dmg", "browser_download_url": "https://example.com/ATools.dmg"]
    ]
    let preferredAsset = UpdateManager.preferredReleaseAsset(from: releaseAssets)
    TestAssertions.expect(preferredAsset?.name == "ATools.dmg", "DMG should be preferred over ZIP")
    TestAssertions.expect(preferredAsset?.url.absoluteString.hasSuffix("/ATools.dmg") == true, "Preferred asset URL should be preserved")
    let zipOnlyAsset = UpdateManager.preferredReleaseAsset(from: [releaseAssets[0]])
    TestAssertions.expect(zipOnlyAsset?.name == "ATools.zip", "ZIP should be used when DMG is unavailable")
    TestAssertions.expect(UpdateManager.normalizedVersion("v1.1.1") == "1.1.1", "Normalized version should strip the v prefix")
    TestAssertions.expect(UpdateManager.isBlockedUpdateLocation("/private/var/folders/abc/AppTranslocation/123/d/ATools.app"), "AppTranslocation must block in-place update")
    TestAssertions.expect(UpdateManager.isBlockedUpdateLocation("/Volumes/ATools/ATools.app"), "Read-only DMG volume must block in-place update")
    TestAssertions.expect(!UpdateManager.isBlockedUpdateLocation("/Applications/ATools.app"), "Applications folder should allow in-place update")
    print("      ✓ UpdateManager asset selection and update-location guards verified.")

    // Check About Tab Layout Width (ensure strict 780.0pt)
    SettingsWindowController.shared.selectTab(.about)
    if let win = SettingsWindowController.shared.window {
        win.displayIfNeeded()
        win.contentView?.layoutSubtreeIfNeeded()
        TestAssertions.expect(abs(win.frame.width - 780.0) < 0.5, "About tab window width MUST be 780.0pt, got \(win.frame.width)")
        if let aboutContent = win.contentView {
            aboutContent.layoutSubtreeIfNeeded()
            if let rep = aboutContent.bitmapImageRepForCachingDisplay(in: aboutContent.bounds) {
                aboutContent.cacheDisplay(in: aboutContent.bounds, to: rep)
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: URL(fileURLWithPath: "/tmp/about_preview.png"))
                    print("      ✓ Saved About tab preview to /tmp/about_preview.png")
                }
            }
        }
        print("      ✓ About Tab with update manager maintains strictly 780.0pt width.")
    }

    // 12. Test AutoQuitManager: Config Round-trip & Watch Rules (Pure Functions)
    print("[12/12] Testing AutoQuit config persistence & watch rules...")
    do {
        // 4 个新字段 encode/decode 往返
        var autoQuitCfg = ConfigManager.shared.config
        autoQuitCfg.enableAutoQuit = true
        autoQuitCfg.autoQuitMode = .onlyListed
        autoQuitCfg.autoQuitAppRules = ["com.apple.TextEdit", "com.google.Chrome"]
        autoQuitCfg.autoQuitDelaySeconds = 5
        let autoQuitRoundtrip = try JSONDecoder().decode(AtoolsConfig.self, from: JSONEncoder().encode(autoQuitCfg))
        TestAssertions.expect(autoQuitRoundtrip.enableAutoQuit == true, "enableAutoQuit should round-trip")
        TestAssertions.expect(autoQuitRoundtrip.autoQuitMode == .onlyListed, "autoQuitMode should round-trip")
        TestAssertions.expect(autoQuitRoundtrip.autoQuitAppRules == ["com.apple.TextEdit", "com.google.Chrome"], "autoQuitAppRules should round-trip")
        TestAssertions.expect(autoQuitRoundtrip.autoQuitDelaySeconds == 5, "autoQuitDelaySeconds should round-trip")

        // 旧版配置（缺字段）必须落到安全默认：总开关关闭
        let autoQuitLegacy = try JSONDecoder().decode(AtoolsConfig.self, from: "{\"version\":4,\"categories\":[]}".data(using: .utf8)!)
        TestAssertions.expect(autoQuitLegacy.enableAutoQuit == false, "missing enableAutoQuit must default to OFF")
        TestAssertions.expect(autoQuitLegacy.autoQuitMode == .allApps, "missing autoQuitMode must default to .allApps")
        TestAssertions.expect(autoQuitLegacy.autoQuitAppRules.isEmpty, "missing autoQuitAppRules must default to []")
        TestAssertions.expect(autoQuitLegacy.autoQuitDelaySeconds == 2, "missing autoQuitDelaySeconds must default to 2s")

        // 解码期 clamp 越界延迟
        autoQuitCfg.autoQuitDelaySeconds = 999
        let clamped = try JSONDecoder().decode(AtoolsConfig.self, from: JSONEncoder().encode(autoQuitCfg))
        TestAssertions.expect(clamped.autoQuitDelaySeconds == 10, "autoQuitDelaySeconds must clamp to 10 on decode")

        // 监视资格纯函数：系统排除 / 自身 / 后台策略 / 未启动 / 无 bundleID
        let watch: (String?, NSApplication.ActivationPolicy, Bool, Bool, AutoQuitMode, [String]) -> Bool = {
            AutoQuitManager.shouldWatch(bundleID: $0, activationPolicy: $1, isFinishedLaunching: $2, isSelf: $3, mode: $4, rules: $5)
        }
        TestAssertions.expect(watch("com.apple.finder", .regular, true, false, .allApps, []) == false, "Finder must be system-excluded")
        TestAssertions.expect(watch("com.apple.Spotlight", .regular, true, false, .allApps, []) == false, "Spotlight must be system-excluded")
        TestAssertions.expect(watch("com.apple.notificationcenterui", .regular, true, false, .allApps, []) == false, "NotificationCenter must be system-excluded")
        TestAssertions.expect(watch("com.apple.dock", .regular, true, false, .allApps, []) == false, "Dock must be system-excluded")
        TestAssertions.expect(watch("cc.atools.app", .regular, true, true, .allApps, []) == false, "ATools itself must never be watched")
        TestAssertions.expect(watch("com.apple.TextEdit", .accessory, true, false, .allApps, []) == false, "Non-regular policy apps must not be watched")
        TestAssertions.expect(watch("com.apple.TextEdit", .regular, false, false, .allApps, []) == false, "Not-finished-launching apps must not be watched")
        TestAssertions.expect(watch(nil, .regular, true, false, .allApps, []) == false, "Processes without bundleID must not be watched")
        TestAssertions.expect(watch("com.apple.TextEdit", .regular, true, false, .allApps, []) == true, "allApps mode watches unlisted regular apps")
        TestAssertions.expect(watch("com.apple.TextEdit", .regular, true, false, .allApps, ["com.apple.TextEdit"]) == false, "allApps mode treats rules as exclusions")
        TestAssertions.expect(watch("com.apple.TextEdit", .regular, true, false, .onlyListed, ["com.apple.TextEdit"]) == true, "onlyListed mode treats rules as inclusions")
        TestAssertions.expect(watch("com.apple.TextEdit", .regular, true, false, .onlyListed, ["com.apple.textedit"]) == true, "onlyListed mode handles case-insensitive bundle IDs")
        TestAssertions.expect(watch("com.apple.TextEdit", .regular, true, false, .onlyListed, []) == false, "onlyListed mode ignores unlisted apps")

        // 零窗判定：AX 查询失败（nil）绝不能视为零窗，否则误杀
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(0) == true, "0 windows confirmed must schedule quit")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(nil) == false, "AX query failure must never count as zero windows")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(2) == false, "2 windows must not schedule quit")

        // 双重权威校验（WindowServer 交叉保护）：
        // 即使 AX 偶发报 0（如失焦、多虚拟桌面切换、临时浮层销毁），只要 WindowServer 确认有标准窗口，绝对不能退出！
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(axCount: 0, windowServerCount: 1) == false, "WindowServer has 1 window must protect app on focus loss")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(axCount: 0, windowServerCount: 3) == false, "WindowServer has 3 windows must protect background app")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(axCount: 0, windowServerCount: 0) == true, "Both AX and WindowServer 0 confirms window close")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(axCount: nil, windowServerCount: 0) == false, "AX failure must never quit even if WindowServer 0")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(axCount: 1, windowServerCount: 1) == false, "Active running window must not quit")
        TestAssertions.expect(AutoQuitManager.isConfirmedZeroWindowCount(axCount: 0, windowServerCount: nil) == true, "AX 0 with unknown WindowServer falls back to quit")
        print("      ✓ AutoQuit config round-trip, legacy defaults & watch rules verified.")
    } catch {
        TestAssertions.expect(false, "AutoQuit diagnostics threw: \(error)")
    }

    // 12.1. Test Regular App Filtering & Dual AutoQuit Rules
    print("[12.1] Testing allRegularApps UI filtering & dual AutoQuit rule lists...")
    do {
        // AppHotspotIndex regular apps filtering
        let allApps = AppHotspotIndex.shared.allApps
        let regularApps = AppHotspotIndex.shared.allRegularApps
        TestAssertions.expect(!allApps.isEmpty, "allApps should not be empty")
        TestAssertions.expect(!regularApps.isEmpty, "allRegularApps should not be empty")
        TestAssertions.expect(regularApps.count <= allApps.count, "regularApps should be a subset of allApps")

        // Exclusions verified: no prefPanes, no system-excluded daemons/Dock/Finder/Spotlight, no empty bundleIDs
        for app in regularApps {
            TestAssertions.expect(!app.path.hasSuffix(".prefPane"), "prefPanes must not be in regularApps: \(app.path)")
            if let bid = app.bundleId {
                TestAssertions.expect(!AutoQuitManager.systemExcludedBundleIDs.contains(bid), "System excluded app \(bid) must not be in regularApps")
                TestAssertions.expect(bid != "cc.atools.app" && bid != "cc.atools.app.dev", "ATools itself must not be in regularApps")
            } else {
                TestAssertions.expect(false, "Regular app must have a valid bundleId: \(app.name)")
            }
        }

        // Dual independent rules roundtrip & migration
        var dualConfig = ConfigManager.shared.config
        dualConfig.autoQuitExcludeAppRules = ["com.apple.Music"]
        dualConfig.autoQuitOnlyListedAppRules = ["com.dingtalk.mac", "com.tencent.xinWeChat"]
        let dualEncoded = try JSONEncoder().encode(dualConfig)
        let dualDecoded = try JSONDecoder().decode(AtoolsConfig.self, from: dualEncoded)
        TestAssertions.expect(dualDecoded.autoQuitExcludeAppRules == ["com.apple.Music"], "exclude rules must roundtrip independently")
        TestAssertions.expect(dualDecoded.autoQuitOnlyListedAppRules == ["com.dingtalk.mac", "com.tencent.xinWeChat"], "onlyListed rules must roundtrip independently")
        TestAssertions.expect(dualDecoded.rules(for: .allApps) == ["com.apple.Music"], "rules(for: .allApps) matches exclude list")
        TestAssertions.expect(dualDecoded.rules(for: .onlyListed) == ["com.dingtalk.mac", "com.tencent.xinWeChat"], "rules(for: .onlyListed) matches onlyListed list")

        // Legacy format migration
        let legacyOnlyListedJSON = """
        {"version":4,"autoQuitMode":"onlyListed","autoQuitAppRules":["com.dingtalk.mac"]}
        """.data(using: .utf8)!
        let migratedOnlyListed = try JSONDecoder().decode(AtoolsConfig.self, from: legacyOnlyListedJSON)
        TestAssertions.expect(migratedOnlyListed.autoQuitOnlyListedAppRules == ["com.dingtalk.mac"], "Legacy rules under onlyListed mode must migrate to autoQuitOnlyListedAppRules")
        TestAssertions.expect(migratedOnlyListed.autoQuitExcludeAppRules.isEmpty, "autoQuitExcludeAppRules remains empty on onlyListed legacy decode")

        let legacyExcludeJSON = """
        {"version":4,"autoQuitMode":"allApps","autoQuitAppRules":["com.apple.Safari"]}
        """.data(using: .utf8)!
        let migratedExclude = try JSONDecoder().decode(AtoolsConfig.self, from: legacyExcludeJSON)
        TestAssertions.expect(migratedExclude.autoQuitExcludeAppRules == ["com.apple.Safari"], "Legacy rules under allApps mode must migrate to autoQuitExcludeAppRules")
        TestAssertions.expect(migratedExclude.autoQuitOnlyListedAppRules.isEmpty, "autoQuitOnlyListedAppRules remains empty on allApps legacy decode")

        print("      ✓ allRegularApps UI filtering & dual AutoQuit rule independence verified.")
    } catch {
        TestAssertions.expect(false, "Regular apps & dual rules diagnostic failed: \(error)")
    }

    // 12.2. Test PanelCoordinator: Pinned Shelf Resilience & Hotkey Isolation
    print("[12.2] Testing PanelCoordinator pinned shelf resilience...")
    do {
        let coordinator = PanelCoordinator.shared
        coordinator.isShelfPinned = true
        coordinator.showShelfPanel()
        TestAssertions.expect(coordinator.shelfPanel.isVisible == true, "ShelfPanel should be visible after showShelfPanel")

        // Activating search panel while shelf is pinned MUST NOT dismiss shelf
        coordinator.showSearchPanel()
        TestAssertions.expect(coordinator.searchPanel.isVisible == true, "SearchPanel should be visible after showSearchPanel")
        TestAssertions.expect(coordinator.shelfPanel.isVisible == true, "ShelfPanel MUST remain visible when search panel opens while pinned")

        // Dismissing search panel MUST NOT dismiss shelf
        coordinator.hideSearchPanel(restoreFocus: false, animated: false)
        TestAssertions.expect(coordinator.searchPanel.isVisible == false, "SearchPanel should be hidden after hideSearchPanel")
        TestAssertions.expect(coordinator.shelfPanel.isVisible == true, "ShelfPanel MUST remain visible when search panel closes")

        // General hideAllPanels (e.g. outside click or app switch) MUST NOT dismiss pinned shelf
        coordinator.hideAllPanels(restoreFocus: false, animated: false, forceHidePinnedShelf: false)
        TestAssertions.expect(coordinator.shelfPanel.isVisible == true, "ShelfPanel MUST remain visible on default hideAllPanels")

        // Explicit shelf toggle hotkey MUST be able to dismiss and reopen pinned shelf
        coordinator.togglePanel(.shelf, animated: false)
        TestAssertions.expect(coordinator.shelfPanel.isVisible == false, "Shelf toggle hotkey MUST dismiss shelf even if pinned")

        coordinator.togglePanel(.shelf, animated: false)
        TestAssertions.expect(coordinator.shelfPanel.isVisible == true, "Shelf toggle hotkey MUST reopen shelf")

        // Cleanup
        coordinator.hideShelfPanel(restoreFocus: false, animated: false, forceHidePinned: true)
        coordinator.isShelfPinned = false
        print("      ✓ Pinned shelf resilience & hotkey isolation verified.")
    }

    if TestAssertions.failures > 0 {
        print(" [ATools] \(TestAssertions.failures) diagnostic expectation(s) failed.")
        try? FileManager.default.removeItem(at: testFixtureURL)
        try? FileManager.default.removeItem(at: tempTestDir)
        exit(1)
    }

    print("==================================================")
    print(" [ATools] All diagnostics PASSED successfully!")
    print("==================================================")

    // `defer` blocks don't run when the process ends through exit(), so clean up explicitly.
    try? FileManager.default.removeItem(at: testFixtureURL)
    try? FileManager.default.removeItem(at: tempTestDir)
    exit(0)
}

// Maintenance flag (no UI): inspect or flip login-item registration for *this* bundle path.
// The system keys SMAppService.mainApp items by the running app's bundle, so a dev copy
// and the installed copy register separately; running this flag per copy lets us clean up
// stale duplicates: `ATools --login-item [status|register|unregister]`
if CommandLine.arguments.contains("--login-item") {
    let action = CommandLine.arguments.dropFirst().last { $0 != "--login-item" } ?? "status"
    let controller = LaunchAtLoginController.shared
    do {
        switch action {
        case "register":
            try controller.setEnabled(true)
        case "unregister":
            try controller.setEnabled(false)
        case "status":
            break
        default:
            fputs("usage: ATools --login-item [status|register|unregister]\n", stderr)
            exit(2)
        }
        print("[login-item] bundle=\(Bundle.main.bundlePath) state=\(controller.state)")
    } catch {
        fputs("[login-item] \(action) failed: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
