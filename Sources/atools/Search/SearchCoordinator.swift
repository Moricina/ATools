import Foundation
import AppKit

public final class SearchCoordinator {
    public static let shared = SearchCoordinator()

    private var debounceWorkItem: DispatchWorkItem?
    private var currentGenerationId: UInt64 = 0

    private init() {}

    /// Drops any debounced Spotlight query and in-flight results, e.g. when the panel hides.
    public func cancelPendingSearches() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        currentGenerationId &+= 1
        SpotlightBridge.shared.stop()
    }

    public func search(query: String, onResults: @escaping ([SearchResult]) -> Void) {
        debounceWorkItem?.cancel()
        currentGenerationId &+= 1
        let generation = currentGenerationId

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SpotlightBridge.shared.stop()
            DispatchQueue.main.async {
                onResults([])
            }
            return
        }

        // Layer 1: Instant In-Memory Synchronous Results (<1ms)
        var instantResults: [SearchResult] = []

        // 1. Math calculation
        if ConfigManager.shared.config.enableCalculator,
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

        // 2. System Commands (Lock, Sleep, Trash, etc.)
        // Exact keyword hits rank above apps; partial hits go below them so that the default
        // (first) row for an app name is the app itself, never a disruptive system action.
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

        // 3. In-Memory Apps (0ms)
        let apps = AppHotspotIndex.shared.search(trimmed)
        for app in apps.prefix(AppConstants.instantAppResultCount) {
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
        instantResults.append(contentsOf: partialActionResults)

        // 4. Offline Dictionary — ranked after apps: "Safari", "Notes", "Mail"... all have
        // dictionary entries and previously stole the default Enter action from the app.
        if ConfigManager.shared.config.enableDictionary,
           let def = DictionaryService.shared.lookup(trimmed) {
            instantResults.append(SearchResult(
                id: "dict_\(trimmed)",
                title: "词典: \(trimmed)",
                subtitle: def,
                type: .dictionary,
                score: 800,
                icon: ThumbnailPipeline.shared.symbolIcon(name: "character.book.closed.fill"),
                action: {
                    let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? trimmed
                    if let url = URL(string: "dict://\(encoded)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            ))
        }

        // Post instant results first with web search fallback
        var instantMerged = instantResults
        if ConfigManager.shared.config.enableWebSearch {
            instantMerged.append(makeWebSearchResult(for: trimmed))
        }
        runtimeLog("[Coordinator] dispatching instant results: count=\(instantMerged.count) for '\(trimmed)'")
        DispatchQueue.main.async {
            onResults(instantMerged)
        }

        // Layer 2: Debounced Spotlight Full-Disk File Search (150ms)
        guard ConfigManager.shared.config.enableFullDiskSearch else {
            runtimeLog("[Coordinator] enableFullDiskSearch is FALSE! Skipping Layer 2.")
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            runtimeLog("[Coordinator] workItem running for '\(trimmed)', gen=\(generation)")
            let limit = ConfigManager.shared.config.searchResultLimit
            SpotlightBridge.shared.searchFiles(matching: trimmed, limit: limit) { fileResults in
                runtimeLog("[Coordinator] Spotlight returned \(fileResults.count) files for '\(trimmed)', currGen=\(self.currentGenerationId), taskGen=\(generation)")
                guard self.currentGenerationId == generation else {
                    runtimeLog("[Coordinator] Dropping outdated results (currGen \(self.currentGenerationId) != taskGen \(generation))")
                    return
                }

                var merged = instantResults

                // Append file results
                for res in fileResults {
                    if !merged.contains(where: { $0.path == res.path }) {
                        merged.append(res)
                    }
                }

                // Append Web Search Fallback at the very end if enabled
                if ConfigManager.shared.config.enableWebSearch {
                    merged.append(self.makeWebSearchResult(for: trimmed))
                }

                DispatchQueue.main.async {
                    if self.currentGenerationId == generation {
                        runtimeLog("[Coordinator] onResults called with total \(merged.count) results for '\(trimmed)'")
                        onResults(merged)
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
