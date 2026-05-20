//
//  BookStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation
import ZipArchive

enum FileNames: Sendable {
    static let metadata = "metadata.json"
    static let bookmark = "bookmark.json"
    static let bookinfo = "bookinfo.json"
    static let shelves = "shelves.json"
    static let statistics = "statistics.json"
    static let sasayakiMatch = "sasayaki_match.json"
    static let sasayakiPlayback = "sasayaki_playback.json"
    static let highlights = "highlights.json"
}

struct BookStorage {
    static func getAppDirectory() throws -> URL {
        guard let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BookStorageError.appDirectoryNotFound
        }
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    static func migrateFromDocuments() {
        guard let appSupport = try? getAppDirectory(),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let migrated = UserDefaults.standard.bool(forKey: "migratedToAppSupport")
        guard !migrated else { return }
        
        let items = ["Books", "Fonts", "Dictionaries", "Audio", "anki_words.json", "anki_config.json"]
        for item in items {
            let src = documents.appendingPathComponent(item)
            let dst = appSupport.appendingPathComponent(item)
            guard FileManager.default.fileExists(atPath: src.path(percentEncoded: false)),
                  !FileManager.default.fileExists(atPath: dst.path(percentEncoded: false)) else { continue }
            try? FileManager.default.moveItem(at: src, to: dst)
        }
        
        UserDefaults.standard.set(true, forKey: "migratedToAppSupport")
    }
    
    static func migrateBooks() {
        guard let booksDir = try? getBooksDirectory(),
              FileManager.default.fileExists(atPath: booksDir.path(percentEncoded: false)) else { return }
        
        let migrated = UserDefaults.standard.bool(forKey: "migratedBooks")
        guard !migrated else { return }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: booksDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for folder in contents {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            
            let destination = folder.appendingPathComponent(folder.lastPathComponent).appendingPathExtension("epub")
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }
            
            let mimetype = folder.appendingPathComponent("mimetype")
            guard FileManager.default.fileExists(atPath: mimetype.path(percentEncoded: false)) else { continue }
            
            let metadata = loadMetadata(root: folder)
            let coverName = metadata?.cover.map { URL(fileURLWithPath: $0).lastPathComponent }
            repackEpub(folder: folder, destination: destination, coverName: coverName)
            
            if let metadata {
                var updated = BookMetadata(
                    id: metadata.id,
                    title: metadata.title,
                    epub: folder.lastPathComponent + ".epub",
                    cover: metadata.cover,
                    folder: metadata.folder,
                    lastAccess: metadata.lastAccess
                )
                updated.renamedTitle = metadata.renamedTitle
                try? save(updated, inside: folder, as: FileNames.metadata)
            }
        }
        
        UserDefaults.standard.set(true, forKey: "migratedBooks")
    }
    
    private static func repackEpub(folder: URL, destination: URL, coverName: String?) {
        let archive = SSZipArchive(path: destination.path(percentEncoded: false))
        guard archive.open() else { return }
        
        let mimetype = folder.appendingPathComponent("mimetype")
        archive.writeFile(
            atPath: mimetype.path(percentEncoded: false),
            withFileName: "mimetype",
            compressionLevel: 0,
            password: nil,
            aes: false
        )
        try? FileManager.default.removeItem(at: mimetype)
        
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            archive.close()
            return
        }
        
        var dirsToRemove: [URL] = []
        for case let url as URL in enumerator {
            let fullPath = url.path(percentEncoded: false)
            let relPath = url.standardizedFileURL.pathComponents
                .dropFirst(folder.standardizedFileURL.pathComponents.count)
                .joined(separator: "/")
            
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                dirsToRemove.append(url)
                continue
            }
            
            if url.pathExtension == "json" || url.pathExtension == "epub"
                || url.lastPathComponent == coverName {
                continue
            }
            
            archive.writeFile(
                atPath: fullPath,
                withFileName: relPath,
                compressionLevel: -1,
                password: nil,
                aes: false
            )
            try? FileManager.default.removeItem(at: url)
        }
        
        archive.close()
        
        for dir in dirsToRemove.sorted(by: { $0.path.count > $1.path.count }) {
            try? FileManager.default.removeItem(at: dir)
        }
    }
    
    static func getBooksDirectory() throws -> URL {
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
    
    static func loadMetadata(root: URL) -> BookMetadata? {
        load(BookMetadata.self, from: root.appendingPathComponent(FileNames.metadata))
    }
    
    static func loadStatistics(root: URL) -> [Statistics]? {
        load([Statistics].self, from: root.appendingPathComponent(FileNames.statistics))
    }
    
    static func loadSasayakiMatch(root: URL) -> SasayakiMatchData? {
        load(SasayakiMatchData.self, from: root.appendingPathComponent(FileNames.sasayakiMatch))
    }
    
    static func loadSasayakiPlayback(root: URL) -> SasayakiPlaybackData? {
        load(SasayakiPlaybackData.self, from: root.appendingPathComponent(FileNames.sasayakiPlayback))
    }
    
    static func loadHighlights(root: URL) -> [Highlight]? {
        load([Highlight].self, from: root.appendingPathComponent(FileNames.highlights))
    }
    
    static func loadShelves() -> [BookShelf]? {
        load([BookShelf].self, from: try! getBooksDirectory().appendingPathComponent(FileNames.shelves))
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
        let parser = EPUBParser()
        do {
            return try parser.parse(documentAt: path)
        } catch {
            throw BookStorageError.epubImportFailed(error)
        }
    }
    
    enum BookStorageError: LocalizedError {
        case accessDenied
        case appDirectoryNotFound
        case epubImportFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Could not access .epub file"
            case .appDirectoryNotFound:
                return "App directory not found"
            case .epubImportFailed(let error):
                return "Could not import .epub file: \(error.localizedDescription)"
            }
        }
    }
}
