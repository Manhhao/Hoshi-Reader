import Foundation
import Network

nonisolated struct GoogleDriveSyncCache: Codable {
    var cursor: String?
    var root = ""
    var stateFolder = ""
    var bookFolder = ""
    var bookVersions: [String: [String: String]] = [:]
}

@MainActor
@Observable
final class GoogleDriveSyncManager {
    static let shared = GoogleDriveSyncManager()
    var errorMessage: String?
    var lastSync: Date?
    let store = SyncStorage.shared
    let drive = GoogleDriveSyncHandler.shared
    private let pathMonitor = NWPathMonitor()
    var cache = GoogleDriveSyncCache()
    
    private var stateTask: Task<Void, Never>?
    private var fileTransferTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    var downloadTask: Task<Void, Never>?
    private var stopped = false
    private var unsupportedFormat = false
    
    var isSyncing: Bool { stateTask != nil }
    
    var enabled: Bool {
        UserConfig.shared.enableSync && UserConfig.shared.syncProvider == .gdrive
        && GoogleDriveAuth.shared.isAuthenticated(for: .gdrive) && !stopped
    }
    
    private init() {
        cache = (try? SyncFormat.decode(GoogleDriveSyncCache.self, from: Data(contentsOf: cacheURL()))) ?? GoogleDriveSyncCache()
        store.onChange = { [weak self] in
            self?.schedule()
        }
        try? store.prepareLibrary()
        
        pathMonitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                Task { @MainActor in
                    await GoogleDriveSyncManager.shared.sync()
                }
            }
        }
        
        pathMonitor.start(queue: DispatchQueue(label: "GoogleDriveSync"))
    }
    
    func start() {
        GoogleDriveClient.shared.resume()
        stopped = false
        pollTask?.cancel()
        
        guard enabled else { return }
        pollTask = Task {
            await sync()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    return
                }
                await sync()
            }
        }
    }
    
    func pause() async {
        pollTask?.cancel()
        pollTask = nil
        await sync()
    }
    
    func stop() async {
        stopped = true
        pollTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        stateTask?.cancel()
        fileTransferTask?.cancel()
        
        downloadTask?.cancel()
        
        await GoogleDriveClient.shared.stop()
        await stateTask?.value
        await fileTransferTask?.value
        
        await downloadTask?.value
        
        stateTask = nil
        fileTransferTask = nil
        downloadTask = nil
    }
    
    func signOut() async throws {
        await stop()
        if UserConfig.shared.syncProvider == .gdrive {
            try resetConnection()
        }
        TokenStorage.clear()
        TtuDriveHandler.clearCache()
    }
    
    func clearCache() async throws {
        await stop()
        cache = GoogleDriveSyncCache()
        try saveCache()
        
        start()
    }
    
    func resetConnection(restoringBackup: Bool = false) throws {
        if restoringBackup {
            try store.reload()
        }
        
        try store.prepareLibrary()
        try removePlaceholders()
        try store.resetSyncState()
        cache = GoogleDriveSyncCache()
        unsupportedFormat = false
        errorMessage = nil
        lastSync = nil
        try saveCache()
    }
    
    func schedule() {
        guard enabled else { return }
        guard stateTask == nil, debounceTask == nil else { return }
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            debounceTask = nil
            await sync()
        }
    }
    
    func sync(book: BookMetadata? = nil) async {
        guard enabled else { return }
        let previous = stateTask
        if book == nil, let previous {
            await previous.value
            return
        }
        
        debounceTask?.cancel()
        debounceTask = nil
        let previousFileTransfers = book == nil ? nil : fileTransferTask
        if book != nil {
            previous?.cancel()
            previousFileTransfers?.cancel()
        }
        
        let task = Task {
            await previous?.value
            await previousFileTransfers?.value
            
            do {
                try Task.checkCancellation()
                errorMessage = nil
                
                if let book {
                    if cache.stateFolder.isEmpty {
                        try await loadLayout()
                    }
                    
                    let key = book.folder.precomposedStringWithCanonicalMapping
                    try await syncBook(key)
                    return
                }
                
                let (changed, cursor) = try await changes()
                let pending = store.state.books.compactMap { $0.value.pending ? $0.key : nil }
                let keys = changed.union(pending)
                for key in keys.subtracting([".shelves"]).sorted() {
                    try await syncBook(key)
                }
                if !store.state.books.values.contains(where: { !$0.attached && !$0.deleted }) {
                    if keys.contains(".shelves") || store.state.shelvesPending {
                        try await syncShelves()
                    }
                    cache.cursor = cursor
                    try saveCache()
                    lastSync = .now
                    unsupportedFormat = false
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    if error is SyncFormatError {
                        unsupportedFormat = true
                    }
                    fileTransferTask?.cancel()
                }
            }
        }
        
        stateTask = task
        await task.value
        
        if !task.isCancelled {
            stateTask = nil
            
            if book != nil || (errorMessage == nil && (store.state.books.values.contains(where: { $0.pending }) || store.state.shelvesPending)) {
                schedule()
            }
            if book == nil {
                startFileSync()
            }
        }
    }
    
    func startFileSync() {
        guard enabled, !unsupportedFormat, errorMessage == nil, !isSyncing, fileTransferTask == nil, downloadTask == nil, !cache.bookFolder.isEmpty else { return }
        fileTransferTask = Task {
            defer { fileTransferTask = nil }
            for key in store.state.books.keys.sorted() {
                if Task.isCancelled {
                    return
                }
                
                for fileType in SyncFileType.allCases {
                    do {
                        try await uploadFile(key: key, fileType: fileType)
                        if fileType != .epub {
                            try await downloadFile(key: key, fileType: fileType)
                        }
                    } catch {
                        if stopsFileSync(error) {
                            return
                        }
                    }
                }
                
                do {
                    try await cleanupFiles(key: key)
                } catch {
                    if stopsFileSync(error) {
                        return
                    }
                }
            }
        }
    }
    
    private func stopsFileSync(_ error: Error) -> Bool {
        if Task.isCancelled {
            return true
        }
        
        errorMessage = error.localizedDescription
        if error is SyncFormatError {
            unsupportedFormat = true
            return true
        }
        return false
    }
    
    func downloadBook(_ book: BookMetadata, onProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws -> BookMetadata {
        let key = book.folder.precomposedStringWithCanonicalMapping
        await sync(book: book)
        if unsupportedFormat {
            throw SyncFormatError.unsupportedVersion
        }
        if let errorMessage {
            throw GoogleDriveError.apiError(errorMessage, statusCode: nil)
        }
        
        try Task.checkCancellation()
        
        let root = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        if store.state.books[key]?.deleted == true {
            throw GoogleDriveError.apiError("This book was deleted.", statusCode: nil)
        }
        
        if enabled, store.state.books[key]?.files[.epub]?.value != nil {
            try await downloadFile(key: key, fileType: .epub, onProgress: onProgress)
        }
        
        try Task.checkCancellation()
        
        let metadata = BookStorage.loadMetadata(root: root) ?? book
        guard metadata.epub != nil else {
            throw GoogleDriveError.apiError("This book has not been uploaded yet.", statusCode: nil)
        }
        return metadata
    }
    
    private func changes() async throws -> (Set<String>, String) {
        var keys: Set<String> = []
        var cursor: String
        if let saved = cache.cursor {
            cursor = saved
        } else {
            cursor = try await drive.startToken()
            keys = try await listRemote()
        }
        while true {
            let page = try await drive.changes(cursor: cursor)
            try Task.checkCancellation()
            if page.changes.contains(where: { change in
                guard let file = change.file, file.isFolder else { return false }
                return file.name == "Hoshi Reader" || file.parents?.contains(cache.root) == true
            }) {
                keys.formUnion(try await listRemote())
            }
            for change in page.changes where !change.removed && change.file?.trashed != true {
                if let file = change.file, file.parents?.contains(cache.stateFolder) == true,
                   let key = file.stateKey {
                    keys.insert(key)
                }
            }
            guard let next = page.nextPageToken else { return (keys, page.newStartPageToken!) }
            cursor = next
        }
    }
    
    private func loadLayout() async throws {
        let layout = try await drive.layout()
        try Task.checkCancellation()
        cache.root = layout.root
        cache.stateFolder = layout.state
        cache.bookFolder = layout.books
    }
    
    private func listRemote() async throws -> Set<String> {
        try await loadLayout()
        let files = try await drive.children(parent: cache.stateFolder)
        try Task.checkCancellation()
        return Set(files.compactMap(\.stateKey))
    }
    
    private func syncBook(_ key: String) async throws {
        let files = try await drive.children(parent: cache.stateFolder, name: key + ".json")
        try Task.checkCancellation()
        
        var versions = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.version) })
        if files.count == 1, store.state.books[key]?.pending == false, cache.bookVersions[key] == versions {
            return
        }
        if cache.bookVersions.removeValue(forKey: key) != nil {
            try saveCache()
        }
        
        let remote = try await readState(files, merge: SyncBook.merge)
        try mergeBook(key, remote: remote)
        
        guard let book = try store.loadBook(key: key) else {
            return
        }
        
        if book.needsUpload(remote: remote) || files.count > 1 {
            let written = try await writeState(book, name: key + ".json", files: files)
            versions = [written.id: written.version]
        }
        
        if store.state.books[key]!.pending, try store.loadBook(key: key) == book {
            store.state.books[key]!.pending = false
            try store.save()
        }
        cache.bookVersions[key] = versions
        try saveCache()
    }
    
    private func readState<T: Codable & Sendable>(_ files: [GoogleDriveFile], merge: (T, T) -> T) async throws -> T? {
        var state: T?
        
        for file in files {
            let data = try await drive.read(file)
            try Task.checkCancellation()
            let incoming = try SyncFormat.decode(T.self, from: data)
            state = state.map { merge($0, incoming) } ?? incoming
        }
        return state
    }
    
    @discardableResult
    private func writeState<T: Codable & Sendable>(_ state: T, name: String, files: [GoogleDriveFile]) async throws -> GoogleDriveFile {
        let written = try await GoogleDriveClient.shared.write(data: SyncFormat.encode(state), name: name, parent: cache.stateFolder, fileId: files.first?.id)
        for duplicate in files.dropFirst() {
            try Task.checkCancellation()
            try await drive.trash(duplicate)
        }
        return written
    }
    
    private func mergeBook(_ key: String, remote: SyncBook?) throws {
        let root = try SyncStorage.resolveBookDirectory(folder: key)
        if BookStorage.loadMetadata(root: root) != nil {
            try store.prepareBook(root: root)
        }
        guard let remote, let book = store.state.books[key] else {
            if let merged = try remote ?? store.loadBook(key: key) {
                try store.applyBook(key: key, book: merged)
            }
            return
        }
        
        let replaced = remote.generation > book.generation && (book.attached || book.deleted)
        if replaced || (remote.deleted && remote.generation >= book.generation),
           let reader = ReaderIntentBridge.shared.reader, reader.book.folder == key {
            reader.stopTracking()
            reader.sasayakiPlayer.teardown()
            reader.bookDeleted = true
        }
        
        var local = try store.loadBook(key: key)!
        if replaced {
            try store.removeBookFiles(key: key)
            store.state.books[key]!.cleanup.insert(book.generation)
        }
        if !book.attached && book.generation == 0 {
            local.metadata = remote.metadata
        }
        if !book.attached && !book.deleted && !remote.deleted {
            local.generation = remote.generation
        }
        try store.applyBook(key: key, book: SyncBook.merge(local, remote))
    }
    
    private func syncShelves() async throws {
        let files = try await drive.children(parent: cache.stateFolder, name: ".shelves.json")
        let remote = try await readState(files, merge: SyncShelves.merge)
        let local = SyncShelves(shelves: BookStorage.loadShelfList())
        let merged = remote.map { SyncShelves.merge($0, local) } ?? local
        try store.applyShelves(merged.shelves)
        if (merged != remote && !merged.shelves.isEmpty) || files.count > 1 {
            try await writeState(merged, name: ".shelves.json", files: files)
        }
        
        store.state.shelvesPending = BookStorage.loadShelfList() != merged.shelves
        try store.save()
    }
    
    private func uploadFile(key: String, fileType: SyncFileType) async throws {
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
        
        let folder = try await drive.fileFolder(books: cache.bookFolder, key: key, generation: record.generation, create: true)
        try await drive.upload(data: data, fileName: name, folder: folder!)
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
    
    private func canPublish(key: String, fileType: SyncFileType, source: Int64, generation: Int) -> Bool {
        let record = store.state.books[key]!
        return record.generation == generation && record.sources[fileType] == source
            && (!record.deleted || fileType == .cover)
            && (record.files[fileType]?.modified ?? .min) <= source
    }
    
    private func downloadFile(key: String, fileType: SyncFileType, onProgress: @MainActor @Sendable @escaping (Double) -> Void = { _ in }) async throws {
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
        
        let folder = try await drive.fileFolder(books: cache.bookFolder, key: key, generation: record.generation, create: false)
        
        let data = try await drive.download(fileName: name, folder: folder, onProgress: onProgress)
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
    
    private func cleanupFiles(key: String) async throws {
        for generation in store.state.books[key]!.cleanup {
            if store.state.books[key]!.pending {
                return
            }
            
            let files = try await drive.children(parent: cache.stateFolder, name: key + ".json")
            let remote = try await readState(files, merge: SyncBook.merge)
            try mergeBook(key, remote: remote)
            
            let book = try store.loadBook(key: key)!
            if book.needsUpload(remote: remote) {
                store.state.books[key]!.pending = true
                
                try store.saveChanges(booksChanged: false)
                return
            }
            
            let folder = try await drive.fileFolder(books: cache.bookFolder, key: key, generation: generation, create: false)
            
            var recent = false
            if let folder, generation < book.generation {
                try await GoogleDriveClient.shared.trashFile(fileId: folder)
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
    
    private func removePlaceholders() throws {
        for book in try BookStorage.loadAllBooks() where book.epub == nil {
            let root = try SyncStorage.bookDirectory(folder: book.folder)
            if StatisticsStorage.load(root: root).values.contains(where: { $0.value != nil }) {
                try StatisticsStorage.archive(book)
            } else {
                store.state.books[book.folder] = nil
            }
            try BookStorage.delete(at: root)
        }
        
        NotificationCenter.default.post(name: SyncStorage.booksChangedNotification, object: nil)
    }
    
    private func cacheURL() throws -> URL {
        try BookStorage.getAppDirectory().appendingPathComponent("drive-sync.json")
    }
    
    private func saveCache() throws {
        try SyncFormat.encode(cache).write(to: cacheURL(), options: .atomic)
    }
}
