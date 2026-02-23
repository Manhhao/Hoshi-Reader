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
import CYomitanDicts

enum ActiveSheet: Identifiable {
    case appearance
    case chapters
    case statistics
    var id: Self { self }
}

struct PopupItem: Identifiable {
    let id: UUID = UUID()
    var showPopup: Bool
    var currentSelection: SelectionData?
    var lookupResults: [LookupResult] = []
    var dictionaryStyles: [String: String] = [:]
    var isVertical: Bool
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
    let document: EPUBDocument
    let rootURL: URL
    let enableStatistics: Bool
    let autostartStatistics: Bool
    
    // reader
    var index: Int = 0
    var currentProgress: Double = 0.0
    var activeSheet: ActiveSheet?
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
    
    init(document: EPUBDocument, rootURL: URL, enableStatistics: Bool, autostartStatistics: Bool) {
        self.document = document
        self.rootURL = rootURL
        self.enableStatistics = enableStatistics
        self.autostartStatistics = autostartStatistics
        
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
        
        if let url = getCurrentChapter() {
            bridge.updateState(url: url, progress: currentProgress)
            bridge.send(.loadChapter(url: url, progress: currentProgress))
        }
    }
    
    func loadStatistics() {
        stats = BookStorage.loadStatistics(root: rootURL) ?? []
        todaysStatistics = stats.first(where: { $0.dateKey == Self.formattedDate(date: .now) }) ?? Self.getDefaultStatistic(title: document.title ?? "")
        
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
    
    func jumpToChapter(index: Int) {
        flushStats()
        loadChapter(index: index, progress: 0)
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
    
    func handleTextSelection(_ selection: SelectionData, maxResults: Int, isVertical: Bool) -> Int? {
        let lookupResults = LookupEngine.shared.lookup(selection.text, maxResults: maxResults)
        var dictionaryStyles: [String: String] = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        let popup = PopupItem(
            showPopup: false,
            currentSelection: selection,
            lookupResults: LookupEngine.shared.lookup(selection.text, maxResults: maxResults),
            dictionaryStyles: dictionaryStyles,
            isVertical: isVertical
        )
        popups.append(popup)
        
        if let firstResult = lookupResults.first {
            withAnimation(.default.speed(2)) {
                popups[popups.count - 1].showPopup = true
            }
            return String(firstResult.matched).count
        }
        return nil
    }
    
    func closePopups() {
        let popupIds = Set(popups.map(\.id))
        withAnimation(.default.speed(2)) {
            for index in popups.indices {
                popups[index].showPopup = false
            }
        } completion: {
            self.popups.removeAll { popupIds.contains($0.id) }
        }
    }
    
    func closeChildPopups(parent: Int) {
        var popupIds: Set<UUID> = []
        withAnimation(.default.speed(2)) {
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
    }
    
    private func loadChapter(index: Int, progress: Double) {
        self.index = index
        persistBookmark(progress: progress)
        if let url = getCurrentChapter() {
            bridge.updateState(url: url, progress: progress)
            bridge.send(.loadChapter(url: url, progress: progress))
        }
    }
    
    private func flushStats() {
        guard isTracking else { return }
        updateStats()
        saveStats()
    }
    
    private func resetTrackingBaseline() {
        lastCount = currentCharacter
        lastTimestamp = .now
    }
    
    static private func getDefaultStatistic(title: String) -> Statistics {
        return Statistics(title: title, dateKey: Self.formattedDate(date: .now), charactersRead: 0, readingTime: 0, minReadingSpeed: 0, altMinReadingSpeed: 0, lastReadingSpeed: 0, maxReadingSpeed: 0, lastStatisticModified: 0)
    }
    
    static private func formattedDate(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
