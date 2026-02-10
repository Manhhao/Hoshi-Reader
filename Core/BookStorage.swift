//
//  BookStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation

enum FileNames: Sendable {
    static let metadata = "metadata.json"
    static let bookmark = "bookmark.json"
    static let bookinfo = "bookinfo.json"
    static let shelves = "shelves.json"
    static let statistics = "statistics.json"
}

struct BookStorage {
    static func getDocumentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw BookStorageError.documentsDirectoryNotFound
        }
        return url
    }
    
    static func getBooksDirectory() throws -> URL {
        try getDocumentsDirectory().appendingPathComponent("Books")
    }
    
    @discardableResult
    static func copySecurityScopedFile(from fileURL: URL, to destinationPath: String? = nil) throws -> URL {
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw BookStorageError.accessDenied
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        
        let documentsDirectory = try getDocumentsDirectory()
        let destinationURL = documentsDirectory.appendingPathComponent(destinationPath ?? fileURL.lastPathComponent)
        
        let destinationFolder = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        try replaceFile(at: destinationURL, with: fileURL)
        return destinationURL
    }
    
    @discardableResult
    static func copyFile(from fileURL: URL, to destinationPath: String) throws -> URL {
        let documentsDirectory = try getDocumentsDirectory()
        let destinationURL = documentsDirectory.appendingPathComponent(destinationPath)
        
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
    
    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
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
        load([Statistics].self, from: root.appendingPathComponent(FileNames.metadata))
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
        case documentsDirectoryNotFound
        case epubImportFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Could not access .epub file"
            case .documentsDirectoryNotFound:
                return "Documents directory not found"
            case .epubImportFailed(let error):
                return "Could not import .epub file: \(error.localizedDescription)"
            }
        }
    }
}
