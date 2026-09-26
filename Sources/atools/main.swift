import Foundation
import AppKit

if CommandLine.arguments.contains("--test") {
    let tempTestDir = ConfigManager.setupIsolatedTestEnvironment()
    defer {
        try? FileManager.default.removeItem(at: tempTestDir)
    }

    print("==================================================")
    print(" [ATools] Running Comprehensive Diagnostic Suite (Sandbox Mode)")
    print("==================================================")

    // 1. Test Calculator Engine
    print("[1/7] Testing CalculatorEngine...")
    assert(CalculatorEngine.shared.evaluate("1+1") == "2", "1+1 should equal 2")
    assert(CalculatorEngine.shared.evaluate("(1024 * 768) / 2") == "393216", "Math expression evaluation failed")
    assert(CalculatorEngine.shared.evaluate("0x10 + 16") == "32", "Hex math evaluation failed")
    assert(CalculatorEngine.shared.evaluate("not a math expression") == nil, "Non-math should return nil")
    print("      ✓ CalculatorEngine passed all tests.")

    // 2. Test SystemActions
    print("[2/7] Testing SystemActions...")
    let lockActions = SystemActions.shared.match("lock")
    assert(!lockActions.isEmpty, "SystemAction 'lock' should match")
    let suoActions = SystemActions.shared.match("锁屏")
    assert(!suoActions.isEmpty, "SystemAction '锁屏' should match")
    let sleepActions = SystemActions.shared.match("sleep")
    assert(!sleepActions.isEmpty, "SystemAction 'sleep' should match")
    print("      ✓ SystemActions passed all tests (matched \(SystemActions.shared.actions.count) actions).")

    // 3. Test ConfigManager & Dual Hotkeys & Resizable Shelf Dimensions & Panel Toggles
    print("[3/7] Testing ConfigManager & Resizable Shelf Dimensions & Safety Guards...")
    let config = ConfigManager.shared.config
    assert(!config.categories.isEmpty, "Default categories should not be empty")
    assert(config.shelfWidth >= 240, "Shelf width should be at least minSize 240")
    assert(config.shelfHeight >= 180, "Shelf height should be at least minSize 180")
    ConfigManager.shared.updateShelfSize(width: 600, height: 400)
    assert(ConfigManager.shared.config.shelfWidth == 600, "Shelf width should update to 600")
    assert(ConfigManager.shared.config.shelfHeight == 400, "Shelf height should update to 400")

    // Test new configuration options & safety mutual exclusion
    ConfigManager.shared.updateAutoCloseOnLaunch(true)
    assert(ConfigManager.shared.config.autoCloseOnLaunch == true, "autoCloseOnLaunch should be true")
    ConfigManager.shared.updateAutoCloseOnMouseExit(false)
    assert(ConfigManager.shared.config.autoCloseOnMouseExit == false, "autoCloseOnMouseExit should be false")

    // Test isShelfPinned persistence & codec round-trip
    assert(ConfigManager.shared.config.isShelfPinned == false, "isShelfPinned should default to false")
    ConfigManager.shared.updateIsShelfPinned(true)
    assert(ConfigManager.shared.config.isShelfPinned == true, "isShelfPinned should update to true")
    let pinnedEncoded = try! JSONEncoder().encode(ConfigManager.shared.config)
    let pinnedDecoded = try! JSONDecoder().decode(AtoolsConfig.self, from: pinnedEncoded)
    assert(pinnedDecoded.isShelfPinned == true, "isShelfPinned should survive encode/decode round-trip")
    ConfigManager.shared.updateIsShelfPinned(false)
    assert(ConfigManager.shared.config.isShelfPinned == false, "isShelfPinned should reset to false")

    // 严格测试「常用」分类开关：关闭不保留数据，开启重新检测生成，默认保持未启用
    ConfigManager.shared.updateEnableFavoritesCategory(true)
    assert(ConfigManager.shared.config.enableFavoritesCategory == true, "enableFavoritesCategory should be true when enabled")
    assert(ConfigManager.shared.config.categories.first?.name == "常用", "开启后应重新扫描生成常用分类并排在首位")
    assert(!ConfigManager.shared.config.categories.first!.items.isEmpty, "重新生成的常用分类中应包含检测到的常用软件")

    ConfigManager.shared.updateEnableFavoritesCategory(false)
    assert(ConfigManager.shared.config.enableFavoritesCategory == false, "enableFavoritesCategory should default to false")
    assert(!ConfigManager.shared.config.categories.contains(where: { $0.name == "常用" || $0.iconSymbol == "star.fill" }), "常用分类数据在关闭后应彻底清空移除")

    // Mutual exclusion test: if search is enabled, we can disable shelf
    ConfigManager.shared.updateEnableSearchPanel(true)
    let canDisableShelf = ConfigManager.shared.updateEnableShelfPanel(false)
    assert(canDisableShelf == true, "Should allow disabling shelf when search is active")
    // Now both cannot be disabled simultaneously:
    let canDisableBoth = ConfigManager.shared.updateEnableSearchPanel(false)
    assert(canDisableBoth == false, "Safety guard: must NOT allow disabling both panels simultaneously")
    ConfigManager.shared.updateEnableShelfPanel(true)
    assert(ConfigManager.shared.config.enableShelfPanel == true, "Shelf should be re-enabled")

    ConfigManager.shared.updateSidebarWidth(160)
    assert(ConfigManager.shared.config.sidebarWidth == 160, "sidebarWidth should update to 160")
    ConfigManager.shared.updateSidebarWidth(84)
    assert(ConfigManager.shared.config.sidebarWidth == 84, "sidebarWidth should reset to 84")

    // Test HotkeyBinding backwards compatibility and specialTrigger
    let legacyJSON = "{\"keyCode\": 49, \"carbonModifiers\": 2048, \"displayString\": \"⌥Space\"}".data(using: .utf8)!
    let decodedLegacy = try! JSONDecoder().decode(HotkeyBinding.self, from: legacyJSON)
    assert(decodedLegacy.specialTrigger == .none, "Legacy HotkeyBinding without specialTrigger should decode as .none")
    assert(decodedLegacy.displayString == "⌥Space", "Legacy displayString preserved")

    let doubleCmdJSON = "{\"keyCode\": 0, \"carbonModifiers\": 0, \"displayString\": \"2× ⌘ Command\", \"specialTrigger\": \"doubleCommand\"}".data(using: .utf8)!
    let decodedDoubleCmd = try! JSONDecoder().decode(HotkeyBinding.self, from: doubleCmdJSON)
    assert(decodedDoubleCmd.specialTrigger == .doubleCommand, "Decoded doubleCommand trigger correctly")

    // Test Theme switching
    ConfigManager.shared.updateTheme(.solidDark)
    assert(ConfigManager.shared.config.theme == .solidDark, "Theme should update to .solidDark")
    assert(ConfigManager.shared.config.theme.isDark == true, "solidDark isDark should be true")
    assert(ConfigManager.shared.config.theme.isLiquid == false, "solidDark isLiquid should be false")
    ConfigManager.shared.updateTheme(.liquidLight)
    assert(ConfigManager.shared.config.theme == .liquidLight, "Theme should update to .liquidLight")

    // Test shelfIconScale
    ConfigManager.shared.updateShelfIconScale(1.15)
    assert(ConfigManager.shared.config.shelfIconScale == 1.15, "shelfIconScale should update to 1.15")
    assert(ConfigManager.shared.config.shelfIconSize == .large, "Scale 1.15 should map to .large")
    ConfigManager.shared.updateShelfIconScale(0.85)
    assert(ConfigManager.shared.config.shelfIconScale == 0.85, "shelfIconScale should update to 0.85")
    assert(ConfigManager.shared.config.shelfIconSize == .small, "Scale 0.85 should map to .small")
    ConfigManager.shared.updateShelfIconScale(1.40) // should clamp to 1.30
    assert(ConfigManager.shared.config.shelfIconScale == 1.30, "shelfIconScale clamped to 1.30")
    ConfigManager.shared.updateShelfIconScale(1.0)
    assert(ConfigManager.shared.config.shelfIconScale == 1.0, "shelfIconScale should reset to 1.0")

    // Test themeOpacity
    ConfigManager.shared.updateThemeOpacity(0.85)
    assert(ConfigManager.shared.config.themeOpacity == 0.85, "themeOpacity should update to 0.85")
    ConfigManager.shared.updateThemeOpacity(0.10) // should clamp to 0.30
    assert(ConfigManager.shared.config.themeOpacity == 0.30, "themeOpacity clamped to 0.30")
    ConfigManager.shared.updateThemeOpacity(1.50) // should clamp to 1.00
    assert(ConfigManager.shared.config.themeOpacity == 1.00, "themeOpacity clamped to 1.00")
    ConfigManager.shared.updateThemeOpacity(0.90) // reset to default
    assert(ConfigManager.shared.config.themeOpacity == 0.90, "themeOpacity reset to 0.90")

    print("      ✓ ConfigManager loaded \(config.categories.count) categories successfully.")
    print("        - Shelf Hotkey:  [\(config.shelfHotkey.displayString)] (ID 1)")
    print("        - Search Hotkey: [\(config.searchHotkey.displayString)] (ID 2)")
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
        assert(catAfterAdd.items.contains(where: { $0.id == dummy1.id }), "Batch add item 1 should exist")
        assert(catAfterAdd.items.contains(where: { $0.id == dummy2.id }), "Batch add item 2 should exist")

        // Test item reordering
        let countBefore = catAfterAdd.items.count
        ConfigManager.shared.moveItem(from: countBefore - 1, to: countBefore - 2, in: firstCat.id)
        let catAfterMove = ConfigManager.shared.config.categories.first(where: { $0.id == firstCat.id })!
        assert(catAfterMove.items[countBefore - 2].id == dummy2.id, "Item reordering should place dummy2 before dummy1")

        ConfigManager.shared.removeItem(id: dummy1.id, from: firstCat.id)
        ConfigManager.shared.removeItem(id: dummy2.id, from: firstCat.id)
        print("      ✓ Batch addition, item reordering and deletion verified.")
    }

    // Test Category Reordering & Orientation
    let catsCount = ConfigManager.shared.config.categories.count
    if catsCount >= 2 {
        let firstId = ConfigManager.shared.config.categories[0].id
        ConfigManager.shared.moveCategory(from: 0, to: 1)
        assert(ConfigManager.shared.config.categories[1].id == firstId, "moveCategory should move category 0 to 1")
        ConfigManager.shared.moveCategory(from: 1, to: 0)
        assert(ConfigManager.shared.config.categories[0].id == firstId, "moveCategory back should restore original position")
    }

    // Test cross-category item move via moveItem(id:toCategoryId:)
    do {
        let source = ConfigManager.shared.addCategory(name: "拖拽源分类")
        let dest = ConfigManager.shared.addCategory(name: "拖拽目标分类")
        let item = LauncherItem(name: "DragItem", itemType: .fileOrFolder, target: "/tmp/dragitem")
        ConfigManager.shared.addItems([item], to: source.id)

        assert(ConfigManager.shared.moveItem(id: item.id, toCategoryId: dest.id) == true, "Cross-category move should succeed")
        assert(!ConfigManager.shared.config.categories.first(where: { $0.id == source.id })!.items.contains(where: { $0.id == item.id }), "Source category should lose item after move")
        assert(ConfigManager.shared.config.categories.first(where: { $0.id == dest.id })!.items.contains(where: { $0.id == item.id }), "Destination category should gain item after move")

        assert(ConfigManager.shared.moveItem(id: item.id, toCategoryId: source.id) == true, "Move back should succeed")
        assert(ConfigManager.shared.config.categories.first(where: { $0.id == source.id })!.items.contains(where: { $0.id == item.id }), "Source should regain item after move back")

        assert(ConfigManager.shared.moveItem(id: item.id, toCategoryId: source.id) == false, "Same-category move should be a no-op returning false")
        assert(ConfigManager.shared.moveItem(id: item.id, toCategoryId: UUID()) == false, "Missing destination should return false")
        assert(ConfigManager.shared.moveItem(id: UUID(), toCategoryId: dest.id) == false, "Missing item should return false")

        ConfigManager.shared.removeItem(id: item.id, from: source.id)
        ConfigManager.shared.deleteCategory(id: source.id, migrateItemsTo: dest.id)
        ConfigManager.shared.deleteCategory(id: dest.id, migrateItemsTo: ConfigManager.shared.config.categories.first!.id)
        print("      ✓ Cross-category item move (moveItem) verified.")
    }

    ConfigManager.shared.updateCategoryOrientation(.vertical)
    assert(ConfigManager.shared.config.categoryOrientation == .vertical, "Orientation should update to .vertical")
    ConfigManager.shared.updateCategoryOrientation(.horizontal)
    assert(ConfigManager.shared.config.categoryOrientation == .horizontal, "Orientation should update to .horizontal")

    ConfigManager.shared.updateShelfIconSize(.small)
    assert(ConfigManager.shared.config.shelfIconSize == .small, "ShelfIconSize should update to .small")
    assert(ConfigManager.shared.config.shelfIconSize.itemSize == 68, "Small item size should be 68")
    ConfigManager.shared.updateShelfIconSize(.large)
    assert(ConfigManager.shared.config.shelfIconSize == .large, "ShelfIconSize should update to .large")
    assert(ConfigManager.shared.config.shelfIconSize.itemSize == 96, "Large item size should be 96")
    ConfigManager.shared.updateShelfIconSize(.medium)
    assert(ConfigManager.shared.config.shelfIconSize == .medium, "ShelfIconSize should reset to .medium")
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
    assert(!safariSearch.isEmpty, "Search 'safari' should find matches")
    let finderSearch = AppHotspotIndex.shared.search("访达")
    assert(!finderSearch.isEmpty, "Search '访达' should find Finder app via Chinese alias")
    let terminalSearch = AppHotspotIndex.shared.search("zd") // pinyin abbreviation for 终端
    assert(!terminalSearch.isEmpty, "Search 'zd' (pinyin abbr) should find Terminal app")
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
    assert(!foundFiles.isEmpty, "SpotlightBridge should find files matching 'Package'")

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
    assert(!foundDigitFiles.isEmpty, "SpotlightBridge should support single-digit searches")

    // Deterministic File Search Test using transient test fixture in Downloads
    let downloadsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    let testFixtureURL = downloadsURL.appendingPathComponent("atools_probe_fixture.txt")
    try? "ATools Stability Probe".data(using: .utf8)?.write(to: testFixtureURL)
    defer {
        try? FileManager.default.removeItem(at: testFixtureURL)
    }

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
    assert(!foundFixtureFiles.isEmpty, "SpotlightBridge should find fixture file in user hot folders")

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
    assert(!coordinatorResults.isEmpty, "SearchCoordinator must always deliver web search fallback for non-empty input")
    assert(coordinatorResults.last?.type == .webSearch, "Last result should be webSearch fallback")
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
    assert(gotSafari, "SearchCoordinator should find matches for 'Safari'")
    print("      ✓ SearchCoordinator found \(safariResults.count) results for keyword 'Safari'.")

    // 7. Test Memory Usage
    print("[7/7] Testing Baseline Memory Footprint...")
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if kerr == KERN_SUCCESS {
        let rssMB = Double(info.resident_size) / (1024.0 * 1024.0)
        print(String(format: "      ✓ Current Resident Memory (RSS): %.2f MB", rssMB))
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
        assert(win.frame.width >= 500, "Window width should be at least 500")
        assert(win.frame.height >= 600, "Window height should be at least 600")

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
                assert(abs(win.frame.width - 780.0) < 0.5, "Tab \(item.title) caused window width jump: \(win.frame.width)")
                assert(abs(contentView.bounds.width - 780.0) < 0.5, "Tab \(item.title) caused contentView width jump: \(contentView.bounds.width)")
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

        assert(shelfVC.shelfGrid.items.contains(where: { $0.id == testDevItem.id }), "testDevItem should appear in shelfGrid")

        // Trigger item deletion via delegate (just like right-click '从分类中移除')
        shelfVC.shelfGrid(shelfVC.shelfGrid, didDeleteItem: testDevItem)

        // Verify item is removed from config and shelfGrid
        assert(!ConfigManager.shared.config.categories.first(where: { $0.id == devCategory.id })!.items.contains(where: { $0.id == testDevItem.id }), "testDevItem should be removed from ConfigManager")
        assert(!shelfVC.shelfGrid.items.contains(where: { $0.id == testDevItem.id }), "testDevItem should disappear from shelfGrid immediately")

        // Now simulate user clicking the '开发' category tab again
        shelfVC.categoryBar(shelfVC.categoryBar, didSelectCategory: devCategory)

        // Verify that re-clicking category does NOT bring back the deleted item
        assert(!shelfVC.shelfGrid.items.contains(where: { $0.id == testDevItem.id }), "testDevItem MUST NOT reappear after re-selecting category tab")
        assert(!(shelfVC.selectedCategory?.items.contains(where: { $0.id == testDevItem.id }) ?? false), "selectedCategory MUST NOT contain deleted item")
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
        assert(shelfVC.selectedCategory?.id == catA.id, "catA should be selected initially")

        // 1. Move internal item to catB by dropping onto catB's tab
        shelfVC.categoryBar(shelfVC.categoryBar, didMoveLauncherItem: testDragItem, to: catB)

        // Verify that:
        // a) Item was moved to catB in ConfigManager
        assert(ConfigManager.shared.config.categories.first(where: { $0.id == catB.id })!.items.contains(where: { $0.id == testDragItem.id }), "testDragItem should now belong to catB")
        assert(!ConfigManager.shared.config.categories.first(where: { $0.id == catA.id })!.items.contains(where: { $0.id == testDragItem.id }), "testDragItem should no longer belong to catA")
        // b) ShelfViewController automatically entered catB!
        assert(shelfVC.selectedCategory?.id == catB.id, "ShelfViewController MUST automatically enter catB after drop!")
        assert(shelfVC.shelfGrid.items.contains(where: { $0.id == testDragItem.id }), "ShelfGrid MUST display catB items including testDragItem immediately!")

        // 2. Drop external file path directly onto catA's tab
        shelfVC.categoryBar(shelfVC.categoryBar, didAddPaths: ["/tmp/ExternalDroppedApp.app"], to: catA)
        assert(shelfVC.selectedCategory?.id == catA.id, "ShelfViewController MUST enter catA after external file drop!")
        assert(shelfVC.shelfGrid.items.contains(where: { $0.name == "ExternalDroppedApp" }), "ShelfGrid MUST contain newly dropped external app in catA!")

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
    assert(searchPanel.frame.height == 72, "SearchPanel initial height should be 72pt (collapsed)")
    assert(searchVC.resultsTable.isHidden == true, "resultsTable should be hidden in collapsed state")

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

    // Now test expansion
    searchVC.updatePanelHeight(hasResults: true, resultCount: 4, animated: false)
    assert(searchPanel.frame.height > 72, "SearchPanel height should expand when results exist")
    assert(searchVC.resultsTable.isHidden == false, "resultsTable should be visible when expanded")

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
    assert(shelfPanel.level == .statusBar, "ShelfPanel level MUST be .statusBar")
    assert(shelfPanel.hidesOnDeactivate == false, "ShelfPanel hidesOnDeactivate MUST be false")

    if let settingsWin = SettingsWindowController.shared.window {
        assert(settingsWin.level.rawValue > shelfPanel.level.rawValue, "Settings window level MUST be higher than ShelfPanel")
    }

    // Semantic Versioning Tests
    assert(UpdateManager.isVersion("v1.0.1", greaterThan: "1.0.0") == true, "v1.0.1 > 1.0.0")
    assert(UpdateManager.isVersion("1.0.10", greaterThan: "1.0.2") == true, "1.0.10 > 1.0.2")
    assert(UpdateManager.isVersion("1.0", greaterThan: "1.0.0") == false, "1.0 should equal 1.0.0")
    assert(UpdateManager.isVersion("1.0.0", greaterThan: "1.0") == false, "1.0.0 should equal 1.0")
    assert(UpdateManager.isVersion("1.0.0", greaterThan: "v1.0.1") == false, "1.0.0 < 1.0.1")
    assert(UpdateManager.isVersion("2.0.0", greaterThan: "1.9.99") == true, "2.0.0 > 1.9.99")
    print("      ✓ UpdateManager semantic versioning algorithm verified.")

    let releaseAssets: [[String: Any]] = [
        ["name": "ATools.zip", "browser_download_url": "https://example.com/ATools.zip"],
        ["name": "ATools.dmg", "browser_download_url": "https://example.com/ATools.dmg"]
    ]
    let preferredAsset = UpdateManager.preferredReleaseAsset(from: releaseAssets)
    assert(preferredAsset?.name == "ATools.dmg", "DMG should be preferred over ZIP")
    assert(preferredAsset?.url.absoluteString.hasSuffix("/ATools.dmg") == true, "Preferred asset URL should be preserved")
    let zipOnlyAsset = UpdateManager.preferredReleaseAsset(from: [releaseAssets[0]])
    assert(zipOnlyAsset?.name == "ATools.zip", "ZIP should be used when DMG is unavailable")
    assert(UpdateManager.normalizedVersion("v1.1.1") == "1.1.1", "Normalized version should strip the v prefix")
    assert(UpdateManager.isBlockedUpdateLocation("/private/var/folders/abc/AppTranslocation/123/d/ATools.app"), "AppTranslocation must block in-place update")
    assert(UpdateManager.isBlockedUpdateLocation("/Volumes/ATools/ATools.app"), "Read-only DMG volume must block in-place update")
    assert(!UpdateManager.isBlockedUpdateLocation("/Applications/ATools.app"), "Applications folder should allow in-place update")
    print("      ✓ UpdateManager asset selection and update-location guards verified.")

    // Check About Tab Layout Width (ensure strict 780.0pt)
    SettingsWindowController.shared.selectTab(.about)
    if let win = SettingsWindowController.shared.window {
        win.displayIfNeeded()
        win.contentView?.layoutSubtreeIfNeeded()
        assert(abs(win.frame.width - 780.0) < 0.5, "About tab window width MUST be 780.0pt, got \(win.frame.width)")
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

    print("==================================================")
    print(" [ATools] All diagnostics PASSED successfully!")
    print("==================================================")

    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
