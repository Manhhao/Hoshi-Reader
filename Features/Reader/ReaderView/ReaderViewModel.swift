//
//  ReaderViewModel.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
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
    var timeRead: Double = 0
    var charsRead: Int = 0
    var avgSpeed: Int = 0
    var maxSpeed: Int = 0
    var minSpeed: Int = 0
    var lastCount: Int = 0
    
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
        lastCount = currentCharacter
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
            print("time: \(timeRead)")
            print("chars: \(charsRead)")
            print("avg: \(avgSpeed)")
            print("max: \(maxSpeed)/h")
            print("min: \(minSpeed)/h")
            print("\(lastTimestamp)")
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
    
    func updateStats() {
        let now: Date = .now
        let timeDelta = now.timeIntervalSince(lastTimestamp)
        guard timeDelta > 0 else {
            return
        }
        
        timeRead += timeDelta
        let charDelta = currentCharacter - lastCount
        charsRead = max(charsRead + charDelta, 0)
        avgSpeed = Int(Double(charsRead) / timeRead * 3600)
        maxSpeed = max(maxSpeed, avgSpeed)
        minSpeed = minSpeed != 0 ? min(minSpeed, avgSpeed) : avgSpeed
        lastTimestamp = now
        lastCount = currentCharacter
    }
    
    func saveStats() {
        
    }
}
