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
    
    // reader
    var index: Int = 0
    var currentProgress: Double = 0.0
    var activeSheet: ActiveSheet?
    var bookInfo: BookInfo
    
    // lookups
    var showPopup = false
    var currentSelection: SelectionData?
    var lookupResults: [LookupResult] = []
    var dictionaryStyles: [String: String] = [:]
    
    // stats
    var isTracking = false
    var isPaused = false
    var lastTimestamp: Date = .now
    var lastCount: Int = 0
    var stats: [Statistics] = []
    var sessionStatistics: Statistics
    var todaysStatistics: Statistics
    var allTimeStatistics: Statistics
    
    init(document: EPUBDocument, rootURL: URL) {
        self.document = document
        self.rootURL = rootURL
        
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
        
        // TODO: add menu option to enable/disable stats
        sessionStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        todaysStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        allTimeStatistics = Self.getDefaultStatistic(title: document.title ?? "")
        
        loadStatistics()
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
        currentProgress = progress
        let bookmark = Bookmark(
            chapterIndex: index,
            progress: progress,
            characterCount: currentCharacter,
            lastModified: Date()
        )
        if isTracking {
            updateStats()
            saveStats()
        }
        try? BookStorage.save(bookmark, inside: rootURL, as: FileNames.bookmark)
    }
    
    func setIndex(index: Int, progress: Double) {
        self.index = index
        currentProgress = progress
        saveBookmark(progress: progress)
    }
    
    func nextChapter() -> Bool {
        if index < document.spine.items.count - 1 {
            setIndex(index: index + 1, progress: 0)
            return true
        }
        return false
    }
    
    func previousChapter() -> Bool {
        if index > 0 {
            setIndex(index: index - 1, progress: 1)
            return true
        }
        return false
    }
    
    func handleTextSelection(_ selection: SelectionData, maxResults: Int) -> Int? {
        currentSelection = selection
        lookupResults = LookupEngine.shared.lookup(selection.text, maxResults: maxResults)
        dictionaryStyles = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        
        if let firstResult = lookupResults.first {
            withAnimation(.default.speed(2)) {
                showPopup = true
            }
            return String(firstResult.matched).count
        } else {
            closePopup()
            return nil
        }
    }
    
    func closePopup() {
        withAnimation(.default.speed(2)) {
            showPopup = false
        }
    }
    
    func startTracking() {
        isTracking = true
        lastTimestamp = .now
        lastCount = currentCharacter
    }
    
    func stopTracking() {
        guard isTracking else {
            return
        }
        isTracking = false
        updateStats()
        saveStats()
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
    
    static private func getDefaultStatistic(title: String) -> Statistics {
        return Statistics(title: title, dateKey: Self.formattedDate(date: .now), charactersRead: 0, readingTime: 0, minReadingSpeed: 0, altMinReadingSpeed: 0, lastReadingSpeed: 0, maxReadingSpeed: 0, lastStatisticModified: 0)
    }
    
    static private func formattedDate(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
