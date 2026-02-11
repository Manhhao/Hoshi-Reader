//
//  BookshelfViewModel.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

@Observable
@MainActor
class BookshelfViewModel {
    var books: [BookMetadata] = []
    var shelves: [BookShelf] = []
    var isImporting: Bool = false
    var shouldShowError: Bool = false
    var errorMessage: String = ""
    var shouldShowSuccess: Bool = false
    var successMessage: String = ""
    var isSyncing: Bool = false
    
    private var bookProgress: [UUID: Double] = [:]
    
    func loadBooks() {
        do {
            books = try BookStorage.loadAllBooks()
            loadBookProgress()
            loadShelves()
            print(try BookStorage.getDocumentsDirectory().path(percentEncoded: false))
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func loadShelves() {
        shelves = BookStorage.loadShelves() ?? []
    }
    
    func saveShelves() {
        try? BookStorage.save(shelves, inside: try! BookStorage.getBooksDirectory(), as: FileNames.shelves)
    }
    
    func createShelf(name: String) {
        if !shelves.contains(where: { $0.name == name }) {
            shelves.append(BookShelf(name: name, bookIds: []))
            saveShelves()
        }
    }
    
    func deleteShelf(name: String) {
        shelves.removeAll(where: { $0.name == name })
        saveShelves()
    }
    
    func moveShelves(from source: IndexSet, to destination: Int) {
        shelves.move(fromOffsets: source, toOffset: destination)
        saveShelves()
    }
    
    func moveBook(_ id: UUID, to name: String?) {
        for i in shelves.indices {
            shelves[i].bookIds.removeAll { $0 == id }
        }
        if let name,
           let index = shelves.firstIndex(where: { $0.name == name }) {
            shelves[index].bookIds.append(id)
        }
        saveShelves()
    }
    
    func moveBooks(_ books: Set<BookMetadata>, to name: String?) {
        for book in books {
            moveBook(book.id, to: name)
        }
    }

    func deleteBooks(_ books: Set<BookMetadata>) {
        for book in books {
            deleteBook(book)
        }
    }
    
    func shelfSections(sortedBy: SortOption) -> [ShelfSection] {
        var sections: [ShelfSection] = []
        for shelf in shelves {
            let shelvedBooks = books.filter { shelf.bookIds.contains($0.id) }
            sections.append(ShelfSection(shelf: shelf, books: sortBooks(shelvedBooks, by: sortedBy)))
        }
        
        let unshelved = books.filter { !sections.flatMap { $0.books }.contains($0) }
        sections.append(ShelfSection(shelf: nil, books: sortBooks(unshelved, by: sortedBy)))
        
        return sections
    }
    
    func sortBooks(_ books: [BookMetadata], by option: SortOption) -> [BookMetadata] {
        switch option {
        case .recent:
            return books.sorted { $0.lastAccess > $1.lastAccess }
        case .title:
            return books.sorted { ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending }
        }
    }
    
    func sortedBooks(by option: SortOption) -> [BookMetadata] {
        sortBooks(books, by: option)
    }
    
    private func loadBookProgress() {
        guard let directory = try? BookStorage.getBooksDirectory() else {
            return
        }
        
        for book in books {
            guard let folder = book.folder else {
                continue
            }
            let root = directory.appendingPathComponent(folder)
            
            let bookInfo = BookStorage.loadBookInfo(root: root)
            let bookmark = BookStorage.loadBookmark(root: root)
            
            if let total = bookInfo?.characterCount, total > 0,
               let current = bookmark?.characterCount {
                bookProgress[book.id] = Double(current) / Double(total)
            } else {
                bookProgress[book.id] = 0.0
            }
        }
    }
    
    func progress(for book: BookMetadata) -> Double {
        bookProgress[book.id] ?? 0.0
    }
    
    func deleteBook(_ book: BookMetadata) {
        do {
            if let folder = book.folder {
                let bookURL = try BookStorage.getBooksDirectory().appendingPathComponent(folder)
                try BookStorage.delete(at: bookURL)
            }
            withAnimation {
                books.removeAll { $0.id == book.id }
            }
            for i in shelves.indices {
                shelves[i].bookIds.removeAll { $0 == book.id }
            }
            saveShelves()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func importBook(result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try processImport(sourceURL: url)
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    private func determineSyncDirection(local: Bookmark?, ttuProgress: TtuProgress?) -> SyncDirection {
        guard let local = local, let lastModified = local.lastModified else {
            if ttuProgress != nil {
                return .importFromTtu
            } else {
                return .synced
            }
        }
        
        guard let ttuProgress else {
            return .exportToTtu
        }
        
        if lastModified > ttuProgress.lastBookmarkModified {
            return .exportToTtu
        } else if ttuProgress.lastBookmarkModified > lastModified {
            return .importFromTtu
        } else {
            return .synced
        }
    }
    
    func syncBook(book: BookMetadata, direction: SyncDirection? = nil) {
        guard let title = book.title,
              let bookFolder = book.folder else { return }
        
        isSyncing = true
        Task {
            defer {
                isSyncing = false
            }
            
            do {
                let root = try await GoogleDriveHandler.shared.findRootFolder()
                let books = try await GoogleDriveHandler.shared.listBooks(rootFolder: root)
                guard let driveFolder = books.first(where: { $0.name == title }) else {
                    showError(message: "Could not find \(title) on Google Drive")
                    // TODO: create book on google drive
                    return
                }
                
                let progressFileId = try await GoogleDriveHandler.shared.findProgressFileId(folderId: driveFolder.id)
                let ttuProgress: TtuProgress? = if let progressFileId {
                    try await GoogleDriveHandler.shared.getProgressFile(fileId: progressFileId)
                } else {
                    nil
                }
                
                let directory = try BookStorage.getBooksDirectory()
                let url = directory.appendingPathComponent(bookFolder)
                
                let localBookmark = BookStorage.loadBookmark(root: url)
                
                let syncDirection = direction ?? determineSyncDirection(local: localBookmark, ttuProgress: ttuProgress)
                switch syncDirection {
                case .importFromTtu:
                    guard let ttuProgress else { return }
                    importProgress(ttuProgress: ttuProgress, to: url)
                    showSuccess(message: "Synced \(title) from ッツ\n\(ttuProgress.exploredCharCount) characters")
                case .exportToTtu:
                    guard let localBookmark else { return }
                    try await exportProgress(
                        localBookmark: localBookmark,
                        ttuProgress: ttuProgress,
                        folderId: driveFolder.id,
                        fileId: progressFileId,
                        url: url
                    )
                    showSuccess(message: "Synced \(title) to ッツ\n\(localBookmark.characterCount) characters")
                case .synced:
                    showSuccess(message: "\(title) is already synced")
                }
            } catch {
                showError(message: "Sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func importProgress(ttuProgress: TtuProgress, to url: URL) {
        guard let bookInfo = BookStorage.loadBookInfo(root: url) else { return }
        
        var chapterIndex = 0
        var progress = 0.0
        
        for chapter in bookInfo.chapterInfo.values {
            if chapter.chapterCount == 0 {
                continue
            }
            
            let start = chapter.currentTotal
            let end = start + chapter.chapterCount
            
            if ttuProgress.exploredCharCount >= start && ttuProgress.exploredCharCount <= end {
                chapterIndex = chapter.spineIndex ?? 0
                progress = Double(ttuProgress.exploredCharCount - start) / Double(chapter.chapterCount)
                break
            }
        }
        
        let bookmark = Bookmark(
            chapterIndex: chapterIndex,
            progress: progress,
            characterCount: ttuProgress.exploredCharCount,
            lastModified: ttuProgress.lastBookmarkModified
        )
        
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
        loadBookProgress()
    }
    
    private func exportProgress(localBookmark: Bookmark, ttuProgress: TtuProgress?, folderId: String, fileId: String?, url: URL) async throws {
        guard let bookInfo = BookStorage.loadBookInfo(root: url),
              let lastModified = localBookmark.lastModified else { return }
        
        let unixTimestamp = Int(lastModified.timeIntervalSince1970 * 1000)
        let roundedDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp) / 1000.0)
        
        let progress = TtuProgress(
            dataId: ttuProgress?.dataId ?? 0,
            exploredCharCount: localBookmark.characterCount,
            progress: Double(localBookmark.characterCount) / Double(bookInfo.characterCount),
            lastBookmarkModified: roundedDate
        )
        
        try await GoogleDriveHandler.shared.updateProgressFile(
            folderId: folderId,
            fileId: fileId,
            progress: progress
        )
        
        let bookmark = Bookmark(
            chapterIndex: localBookmark.chapterIndex,
            progress: localBookmark.progress,
            characterCount: localBookmark.characterCount,
            lastModified: roundedDate
        )
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
    }
    
    private func processImport(sourceURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension())
        
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension())
        }
        
        let tempDocument = try BookStorage.loadEpub(tempURL)
        guard let title = tempDocument.title, !title.isEmpty else {
            return
        }
        
        let safeTitle = sanitizeFileName(title)
        
        let booksDir = try BookStorage.getBooksDirectory()
        let targetFolder = booksDir.appendingPathComponent(safeTitle)
        
        if FileManager.default.fileExists(atPath: targetFolder.path(percentEncoded: false)) {
            return
        }
        
        let destinationPath = "Books/\(safeTitle).epub"
        let localURL = try BookStorage.copyFile(from: tempURL, to: destinationPath)
        let bookFolder = localURL.deletingPathExtension()
        
        let document = try BookStorage.loadEpub(localURL)
        
        try finalizeImport(localURL: localURL, bookFolder: bookFolder, document: document)
    }
    
    private func finalizeImport(localURL: URL, bookFolder: URL, document: EPUBDocument) throws {
        do {
            var coverURL: String?
            if let coverPath = findCoverInManifest(document: document) {
                let coverSourceURL = document.contentDirectory.appendingPathComponent(coverPath)
                let coverDestination = "Books/\(bookFolder.lastPathComponent)/\(URL(fileURLWithPath: coverPath).lastPathComponent)"
                try BookStorage.copyFile(from: coverSourceURL, to: coverDestination)
                coverURL = coverDestination
            }
            
            let metadata = BookMetadata(
                title: document.title,
                cover: coverURL,
                folder: bookFolder.lastPathComponent,
                lastAccess: Date()
            )
            
            let bookinfo = BookProcessor.process(document: document)
            
            try BookStorage.save(metadata, inside: bookFolder, as: FileNames.metadata)
            try BookStorage.save(bookinfo, inside: bookFolder, as: FileNames.bookinfo)
            try BookStorage.delete(at: localURL)
            
            books = try BookStorage.loadAllBooks()
        } catch {
            try? BookStorage.delete(at: localURL)
            try? BookStorage.delete(at: bookFolder)
            throw error
        }
    }
    
    private func sanitizeFileName(_ string: String) -> String {
        return string
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.newlines).union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func findCoverInManifest(document: EPUBDocument) -> String? {
        // EPUB3
        // <item href="Images/embed0028_HD.jpg" properties="cover-image" id="embed0028_HD" media-type="image/jpeg"/>
        if let coverItem = document.manifest.items.values.first(where: { $0.property?.contains("cover-image") == true }) {
            return coverItem.path
        }
        
        // EPUB2
        // <meta name="cover" content="cover"/>
        // <item id="cover" href="cover.jpeg" media-type="image/jpeg"/>
        if let coverId = document.metadata.coverId,
           let coverItem = document.manifest.items[coverId] {
            return coverItem.path
        }
        
        // fallbacks in case the epub doesn't conform to any standards
        let imageTypes: [EPUBMediaType] = [.jpeg, .png, .gif, .svg]
        if let coverItem = document.manifest.items.values.first(where: { $0.id.lowercased().contains("cover") }),
           imageTypes.contains(coverItem.mediaType) {
            return coverItem.path
        }
        if let firstImage = document.manifest.items.values.first(where: { imageTypes.contains($0.mediaType) }) {
            return firstImage.path
        }
        
        return nil
    }
    
    private func showError(message: String) {
        errorMessage = message
        shouldShowError = true
    }
    
    private func showSuccess(message: String) {
        successMessage = message
        shouldShowSuccess = true
    }
}

struct ShelfSection {
    let shelf: BookShelf?
    var books: [BookMetadata]
}
