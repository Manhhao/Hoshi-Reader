//
//  BookStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation
import ZIPFoundation

nonisolated enum FileNames: Sendable {
    static let metadata = "metadata.json"
    static let bookmark = "bookmark.json"
    static let bookinfo = "bookinfo.json"
    static let shelves = "shelves.json"
    static let statistics = "statistics.json"
    static let sasayakiMatch = "sasayaki_match.json"
    static let sasayakiPlayback = "sasayaki_playback.json"
    static let sasayakiTranscript = "sasayaki_transcript.json"
    static let highlights = "highlights.json"
}

struct BookStorage {
    static var migrationsComplete: Bool {
        return true
    }
    
    nonisolated private static let appDirectory: URL? = {
        guard let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()
    
    nonisolated static func getAppDirectory() throws -> URL {
        guard let appDirectory else {
            throw BookStorageError.appDirectoryNotFound
        }
        return appDirectory
    }
    
    nonisolated static func getBooksDirectory() throws -> URL {
        try getAppDirectory().appendingPathComponent("Books")
    }
    
    @discardableResult
    static func copySecurityScopedFile(from fileURL: URL, to destinationPath: String? = nil) throws -> URL {
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw BookStorageError.accessDenied
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        
        let appDirectory = try getAppDirectory()
        let destinationURL = appDirectory.appendingPathComponent(destinationPath ?? fileURL.lastPathComponent)
        
        let destinationFolder = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        try replaceFile(at: destinationURL, with: fileURL)
        return destinationURL
    }
    
    @discardableResult
    static func copyFile(from fileURL: URL, to destinationPath: String) throws -> URL {
        let appDirectory = try getAppDirectory()
        let destinationURL = appDirectory.appendingPathComponent(destinationPath)
        
        if destinationURL.path(percentEncoded: false) == fileURL.path(percentEncoded: false) {
            return destinationURL
        }
        
        let destinationFolder = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        try replaceFile(at: destinationURL, with: fileURL)
        return destinationURL
    }
    
    private static func replaceFile(at destination: URL, with source: URL) throws {
        try delete(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
    
    static func delete(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
    
    static func save<T: Encodable>(_ object: T, inside directory: URL, as fileName: String) throws {
        let targetURL = directory.appendingPathComponent(fileName)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(object)
        
        try data.write(to: targetURL, options: .atomic)
    }
    
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    static func loadBookmark(root: URL) -> Bookmark? {
        load(Bookmark.self, from: root.appendingPathComponent(FileNames.bookmark))
    }
    
    static func loadBookInfo(root: URL) -> BookInfo? {
        load(BookInfo.self, from: root.appendingPathComponent(FileNames.bookinfo))
    }
    
    nonisolated static func loadMetadata(root: URL) -> BookMetadata? {
        let url = root.appendingPathComponent(FileNames.metadata)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(BookMetadata.self, from: data)
    }
    
    nonisolated static func saveMetadata(_ metadata: BookMetadata, inside directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(metadata)
        try data.write(to: directory.appendingPathComponent(FileNames.metadata), options: .atomic)
    }
    
    static func loadSasayakiMatch(root: URL) -> SasayakiMatchData? {
        load(SasayakiMatchData.self, from: root.appendingPathComponent(FileNames.sasayakiMatch))
    }
    
    static func loadSasayakiTranscript(root: URL) -> SasayakiTranscript? {
        load(SasayakiTranscript.self, from: root.appendingPathComponent(FileNames.sasayakiTranscript))
    }
    
    static func loadSasayakiPlayback(root: URL) -> SasayakiPlaybackData? {
        load(SasayakiPlaybackData.self, from: root.appendingPathComponent(FileNames.sasayakiPlayback))
    }
    
    static func savePlayback(_ playback: inout SasayakiPlaybackData, root: URL) throws -> Bool {
        let stored = loadSasayakiPlayback(root: root)
        let changed = stored?.lastPosition != playback.lastPosition || stored?.delay != playback.delay || stored?.rate != playback.rate
        playback.modified = changed ? Date.now.milliseconds : stored?.modified
        try save(playback, inside: root, as: FileNames.sasayakiPlayback)
        return changed
    }
    
    static func loadHighlightRecords(root: URL) -> [String: Timestamped<Highlight?>] {
        let url = root.appendingPathComponent(FileNames.highlights)
        if let records = load([String: Timestamped<Highlight?>].self, from: url) {
            return records
        }
        let highlights = load([Highlight].self, from: url) ?? []
        return Dictionary(uniqueKeysWithValues: highlights.map { ($0.id.uuidString, Timestamped(modified: $0.createdAt.milliseconds, value: $0)) })
    }
    
    static func loadHighlights(root: URL) -> [Highlight] {
        loadHighlightRecords(root: root).values.compactMap(\.value).sorted { $0.createdAt < $1.createdAt }
    }
    
    static func saveHighlights(_ highlights: [Highlight], root: URL) throws {
        var records = loadHighlightRecords(root: root)
        let now = Date.now.milliseconds
        let ids = Set(highlights.map(\.id.uuidString))
        for (id, record) in records where record.value != nil && !ids.contains(id) {
            records[id] = Timestamped(modified: now, value: nil)
        }
        for highlight in highlights {
            let id = highlight.id.uuidString
            if records[id] == nil || (records[id]!.value != nil && records[id]!.value != highlight) {
                records[id] = Timestamped(modified: now, value: highlight)
            }
        }
        try save(records, inside: root, as: FileNames.highlights)
    }
    
    static func loadShelfList() -> [String: Timestamped<Int?>] {
        guard let booksDirectory = try? getBooksDirectory() else { return [:] }
        let url = booksDirectory.appendingPathComponent(FileNames.shelves)
        if let shelves = load([String: Timestamped<Int?>].self, from: url) {
            return shelves
        }
        
        guard let legacy = load([BookShelf].self, from: url) else { return [:] }
        var shelves: [String: Timestamped<Int?>] = [:]
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: booksDirectory, includingPropertiesForKeys: nil)
            var books = Dictionary(uniqueKeysWithValues: folders.compactMap { loadMetadata(root: $0) }.map { ($0.id, $0) })
            for (index, shelf) in legacy.enumerated() {
                let name = shelf.name.precomposedStringWithCanonicalMapping
                shelves[name] = Timestamped(modified: 0, value: index)
                for id in shelf.bookIds where books[id] != nil {
                    var membership = books[id]!.shelves ?? [:]
                    membership[name] = Timestamped(modified: 0, value: true)
                    books[id]!.shelves = membership
                }
            }
            for book in books.values where book.shelves != nil {
                try saveMetadata(book, inside: booksDirectory.appendingPathComponent(book.folder))
            }
            try saveShelfList(shelves)
        } catch {}
        return shelves
    }
    
    static func saveShelfList(_ shelves: [String: Timestamped<Int?>]) throws {
        try save(shelves, inside: getBooksDirectory(), as: FileNames.shelves)
    }
    
    static func loadAllBooks() throws -> [BookMetadata] {
        let booksDirectory = try getBooksDirectory()
        
        if !FileManager.default.fileExists(atPath: booksDirectory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        }
        
        var books: [BookMetadata] = []
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: booksDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for url in contents {
            let resources = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard resources.isDirectory == true else {
                continue
            }
            
            let metadataURL = url.appendingPathComponent(FileNames.metadata)
            
            if FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) {
                let data = try Data(contentsOf: metadataURL)
                let book = try JSONDecoder().decode(BookMetadata.self, from: data)
                books.append(book)
            }
        }
        
        return books
    }
    
    static func loadEpub(_ path: URL) throws -> EPUBDocument {
        let tempDirectory = try getAppDirectory().appendingPathComponent("Temp")
        try? FileManager.default.removeItem(at: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let destination = tempDirectory.appendingPathComponent(path.deletingPathExtension().lastPathComponent)
        try FileManager.default.unzipItem(at: path, to: destination)
        
        let parser = EPUBParser()
        do {
            return try parser.parse(documentAt: destination)
        } catch {
            throw BookStorageError.epubImportFailed(error)
        }
    }
    
    static func sanitizeFileName(_ string: String) -> String {
        return string
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.newlines).union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated enum BookStorageError: LocalizedError {
        case accessDenied
        case appDirectoryNotFound
        case epubImportFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return String(localized: "Could not access .epub file")
            case .appDirectoryNotFound:
                return String(localized: "App directory not found")
            case .epubImportFailed(let error):
                return String(localized: "Could not import .epub file: \(error.localizedDescription)")
            }
        }
    }
}
