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
    var clearHighlight: Bool
    var sasayakiCue: SasayakiMatch?
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
    private var pendingAutoExport = false
    private var debounceTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    
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
            }
        )
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
        scheduleAutoExport()
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
    
    func flushAutoSync() async {
        debounceTask?.cancel()
        debounceTask = nil
        await runAutoExport(direction: nil)
    }
    
    func loadStatistics() {
        stats = BookStorage.loadStatistics(root: rootURL) ?? []
        todaysStatistics = stats.first(where: { $0.dateKey == Self.formattedDate(date: .now) }) ?? Self.getDefaultStatistic(title: document.title ?? "")
        allTimeStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        
        for stat in stats {
            allTimeStatistics.readingTime += stat.readingTime
            allTimeStatistics.charactersRead += stat.charactersRead
            allTimeStatistics.lastReadingSpeed = allTimeStatistics.readingTime > 0 ? Int((Double(allTimeStatistics.charactersRead) / allTimeStatistics.readingTime) * 3600.0) : 0
        }
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
    
    func getCurrentChapter() -> URL? {
        guard document.spine.items.indices.contains(index) else {
            return nil
        }
        
        let item = document.spine.items[index]
        guard let manifestItem = document.manifest.items[item.idref] else {
            return nil
        }
        return document.contentDirectory.appendingPathComponent(manifestItem.path)
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
        flushStats()
        if result.spineIndex == self.index {
            persistBookmark(progress: result.progress)
            bridge.send(.restoreProgress(result.progress))
        } else {
            loadChapter(index: result.spineIndex, progress: result.progress)
        }
        resetTrackingBaseline()
    }
    
    func jumpToChapter(index: Int, fragment: String? = nil) {
        flushStats()
        loadChapter(index: index, progress: 0, fragment: fragment)
        resetTrackingBaseline()
    }
    
    func jumpToLink(_ url: URL) -> Bool {
        guard let destination = resolveSpineDestination(for: url) else {
            return false
        }
        
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
    
    func handleTextSelection(_ selection: SelectionData, maxResults: Int, scanLength: Int, isVertical: Bool, isFullWidth: Bool) -> Int? {
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
            clearHighlight: false,
            sasayakiCue: cue
        )
        popups.append(popup)
        
        if let firstResult = lookupResults.first {
            if sasayakiPlayer.isPlaying {
                sasayakiPlayer.togglePlayback()
                wasPaused = true
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
    
    func clearWebHighlight() {
        bridge.send(.clearHighlight)
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
    
    // https://github.com/ttu-ttu/ebook-reader/blob/2703b50ec52b2e4f70afcab725c0f47dd8a66bf4/apps/web/src/lib/components/book-reader/book-reading-tracker/book-reading-tracker.svelte#L722
    func updateStatistic(to: inout Statistics, timeDiff: Double, characterDiff: Int, lastStatisticModified: Int) {
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
    
    func saveStats() {
        if let index = stats.firstIndex(where: { $0.dateKey == Self.formattedDate(date: .now) }) {
            stats[index] = todaysStatistics
        } else {
            stats.append(todaysStatistics)
        }
        
        try? BookStorage.save(stats, inside: rootURL, as: FileNames.statistics)
        scheduleAutoExport()
    }
    
    func resetTrackingBaseline() {
        lastCount = currentCharacter
        lastTimestamp = .now
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
        if let url = getCurrentChapter() {
            let cues = sasayakiPlayer.hasMatch ? sasayakiPlayer.cues(for: index) : nil
            bridge.updateState(url: url, progress: progress, sasayakiCues: cues)
            bridge.send(.loadChapter(url: url, progress: progress, fragment: fragment, sasayakiCues: cues))
        }
    }
    
    private func loadCurrentChapter() {
        if let url = getCurrentChapter() {
            let cues = sasayakiPlayer.hasMatch ? sasayakiPlayer.cues(for: index) : nil
            bridge.updateState(url: url, progress: currentProgress, sasayakiCues: cues)
            bridge.send(.loadChapter(url: url, progress: currentProgress, fragment: nil, sasayakiCues: cues))
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
        while let existing = exportTask {
            await existing.value
            if exportTask == existing {
                exportTask = nil
            }
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
        if exportTask == task {
            exportTask = nil
        }
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
    
    static private func getDefaultStatistic(title: String) -> Statistics {
        return Statistics(title: title, dateKey: Self.formattedDate(date: .now), charactersRead: 0, readingTime: 0, minReadingSpeed: 0, altMinReadingSpeed: 0, lastReadingSpeed: 0, maxReadingSpeed: 0, lastStatisticModified: 0)
    }
    
    static private func formattedDate(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
