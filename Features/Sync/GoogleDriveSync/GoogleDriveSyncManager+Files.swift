import Foundation

extension GoogleDriveSyncManager {
    func runFileSync() async throws -> Bool {
        enqueue(reset: true)
        let listing = progress == nil ? Listing() : try await listFiles()
        countSizes(listing)
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                sampleFlows()
            }
        }
        defer { ticker.cancel() }
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
            let open = epubs < 4 && priority == 0
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
                    try await syncFiles(key: job.key, listing: listing)
                    if job.epub && wantsEpub(job.key) {
                        try await downloadFile(key: job.key, fileType: .epub, listing: listing)
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
            finishTransfer(job.key, finished: !deferred && failure == nil)
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
    
    private func needsEpubUpload(_ record: SyncRecord) -> Bool {
        guard record.attached, !record.deleted, let source = record.sources[.epub] else { return false }
        return (record.files[.epub]?.modified ?? .min) < source
    }
    
    private func pendingFiles(key: String, record: SyncRecord, epub: Bool, listing: Listing?) -> [(fileType: SyncFileType, direction: Direction, size: Int64?)] {
        var files: [(fileType: SyncFileType, direction: Direction, size: Int64?)] = []
        for fileType in SyncFileType.allCases where !record.deleted || fileType == .cover {
            let source = record.sources[fileType]
            let published = record.files[fileType]
            if record.attached, let source, (published?.modified ?? .min) < source {
                let url = try? store.sourceURL(key: key, fileType: fileType)
                let size = url.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.int64Value } ?? 0
                files.append((fileType, .upload, size))
            } else if fileType != .epub || epub, let published, (source ?? .min) < published.modified, let name = published.value {
                files.append((fileType, .download, listing.flatMap { size($0, key: key, generation: record.generation, name: name) }))
            }
        }
        return files
    }
    
    private func count(_ key: String, files: [(fileType: SyncFileType, direction: Direction, size: Int64?)]) {
        for file in files {
            guard let size = file.size else { continue }
            if file.direction == .download {
                if downloadFlow.counted.insert("\(key)/\(file.fileType)").inserted {
                    downloadFlow.total += size
                }
            } else if uploadFlow.counted.insert("\(key)/\(file.fileType)").inserted {
                uploadFlow.total += size
            }
        }
    }
    
    private func size(of files: [(fileType: SyncFileType, direction: Direction, size: Int64?)]) -> Int64? {
        files.reduce(Int64(0)) { total, file in total.flatMap { total in file.size.map { total + $0 } } }
    }
    
    private func countSizes(_ listing: Listing) {
        for index in transfers.indices {
            let key = transfers[index].key
            guard let record = store.state.books[key] else { continue }
            let files = pendingFiles(key: key, record: record, epub: downloads.contains(key), listing: listing)
            count(key, files: files)
            transfers[index].size = size(of: files)
        }
    }
    
    private func begin(_ key: String, fileType: SyncFileType, direction: Direction, total: Int64) {
        count(key, files: [(fileType, direction, total)])
        interrupted[key] = nil
        moving[key] = Moving(direction: direction, total: total)
    }
    
    private func advance(_ key: String, to bytes: Int64) {
        moving[key]?.done = max(bytes, 0)
    }
    
    private func end(_ key: String, succeeded: Bool) {
        guard let moving = moving.removeValue(forKey: key) else { return }
        if succeeded {
            if moving.direction == .download {
                downloadFlow.done += moving.total
            } else {
                uploadFlow.done += moving.total
            }
        } else {
            interrupted[key] = Transfer(direction: moving.direction, done: min(moving.done, moving.total), total: moving.total, state: .interrupted)
        }
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
            moving = [:]
            interrupted = [:]
            uploadFlow = Flow()
            downloadFlow = Flow()
        }
        for key in store.state.books.keys.sorted() {
            let record = store.state.books[key]!
            let files = pendingFiles(key: key, record: record, epub: downloads.contains(key), listing: nil)
            count(key, files: files)
            if !jobs.contains(where: { $0.key == key }) {
                jobs.append(Job(key: key, epub: needsEpubUpload(record) || (downloads.contains(key) && missingEpub(record))))
            }
            guard !transfers.contains(where: { $0.key == key }), let direction = transferDirection(record, epub: downloads.contains(key)) else { continue }
            let metadata = record.deleted ? nil : (try? SyncStorage.bookDirectory(folder: key)).flatMap { BookStorage.loadMetadata(root: $0) }
            transfers.append(QueueItem(key: key, title: metadata?.title ?? bookTitle(key, deleted: record.deleted), direction: direction, coverURL: metadata?.coverURL, size: size(of: files)))
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
        
        let total = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        begin(key, fileType: fileType, direction: .upload, total: total)
        do {
            try await upload(listing, key: key, generation: record.generation, name: name, file: url, resumable: fileType == .epub) { [weak self] bytes in
                self?.advance(key, to: bytes)
            }
            end(key, succeeded: true)
        } catch {
            end(key, succeeded: false)
            throw error
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
        let size = file.size.flatMap { Int64($0) } ?? 0
        let data: Data
        begin(key, fileType: fileType, direction: .download, total: size)
        do {
            data = try await drive.download(file) { [weak self] fraction in
                self?.advance(key, to: Int64(fraction * Double(size)))
                onProgress(fraction)
            }
            end(key, succeeded: true)
        } catch {
            end(key, succeeded: false)
            throw error
        }
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
