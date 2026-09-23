//
//  StatisticsStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StatisticsStorage {
    static var onSave: ((String, [String: Timestamped<ReadingSession?>]) -> Void)?
    
    static func loadAll(resetTime: Int) -> [BookStatistics] {
        guard let booksDirectory = try? BookStorage.getBooksDirectory() else {
            return []
        }
        
        let books = ((try? BookStorage.loadAllBooks()) ?? []).compactMap {
            bookStatistics($0, root: booksDirectory.appendingPathComponent($0.folder), isDeleted: false, resetTime: resetTime)
        }
        
        return books + loadArchived(resetTime: resetTime)
    }
    
    static func loadArchived(resetTime: Int = UserConfig.shared.statisticsResetTime) -> [BookStatistics] {
        guard let root = try? archiveDirectory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents.compactMap { url in
            BookStorage.loadMetadata(root: url).flatMap { bookStatistics($0, root: url, isDeleted: true, resetTime: resetTime) }
        }
    }
    
    static func load(root: URL) -> [String: Timestamped<ReadingSession?>] {
        let url = root.appendingPathComponent(FileNames.statistics)
        if let sessions = BookStorage.load([String: Timestamped<ReadingSession?>].self, from: url) {
            return sessions
        }
        
        guard let daily = BookStorage.load([TtuStatistics].self, from: url) else { return [:] }
        let sessions = TtuStatistics.legacySessions(daily, key: root.lastPathComponent)
        try? BookStorage.save(sessions, inside: root, as: FileNames.statistics)
        return sessions
    }
    
    static func load(folder: String) -> [String: Timestamped<ReadingSession?>] {
        guard let root = bookDirectory(folder: folder) ?? archivedBookDirectory(folder: folder) else { return [:] }
        return load(root: root)
    }
    
    static func save(_ sessions: [String: Timestamped<ReadingSession?>], folder: String) {
        guard let root = bookDirectory(folder: folder) ?? archivedBookDirectory(folder: folder) else { return }
        try? BookStorage.save(sessions, inside: root, as: FileNames.statistics)
        if root.deletingLastPathComponent().lastPathComponent == statisticsArchive,
           sessions.values.allSatisfy({ $0.value == nil }) {
            try? BookStorage.delete(at: root.appendingPathComponent(statisticsCover))
        }
        onSave?(folder, sessions)
    }
    
    static func edit(id: String, folder: String, charactersRead: Int?, readingTime: Double?) {
        var sessions = load(folder: folder)
        guard var session = sessions[id]?.value else { return }
        if let charactersRead {
            session.charactersRead = charactersRead
        }
        if let readingTime {
            session.readingTime = readingTime
        }
        guard session != sessions[id]?.value else { return }
        sessions[id] = Timestamped(modified: Date.now.milliseconds, value: session)
        save(sessions, folder: folder)
    }
    
    static func delete(ids: [String], folder: String) {
        var sessions = load(folder: folder)
        for id in ids where sessions[id]?.value != nil {
            sessions[id] = Timestamped(modified: Date.now.milliseconds, value: nil as ReadingSession?)
        }
        save(sessions, folder: folder)
    }
    
    static func archive(_ book: BookMetadata) throws {
        guard let root = bookDirectory(folder: book.folder) else { return }
        let destination = try archiveDirectory().appendingPathComponent(book.folder)
        
        let sessions = SyncBook.mergeRecords(load(root: root), load(root: destination))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try BookStorage.save(sessions, inside: destination, as: FileNames.statistics)
        
        var metadata = BookMetadata(
            title: book.displayTitle,
            author: book.author,
            cover: sessions.values.contains { $0.value != nil } ? writeArchivedCover(book, inside: destination) : nil,
            folder: book.folder,
            lastAccess: book.lastAccess
        )
        metadata.modified = book.modified
        metadata.characterCount = book.characterCount ?? BookStorage.loadBookInfo(root: root)?.characterCount
        try BookStorage.saveMetadata(metadata, inside: destination)
    }
    
    static func restore(folder: String) throws {
        guard let archived = archivedBookDirectory(folder: folder),
              let root = bookDirectory(folder: folder) else {
            return
        }
        
        let sessions = SyncBook.mergeRecords(load(root: root), load(root: archived))
        try BookStorage.save(sessions, inside: root, as: FileNames.statistics)
        try FileManager.default.removeItem(at: archived)
    }
    
    static func clearArchive() {
        guard let root = try? archiveDirectory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents {
            delete(ids: Array(load(root: url).keys), folder: url.lastPathComponent)
        }
    }
    
    private static func bookStatistics(_ book: BookMetadata, root: URL, isDeleted: Bool, resetTime: Int) -> BookStatistics? {
        let days = StatisticsDay.grouped(load(root: root), resetTime: resetTime)
            .filter { $0.total.charactersRead > 0 || $0.total.readingTime > 0 }
        return days.isEmpty ? nil : BookStatistics(metadata: book, isDeleted: isDeleted, days: days)
    }
    
    private static func writeArchivedCover(_ book: BookMetadata, inside directory: URL) -> String? {
        let destinationURL = directory.appendingPathComponent(statisticsCover)
        try? FileManager.default.removeItem(at: destinationURL)
        
        guard let coverURL = book.coverURL,
              let source = CGImageSourceCreateWithURL(coverURL as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return "Books/\(statisticsArchive)/\(book.folder)/\(statisticsCover)"
    }
    
    private static func archiveDirectory() throws -> URL {
        try BookStorage.getBooksDirectory().appendingPathComponent(statisticsArchive)
    }
    
    private static func bookDirectory(folder: String) -> URL? {
        guard let url = try? BookStorage.getBooksDirectory().appendingPathComponent(folder),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return url
    }
    
    private static func archivedBookDirectory(folder: String) -> URL? {
        guard let url = try? archiveDirectory().appendingPathComponent(folder),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return url
    }
    
    private static let statisticsArchive = "statistics_archive"
    private static let statisticsCover = "cover.jpg"
}
