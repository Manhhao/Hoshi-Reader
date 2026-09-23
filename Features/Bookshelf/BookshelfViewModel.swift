//
//  BookshelfViewModel.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import SwiftUI
import EPUBKit

@Observable
@MainActor
class BookshelfViewModel {
    var books: [BookMetadata] = []
    var shelves: [BookShelf] = []
    var googleDriveBooks: [BookMetadata] = []
    var isImporting: Bool = false
    var shouldShowError: Bool = false
    var errorMessage: String = ""
    var shouldShowSuccess: Bool = false
    var successMessage: String = ""
    var isSyncing: Bool = false
    var isDownloading: Bool = false
    var importBooksProgress: String?
    var downloadingBooks: [UUID: Double] = [:]
    var sasayakiProgress: SasayakiTranscriptionProgress?
    var sasayakiError: String?
    
    private var bookProgress: [UUID: Double] = [:]
    private var googleDriveSyncFiles: [UUID: TtuSyncFiles] = [:]
    private var sasayakiTask: Task<Void, Never>?
    private var sasayakiBookId: UUID?
    
    func loadBooks() {
        do {
            _ = BookStorage.loadShelfList()
            books = try BookStorage.loadAllBooks()
            loadBookProgress()
            loadShelves()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func loadShelves() {
        shelves = BookStorage.loadShelfList()
            .compactMap { name, shelf in shelf.value.map { (name: name, position: $0) } }
            .sorted { ($0.position, $0.name) < ($1.position, $1.name) }
            .map { shelf in BookShelf(name: shelf.name, bookIds: books.filter { $0.shelves?[shelf.name]?.value == true }.map(\.id)) }
    }
    
    func updateShelfList(_ update: (inout [String: Timestamped<Int?>]) -> Void) {
        var list = BookStorage.loadShelfList()
        update(&list)
        try? BookStorage.saveShelfList(list)
        try? SyncStorage.shared.handleShelvesChange()
        loadShelves()
    }
    
    func updateMemberships(_ memberships: [String: Bool], bookId: UUID) {
        let index = books.firstIndex { $0.id == bookId }!
        let root = try! BookStorage.getBooksDirectory().appendingPathComponent(books[index].folder)
        var metadata = BookStorage.loadMetadata(root: root)!
        var shelves = metadata.shelves ?? [:]
        for (name, member) in memberships where (shelves[name]?.value ?? false) != member {
            shelves[name] = Timestamped(modified: Date.now.milliseconds, value: member)
        }
        if shelves != metadata.shelves ?? [:] {
            metadata.shelves = shelves
            try? BookStorage.saveMetadata(metadata, inside: root)
            try? SyncStorage.shared.handleBookChange(folder: metadata.folder)
        }
        books[index] = metadata
    }
    
    func createShelf(name: String) {
        if !shelves.contains(where: { $0.name == name }) {
            updateShelfList { list in
                list[name.precomposedStringWithCanonicalMapping] = Timestamped(
                    modified: Date.now.milliseconds,
                    value: (list.values.compactMap(\.value).max() ?? -1) + 1
                )
            }
        }
    }
    
    func deleteShelf(name: String) {
        for id in shelves.first(where: { $0.name == name })!.bookIds {
            updateMemberships([name: false], bookId: id)
        }
        updateShelfList { $0[name] = Timestamped(modified: Date.now.milliseconds, value: nil) }
    }
    
    func moveShelves(from source: IndexSet, to destination: Int) {
        shelves.move(fromOffsets: source, toOffset: destination)
        updateShelfList { list in
            for (index, shelf) in shelves.enumerated() {
                list[shelf.name] = Timestamped(modified: Date.now.milliseconds, value: index)
            }
        }
    }
    
    func moveBook(_ id: UUID, to name: String?) {
        updateMemberships(Dictionary(uniqueKeysWithValues: shelves.map { ($0.name, $0.name == name) }), bookId: id)
        loadShelves()
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
    
    func shelfSections(sortedBy: SortOption, showReading: Bool = false) -> [ShelfSection] {
        var sections: [ShelfSection] = []
        
        if showReading {
            let reading = books.filter {
                let p = progress(for: $0)
                return p > 0 && p < 0.999
            }
            if !reading.isEmpty {
                sections.append(ShelfSection(
                    shelf: BookShelf(name: "Reading", bookIds: []),
                    books: sortBooks(reading, by: sortedBy),
                    isReading: true
                ))
            }
        }
        
        for shelf in shelves {
            let shelvedBooks = books.filter { shelf.bookIds.contains($0.id) }
            sections.append(ShelfSection(shelf: shelf, books: sortBooks(shelvedBooks, by: sortedBy)))
        }
        
        if !googleDriveBooks.isEmpty {
            sections.append(ShelfSection(
                shelf: BookShelf(name: "Google Drive", bookIds: []),
                books: sortBooks(googleDriveBooks, by: sortedBy),
                isGoogleDrive: true
            ))
        }
        
        let shelvedIds = Set(shelves.flatMap { $0.bookIds })
        let unshelved = books.filter { !shelvedIds.contains($0.id) }
        sections.append(ShelfSection(shelf: nil, books: sortBooks(unshelved, by: sortedBy)))
        
        return sections
    }
    
    func sortBooks(_ books: [BookMetadata], by option: SortOption) -> [BookMetadata] {
        switch option {
        case .recent:
            return books.sorted { $0.lastAccess > $1.lastAccess }
        case .title:
            return books.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
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
            let root = directory.appendingPathComponent(book.folder)
            
            let bookInfo = BookStorage.loadBookInfo(root: root)
            let bookmark = BookStorage.loadBookmark(root: root)
            
            if let total = bookInfo?.characterCount ?? book.characterCount, total > 0,
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
    
    func deleteLocalBook(_ book: BookMetadata) {
        do {
            try SyncStorage.shared.deleteLocalBook(key: book.folder)
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func deleteBook(_ book: BookMetadata) {
        if sasayakiBookId == book.id {
            sasayakiTask?.cancel()
        }
        do {
            let bookURL = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
            try SyncStorage.shared.prepareBook(root: bookURL)
            try SyncStorage.shared.deleteBook(key: book.folder)
            books.removeAll { $0.id == book.id }
            loadShelves()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func renameBook(_ book: BookMetadata, title: String) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else {
            return
        }
        
        let bookURL = try! BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        var metadata = BookStorage.loadMetadata(root: bookURL)!
        metadata.renamedTitle = title.isEmpty ? nil : title
        metadata.modified = Date.now.milliseconds
        try? BookStorage.saveMetadata(metadata, inside: bookURL)
        books[index] = metadata
        try? SyncStorage.shared.handleBookChange(folder: book.folder)
    }
    
    func importBook(result: Result<URL, Error>) {
        do {
            try importBook(from: try result.get())
            loadBooks()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func importBooks(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if urls.isEmpty {
                return
            }
            
            if urls.count == 1 {
                importBook(result: .success(urls[0]))
                return
            }
            
            importBooksProgress = "Importing 1 / \(urls.count)..."
            Task {
                defer { importBooksProgress = nil }
                await Task.yield()
                
                var failed: [String] = []
                for (index, url) in urls.enumerated() {
                    autoreleasepool {
                        do {
                            try importBook(from: url)
                        } catch {
                            failed.append(url.lastPathComponent)
                        }
                    }
                    let next = index + 1
                    if next < urls.count {
                        importBooksProgress = "Importing \(next + 1) / \(urls.count)..."
                        await Task.yield()
                    }
                }
                loadBooks()
                
                if !failed.isEmpty {
                    showError(message: "Failed to import:\n\(failed.joined(separator: "\n"))")
                }
            }
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func importRemoteBook(from url: URL) {
        isDownloading = true
        Task {
            defer {
                isDownloading = false
            }
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                try processImport(sourceURL: tempURL)
                loadBooks()
            } catch {
                showError(message: "Download failed: \(error.localizedDescription)")
            }
        }
    }
    
    func syncBook(book: BookMetadata, direction: TtuSyncDirection? = nil, syncBookData: Bool, syncStats: Bool, statsSyncMode: StatisticsSyncMode, syncAudioBook: Bool) {
        isSyncing = true
        Task {
            defer { isSyncing = false }
            if UserConfig.shared.syncProvider == .ttu {
                do {
                    let result = try await TtuSyncManager.shared.syncBook(
                        book: book,
                        direction: direction,
                        syncBookData: syncBookData,
                        syncStats: syncStats,
                        statsSyncMode: statsSyncMode,
                        syncAudioBook: syncAudioBook
                    )
                    handleSyncResult(result)
                } catch {
                    showError(message: String(localized: "Sync failed: \(error.localizedDescription)"))
                }
            } else {
                await GoogleDriveSyncManager.shared.sync(book: book)
            }
        }
    }
    
    func loadGoogleDriveBooks(suppressOfflineErrors: Bool = false) async {
        if UserConfig.shared.syncProvider == .gdrive {
            googleDriveBooks = []
            await GoogleDriveSyncManager.shared.sync()
            return
        }
        
        do {
            let root = try await TtuDriveHandler.shared.findRootFolder()
            let folders = try await TtuDriveHandler.shared.listBooks(rootFolder: root)
            let localTitles = Set(books.map { TtuDriveHandler.sanitizeTtuFilename($0.title) })
            let remoteFolders = folders.filter { !localTitles.contains($0.name) }
            let allFiles = try await TtuDriveHandler.shared.listSyncFiles(folderIds: remoteFolders.map(\.id))
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("gdrive-covers")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            
            let results = await withTaskGroup(of: (BookMetadata, TtuSyncFiles)?.self) { group in
                for folder in remoteFolders {
                    guard let files = allFiles[folder.id], files.bookData != nil else { continue }
                    group.addTask {
                        var cover: String?
                        if let thumbnailURL = files.cover?.thumbnailLink?
                            .replacingOccurrences(of: "=s\\d+$", with: "=s768", options: .regularExpression),
                           let url = URL(string: thumbnailURL) {
                            let cached = cacheDir.appendingPathComponent(folder.id)
                            if !FileManager.default.fileExists(atPath: cached.path(percentEncoded: false)) {
                                if let (data, _) = try? await URLSession.shared.data(from: url) {
                                    try? data.write(to: cached)
                                }
                            }
                            if FileManager.default.fileExists(atPath: cached.path(percentEncoded: false)) {
                                cover = cached.path(percentEncoded: false)
                            }
                        }
                        let title = await TtuDriveHandler.desanitizeTtuFilename(folder.name)
                        let book = BookMetadata(title: title, cover: cover, folder: folder.id, lastAccess: files.lastAccess ?? .distantPast)
                        return (book, files)
                    }
                }
                var collected: [(BookMetadata, TtuSyncFiles)] = []
                for await result in group {
                    if let result {
                        collected.append(result)
                    }
                }
                return collected
            }
            
            var remoteSyncFiles: [UUID: TtuSyncFiles] = [:]
            for (book, files) in results {
                remoteSyncFiles[book.id] = files
                if let name = files.progress?.name.dropLast(5),
                   let value = name.split(separator: "_").last.flatMap({ Double($0) }) {
                    bookProgress[book.id] = value
                }
            }
            
            googleDriveBooks = results.map(\.0).sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            googleDriveSyncFiles = remoteSyncFiles
        } catch let error as URLError where error.code == .cancelled {
        } catch let error as URLError where suppressOfflineErrors && [.notConnectedToInternet, .timedOut, .networkConnectionLost].contains(error.code) {
        } catch {
            showError(message: "Failed to fetch books from Google Drive: \(error.localizedDescription)")
        }
    }
    
    func downloadBook(_ book: BookMetadata, onOpen: @escaping (BookMetadata) -> Void) {
        guard downloadingBooks[book.id] == nil else {
            return
        }
        
        downloadingBooks[book.id] = 0
        let sync = GoogleDriveSyncManager.shared
        sync.downloadTask?.cancel()
        sync.downloadTask = Task {
            defer {
                downloadingBooks.removeValue(forKey: book.id)
                if !Task.isCancelled {
                    sync.downloadTask = nil
                    sync.startFileSync()
                }
            }
            
            do {
                let downloaded = try await sync.downloadBook(book) { progress in
                    self.downloadingBooks[book.id] = progress
                }
                try Task.checkCancellation()
                loadBooks()
                onOpen(downloaded)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    showError(message: error.localizedDescription)
                }
            }
        }
    }
    
    func importGoogleDriveBook(_ book: BookMetadata, syncStats: Bool, syncAudioBook: Bool) {
        guard let syncFiles = googleDriveSyncFiles[book.id],
              downloadingBooks[book.id] == nil else {
            return
        }
        downloadingBooks[book.id] = 0
        Task {
            defer {
                downloadingBooks.removeValue(forKey: book.id)
            }
            do {
                _ = try await TtuSyncManager.shared.importGoogleDriveBook(
                    syncFiles: syncFiles,
                    syncStats: syncStats,
                    syncAudioBook: syncAudioBook
                ) { progress in
                    self.downloadingBooks[book.id] = progress
                }
                googleDriveBooks.removeAll { $0.id == book.id }
                googleDriveSyncFiles.removeValue(forKey: book.id)
                loadBooks()
            } catch {
                showError(message: "Failed to import book from Google Drive: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteGoogleDriveBook(_ book: BookMetadata) {
        guard downloadingBooks[book.id] == nil else { return }
        Task {
            do {
                guard UserConfig.shared.syncProvider == .ttu, GoogleDriveAuth.shared.isAuthenticated(for: .ttu) else {
                    throw GoogleDriveAuthError.notAuthenticated
                }
                
                try await GoogleDriveClient.shared.trashFile(fileId: book.folder)
                googleDriveBooks.removeAll { $0.id == book.id }
                googleDriveSyncFiles.removeValue(forKey: book.id)
                bookProgress.removeValue(forKey: book.id)
            } catch {
                showError(message: "Failed to delete book from Google Drive: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleSyncResult(_ result: TtuSyncResult) {
        switch result {
        case .synced(let title):
            showSuccess(message: "\(title) is already synced")
        case .imported(let title, let characterCount):
            loadBookProgress()
            showSuccess(message: "Synced \(title) from ッツ\n\(characterCount) characters")
        case .exported(let title, let characterCount):
            showSuccess(message: "Synced \(title) to ッツ\n\(characterCount) characters")
        case .skipped:
            break
        }
    }
    
    func markRead(book: BookMetadata) {
        let directory = try! BookStorage.getBooksDirectory()
        let url = directory.appendingPathComponent(book.folder)
        guard let bookInfo = BookStorage.loadBookInfo(root: url) else { return }
        
        let bookmark = Bookmark(
            chapterIndex: bookInfo.chapterInfo.values.compactMap(\.spineIndex).max() ?? 0,
            progress: 1,
            characterCount: bookInfo.characterCount,
            lastModified: Date()
        )
        
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
        try? SyncStorage.shared.handleBookChange(folder: book.folder)
        loadBookProgress()
    }
    
    func clearInbox() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let inboxDirectory = documentsDirectory.appendingPathComponent("Inbox")
        guard FileManager.default.fileExists(atPath: inboxDirectory.path(percentEncoded: false)),
              let inboxContents = try? FileManager.default.contentsOfDirectory(
                at: inboxDirectory,
                includingPropertiesForKeys: nil
              ) else {
            return
        }
        
        for item in inboxContents {
            try? FileManager.default.removeItem(at: item)
        }
    }
    
    func runSasayakiMatch(book: BookMetadata, srtURL: URL) throws -> SasayakiMatchData {
        let rootURL = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        let accessing = srtURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                srtURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let srtData = try Data(contentsOf: srtURL)
        let cues = SasayakiParser.parseCues(from: srtData)
        let result = try SasayakiMatcher.match(rootURL: rootURL, cues: cues)
        try SyncStorage.shared.saveSasayakiMatch(result, folder: book.folder, root: rootURL)
        
        return result
    }
    
    func sasayakiIsRunning(_ book: BookMetadata) -> Bool {
        sasayakiTask != nil && sasayakiBookId == book.id
    }
    
    func pauseSasayakiTranscription() {
        sasayakiTask?.cancel()
    }
    
    @available(iOS 26.0, *)
    func startSasayakiTranscription(book: BookMetadata, audioURL: URL) {
        guard sasayakiTask == nil else {
            return
        }
        sasayakiBookId = book.id
        sasayakiError = nil
        sasayakiTask = Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                sasayakiTask = nil
                sasayakiProgress = nil
                sasayakiBookId = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                try await runSasayakiTranscription(book: book, audioURL: audioURL)
            } catch is CancellationError {
            } catch {
                sasayakiError = error.localizedDescription
            }
        }
    }
    
    @available(iOS 26.0, *)
    private func runSasayakiTranscription(book: BookMetadata, audioURL: URL) async throws {
        let rootURL = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        let accessing = audioURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                audioURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let audio = try AVAudioFile(forReading: audioURL)
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        
        var playback = BookStorage.loadSasayakiPlayback(root: rootURL) ?? SasayakiPlaybackData(lastPosition: 0)
        playback.audioBookmark = try? audioURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try? BookStorage.save(playback, inside: rootURL, as: FileNames.sasayakiPlayback)
        
        var transcript = SasayakiTranscript(through: 0, duration: duration, tokens: [])
        if let saved = BookStorage.loadSasayakiTranscript(root: rootURL), saved.duration == duration {
            transcript = saved
        }
        
        sasayakiProgress = .transcribing(through: transcript.through, duration: duration, remaining: nil)
        var lastPersist = Date()
        let startPosition = transcript.through
        var firstResultAt: Date?
        do {
            if !transcript.isComplete {
                try await SasayakiTranscriber.transcribe(file: audio, from: transcript.through) { fraction in
                    self.sasayakiProgress = .downloading(fraction)
                } onTokens: { tokens, through in
                    transcript.tokens.append(contentsOf: tokens)
                    transcript.through = through
                    let startedAt = firstResultAt ?? Date()
                    firstResultAt = startedAt
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let processed = through - startPosition
                    let remaining = elapsed > 3 && processed > 30
                    ? (duration - through) * elapsed / processed
                    : nil
                    self.sasayakiProgress = .transcribing(through: through, duration: duration, remaining: remaining)
                    if Date().timeIntervalSince(lastPersist) > 15 {
                        lastPersist = Date()
                        try? BookStorage.save(transcript, inside: rootURL, as: FileNames.sasayakiTranscript)
                    }
                }
            }
        } catch is CancellationError {
        }
        
        guard !transcript.tokens.isEmpty else {
            return
        }
        try? BookStorage.save(transcript, inside: rootURL, as: FileNames.sasayakiTranscript)
        
        sasayakiProgress = .aligning
        let tokens = transcript.tokens
        let source = try SasayakiSource.build(rootURL: rootURL)
        let result = await Task.detached(priority: .userInitiated) {
            SasayakiAligner.align(source: source, tokens: tokens)
        }.value
        
        try SyncStorage.shared.saveSasayakiMatch(result, folder: book.folder, root: rootURL)
    }
    
    func clearSasayakiTranscript(book: BookMetadata) throws {
        let rootURL = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(FileNames.sasayakiTranscript))
    }
    
    func loadSasayakiAudioURL(book: BookMetadata) -> URL? {
        guard let books = try? BookStorage.getBooksDirectory() else {
            return nil
        }
        
        let root = books.appendingPathComponent(book.folder)
        guard var playback = BookStorage.loadSasayakiPlayback(root: root),
              let bookmark = playback.audioBookmark else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        if isStale {
            playback.audioBookmark = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try? BookStorage.save(playback, inside: root, as: FileNames.sasayakiPlayback)
        }
        return url
    }
    
    private func importBook(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try processImport(sourceURL: url)
    }
    
    private func processImport(sourceURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
        
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension())
        }
        
        let tempDocument = try BookStorage.loadEpub(tempURL)
        let title: String = {
            if let t = tempDocument.title, !t.isEmpty {
                return t
            }
            return sourceURL.deletingPathExtension().lastPathComponent
        }()
        
        let safeTitle = BookStorage.sanitizeFileName(title)
        
        let booksDir = try BookStorage.getBooksDirectory()
        let bookFolder = booksDir.appendingPathComponent(safeTitle)
        
        if let existing = BookStorage.loadMetadata(root: bookFolder), existing.epub != nil {
            return
        }
        
        try FileManager.default.createDirectory(at: bookFolder, withIntermediateDirectories: true)
        
        let localURL = bookFolder.appendingPathComponent(sourceURL.lastPathComponent)
        try BookStorage.copyFile(from: tempURL, to: "Books/\(safeTitle)/\(localURL.lastPathComponent)")
        
        let document = try BookStorage.loadEpub(localURL)
        try finalizeImport(localURL: localURL, bookFolder: bookFolder, document: document, title: title)
        let metadata = BookStorage.loadMetadata(root: bookFolder)!
        try SyncStorage.shared.handleBookImport(book: metadata, root: bookFolder)
    }
    
    private func finalizeImport(localURL: URL, bookFolder: URL, document: EPUBDocument, title: String) throws {
        do {
            var coverURL: String?
            if let coverPath = findCoverInManifest(document: document) {
                let coverSourceURL = document.contentDirectory.appendingPathComponent(coverPath)
                let coverDestination = "Books/\(bookFolder.lastPathComponent)/\(URL(fileURLWithPath: coverPath).lastPathComponent)"
                try BookStorage.copyFile(from: coverSourceURL, to: coverDestination)
                coverURL = coverDestination
            }
            
            let existing = BookStorage.loadMetadata(root: bookFolder)
            var metadata = BookMetadata(
                id: existing?.id ?? UUID(),
                title: title,
                author: document.author?.trimmingCharacters(in: .whitespacesAndNewlines),
                epub: localURL.lastPathComponent,
                cover: coverURL,
                folder: bookFolder.lastPathComponent,
                lastAccess: Date()
            )
            
            metadata.renamedTitle = existing?.renamedTitle
            metadata.shelves = existing?.shelves
            let bookinfo = BookProcessor.process(document: document)
            
            try BookStorage.save(metadata, inside: bookFolder, as: FileNames.metadata)
            try BookStorage.save(bookinfo, inside: bookFolder, as: FileNames.bookinfo)
            
            if let bookmark = BookStorage.loadBookmark(root: bookFolder) {
                let position = bookinfo.resolveCharacterPosition(bookmark.characterCount)
                let resolved = Bookmark(
                    chapterIndex: position?.spineIndex ?? 0,
                    progress: position?.progress ?? 0,
                    characterCount: bookmark.characterCount,
                    lastModified: bookmark.lastModified
                )
                try BookStorage.save(resolved, inside: bookFolder, as: FileNames.bookmark)
            }
        } catch {
            try? BookStorage.delete(at: localURL)
            try? BookStorage.delete(at: bookFolder)
            throw error
        }
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
        
        // fallback in case the epub doesn't conform to any standards
        let imageTypes: [EPUBMediaType] = [.jpeg, .png, .gif, .svg]
        if let coverItem = document.manifest.items.values.first(where: { $0.id.lowercased().contains("cover") }),
           imageTypes.contains(coverItem.mediaType) {
            return coverItem.path
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

struct ShelfSection: Identifiable {
    let shelf: BookShelf?
    var books: [BookMetadata]
    var isReading: Bool = false
    var isGoogleDrive: Bool = false
    
    var id: String {
        if isReading {
            return "__reading__"
        }
        if isGoogleDrive {
            return "__gdrive__"
        }
        return shelf.map { "shelf:\($0.name)" } ?? "unshelved"
    }
}
