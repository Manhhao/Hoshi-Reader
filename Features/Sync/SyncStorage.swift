import Foundation

nonisolated struct SyncRecord: Codable, Equatable, Sendable {
    var generation: Int
    var deleted: Bool
    var files: SyncFiles = [:]
    var sources: [SyncFileType: Int64] = [:]
    var attached = false
    var pending = true
    var cleanup: Set<Int> = []
}

nonisolated struct SyncState: Codable {
    var books: [String: SyncRecord] = [:]
    var shelvesPending = false
}

@MainActor
@Observable
final class SyncStorage {
    static let shared = SyncStorage()
    static let booksChangedNotification = Notification.Name("hoshiBooksChanged")
    var state = SyncState()
    
    var onChange: (() -> Void)?
    
    private init() {
        try? reload()
        StatisticsStorage.onSave = { folder, sessions in
            try? self.handleSessionsChange(folder: folder, sessions: sessions)
        }
    }
    
    func reload() throws {
        state = BookStorage.load(SyncState.self, from: try storageURL()) ?? SyncState()
    }
    
    func save() throws {
        try JSONEncoder().encode(state).write(to: storageURL(), options: .atomic)
    }
    
    func saveChanges(booksChanged: Bool = true) throws {
        try save()
        if booksChanged {
            NotificationCenter.default.post(name: Self.booksChangedNotification, object: nil)
        }
        onChange?()
    }
    
    func markPending(_ key: String) throws {
        if !state.books[key]!.pending {
            state.books[key]!.pending = true
            try save()
        }
        onChange?()
    }
    
    func resetSyncState() throws {
        for (key, var record) in state.books {
            let archived = BookStorage.loadMetadata(root: try SyncStorage.bookDirectory(folder: key)) == nil
            record.generation = archived ? 0 : 1
            record.deleted = archived
            record.files = [:]
            record.attached = false
            record.pending = true
            state.books[key] = record
        }
        
        state.shelvesPending = true
        try saveChanges()
    }
    
    func prepareLibrary() throws {
        for root in try SyncStorage.bookDirectories() {
            _ = StatisticsStorage.load(root: root)
            try prepareBook(root: root)
        }
        
        _ = BookStorage.loadShelfList()
        try save()
    }
    
    func prepareBook(root: URL) throws {
        let key = root.lastPathComponent.precomposedStringWithCanonicalMapping
        if state.books[key] != nil {
            return
        }
        
        let archived = root.deletingLastPathComponent().lastPathComponent == "statistics_archive"
        var record = SyncRecord(generation: archived ? 0 : 1, deleted: archived)
        for fileType in SyncFileType.allCases {
            if try sourceURL(key: key, fileType: fileType) != nil {
                record.sources[fileType] = Date.now.milliseconds
            }
        }
        state.books[key] = record
    }
    
    func loadBook(key: String) throws -> SyncBook? {
        guard let record = state.books[key] else { return nil }
        let root = try SyncStorage.resolveBookDirectory(folder: key)
        guard let metadata = BookStorage.loadMetadata(root: root) else { return nil }
        var book = SyncBook(
            generation: record.generation,
            deleted: record.deleted,
            metadata: Timestamped(modified: metadata.modified ?? 0, value: SyncMetadata(title: metadata.displayTitle, author: metadata.author)),
            characterCount: max(metadata.characterCount ?? 0, BookStorage.loadBookInfo(root: root)?.characterCount ?? 0),
            files: record.files
        )
        book.sessions = StatisticsStorage.load(root: root)
        
        if !record.deleted {
            if let bookmark = BookStorage.loadBookmark(root: root) {
                book.bookmark = Timestamped(
                    modified: (bookmark.lastModified ?? .distantPast).milliseconds,
                    value: SyncBookmark(characterCount: bookmark.characterCount)
                )
            }
            if let playback = BookStorage.loadSasayakiPlayback(root: root) {
                book.audiobook = Timestamped(
                    modified: playback.modified ?? 0,
                    value: SyncPlayback(lastPosition: playback.lastPosition, delay: playback.delay, rate: Double(playback.rate))
                )
            }
            book.highlights = BookStorage.loadHighlightRecords(root: root).mapValues { $0.replacing($0.value.map(SyncHighlight.init)) }
            book.shelves = metadata.shelves ?? [:]
        }
        return book
    }
    
    func applyBook(key: String, book: SyncBook) throws {
        let oldRecord = state.books[key]
        let bookURL = try SyncStorage.bookDirectory(folder: key)
        let existing = BookStorage.loadMetadata(root: bookURL)
        let folder = existing?.folder ?? bookURL.lastPathComponent
        var booksChanged = existing != nil && (book.deleted || oldRecord?.generation != book.generation)
        if book.deleted, let existing {
            try StatisticsStorage.archive(existing)
            try BookStorage.delete(at: bookURL)
        }
        
        let root = try SyncStorage.bookDirectory(folder: folder, archived: book.deleted)
        let oldMetadata = BookStorage.loadMetadata(root: root)
        var metadata = BookMetadata(
            id: oldMetadata?.id ?? UUID(),
            title: oldMetadata?.title ?? book.metadata.value.title,
            author: book.metadata.value.author,
            epub: oldMetadata?.epub,
            cover: oldMetadata?.cover,
            folder: oldMetadata?.folder ?? folder,
            lastAccess: oldMetadata?.lastAccess ?? .distantPast
        )
        metadata.renamedTitle = metadata.title == book.metadata.value.title ? nil : book.metadata.value.title
        metadata.modified = book.metadata.modified
        metadata.characterCount = book.characterCount
        if !book.deleted {
            metadata.shelves = book.shelves
            if let bookmark = book.bookmark {
                metadata.lastAccess = max(metadata.lastAccess, Date(milliseconds: bookmark.modified))
            }
        }
        
        if metadata != oldMetadata {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try BookStorage.saveMetadata(metadata, inside: root)
            booksChanged = true
        }
        
        var record =
            state.books[key]
            ?? SyncRecord(generation: book.generation, deleted: book.deleted)
        
        record.generation = book.generation
        record.deleted = book.deleted
        record.files = book.files
        record.attached = true
        let oldSessions = StatisticsStorage.load(root: root)
        if book.sessions != oldSessions {
            try BookStorage.save(book.sessions, inside: root, as: FileNames.statistics)
            booksChanged = true
        }
        if !book.deleted {
            try StatisticsStorage.restore(folder: folder)
            
            var bookmark = BookStorage.loadBookmark(root: root)
            let bookmarkChanged = book.bookmark.map { bookmark?.characterCount != $0.value.characterCount } ?? false
            if let change = book.bookmark {
                let modified = (bookmark?.lastModified ?? .distantPast).milliseconds
                if bookmarkChanged {
                    booksChanged = true
                    let position = BookStorage.loadBookInfo(root: root)?.resolveCharacterPosition(change.value.characterCount)
                    bookmark = Bookmark(
                        chapterIndex: position?.spineIndex ?? 0,
                        progress: position?.progress ?? 0,
                        characterCount: change.value.characterCount
                    )
                }
                if bookmarkChanged || modified != change.modified {
                    bookmark!.lastModified = Date(milliseconds: change.modified)
                    try BookStorage.save(bookmark!, inside: root, as: FileNames.bookmark)
                }
            }
            
            if BookStorage.loadHighlightRecords(root: root).mapValues({ $0.replacing($0.value.map(SyncHighlight.init)) }) != book.highlights {
                let highlights = Dictionary(uniqueKeysWithValues: book.highlights.map { id, record in
                    (id, record.replacing(record.value?.highlight(id: id)))
                })
                try BookStorage.save(highlights, inside: root, as: FileNames.highlights)
            }
            
            if let change = book.audiobook {
                var playback = BookStorage.loadSasayakiPlayback(root: root) ?? SasayakiPlaybackData(lastPosition: 0)
                let syncedPlayback = change.value
                if playback.modified != change.modified || playback.lastPosition != syncedPlayback.lastPosition || playback.delay != syncedPlayback.delay || Double(playback.rate) != syncedPlayback.rate {
                    playback.lastPosition = syncedPlayback.lastPosition
                    playback.delay = syncedPlayback.delay
                    playback.rate = Float(syncedPlayback.rate)
                    playback.modified = change.modified
                    try BookStorage.save(playback, inside: root, as: FileNames.sasayakiPlayback)
                }
            }
            if let reader = ReaderIntentBridge.shared.reader, reader.book.folder == key, !reader.bookDeleted {
                reader.applySyncedState(book, bookmarkChanged: bookmarkChanged)
            }
        } else {
            for fileType in [SyncFileType.epub, .sasayaki] {
                record.sources.removeValue(forKey: fileType)
            }
        }
        
        state.books[key] = record
        try clearUnusedCover(key: key, sessions: book.sessions)
        if state.books[key] != oldRecord {
            try save()
        }
        if booksChanged {
            NotificationCenter.default.post(name: Self.booksChangedNotification, object: nil)
        }
    }
    
    func handleBookImport(book: BookMetadata, root: URL) throws {
        let archiveURL = try SyncStorage.bookDirectory(folder: book.folder, archived: true)
        if BookStorage.loadMetadata(root: archiveURL) != nil {
            try prepareBook(root: archiveURL)
        }
        if let oldRecord = state.books[book.folder], oldRecord.deleted {
            state.books[book.folder] = SyncRecord(
                generation: max(1, oldRecord.generation + 1),
                deleted: false,
                attached: oldRecord.attached || oldRecord.generation > 0,
                cleanup: oldRecord.cleanup.union([oldRecord.generation])
            )
        }
        
        var metadata = book
        metadata.modified = Date.now.milliseconds
        try BookStorage.saveMetadata(metadata, inside: root)
        try StatisticsStorage.restore(folder: book.folder)
        try prepareBook(root: root)
        
        for fileType in SyncFileType.allCases {
            if try sourceURL(key: book.folder, fileType: fileType) != nil {
                markFileChanged(key: book.folder, fileType: fileType)
            }
        }
        
        state.books[book.folder]!.pending = true
        try saveChanges()
    }
    
    func deleteLocalBook(key: String) throws {
        let root = try SyncStorage.bookDirectory(folder: key)
        var metadata = BookStorage.loadMetadata(root: root)!
        try BookStorage.delete(at: root.appendingPathComponent(metadata.epub!))
        metadata.epub = nil
        try BookStorage.saveMetadata(metadata, inside: root)
        
        state.books[key]!.sources.removeValue(forKey: .epub)
        try save()
        NotificationCenter.default.post(name: Self.booksChangedNotification, object: nil)
    }
    
    func deleteBook(key: String) throws {
        let root = try SyncStorage.bookDirectory(folder: key)
        try StatisticsStorage.archive(BookStorage.loadMetadata(root: root)!)
        
        var record = state.books[key]!
        record.deleted = true
        record.pending = true
        record.cleanup.insert(record.generation)
        record.files[.epub] = nil
        record.files[.sasayaki] = nil
        record.sources[.epub] = nil
        record.sources[.sasayaki] = nil
        state.books[key] = record
        
        try saveChanges()
        try BookStorage.delete(at: root)
        
        try clearUnusedCover(key: key)
        try saveChanges()
    }
    
    func handleBookChange(folder: String) throws {
        if state.books[folder] == nil {
            try prepareBook(root: SyncStorage.resolveBookDirectory(folder: folder))
            try save()
        }
        try markPending(folder)
    }
    
    func markFileChanged(key: String, fileType: SyncFileType) {
        state.books[key]!.sources[fileType] = Date.now.milliseconds
        state.books[key]!.pending = true
    }
    
    func saveSasayakiMatch(_ match: SasayakiMatchData, folder: String, root: URL) throws {
        try prepareBook(root: root)
        try BookStorage.save(match, inside: root, as: FileNames.sasayakiMatch)
        markFileChanged(key: folder, fileType: .sasayaki)
        try saveChanges(booksChanged: false)
    }
    
    func handleShelvesChange() throws {
        state.shelvesPending = true
        try saveChanges()
    }
    
    func applyShelves(_ shelves: [String: Timestamped<Int?>]) throws {
        if shelves != BookStorage.loadShelfList() {
            try BookStorage.saveShelfList(shelves)
            NotificationCenter.default.post(name: Self.booksChangedNotification, object: nil)
        }
    }
    
    func sourceURL(key: String, fileType: SyncFileType) throws -> URL? {
        let root = try SyncStorage.resolveBookDirectory(folder: key)
        let metadata = BookStorage.loadMetadata(root: root)
        switch fileType {
        case .epub:
            return metadata?.epub.map { root.appendingPathComponent($0) }
        case .cover:
            return metadata?.coverURL
        case .sasayaki:
            let url = root.appendingPathComponent(FileNames.sasayakiMatch)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
    
    func clearUnusedCover(key: String, sessions: [String: Timestamped<ReadingSession?>]? = nil) throws {
        var record = state.books[key]!
        if !record.deleted {
            return
        }
        
        let sessions = sessions ?? StatisticsStorage.load(folder: key)
        if sessions.values.allSatisfy({ $0.value == nil }) {
            let root = try Self.resolveBookDirectory(folder: key)
            if var metadata = BookStorage.loadMetadata(root: root), let cover = metadata.coverURL {
                try BookStorage.delete(at: cover)
                metadata.cover = nil
                try BookStorage.saveMetadata(metadata, inside: root)
            }
            let published = record.files[.cover]
            if published?.value == nil && (record.sources[.cover] ?? .min) <= (published?.modified ?? .min) {
                return
            }
            
            let modified = Date.now.milliseconds
            record.files[.cover] = Timestamped(modified: modified, value: nil)
            record.sources[.cover] = modified
            record.cleanup.insert(record.generation)
            record.pending = true
            state.books[key] = record
        }
    }
    
    func removeBookFiles(key: String) throws {
        let root = try SyncStorage.resolveBookDirectory(folder: key)
        if var metadata = BookStorage.loadMetadata(root: root) {
            if let epub = metadata.epub {
                try BookStorage.delete(at: root.appendingPathComponent(epub))
            }
            if let cover = metadata.coverURL {
                try BookStorage.delete(at: cover)
            }
            
            try BookStorage.delete(at: root.appendingPathComponent(FileNames.bookinfo))
            try BookStorage.delete(at: root.appendingPathComponent(FileNames.sasayakiMatch))
            try BookStorage.delete(at: root.appendingPathComponent(FileNames.sasayakiTranscript))
            try BookStorage.delete(at: root.appendingPathComponent(FileNames.bookmark))
            try BookStorage.delete(at: root.appendingPathComponent(FileNames.highlights))
            
            if var playback = BookStorage.loadSasayakiPlayback(root: root) {
                playback.lastPosition = 0
                playback.delay = 0
                playback.rate = 1
                playback.modified = nil
                try BookStorage.save(playback, inside: root, as: FileNames.sasayakiPlayback)
            }
            
            metadata.epub = nil
            metadata.cover = nil
            try BookStorage.saveMetadata(metadata, inside: root)
        }
        
        state.books[key]!.sources = [:]
    }
    
    static func bookDirectories() throws -> [URL] {
        let booksDirectory = try BookStorage.getBooksDirectory()
        return try [booksDirectory, booksDirectory.appendingPathComponent("statistics_archive")].flatMap { directory in
            guard FileManager.default.fileExists(atPath: directory.path) else { return [URL]() }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { BookStorage.loadMetadata(root: $0) != nil }
        }
    }
    
    static func bookDirectory(folder: String, archived: Bool = false) throws -> URL {
        try BookStorage.getBooksDirectory().appendingPathComponent(
            (archived ? "statistics_archive/" : "") + folder
        )
    }
    
    static func resolveBookDirectory(folder: String) throws -> URL {
        let bookURL = try bookDirectory(folder: folder)
        return BookStorage.loadMetadata(root: bookURL) != nil ? bookURL : try bookDirectory(folder: folder, archived: true)
    }
    
    private func handleSessionsChange(folder: String, sessions: [String: Timestamped<ReadingSession?>]) throws {
        if state.books[folder] == nil {
            try prepareBook(root: Self.resolveBookDirectory(folder: folder))
            try save()
        }
        if state.books[folder]!.deleted {
            try clearUnusedCover(key: folder, sessions: sessions)
            state.books[folder]!.pending = true
            try saveChanges(booksChanged: false)
        } else {
            try markPending(folder)
        }
    }
    
    private func storageURL() throws -> URL {
        let booksDirectory = try BookStorage.getBooksDirectory()
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        return booksDirectory.appendingPathComponent(".sync.json")
    }
}
