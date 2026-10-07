import Foundation
import AppKit

public final class SearchCoordinator {
    public static let shared = SearchCoordinator()

    private var debounceWorkItem: DispatchWorkItem?
    private var currentGenerationId: UInt64 = 0
    private var dictionaryResults: [UInt64: SearchResult] = [:]
    private var fileResults: [UInt64: [SearchResult]] = [:]

    private init() {}

    /// Drops any debounced Spotlight query and in-flight results, e.g. when the panel hides.
    public func cancelPendingSearches() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        currentGenerationId &+= 1
        dictionaryResults.removeAll()
        fileResults.removeAll()
        SpotlightBridge.shared.stop()
        DictionaryService.shared.cancelPendingLookups()
    }

    public func search(query: String, filter: SearchTypeFilter = .all, onResults: @escaping ([SearchResult]) -> Void) {
        debounceWorkItem?.cancel()
        currentGenerationId &+= 1
        let generation = currentGenerationId
        // Results are keyed by generation and older generations can never be read
        // again (every reader checks currentGenerationId). Without this, each
        // keystroke added up to `searchResultLimit` retained result closures that
        // were only dropped when the panel next hid.
        dictionaryResults.removeAll()
        fileResults.removeAll()

        var effectiveFilter = filter
        var effectiveText = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 若当前未显式指定分类（为 .all），尝试从输入文本中解析快捷前缀（如 "doc: report"）
        if effectiveFilter == .all, let extracted = SearchTypeFilter.extractPrefix(from: effectiveText) {
            effectiveFilter = extracted.filter
            effectiveText = extracted.query
        }

        let trimmed = effectiveText
        guard !trimmed.isEmpty else {
            SpotlightBridge.shared.stop()
            DispatchQueue.main.async {
                onResults([])
            }
            return
        }

        // Layer 1: Instant In-Memory Synchronous Results (<1ms)
        var instantResults: [SearchResult] = []

        // 1. Math calculation (仅在 .all 模式有效)
        if effectiveFilter == .all,
           ConfigManager.shared.config.enableCalculator,
           let mathResult = CalculatorEngine.shared.evaluate(trimmed) {
            instantResults.append(SearchResult(
                id: "calc_\(trimmed)",
                title: "= \(mathResult)",
                subtitle: "按下回车键复制计算结果到剪贴板",
                type: .calculator,
                score: 1000,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mathResult, forType: .string)
                }
            ))
        }

        // 2. System Commands (Lock, Sleep, Trash, etc. 仅在 .all 模式有效)
        if effectiveFilter == .all {
            let lowerQuery = trimmed.lowercased()
            var exactActionResults: [SearchResult] = []
            var partialActionResults: [SearchResult] = []
            for act in SystemActions.shared.match(trimmed) {
                let result = SearchResult(
                    id: "sys_\(act.id)",
                    title: act.name,
                    subtitle: "系统控制指令",
                    type: .systemAction,
                    score: 900,
                    icon: ThumbnailPipeline.shared.symbolIcon(name: act.iconSymbol),
                    action: act.execute
                )
                if act.keywords.contains(lowerQuery) {
                    exactActionResults.append(result)
                } else {
                    partialActionResults.append(result)
                }
            }
            instantResults.append(contentsOf: exactActionResults)
        }

        // 3. In-Memory Apps (0ms) - 在 .all 模式展示前 15 条，在 .application 模式展示全量（上限 searchResultLimit）
        if effectiveFilter == .all || effectiveFilter == .application {
            let appLimit = (effectiveFilter == .application)
                ? ConfigManager.shared.config.searchResultLimit
                : AppConstants.instantAppResultCount
            let apps = AppHotspotIndex.shared.search(trimmed)
            for app in apps.prefix(appLimit) {
                let appPath = app.path
                instantResults.append(SearchResult(
                    id: "app_\(appPath)",
                    title: app.localizedName,
                    subtitle: appPath,
                    path: appPath,
                    type: .application,
                    score: 700,
                    action: {
                        LauncherExecutor.open(path: appPath)
                    }
                ))
            }
        }

        if effectiveFilter == .all {
            let lowerQuery = trimmed.lowercased()
            for act in SystemActions.shared.match(trimmed) where !act.keywords.contains(lowerQuery) {
                instantResults.append(SearchResult(
                    id: "sys_\(act.id)",
                    title: act.name,
                    subtitle: "系统控制指令",
                    type: .systemAction,
                    score: 900,
                    icon: ThumbnailPipeline.shared.symbolIcon(name: act.iconSymbol),
                    action: act.execute
                ))
            }
        }

        let deliver: () -> Void = { [weak self] in
            guard let self else { return }
            var merged = instantResults
            if let dictionary = self.dictionaryResults[generation] { merged.append(dictionary) }
            for result in self.fileResults[generation] ?? [] where !merged.contains(where: { $0.path == result.path }) {
                merged.append(result)
            }
            if effectiveFilter == .all, ConfigManager.shared.config.enableWebSearch {
                merged.append(self.makeWebSearchResult(for: trimmed))
            }
            // Search churn leaves dirty pages in the malloc zones; debounce a quiet
            // period so the last delivery triggers the same anneal as a panel hide.
            MemoryGuardian.shared.scheduleAnneal()
            onResults(merged)
        }
        DispatchQueue.main.async(execute: deliver)

        // 词典查询（仅在 .all 模式有效）
        if effectiveFilter == .all, ConfigManager.shared.config.enableDictionary {
            DictionaryService.shared.lookup(trimmed) { [weak self] definition in
                DispatchQueue.main.async {
                    guard let self, self.currentGenerationId == generation, let definition else { return }
                    self.dictionaryResults[generation] = SearchResult(
                        id: "dict_\(trimmed)", title: "词典: \(trimmed)", subtitle: definition,
                        type: .dictionary, score: 680,
                        icon: ThumbnailPipeline.shared.symbolIcon(name: "character.book.closed.fill"),
                        action: {
                            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? trimmed
                            if let url = URL(string: "dict://\(encoded)") { NSWorkspace.shared.open(url) }
                        }
                    )
                    deliver()
                }
            }
        }

        // 若当前只查找应用，Layer 1 AppHotspotIndex 已全量返回，无需触发 Layer 2 全盘扫描
        if effectiveFilter == .application {
            return
        }

        // Layer 2: Debounced Spotlight Full-Disk File Search (150ms)
        guard ConfigManager.shared.config.enableFullDiskSearch else {
            runtimeLog("[Coordinator] enableFullDiskSearch is FALSE! Skipping Layer 2.")
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            runtimeLog("[Coordinator] workItem running for '\(trimmed)', filter=\(effectiveFilter.rawValue), gen=\(generation)")
            let limit = ConfigManager.shared.config.searchResultLimit
            SpotlightBridge.shared.searchFiles(matching: trimmed, limit: limit, filter: effectiveFilter) { fileResults in
                runtimeLog("[Coordinator] Spotlight returned \(fileResults.count) files for '\(trimmed)', currGen=\(self.currentGenerationId), taskGen=\(generation)")
                guard self.currentGenerationId == generation else {
                    runtimeLog("[Coordinator] Dropping outdated results (currGen \(self.currentGenerationId) != taskGen \(generation))")
                    return
                }

                DispatchQueue.main.async {
                    if self.currentGenerationId == generation {
                        self.fileResults[generation] = fileResults
                        deliver()
                    }
                }
            }
        }

        self.debounceWorkItem = workItem
        let debounceSeconds = Double(ConfigManager.shared.config.searchDebounceMs) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: workItem)
    }

    private func makeWebSearchResult(for trimmed: String) -> SearchResult {
        let engine = ConfigManager.shared.config.webSearchEngine
        let customURL = ConfigManager.shared.config.customWebSearchURL
        let engineName = (engine == .custom && !customURL.isEmpty) ? "自定义引擎" : engine.title
        return SearchResult(
            id: "web_\(trimmed)",
            title: "在浏览器中搜索 \"\(trimmed)\"",
            subtitle: "按下回车键使用 \(engineName) 搜索",
            type: .webSearch,
            score: 10,
            icon: ThumbnailPipeline.shared.symbolIcon(name: "globe"),
            action: {
                if let url = engine.searchURL(for: trimmed, customTemplate: customURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}
