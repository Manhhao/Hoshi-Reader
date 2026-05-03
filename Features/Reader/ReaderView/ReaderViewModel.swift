//
//  ReaderViewModel.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2026 ッツ Reader Authors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import SwiftUI
import CHoshiDicts

enum ActiveSheet: Identifiable {
    case appearance
    case chapters
    case highlights
    case statistics
    case sasayaki
    var id: Self { self }
}

struct PopupItem: Identifiable {
    let id: UUID = UUID()
    var showPopup: Bool
    var currentSelection: SelectionData?
    var lookupResults: [LookupResult] = []
    var dictionaryStyles: [String: String] = [:]
    var isVertical: Bool
    var isFullWidth: Bool
    var clearSelection: Bool
    var sasayakiCue: SasayakiMatch?
}

private struct Position {
    var index: Int
    var progress: Double
}

@Observable
@MainActor
class ReaderLoaderViewModel {
    var document: EPUBDocument?
    let book: BookMetadata
    
    var rootURL: URL? {
        guard let booksFolder = try? BookStorage.getBooksDirectory(),
              let folder = book.folder else {
            return nil
        }
        return booksFolder.appendingPathComponent(folder)
    }
    
    init(book: BookMetadata) {
        self.book = book
        loadBook()
    }
    
    func loadBook() {
        guard let root = rootURL else {
            return
        }
        
        guard let doc = try? BookStorage.loadEpub(root) else {
            return
        }
        
        var bookCopy = self.book
        bookCopy.lastAccess = Date()
        try? BookStorage.save(bookCopy, inside: root, as: FileNames.metadata)
        
        self.document = doc
    }
}

@Observable
@MainActor
class ReaderViewModel {
    let book: BookMetadata
    let document: EPUBDocument
    let rootURL: URL
    var index: Int = 0
    var currentProgress: Double = 0.0
    var activeSheet: ActiveSheet?
    var isLoading = true
    var bookInfo: BookInfo
    let bridge = WebViewBridge()
    
    // lookups
    var popups: [PopupItem] = []
    
    // stats
    var isTracking = false
    var isPaused = false
    var lastTimestamp: Date = .now
    var lastCount: Int = 0
    var stats: [Statistics] = []
    var sessionStatistics: Statistics
    var todaysStatistics: Statistics
    var allTimeStatistics: Statistics
    let enableStatistics: Bool
    let autostartStatistics: Bool
    
    // sasayaki
    var sasayakiPlayer: SasayakiPlayer!
    var wasPaused = false
    
    // sync
    let autoSyncEnabled: Bool
    let syncStats: Bool
    let statsSyncMode: StatisticsSyncMode
    let syncAudioBook: Bool
    var isSyncing = false
    private var pendingAutoExport = false
    private var debounceTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    
    // highlights
    var highlights: [Highlight] = []
    
    // navigation history
    private var backHistory: [Position] = []
    private var forwardHistory: [Position] = []
    private var currentPosition: Position { Position(index: index, progress: currentProgress) }
    var backTarget: Int? { backHistory.last.map { calculateCharacterProgress(for: $0) } }
    var forwardTarget: Int? { forwardHistory.last.map { calculateCharacterProgress(for: $0) } }
    
    init(
        book: BookMetadata,
        document: EPUBDocument,
        rootURL: URL,
        enableStatistics: Bool,
        autostartStatistics: Bool,
        autoSyncEnabled: Bool,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool
    ) {
        self.book = book
        self.document = document
        self.rootURL = rootURL
        self.enableStatistics = enableStatistics
        self.autostartStatistics = autostartStatistics
        self.autoSyncEnabled = autoSyncEnabled
        self.syncStats = syncStats
        self.statsSyncMode = statsSyncMode
        self.syncAudioBook = syncAudioBook
        
        if let bookmark = BookStorage.loadBookmark(root: rootURL) {
            index = bookmark.chapterIndex
            currentProgress = bookmark.progress
        } else {
            index = 0
            currentProgress = 0.0
        }
        
        if let b = BookStorage.loadBookInfo(root: rootURL) {
            bookInfo = b
        } else {
            bookInfo = BookInfo(characterCount: 0, chapterInfo: [:])
        }
        
        sessionStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        todaysStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        allTimeStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        
        if enableStatistics {
            loadStatistics()
        }
        
        if autostartStatistics {
            startTracking()
        }
        
        sasayakiPlayer = SasayakiPlayer(
            rootURL: rootURL,
            bridge: bridge,
            loadChapter: { [weak self] chapterIndex, progress in
                self?.flushStats()
                self?.loadChapter(index: chapterIndex, progress: progress)
                self?.resetTrackingBaseline()
            },
            getCurrentIndex: { [weak self] in
                self?.index ?? 0
            },
            onPlayback: { [weak self] in
                guard self?.syncAudioBook == true else { return }
                self?.scheduleAutoExport()
            }
        )
        
        highlights = BookStorage.loadHighlights(root: rootURL) ?? []
    }
    
    var currentChapterCount: Int {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else {
            return 0
        }
        return chapterInfo.currentTotal + chapterInfo.chapterCount
    }
    
    var currentCharacter: Int {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else {
            return 0
        }
        
        return chapterInfo.currentTotal + Int(Double(chapterInfo.chapterCount) * currentProgress)
    }
    
    var coverURL: URL? {
        if let book = BookStorage.loadMetadata(root: rootURL) {
            return book.coverURL
        }
        return nil
    }
    
    private var currentChapterURL: URL? {
        guard document.spine.items.indices.contains(index) else {
            return nil
        }
        
        let item = document.spine.items[index]
        guard let manifestItem = document.manifest.items[item.idref] else {
            return nil
        }
        return document.contentDirectory.appendingPathComponent(manifestItem.path)
    }
    
    private var chapterRange: (start: Int, end: Int)? {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let info = bookInfo.chapterInfo[manifestItem.path] else {
            return nil
        }
        return (info.currentTotal, info.currentTotal + info.chapterCount)
    }
    
    func handleRestoreCompleted() {
        if !sasayakiPlayer.hasAudio {
            sasayakiPlayer.restoreAudio()
        }
        isLoading = false
        sasayakiPlayer.handleRestoreCompleted(currentIndex: index)
    }
    
    func importSasayakiAudio(from url: URL) throws {
        try sasayakiPlayer.importAudio(from: url)
    }
    
    func syncOnOpen() async {
        if autoSyncEnabled {
            let result = try? await SyncManager.shared.syncBook(
                book: book,
                direction: nil,
                syncStats: syncStats,
                statsSyncMode: statsSyncMode,
                syncAudioBook: syncAudioBook,
                importOnly: true
            )
            
            if case .imported = result {
                reloadAfterImport()
            }
        }
        loadCurrentChapter()
        resetTrackingBaseline()
    }
    
    func syncAfterForeground() async {
        guard autoSyncEnabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let result = try? await SyncManager.shared.syncBook(
            book: book,
            direction: nil,
            syncStats: syncStats,
            statsSyncMode: statsSyncMode,
            syncAudioBook: syncAudioBook,
            importOnly: true
        )
        
        if case .imported = result {
            reloadAfterImport()
            loadCurrentChapter()
            resetTrackingBaseline()
        }
    }
    
    func flushAutoSync() async {
        debounceTask?.cancel()
        debounceTask = nil
        await runAutoExport(direction: .exportToTtu)
    }
    
    func updateProgress(_ progress: Double) {
        currentProgress = progress
    }
    
    func saveBookmark(progress: Double) {
        persistBookmark(progress: progress)
        flushStats()
    }
    
    func jumpToCharacter(_ characterCount: Int) {
        guard let result = bookInfo.resolveCharacterPosition(characterCount) else { return }
        recordPosition()
        navigate(to: Position(index: result.spineIndex, progress: result.progress))
    }
    
    func jumpToChapter(index: Int, fragment: String? = nil) {
        recordPosition()
        navigate(to: Position(index: index, progress: 0), fragment: fragment)
    }
    
    func jumpToLink(_ url: URL) -> Bool {
        guard let destination = resolveSpineDestination(for: url) else {
            return false
        }
        
        recordPosition()
        flushStats()
        
        if destination.spineIndex == self.index {
            if let fragment = destination.fragment {
                bridge.send(.jumpToFragment(fragment))
            } else {
                persistBookmark(progress: 0)
                bridge.send(.restoreProgress(0))
                resetTrackingBaseline()
            }
            return true
        }
        
        loadChapter(index: destination.spineIndex, progress: 0, fragment: destination.fragment)
        resetTrackingBaseline()
        return true
    }
    
    func syncProgressAfterLinkJump(_ progress: Double) {
        persistBookmark(progress: progress)
        resetTrackingBaseline()
    }
    
    func nextChapter() -> Bool {
        guard index < document.spine.items.count - 1 else { return false }
        loadChapter(index: index + 1, progress: 0)
        flushStats()
        return true
    }
    
    func previousChapter() -> Bool {
        guard index > 0 else { return false }
        loadChapter(index: index - 1, progress: 1)
        flushStats()
        return true
    }
    
    func handleTextSelection(_ selection: SelectionData, maxResults: Int, scanLength: Int, isVertical: Bool, isFullWidth: Bool, autoPause: Bool) -> Int? {
        let lookupResults = LookupEngine.shared.lookup(selection.text, maxResults: maxResults, scanLength: scanLength)
        var dictionaryStyles: [String: String] = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        var cue: SasayakiMatch? = nil
        if sasayakiPlayer.hasAudio, let offset = selection.normalizedOffset {
            cue = sasayakiPlayer.findCue(chapterIndex: index, offset: offset)
        }
        let popup = PopupItem(
            showPopup: false,
            currentSelection: selection,
            lookupResults: lookupResults,
            dictionaryStyles: dictionaryStyles,
            isVertical: isVertical,
            isFullWidth: isFullWidth,
            clearSelection: false,
            sasayakiCue: cue
        )
        popups.append(popup)
        
        if let firstResult = lookupResults.first {
            if sasayakiPlayer.isPlaying {
                if autoPause {
                    sasayakiPlayer.togglePlayback()
                    wasPaused = true
                } else {
                    wasPaused = false
                }
            }
            withAnimation(.default.speed(2.2)) {
                popups = popups.map {
                    var p = $0
                    if p.id == popup.id {
                        p.showPopup = true
                    }
                    return p
                }
            }
            return String(firstResult.matched).count
        }
        return nil
    }
    
    func closePopups() {
        let popupIds = Set(popups.map(\.id))
        withAnimation(.default.speed(2.4)) {
            for index in popups.indices {
                popups[index].showPopup = false
            }
        } completion: {
            self.popups.removeAll { popupIds.contains($0.id) }
            if self.popups.isEmpty {
                if self.wasPaused, !self.sasayakiPlayer.isPlaying {
                    self.sasayakiPlayer.togglePlayback()
                }
                self.wasPaused = false
            }
        }
    }
    
    func closeChildPopups(parent: Int) {
        var popupIds: Set<UUID> = []
        withAnimation(.default.speed(2.4)) {
            for index in popups.indices.dropFirst(parent + 1) {
                popups[index].showPopup = false
                popupIds.insert(popups[index].id)
            }
        } completion: {
            self.popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    func clearSelection() {
        bridge.send(.clearSelection)
    }
    
    func startTracking() {
        isTracking = true
        lastTimestamp = .now
        lastCount = currentCharacter
    }
    
    func stopTracking() {
        guard isTracking else { return }
        flushStats()
        isTracking = false
    }
    
    // https://github.com/ttu-ttu/ebook-reader/blob/2703b50ec52b2e4f70afcab725c0f47dd8a66bf4/apps/web/src/lib/components/book-reader/book-reading-tracker/book-reading-tracker.svelte#L72
    func updateStats() {
        let currentDateKey = Self.formattedDate(date: .now)
        if todaysStatistics.dateKey != currentDateKey {
            if let index = stats.firstIndex(where: { $0.dateKey == todaysStatistics.dateKey }) {
                stats[index] = todaysStatistics
            } else {
                stats.append(todaysStatistics)
            }
            todaysStatistics = stats.first(where: { $0.dateKey == currentDateKey }) ?? Self.getDefaultStatistic(title: document.title ?? "")
        }
        
        let now: Date = .now
        let timeDiff = Date.now.timeIntervalSince(lastTimestamp)
        let charDiff = currentCharacter - lastCount
        let finalCharDiff = charDiff < 0 && abs(charDiff) > sessionStatistics.charactersRead ? -sessionStatistics.charactersRead : charDiff;
        let lastStatisticModified = Int(Date.now.timeIntervalSince1970 * 1000)
        guard timeDiff > 0 else {
            return
        }
        
        updateStatistic(to: &sessionStatistics, timeDiff: timeDiff, characterDiff: finalCharDiff, lastStatisticModified: lastStatisticModified)
        updateStatistic(to: &todaysStatistics, timeDiff: timeDiff, characterDiff: finalCharDiff, lastStatisticModified: lastStatisticModified)
        updateStatistic(to: &allTimeStatistics, timeDiff: timeDiff, characterDiff: finalCharDiff, lastStatisticModified: lastStatisticModified)
        
        lastTimestamp = now
        lastCount = currentCharacter
    }
    
    func resetTrackingBaseline() {
        lastCount = currentCharacter
        lastTimestamp = .now
    }
    
    func addHighlight(_ color: HighlightColor, _ creation: HighlightData) {
        guard let range = chapterRange else { return }
        let highlight = Highlight(
            id: creation.id,
            character: range.start + creation.start,
            offset: creation.offset,
            text: creation.text,
            color: color,
            createdAt: Date()
        )
        highlights.append(highlight)
        saveHighlights()
        syncHighlights()
    }
    
    func removeHighlight(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        saveHighlights()
        syncHighlights()
        if let range = chapterRange,
           highlight.character >= range.start,
           highlight.character < range.end {
            bridge.send(.removeHighlight(highlight.id.uuidString))
        }
    }
    
    func navigateBackwards() {
        let target = backHistory.removeLast()
        forwardHistory.append(currentPosition)
        navigate(to: target)
    }
    
    func navigateForwards() {
        let target = forwardHistory.removeLast()
        backHistory.append(currentPosition)
        navigate(to: target)
    }
    
    func clearForwardHistory() {
        if backHistory.isEmpty {
            forwardHistory.removeAll()
        }
    }
    
    private func navigate(to position: Position, fragment: String? = nil) {
        flushStats()
        if position.index == index && fragment == nil {
            persistBookmark(progress: position.progress)
            bridge.send(.restoreProgress(position.progress))
        } else {
            loadChapter(index: position.index, progress: position.progress, fragment: fragment)
        }
        resetTrackingBaseline()
    }
    
    private func persistBookmark(progress: Double) {
        currentProgress = progress
        bridge.updateProgress(progress)
        let bookmark = Bookmark(
            chapterIndex: index,
            progress: progress,
            characterCount: currentCharacter,
            lastModified: Date()
        )
        try? BookStorage.save(bookmark, inside: rootURL, as: FileNames.bookmark)
        scheduleAutoExport()
    }
    
    private func loadChapter(index: Int, progress: Double, fragment: String? = nil) {
        isLoading = true
        sasayakiPlayer.prepareTransition()
        self.index = index
        persistBookmark(progress: progress)
        if let url = currentChapterURL {
            let cues = sasayakiPlayer.hasMatch ? sasayakiPlayer.cues(for: index) : nil
            let highlights = chapterHighlights()
            bridge.updateState(url: url, progress: progress, sasayakiCues: cues, highlights: highlights)
            bridge.send(.loadChapter(url: url, progress: progress, fragment: fragment, sasayakiCues: cues, highlights: highlights))
        }
    }
    
    private func loadCurrentChapter() {
        if let url = currentChapterURL {
            let cues = sasayakiPlayer.hasMatch ? sasayakiPlayer.cues(for: index) : nil
            let highlights = chapterHighlights()
            bridge.updateState(url: url, progress: currentProgress, sasayakiCues: cues, highlights: highlights)
            bridge.send(.loadChapter(url: url, progress: currentProgress, fragment: nil, sasayakiCues: cues, highlights: highlights))
        }
    }
    
    private func reloadAfterImport() {
        if let bookmark = BookStorage.loadBookmark(root: rootURL) {
            index = bookmark.chapterIndex
            currentProgress = bookmark.progress
        }
        if enableStatistics {
            loadStatistics()
        }
        if syncAudioBook {
            sasayakiPlayer.reloadPlayback()
        }
    }
    
    private func scheduleAutoExport() {
        guard autoSyncEnabled else { return }
        pendingAutoExport = true
        guard debounceTask == nil else { return }
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            self?.debounceTask = nil
            await self?.runAutoExport(direction: .exportToTtu)
        }
    }
    
    private func runAutoExport(direction: SyncDirection?) async {
        if let existing = exportTask {
            await existing.value
        }
        
        guard pendingAutoExport else { return }
        pendingAutoExport = false
        
        let task = Task { [weak self] in
            guard let self else { return }
            _ = try? await SyncManager.shared.syncBook(
                book: self.book,
                direction: direction,
                syncStats: self.syncStats,
                statsSyncMode: self.statsSyncMode,
                syncAudioBook: self.syncAudioBook
            )
        }
        exportTask = task
        await task.value
        exportTask = nil
    }
    
    private func resolveSpineDestination(for url: URL) -> (spineIndex: Int, fragment: String?)? {
        let targetPath = normalizedFilePath(url)
        
        for (spineIndex, spineItem) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[spineItem.idref] else {
                continue
            }
            let chapterPath = normalizedFilePath(document.contentDirectory.appendingPathComponent(manifestItem.path))
            if chapterPath == targetPath {
                return (spineIndex, normalizeFragment(url.fragment))
            }
        }
        
        return nil
    }
    
    private func normalizedFilePath(_ url: URL) -> String {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath().path
        return normalized.removingPercentEncoding ?? normalized
    }
    
    private func normalizeFragment(_ fragment: String?) -> String? {
        guard let fragment, !fragment.isEmpty else {
            return nil
        }
        return fragment.removingPercentEncoding ?? fragment
    }
    
    private func flushStats() {
        guard isTracking, !isPaused else { return }
        updateStats()
        saveStats()
    }
    
    // https://github.com/ttu-ttu/ebook-reader/blob/2703b50ec52b2e4f70afcab725c0f47dd8a66bf4/apps/web/src/lib/components/book-reader/book-reading-tracker/book-reading-tracker.svelte#L722
    private func updateStatistic(to: inout Statistics, timeDiff: Double, characterDiff: Int, lastStatisticModified: Int) {
        to.readingTime += timeDiff
        to.charactersRead = max(to.charactersRead + characterDiff, 0)
        to.lastReadingSpeed = to.readingTime > 0 ? Int((Double(to.charactersRead) / to.readingTime) * 3600.0) : 0
        to.maxReadingSpeed = max(to.maxReadingSpeed, to.lastReadingSpeed)
        to.minReadingSpeed = to.minReadingSpeed != 0 ? min(to.minReadingSpeed, to.lastReadingSpeed) : to.lastReadingSpeed
        if characterDiff != 0 {
            to.altMinReadingSpeed = to.altMinReadingSpeed != 0 ? min(to.altMinReadingSpeed, to.lastReadingSpeed) : to.lastReadingSpeed
        }
        to.lastStatisticModified = lastStatisticModified
    }
    
    private func saveStats() {
        if let index = stats.firstIndex(where: { $0.dateKey == todaysStatistics.dateKey }) {
            stats[index] = todaysStatistics
        } else {
            stats.append(todaysStatistics)
        }
        
        stats = Self.deduplicateStatistics(stats)
        try? BookStorage.save(stats, inside: rootURL, as: FileNames.statistics)
        scheduleAutoExport()
    }
    
    private func loadStatistics() {
        stats = Self.deduplicateStatistics(BookStorage.loadStatistics(root: rootURL) ?? [])
        todaysStatistics = stats.first(where: { $0.dateKey == Self.formattedDate(date: .now) }) ?? Self.getDefaultStatistic(title: document.title ?? "")
        allTimeStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        
        for stat in stats {
            allTimeStatistics.readingTime += stat.readingTime
            allTimeStatistics.charactersRead += stat.charactersRead
            allTimeStatistics.lastReadingSpeed = allTimeStatistics.readingTime > 0 ? Int((Double(allTimeStatistics.charactersRead) / allTimeStatistics.readingTime) * 3600.0) : 0
        }
    }
    
    private func chapterHighlights() -> String? {
        guard let range = chapterRange else { return nil }
        let list = highlights.filter { $0.character >= range.start && $0.character < range.end }
        if list.isEmpty {
            return nil
        }
        guard let data = try? JSONEncoder().encode(list),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
    
    private func saveHighlights() {
        try? BookStorage.save(highlights, inside: rootURL, as: FileNames.highlights)
    }
    
    private func syncHighlights() {
        bridge.updateHighlights(chapterHighlights())
    }
    
    private func recordPosition() {
        backHistory.append(currentPosition)
        forwardHistory.removeAll()
    }
    
    private func calculateCharacterProgress(for position: Position) -> Int {
        let spineItem = document.spine.items[position.index]
        let manifestItem = document.manifest.items[spineItem.idref]!
        let chapterInfo = bookInfo.chapterInfo[manifestItem.path]!
        return chapterInfo.currentTotal + Int(Double(chapterInfo.chapterCount) * position.progress)
    }
    
    private static func getDefaultStatistic(title: String) -> Statistics {
        return Statistics(title: title, dateKey: Self.formattedDate(date: .now), charactersRead: 0, readingTime: 0, minReadingSpeed: 0, altMinReadingSpeed: 0, lastReadingSpeed: 0, maxReadingSpeed: 0, lastStatisticModified: 0)
    }
    
    private static func deduplicateStatistics(_ statistics: [Statistics]) -> [Statistics] {
        var grouped: [String: Statistics] = [:]
        for statistic in statistics {
            if let existing = grouped[statistic.dateKey] {
                if statistic.lastStatisticModified > existing.lastStatisticModified {
                    grouped[statistic.dateKey] = statistic
                }
            } else {
                grouped[statistic.dateKey] = statistic
            }
        }
        return Array(grouped.values)
    }
    
    private static func formattedDate(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
