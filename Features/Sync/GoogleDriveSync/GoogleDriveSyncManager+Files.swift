import Foundation

extension GoogleDriveSyncManager {
    func runFileSync() async throws -> Bool {
        enqueue(reset: true)
        let listing = progress == nil ? Listing() : try await listFiles()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await self.work(listing: listing)
                }
            }
            try await group.waitForAll()
        }
        try saveCache()
        if cache.replacedRoot == true, (try? await drive.removeReplaced()) != nil {
            cache.replacedRoot = nil
            try saveCache()
        }
        return listing.published
    }
    
    private func work(listing: Listing) async throws {
        while true {
            try Task.checkCancellation()
            let open = epubs < 3 && priority == 0
            guard let index = jobs.firstIndex(where: { !$0.epub || open }) else {
                if jobs.isEmpty && active == 0 {
                    return
                }
                await wait()
                continue
            }
            let job = jobs.remove(at: index)
            active += 1
            epubs += job.epub ? 1 : 0
            progress?.current.insert(job.key)
            var failure: Error?
            do {
                try await lock(job.key)
                defer { unlock(job.key) }
                try await recordBook(job.key, phase: .file) {
                    if job.epub {
                        try await downloadFile(key: job.key, fileType: .epub, listing: listing)
                    } else {
                        try await syncFiles(key: job.key, listing: listing)
                    }
                }
            } catch {
                failure = error
            }
            let succeeded = failure == nil && bookErrors[BookErrorKey(key: job.key, phase: .file)] == nil
            let deferred = !job.epub && succeeded && wantsEpub(job.key)
            active -= 1
            epubs -= job.epub ? 1 : 0
            if job.epub && succeeded {
                downloads.remove(job.key)
            }
            if deferred {
                jobs.append(Job(key: job.key, epub: true))
            }
            if failure != nil {
                jobs = []
            }
            finishTransfer(job.key, finished: !deferred)
            wake()
            if let failure {
                throw failure
            }
        }
    }
    
    private func lock(_ key: String) async throws {
        while busy.contains(key) {
            await wait()
            try Task.checkCancellation()
        }
        busy.insert(key)
    }
    
    private func unlock(_ key: String) {
        busy.remove(key)
        wake()
    }
    
    var missingBooks: [String] {
        store.state.books.filter { missingEpub($0.value) }.map(\.key)
    }
    
    private func missingEpub(_ record: SyncRecord) -> Bool {
        guard !record.deleted, let published = record.files[.epub], published.value != nil else { return false }
        return (record.sources[.epub] ?? .min) < published.modified
    }
    
    private func wantsEpub(_ key: String) -> Bool {
        downloads.contains(key) && store.state.books[key].map(missingEpub) == true
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
    
    private func transferDirection(_ record: SyncRecord, epub: Bool) -> Direction? {
        let fileTypes = SyncFileType.allCases.filter { !record.deleted || $0 == .cover }
        let upload = record.attached && fileTypes.contains { fileType in
            guard let source = record.sources[fileType] else { return false }
            return (record.files[fileType]?.modified ?? .min) < source
        }
        let download = fileTypes.contains { fileType in
            guard fileType != .epub || epub, let published = record.files[fileType] else { return false }
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
    
    func enqueue(reset: Bool) {
        if reset {
            jobs = []
            active = 0
            epubs = 0
            transfers = []
            progress = nil
        }
        for key in store.state.books.keys.sorted() {
            let job = Job(key: key, epub: false)
            if !jobs.contains(job) {
                jobs.append(job)
            }
            let record = store.state.books[key]!
            guard !transfers.contains(where: { $0.key == key }), let direction = transferDirection(record, epub: downloads.contains(key)) else { continue }
            transfers.append(QueueItem(key: key, title: bookTitle(key, deleted: record.deleted), direction: direction))
            progress = progress ?? Progress(done: 0, total: 0)
            progress?.total += 1
        }
        wake()
    }
    
    private func finishTransfer(_ key: String, finished: Bool) {
        progress?.current.remove(key)
        guard finished, transfers.contains(where: { $0.key == key }) else { return }
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
            priority += 1
            defer {
                priority -= 1
                wake()
            }
            try await lock(key)
            defer { unlock(key) }
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
            listing.published = true
            try store.saveChanges(booksChanged: false)
            return
        }
        
        let fileName = url.lastPathComponent.precomposedStringWithCanonicalMapping
        let name = fileType == .sasayaki ? "\(source)-\(fileName)" : fileName
        
        try await upload(listing, key: key, generation: record.generation, name: name, file: url)
        try Task.checkCancellation()
        if !canPublish(key: key, fileType: fileType, source: source, generation: record.generation) {
            return
        }
        
        if fileType == .sasayaki, let published = store.state.books[key]!.files[.sasayaki]?.value, published != name {
            store.state.books[key]!.cleanup.insert(record.generation)
        }
        store.state.books[key]!.files[fileType] = Timestamped(modified: source, value: name)
        store.state.books[key]!.pending = true
        listing.published = true
        try store.saveChanges(booksChanged: false)
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
        
        guard let file = try await findFile(listing, key: key, generation: record.generation, name: name) else {
            throw GoogleDriveError.apiError("\(name) is missing from Google Drive.", statusCode: 404)
        }
        let data = try await drive.download(file, onProgress: onProgress)
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
            
            let folder = try await folder(listing, key: key, generation: generation)
            
            var recent = false
            if let folder, generation < book.generation {
                try await GoogleDriveClient.shared.trashFile(fileId: folder)
                forgetFolder(listing, key: key, generation: generation)
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
