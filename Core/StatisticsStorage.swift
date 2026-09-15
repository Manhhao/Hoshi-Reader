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
    static func loadAll() -> [BookStatistics] {
        guard let booksDirectory = try? BookStorage.getBooksDirectory() else {
            return []
        }
        
        let books = ((try? BookStorage.loadAllBooks()) ?? []).compactMap {
            bookStatistics($0, root: booksDirectory.appendingPathComponent($0.folder), isDeleted: false)
        }
        
        return books + loadArchived()
    }
    
    static func loadArchived() -> [BookStatistics] {
        guard let root = try? archiveDirectory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents.compactMap { url in
            BookStorage.loadMetadata(root: url).flatMap { bookStatistics($0, root: url, isDeleted: true) }
        }
    }
    
    static func load(folder: String) -> [Statistics] {
        guard let root = bookDirectory(folder: folder) ?? archivedBookDirectory(folder: folder) else {
            return []
        }
        return Statistics.merged(BookStorage.loadStatistics(root: root) ?? [])
    }
    
    static func save(_ statistics: [Statistics], folder: String) {
        let merged = Statistics.merged(statistics).filter(\.hasActivity)
        
        if let root = bookDirectory(folder: folder) {
            try? BookStorage.save(merged, inside: root, as: FileNames.statistics)
        } else if let root = archivedBookDirectory(folder: folder) {
            if merged.isEmpty {
                try? FileManager.default.removeItem(at: root)
            } else {
                try? BookStorage.save(merged, inside: root, as: FileNames.statistics)
            }
        }
    }
    
    static func archive(_ book: BookMetadata) {
        guard let root = bookDirectory(folder: book.folder),
              let statistics = BookStorage.loadStatistics(root: root)?.filter(\.hasActivity),
              !statistics.isEmpty,
              let destination = try? archiveDirectory().appendingPathComponent(book.folder) else {
            return
        }
        
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = BookStorage.loadStatistics(root: destination) ?? []
        try? BookStorage.save(Statistics.merged(existing + statistics), inside: destination, as: FileNames.statistics)
        
        let metadata = BookMetadata(
            title: book.displayTitle,
            author: book.author,
            cover: writeArchivedCover(book, inside: destination),
            folder: book.folder,
            lastAccess: book.lastAccess
        )
        try? BookStorage.saveMetadata(metadata, inside: destination)
    }
    
    static func restore(folder: String) {
        guard let archived = archivedBookDirectory(folder: folder),
              let root = bookDirectory(folder: folder) else {
            return
        }
        
        let existing = BookStorage.loadStatistics(root: root) ?? []
        let restored = BookStorage.loadStatistics(root: archived) ?? []
        try? BookStorage.save(Statistics.merged(existing + restored), inside: root, as: FileNames.statistics)
        try? FileManager.default.removeItem(at: archived)
    }
    
    static func clearArchive() {
        guard let root = try? archiveDirectory() else {
            return
        }
        try? FileManager.default.removeItem(at: root)
    }
    
    private static func bookStatistics(_ book: BookMetadata, root: URL, isDeleted: Bool) -> BookStatistics? {
        let days = Statistics.merged(BookStorage.loadStatistics(root: root) ?? [])
            .filter(\.hasActivity)
            .map(\.readingDay)
        
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
