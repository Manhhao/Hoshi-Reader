import Foundation

private final class Listing {
    var folders: [String: [Int: String]] = [:]
    var files: [String: [String: GoogleDriveFile]] = [:]
}

extension GoogleDriveSyncManager {
    func runFileSync() async throws {
        let keys = store.state.books.keys.sorted()
        beginTransfers(keys)
        let listing = progress == nil ? Listing() : try await listFiles()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                if index >= 8 {
                    try await group.next()
                }
                group.addTask {
                    try await self.transferFiles(key, listing: listing)
                }
            }
            try await group.waitForAll()
        }
    }
    
    private func transferFiles(_ key: String, listing: Listing) async throws {
        try Task.checkCancellation()
        progress?.current.insert(key)
        try await recordBook(key, phase: .file) {
            try await syncFiles(key: key, listing: listing)
        }
        finishTransfer(key)
    }
    
    private func listFiles() async throws -> Listing {
        let listing = Listing()
        let listed = try await drive.list(query: "'me' in owners")
        let keys = Dictionary(uniqueKeysWithValues: listed.filter { $0.parents?.contains(cache.bookFolder) == true }.map { ($0.id, $0.name) })
        for file in listed {
            guard let parent = file.parents?.first else { continue }
            if file.isFolder, let key = keys[parent], let generation = Int(file.name) {
                if listing.folders[key]?[generation] == nil {
                    listing.folders[key, default: [:]][generation] = file.id
                }
            } else if listing.files[parent]?[file.name] == nil {
                listing.files[parent, default: [:]][file.name] = file
            }
        }
        return listing
    }
    
    private func syncFiles(key: String, listing: Listing) async throws {
        var failure: Error?
        for fileType in SyncFileType.allCases {
            try Task.checkCancellation()
            do {
                try await uploadFile(key: key, fileType: fileType, listing: listing)
                if fileType != .epub {
                    try await downloadFile(key: key, fileType: fileType, listing: listing)
                }
            } catch {
                failure = failure ?? error
            }
        }
        
        do {
            try await cleanupFiles(key: key, listing: listing)
        } catch {
            failure = failure ?? error
        }
        if let failure {
            throw failure
        }
    }
    
    private func transferDirection(_ record: SyncRecord) -> Direction? {
        let fileTypes = SyncFileType.allCases.filter { !record.deleted || $0 == .cover }
        let upload = record.attached && fileTypes.contains { fileType in
            guard let source = record.sources[fileType] else { return false }
            return (record.files[fileType]?.modified ?? .min) < source
        }
        let download = fileTypes.contains { fileType in
            guard fileType != .epub, let published = record.files[fileType] else { return false }
            return (record.sources[fileType] ?? .min) < published.modified
        }
        switch (upload, download) {
        case (true, true):
            return .both
        case (true, false):
            return .upload
        case (false, true):
            return .download
        case (false, false):
            return nil
        }
    }
    
    private func beginTransfers(_ keys: [String]) {
        transfers = keys.compactMap { key in
            let record = store.state.books[key]!
            return transferDirection(record).map {
                QueueItem(key: key, title: bookTitle(key, deleted: record.deleted), direction: $0)
            }
        }
        progress = transfers.isEmpty ? nil : Progress(done: 0, total: transfers.count)
    }
    
    private func finishTransfer(_ key: String) {
        progress?.current.remove(key)
        guard transfers.contains(where: { $0.key == key }) else { return }
        progress?.done += 1
        if bookErrors[BookErrorKey(key: key, phase: .file)] == nil {
            transfers.removeAll { $0.key == key }
        }
    }
    
    func downloadBook(_ book: BookMetadata, onProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws -> BookMetadata {
        let key = book.folder.precomposedStringWithCanonicalMapping
        await sync(book: book)
        if unsupportedFormat {
            throw SyncFormatError.unsupportedVersion
        }
        if let errorMessage = errorMessage ?? bookErrors[BookErrorKey(key: key, phase: .state)]?.message {
            throw GoogleDriveError.apiError(errorMessage, statusCode: nil)
        }
        
        try Task.checkCancellation()
        
        let root = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        if store.state.books[key]?.deleted == true {
            throw GoogleDriveError.apiError("This book was deleted.", statusCode: nil)
        }
        
        if enabled, store.state.books[key]?.files[.epub]?.value != nil {
            try await downloadFile(key: key, fileType: .epub, listing: Listing(), onProgress: onProgress)
        }
        
        try Task.checkCancellation()
        
        let metadata = BookStorage.loadMetadata(root: root) ?? book
        guard metadata.epub != nil else {
            throw GoogleDriveError.apiError("This book has not been uploaded yet.", statusCode: nil)
        }
        return metadata
    }
    
    private func uploadFile(key: String, fileType: SyncFileType, listing: Listing) async throws {
        let record = store.state.books[key]!
        if !record.attached || (record.deleted && fileType != .cover) {
            return
        }
        
        guard let source = record.sources[fileType] else { return }
        if let published = record.files[fileType], published.modified >= source {
            return
        }
        
        guard let url = try store.sourceURL(key: key, fileType: fileType) else {
            store.state.books[key]!.files[fileType] = Timestamped(modified: source, value: nil)
            store.state.books[key]!.pending = true
            try store.saveChanges(booksChanged: false)
            return
        }
        
        let fileName = url.lastPathComponent.precomposedStringWithCanonicalMapping
        let name = fileType == .sasayaki ? "\(source)-\(fileName)" : fileName
        
        let data = try await Task.detached {
            try Data(contentsOf: url)
        }.value
        try Task.checkCancellation()
        
        if !canPublish(key: key, fileType: fileType, source: source, generation: record.generation) {
            return
        }
        
        let folder = try await fileFolder(listing, key: key, generation: record.generation, create: true)
        if listing.files[folder!]?[name] == nil {
            try await drive.upload(data: data, fileName: name, folder: folder!)
        }
        try Task.checkCancellation()
        if !canPublish(key: key, fileType: fileType, source: source, generation: record.generation) {
            return
        }
        
        if fileType == .sasayaki, let published = store.state.books[key]!.files[.sasayaki]?.value, published != name {
            store.state.books[key]!.cleanup.insert(record.generation)
        }
        store.state.books[key]!.files[fileType] = Timestamped(modified: source, value: name)
        store.state.books[key]!.pending = true
        try store.saveChanges(booksChanged: false)
    }
    
    private func fileFolder(_ listing: Listing, key: String, generation: Int, create: Bool) async throws -> String? {
        if let folder = listing.folders[key]?[generation] {
            return folder
        }
        let folder = try await drive.fileFolder(books: cache.bookFolder, key: key, generation: generation, create: create)
        listing.folders[key, default: [:]][generation] = folder
        return folder
    }
    
    private func canPublish(key: String, fileType: SyncFileType, source: Int64, generation: Int) -> Bool {
        let record = store.state.books[key]!
        return record.generation == generation && record.sources[fileType] == source
            && (!record.deleted || fileType == .cover)
            && (record.files[fileType]?.modified ?? .min) <= source
    }
    
    private func downloadFile(key: String, fileType: SyncFileType, listing: Listing, onProgress: @MainActor @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        let record = store.state.books[key]!
        if record.deleted && fileType != .cover {
            return
        }
        
        guard let reference = record.files[fileType] else { return }
        if let source = record.sources[fileType], source >= reference.modified {
            return
        }
        
        let root = try SyncStorage.bookDirectory(folder: key, archived: record.deleted)
        
        guard let name = reference.value else {
            try applyDownloadedFile(key: key, fileType: fileType, path: nil, reference: reference)
            return
        }
        if record.deleted,
           StatisticsStorage.load(folder: key).values.allSatisfy({ $0.value == nil }) {
            return
        }
        
        let folder = try await fileFolder(listing, key: key, generation: record.generation, create: false)
        
        let data = try await drive.download(fileName: name, folder: folder, listed: folder.flatMap { listing.files[$0]?[name] }, onProgress: onProgress)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporary)
        }
        try await Task.detached {
            try data.write(to: temporary)
        }.value
        
        try Task.checkCancellation()
        
        let current = store.state.books[key]!
        if current.generation != record.generation || current.deleted != record.deleted || current.files[fileType] != reference {
            return
        }
        if let source = current.sources[fileType], source >= reference.modified {
            return
        }
        
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileName = fileType == .sasayaki ? FileNames.sasayakiMatch : name
        let destination = root.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        let relative = "Books/" + (record.deleted ? "statistics_archive/" : "") + root.lastPathComponent + "/" + fileName
        try applyDownloadedFile(key: key, fileType: fileType, path: relative, reference: reference)
    }
    
    private func applyDownloadedFile(key: String, fileType: SyncFileType, path: String?, reference: Timestamped<String?>) throws {
        let record = store.state.books[key]!
        let root = try SyncStorage.bookDirectory(folder: key, archived: record.deleted)
        
        if let existing = BookStorage.loadMetadata(root: root), fileType != .sasayaki {
            let oldPath: URL?
            if fileType == .epub {
                oldPath = existing.epub.map { root.appendingPathComponent($0) }
            } else {
                oldPath = existing.coverURL
            }
            let appDirectory = try BookStorage.getAppDirectory()
            let newPath = path.map { appDirectory.appendingPathComponent($0) }
            if let oldPath, oldPath != newPath {
                try BookStorage.delete(at: oldPath)
            }
            
            var metadata = existing
            if fileType == .epub {
                metadata.epub = path.map { URL(fileURLWithPath: $0).lastPathComponent }
            }
            if fileType == .cover {
                metadata.cover = path
            }
            
            try BookStorage.saveMetadata(metadata, inside: root)
        }
        if fileType == .sasayaki && path == nil {
            try BookStorage.delete(at: root.appendingPathComponent(FileNames.sasayakiMatch))
        }
        
        store.state.books[key]!.sources[fileType] = reference.modified
        
        try store.save()
        if fileType != .sasayaki {
            NotificationCenter.default.post(name: SyncStorage.booksChangedNotification, object: nil)
        }
        
        if fileType == .sasayaki, let reader = ReaderIntentBridge.shared.reader, reader.book.folder == key {
            reader.reloadSyncedMatch()
        }
    }
    
    private func cleanupFiles(key: String, listing: Listing) async throws {
        for generation in store.state.books[key]!.cleanup {
            if store.state.books[key]!.pending {
                return
            }
            
            let files = try await drive.children(parent: cache.stateFolder, name: key + ".json")
            let remote = try await readState(files, merge: SyncBook.merge)
            try mergeBook(key, remote: remote)
            
            guard let book = try store.loadBook(key: key, remote: remote) else {
                return
            }
            if book.needsUpload(remote: remote) {
                store.state.books[key]!.pending = true
                
                try store.saveChanges(booksChanged: false)
                return
            }
            
            let folder = try await fileFolder(listing, key: key, generation: generation, create: false)
            
            var recent = false
            if let folder, generation < book.generation {
                try await GoogleDriveClient.shared.trashFile(fileId: folder)
                listing.folders[key]?[generation] = nil
                try Task.checkCancellation()
            } else if let folder {
                let files = try await drive.children(parent: folder)
                
                for file in files where !file.isFolder && file.name != book.files[.cover]?.value {
                    let current = store.state.books[key]!
                    let stale = file.name.hasSuffix(FileNames.sasayakiMatch) && file.name != current.files[.sasayaki]?.value
                    if !current.deleted && !stale {
                        continue
                    }
                    if file.isRecent {
                        recent = true
                        continue
                    }
                    
                    try await drive.trash(file)
                    try Task.checkCancellation()
                }
            }
            if recent {
                continue
            }
            
            store.state.books[key]!.cleanup.remove(generation)
            
            try store.save()
        }
    }
}
