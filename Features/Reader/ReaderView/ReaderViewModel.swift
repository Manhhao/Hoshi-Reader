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
    case contents
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
        guard let booksFolder = try? BookStorage.getBooksDirectory() else {
            return nil
        }
        return booksFolder.appendingPathComponent(book.folder)
    }
    
    init(book: BookMetadata) {
        self.book = book
        loadBook()
    }
    
    func loadBook() {
        guard let root = rootURL,
              let epub = book.epub else {
            return
        }
        
        guard let doc = try? BookStorage.loadEpub(root.appendingPathComponent(epub)) else {
            return
        }
        
        let info = BookStorage.loadBookInfo(root: root)
        if info == nil {
            let processed = BookProcessor.process(document: doc)
            try? BookStorage.save(processed, inside: root, as: FileNames.bookinfo)
            if let bookmark = BookStorage.loadBookmark(root: root) {
                let position = processed.resolveCharacterPosition(bookmark.characterCount)
                let resolved = Bookmark(
                    chapterIndex: position?.spineIndex ?? 0,
                    progress: position?.progress ?? 0,
                    characterCount: bookmark.characterCount,
                    lastModified: bookmark.lastModified
                )
                try? BookStorage.save(resolved, inside: root, as: FileNames.bookmark)
            }
        } else if info?.images == nil {
            let processed = BookProcessor.process(document: doc)
            try? BookStorage.save(processed, inside: root, as: FileNames.bookinfo)
        }
        
        CSSSanitizer.sanitizeDirectory(doc.contentDirectory)
        
        var bookCopy = BookStorage.loadMetadata(root: root)!
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
    var contentsTab: ContentsTab = .chapters
    var isLoading = true
    var bookDeleted = false
    private var applyingBookmark = false
    var focusMode = false
    var topSafeArea: CGFloat = 0
    var bottomSafeArea: CGFloat = 0
    var bookInfo: BookInfo
    private let chapterStarts: [Int]
    let bridge = WebViewBridge()
    
    // lookups
    var popups: [PopupItem] = []
    
    // stats
    var isTracking = false
    var isPaused = false
    var lastTimestamp: Date = .now
    var lastCount: Int = 0
    private var sessionId = UUID().uuidString
    private(set) var currentSession = ReadingSession.starting(at: .now)
    private var history: [String: Timestamped<ReadingSession?>] = [:]
    private var historyDays: [Date: ReadingTotal] = [:]
    private var historyTotal = ReadingTotal(date: .distantPast)
    let autostartStatistics: Bool
    
    var statisticsResetTime: Int {
        didSet {
            regroupSessions()
        }
    }
    
    // sasayaki
    var sasayakiPlayer: SasayakiPlayer!
    var wasPaused = false
    
    // sync
    let autoSyncEnabled: Bool
    let syncBookData: Bool
    let syncStats: Bool
    let statsSyncMode: StatisticsSyncMode
    let syncAudioBook: Bool
    var isSyncing = false
    private var pendingAutoExport = false
    private var debounceTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    
    private var pendingSearchHighlight: (offset: Int, length: Int)?
    
    // highlights
    var highlights: [Highlight] = []
    
    // navigation history
    private var backHistory: [Position] = []
    private var forwardHistory: [Position] = []
    private var currentPosition: Position { Position(index: index, progress: currentProgress) }
    var backTarget: Int? { backHistory.last.flatMap { calculateCharacterProgress(for: $0) } }
    var forwardTarget: Int? { forwardHistory.last.flatMap { calculateCharacterProgress(for: $0) } }
    
    init(
        book: BookMetadata,
        document: EPUBDocument,
        rootURL: URL,
        autostartStatistics: Bool,
        statisticsResetTime: Int,
        autoSyncEnabled: Bool,
        syncBookData: Bool,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool
    ) {
        self.book = book
        self.document = document
        self.rootURL = rootURL
        self.autostartStatistics = autostartStatistics
        self.statisticsResetTime = statisticsResetTime
        self.autoSyncEnabled = autoSyncEnabled
        self.syncBookData = syncBookData
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
        
        let info = BookStorage.loadBookInfo(root: rootURL) ?? BookInfo(characterCount: 0, chapterInfo: [:], images: nil)
        bookInfo = info
        chapterStarts = Self.chapterStarts(document: document, bookInfo: info)
        
        loadSessions()
        
        if autostartStatistics {
            startTracking()
        }
        
        sasayakiPlayer = SasayakiPlayer(
            rootURL: rootURL,
            bridge: bridge,
            loadChapter: { [weak self] chapterIndex in
                self?.flushStats()
                self?.loadChapter(index: chapterIndex, progress: self?.sasayakiCueProgress(for: chapterIndex) ?? 0)
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
        
        highlights = BookStorage.loadHighlights(root: rootURL)
    }
    
    // todo: name is misleading after fragment changes. this is technically the character count of the xhtml file, not necessarily the count of a toc chapter. fix during refactor
    var currentChapterCount: Int {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else {
            return 0
        }
        return chapterInfo.currentTotal + chapterInfo.chapterCount
    }
    
    // "true" chapter range
    var currentChapterRange: (character: Int, total: Int, progress: Double) {
        let position = currentCharacter
        let xhtmlEnd = currentChapterCount
        let range = chapterBounds(at: xhtmlEnd > 0 ? min(position, xhtmlEnd - 1) : position)
        let character = position - range.start
        let progress = range.count > 0 ? Double(character) / Double(range.count) : 0
        return (character, range.count, progress)
    }
    
    var currentCharacter: Int {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else {
            return 0
        }
        
        return chapterInfo.currentTotal + Int(Double(chapterInfo.chapterCount) * currentProgress)
    }
    
    var progressString: String {
        let config = UserConfig.shared
        var lines: [String] = []
        if config.readerShowProgress {
            let line = progressLine(current: currentCharacter, total: bookInfo.characterCount)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        
        if config.readerShowChapterProgress {
            let chapter = currentChapterRange
            let line = progressLine(current: chapter.character, total: chapter.total)
            if !line.isEmpty {
                lines.append("(\(line))")
            }
        }
        return lines.joined(separator: config.readerAlwaysShowProgress || config.readerShowProgressTop ? " " : "\n")
    }
    
    private func progressLine(current: Int, total: Int) -> String {
        let config = UserConfig.shared
        var parts: [String] = []
        if config.readerShowCharacters {
            parts.append("\(current) / \(total)")
        }
        if config.readerShowPercentage {
            let percent = total > 0 ? Double(current) / Double(total) * 100 : 0
            parts.append(String(format: "%.2f%%", percent))
        }
        return parts.joined(separator: " ")
    }
    
    var todaysTotal: ReadingTotal {
        let today = StatisticsDay.date(.now, resetTime: statisticsResetTime)
        var total = historyDays[today] ?? ReadingTotal(date: today)
        let start = Date(milliseconds: currentSession.startedAt)
        
        if StatisticsDay.date(start, resetTime: statisticsResetTime) == today {
            total.add(currentSession)
        }
        
        return total
    }
    
    var allTimeTotal: ReadingTotal {
        var total = historyTotal
        total.add(currentSession)
        
        return total
    }
    
    var statisticsString: String {
        let config = UserConfig.shared
        var result: [String] = []
        if config.readerShowReadingSpeed {
            result.append("\(currentSession.readingSpeed.formatted(.number.grouping(.never))) / h")
        }
        if config.readerShowReadingTime {
            result.append("\(Duration.seconds(currentSession.readingTime).formatted(.time(pattern: .hourMinute)))")
        }
        return result.joined(separator: " ")
    }
    
    var coverURL: URL? {
        if let book = BookStorage.loadMetadata(root: rootURL) {
            return book.coverURL
        }
        return nil
    }
    
    var imageURLs: [URL] {
        (bookInfo.images ?? []).map { document.contentDirectory.appendingPathComponent($0) }
    }
    
    // todo: fix naming
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
    
    // todo: fix naming
    private var chapterRange: (start: Int, end: Int)? {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let info = bookInfo.chapterInfo[manifestItem.path] else {
            return nil
        }
        return (info.currentTotal, info.currentTotal + info.chapterCount)
    }
    
    private func sasayakiCueProgress(for chapterIndex: Int) -> Double? {
        guard let cue = sasayakiPlayer.pendingCue, cue.chapterIndex == chapterIndex,
              document.spine.items.indices.contains(chapterIndex),
              let manifestItem = document.manifest.items[document.spine.items[chapterIndex].idref],
              let info = bookInfo.chapterInfo[manifestItem.path] else {
            return nil
        }
        return Double(cue.start) / Double(info.chapterCount)
    }
    
    func handleRestoreCompleted() {
        if applyingBookmark {
            applyingBookmark = false
            resetTrackingBaseline()
        }
        
        if !sasayakiPlayer.hasAudio {
            sasayakiPlayer.restoreAudio()
        }
        isLoading = false
        sasayakiPlayer.handleRestoreCompleted(currentIndex: index)
        if let highlight = pendingSearchHighlight {
            pendingSearchHighlight = nil
            bridge.send(.showSearchHighlight(offset: highlight.offset, length: highlight.length))
        }
    }
    
    func handleProcessTerminated() {
        isLoading = true
        sasayakiPlayer.prepareTransition()
    }
    
    func importSasayakiAudio(from url: URL) throws {
        try sasayakiPlayer.importAudio(from: url)
    }
    
    func syncOnOpen(skipSync: Bool) async {
        if UserConfig.shared.enableSync && UserConfig.shared.syncProvider == .gdrive {
            if !skipSync {
                await GoogleDriveSyncManager.shared.sync(book: book)
            }
            
            if bookDeleted || BookStorage.loadMetadata(root: rootURL)?.epub == nil {
                bookDeleted = true
                return
            }
        } else if autoSyncEnabled {
            let result = try? await TtuSyncManager.shared.syncBook(
                book: book,
                direction: nil,
                syncBookData: syncBookData,
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
        if UserConfig.shared.syncProvider == .gdrive {
            await GoogleDriveSyncManager.shared.sync(book: book)
            return
        }
        
        guard autoSyncEnabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let result = try? await TtuSyncManager.shared.syncBook(
            book: book,
            direction: nil,
            syncBookData: syncBookData,
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
        if UserConfig.shared.syncProvider == .gdrive {
            await GoogleDriveSyncManager.shared.sync()
            
            return
        }
        
        debounceTask?.cancel()
        debounceTask = nil
        await runAutoExport(direction: .exportToTtu)
    }
    
    func applySyncedState(_ syncedBook: SyncBook, bookmarkChanged: Bool) {
        if bookmarkChanged {
            let count = syncedBook.bookmark!.value.characterCount
            
            if let position = bookInfo.resolveCharacterPosition(count) {
                applyingBookmark = true
                isLoading = true
                index = position.spineIndex
                currentProgress = position.progress
                resetTrackingBaseline()
                
                if bridge.chapterURL != nil {
                    loadCurrentChapter()
                }
            }
        }
        
        let values = Dictionary(
            uniqueKeysWithValues: highlights.map { ($0.id.uuidString, SyncHighlight($0)) }
        )
        if values != syncedBook.highlights.compactMapValues(\.value) {
            highlights = BookStorage.loadHighlights(root: rootURL)
            syncHighlights()
        }
        
        if let change = syncedBook.audiobook {
            let value = change.value
            let playback = sasayakiPlayer.playback
            
            if playback.lastPosition != value.lastPosition || playback.delay != value.delay
                || Double(playback.rate) != value.rate {
                sasayakiPlayer.reloadPlayback()
            }
        }
        
        applySessions(syncedBook.sessions)
    }
    
    func reloadSyncedMatch() {
        sasayakiPlayer.matchData = BookStorage.loadSasayakiMatch(root: rootURL)
        sasayakiPlayer.timeline = CueTimeline(match: sasayakiPlayer.matchData)
        bridge.send(.applySasayakiCues(sasayakiPlayer.cues(for: index)))
    }
    
    func updateProgress(_ progress: Double) {
        if applyingBookmark {
            return
        }
        
        currentProgress = progress
    }
    
    func saveBookmark(progress: Double) {
        if applyingBookmark || bookDeleted {
            return
        }
        
        persistBookmark(progress: progress)
        flushStats()
    }
    
    func jumpToCharacter(_ characterCount: Int) {
        guard let result = bookInfo.resolveCharacterPosition(characterCount) else { return }
        recordPosition()
        navigate(to: Position(index: result.spineIndex, progress: result.progress))
    }
    
    func jumpToSearchResult(character: Int, length: Int) {
        guard let result = bookInfo.resolveCharacterPosition(character) else { return }
        let chapterStart = bookInfo.chapterInfo.values.first { $0.spineIndex == result.spineIndex }?.currentTotal ?? 0
        pendingSearchHighlight = (character - chapterStart, length)
        recordPosition()
        navigate(to: Position(index: result.spineIndex, progress: result.progress))
    }
    
    // todo: fix naming
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
    
    // todo: fix naming
    func nextChapter() -> Bool {
        guard index < document.spine.items.count - 1 else { return false }
        loadChapter(index: index + 1, progress: 0)
        flushStats()
        return true
    }
    
    // todo: fix naming
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
        guard !popups.isEmpty else { return }
        let popupIds = Set(popups.map(\.id))
        withAnimation(.default.speed(2.4)) {
            popups = popups.map {
                var p = $0
                p.showPopup = false
                return p
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
        let popupIds = Set(popups.dropFirst(parent + 1).map(\.id))
        guard !popupIds.isEmpty else { return }
        withAnimation(.default.speed(2.4)) {
            popups = popups.map {
                var p = $0
                if popupIds.contains(p.id) {
                    p.showPopup = false
                }
                return p
            }
        } completion: {
            self.popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    func turnPage(_ direction: NavigationDirection) {
        bridge.send(.paginate(direction))
    }
    
    func clearSelection() {
        bridge.send(.clearSelection)
    }
    
    func startTracking() {
        if !currentSession.hasActivity {
            currentSession = .starting(at: .now)
        }
        
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
        if applyingBookmark {
            return
        }
        let now: Date = .now
        let timeDiff = now.timeIntervalSince(lastTimestamp)
        let charDiff = max(currentCharacter - lastCount, -currentSession.charactersRead)
        
        guard timeDiff > 0 else {
            return
        }
        
        currentSession.track(characters: charDiff, time: timeDiff, until: now)
        
        lastTimestamp = now
        lastCount = currentCharacter
    }
    
    func resetTrackingBaseline() {
        lastCount = currentCharacter
        lastTimestamp = .now
    }
    
    func flushStats() {
        guard isTracking else { return }
        if !isPaused {
            updateStats()
        }
        saveStats()
    }
    
    func applySessions(_ sessions: [String: Timestamped<ReadingSession?>]) {
        if let change = sessions[sessionId], change.value == nil {
            sessionId = UUID().uuidString
            currentSession = .starting(at: .now)
        }
        
        if history != sessions {
            history = sessions
            regroupSessions()
        }
    }
    
    func regroupSessions() {
        let savedSessions = history.filter {
            $0.key != sessionId
        }
        historyDays = Dictionary(
            uniqueKeysWithValues: StatisticsDay.grouped(savedSessions, resetTime: statisticsResetTime).map {
                ($0.date, $0.total)
            }
        )
        historyTotal = historyDays.values.reduce(into: ReadingTotal(date: .distantPast)) {
            $0.add($1)
        }
    }
    
    func addHighlight(_ color: HighlightColor, _ creation: HighlightData) {
        guard let range = chapterRange else { return }
        let highlight = Highlight(
            id: creation.id,
            character: range.start + creation.start,
            offset: creation.offset,
            text: creation.text,
            textFurigana: creation.textFurigana,
            color: color,
            createdAt: Date()
        )
        highlights.append(highlight)
        saveHighlights()
        syncHighlights()
    }
    
    func updateHighlight(_ color: HighlightColor, _ id: UUID) {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        if highlights[index].color == color {
            highlights.remove(at: index)
        } else {
            highlights[index].color = color
        }
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
    
    private func chapterBounds(at characterCount: Int) -> (start: Int, count: Int) {
        let next = chapterStarts.firstIndex { $0 > characterCount } ?? chapterStarts.count
        let start = chapterStarts[next - 1]
        let end = next < chapterStarts.count ? chapterStarts[next] : bookInfo.characterCount
        return (start, end - start)
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
        let stored = BookStorage.loadBookmark(root: rootURL)
        let bookmark = Bookmark(
            chapterIndex: index,
            progress: progress,
            characterCount: currentCharacter,
            lastModified: stored?.characterCount == currentCharacter ? stored?.lastModified : Date()
        )
        
        try? BookStorage.save(bookmark, inside: rootURL, as: FileNames.bookmark)
        try? SyncStorage.shared.handleBookChange(folder: book.folder)
        
        scheduleAutoExport()
    }
    
    // todo: fix naming
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
        loadSessions()
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
    
    private func runAutoExport(direction: TtuSyncDirection?) async {
        if let existing = exportTask {
            await existing.value
        }
        
        guard pendingAutoExport else { return }
        pendingAutoExport = false
        
        let task = Task { [weak self] in
            guard let self else { return }
            _ = try? await TtuSyncManager.shared.syncBook(
                book: self.book,
                direction: direction,
                syncBookData: syncBookData,
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
    
    private func saveStats() {
        var sessions = StatisticsStorage.load(folder: book.folder)
        applySessions(sessions)
        if currentSession.hasActivity && sessions[sessionId]?.value != currentSession {
            sessions[sessionId] = Timestamped(modified: Date.now.milliseconds, value: currentSession)
            StatisticsStorage.save(sessions, folder: book.folder)
        }
        
        scheduleAutoExport()
    }
    
    private func loadSessions() {
        applySessions(StatisticsStorage.load(folder: book.folder))
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
        try? BookStorage.saveHighlights(highlights, root: rootURL)
        try? SyncStorage.shared.handleBookChange(folder: book.folder)
    }
    
    private func syncHighlights() {
        bridge.updateHighlights(chapterHighlights())
    }
    
    private func recordPosition() {
        backHistory.append(currentPosition)
        forwardHistory.removeAll()
    }
    
    private func calculateCharacterProgress(for position: Position) -> Int? {
        guard document.spine.items.indices.contains(position.index) else { return nil }
        let spineItem = document.spine.items[position.index]
        guard let manifestItem = document.manifest.items[spineItem.idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else { return nil }
        return chapterInfo.currentTotal + Int(Double(chapterInfo.chapterCount) * position.progress)
    }
    
    private static func chapterStarts(document: EPUBDocument, bookInfo: BookInfo) -> [Int] {
        var starts: Set<Int> = [0]
        func walk(_ node: EPUBTableOfContents) {
            if let item = node.item {
                let parts = item.components(separatedBy: "#")
                if let chapter = bookInfo.chapterInfo[parts[0]] {
                    let offset = parts.count > 1 ? chapter.fragmentOffsets?[parts[1]] ?? 0 : 0
                    starts.insert(chapter.currentTotal + offset)
                }
            }
            node.subTable?.forEach(walk)
        }
        walk(document.tableOfContents)
        return starts.sorted()
    }
}
