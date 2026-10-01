import Foundation
import Network

nonisolated struct GoogleDriveSyncCache: Codable {
    var cursor: String?
    var root = ""
    var stateFolder = ""
    var bookFolder = ""
    var bookVersions: [String: [String: String]] = [:]
}

private struct RemoteChanges {
    var listed: [String: [GoogleDriveFile]]?
    var changed: Set<String>
    var cursor: String
    
    func contains(_ key: String) -> Bool {
        changed.contains(key) || listed?[key] != nil
    }
    
    func files(_ key: String) -> [GoogleDriveFile]? {
        if changed.contains(key) {
            return nil
        }
        return listed.map { $0[key] ?? [] }
    }
}

@MainActor
@Observable
final class GoogleDriveSyncManager {
    enum Phase: Comparable {
        case state
        case file
    }
    
    enum Direction {
        case upload
        case download
        case both
    }
    
    struct QueueItem: Identifiable {
        var key: String
        var title: String
        var direction: Direction?
        var error: String?
        
        var id: String { key }
    }
    
    struct Progress {
        var done: Int
        var total: Int
        var current: Set<String> = []
    }
    
    private struct BookErrorKey: Hashable {
        var key: String
        var phase: Phase
    }
    
    private struct BookError {
        var title: String
        var message: String
    }
    
    private typealias Folders = [String: [Int: String]]
    
    static let shared = GoogleDriveSyncManager()
    var errorMessage: String?
    var lastSync: Date?
    let store = SyncStorage.shared
    let drive = GoogleDriveSyncHandler.shared
    private let pathMonitor = NWPathMonitor()
    var cache = GoogleDriveSyncCache()
    private var remoteBooks: [String: (versions: [String: String], book: SyncBook)] = [:]
    private var listedFiles: [String: [String: GoogleDriveFile]] = [:]
    
    private var stateTask: Task<Void, Never>?
    private var fileTransferTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    var downloadTask: Task<Void, Never>?
    private var stopped = false
    private var unsupportedFormat = false
    private var transfers: [QueueItem] = []
    private(set) var progress: Progress?
    private var bookErrors: [BookErrorKey: BookError] = [:]
    
    var isSyncing: Bool { stateTask != nil || fileTransferTask != nil }
    
    var queue: [QueueItem] {
        var queue = transfers
        for (id, error) in bookErrors.sorted(by: { ($0.key.key, $0.key.phase) < ($1.key.key, $1.key.phase) }) {
            if let index = queue.firstIndex(where: { $0.key == id.key }) {
                queue[index].error = queue[index].error ?? error.message
            } else {
                queue.append(QueueItem(key: id.key, title: error.title, direction: nil, error: error.message))
            }
        }
        return queue
    }
    
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
        transfers = []
        progress = nil
        bookErrors = [:]
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
                    try await recordBook(key, phase: .state) {
                        try await syncBook(key)
                    }
                    return
                }
                
                let remote = try await changes()
                let pending = store.state.books.compactMap { $0.value.pending ? $0.key : nil }
                let keys = remote.changed.union(pending).union((remote.listed ?? [:]).keys).subtracting([".shelves"]).sorted()
                await prefetch(remote, keys: keys)
                for key in keys {
                    try await recordBook(key, phase: .state) {
                        try await syncBook(key, files: remote.files(key))
                    }
                }
                let failed = keys.contains { bookErrors[BookErrorKey(key: $0, phase: .state)] != nil }
                if !failed && !store.state.books.values.contains(where: { !$0.attached && !$0.deleted }) {
                    if remote.contains(".shelves") || store.state.shelvesPending {
                        try await syncShelves()
                    }
                    cache.cursor = remote.cursor
                    try saveCache()
                    lastSync = .now
                    unsupportedFormat = false
                }
            } catch {
                if !Task.isCancelled {
                    failRun(error)
                    fileTransferTask?.cancel()
                }
            }
        }
        
        stateTask = task
        await task.value
        
        if !task.isCancelled {
            stateTask = nil
            
            if book != nil || (errorMessage == nil && !bookErrors.keys.contains(where: { $0.phase == .state }) && (store.state.books.values.contains(where: { $0.pending }) || store.state.shelvesPending)) {
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
            defer {
                fileTransferTask = nil
                progress = nil
                listedFiles = [:]
            }
            do {
                try await runFileSync()
            } catch {
                if !Task.isCancelled {
                    failRun(error)
                }
            }
        }
    }
    
    private func runFileSync() async throws {
        let keys = store.state.books.keys.sorted()
        beginTransfers(keys)
        if progress != nil {
            listedFiles = try await listFiles()
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                if index >= 8 {
                    try await group.next()
                }
                group.addTask {
                    try await self.transferFiles(key)
                }
            }
            try await group.waitForAll()
        }
    }
    
    private func transferFiles(_ key: String) async throws {
        try Task.checkCancellation()
        progress?.current.insert(key)
        var folders: Folders = [:]
        try await recordBook(key, phase: .file) {
            try await syncFiles(key: key, folders: &folders)
        }
        finishTransfer(key)
    }
    
    private func listFiles() async throws -> [String: [String: GoogleDriveFile]] {
        var listed: [String: [String: GoogleDriveFile]] = [:]
        for file in try await drive.list(query: "'me' in owners") {
            if let parent = file.parents?.first, listed[parent]?[file.name] == nil {
                listed[parent, default: [:]][file.name] = file
            }
        }
        return listed
    }
    
    private func syncFiles(key: String, folders: inout Folders) async throws {
        var failure: Error?
        for fileType in SyncFileType.allCases {
            try Task.checkCancellation()
            do {
                try await uploadFile(key: key, fileType: fileType, folders: &folders)
                if fileType != .epub {
                    try await downloadFile(key: key, fileType: fileType, folders: &folders)
                }
            } catch {
                failure = failure ?? error
            }
        }
        
        do {
            try await cleanupFiles(key: key, folders: &folders)
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
    
    private func recordBook(_ key: String, phase: Phase, _ operation: () async throws -> Void) async throws {
        do {
            try await operation()
            bookErrors[BookErrorKey(key: key, phase: phase)] = nil
        } catch {
            if Task.isCancelled || stopsRun(error) {
                throw error
            }
            let deleted = store.state.books[key]?.deleted ?? false
            bookErrors[BookErrorKey(key: key, phase: phase)] = BookError(title: bookTitle(key, deleted: deleted), message: error.localizedDescription)
        }
    }
    
    private func stopsRun(_ error: Error) -> Bool {
        if case GoogleDriveError.unavailable = error {
            return true
        }
        return error is SyncFormatError || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
    
    private func failRun(_ error: Error) {
        errorMessage = error.localizedDescription
        if error is SyncFormatError {
            unsupportedFormat = true
        }
    }
    
    private func bookTitle(_ key: String, deleted: Bool) -> String {
        (try? SyncStorage.bookDirectory(folder: key, archived: deleted)).flatMap { BookStorage.loadMetadata(root: $0) }?.title ?? key
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
            var folders: Folders = [:]
            try await downloadFile(key: key, fileType: .epub, folders: &folders, onProgress: onProgress)
        }
        
        try Task.checkCancellation()
        
        let metadata = BookStorage.loadMetadata(root: root) ?? book
        guard metadata.epub != nil else {
            throw GoogleDriveError.apiError("This book has not been uploaded yet.", statusCode: nil)
        }
        return metadata
    }
    
    private func changes() async throws -> RemoteChanges {
        var listed: [String: [GoogleDriveFile]]?
        var changed: Set<String> = []
        var cursor: String
        if let saved = cache.cursor {
            cursor = saved
        } else {
            cursor = try await drive.startToken()
            listed = try await listRemote()
        }
        while true {
            let page = try await drive.changes(cursor: cursor)
            try Task.checkCancellation()
            if page.changes.contains(where: { change in
                guard let file = change.file, file.isFolder else { return false }
                return file.name == "Hoshi Reader" || file.parents?.contains(cache.root) == true
            }) {
                listed = try await listRemote()
            }
            for change in page.changes where !change.removed && change.file?.trashed != true {
                if let file = change.file, file.parents?.contains(cache.stateFolder) == true,
                   let key = file.stateKey {
                    changed.insert(key)
                }
            }
            guard let next = page.nextPageToken else { return RemoteChanges(listed: listed, changed: changed, cursor: page.newStartPageToken!) }
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
    
    private func listRemote() async throws -> [String: [GoogleDriveFile]] {
        try await loadLayout()
        let files = try await drive.children(parent: cache.stateFolder)
        try Task.checkCancellation()
        var grouped: [String: [GoogleDriveFile]] = [:]
        for file in files {
            if let key = file.stateKey {
                grouped[key, default: []].append(file)
            }
        }
        return grouped
    }
    
    private func syncBook(_ key: String, files listed: [GoogleDriveFile]? = nil) async throws {
        let files = if let listed { listed } else { try await drive.children(parent: cache.stateFolder, name: key + ".json") }
        try Task.checkCancellation()
        
        var versions = fileVersions(files)
        if unchanged(key, files: files) {
            return
        }
        if cache.bookVersions.removeValue(forKey: key) != nil {
            try saveCache()
        }
        
        var remote = remoteBooks[key].flatMap { $0.versions == versions ? $0.book : nil }
        if remote == nil {
            remote = try await readState(files, merge: SyncBook.merge)
        }
        try mergeBook(key, remote: remote)
        
        guard let book = try store.loadBook(key: key, remote: remote) else {
            if store.state.books[key] != nil {
                store.state.books[key]!.pending = false
                store.state.books[key]!.cleanup = []
                try store.save()
            }
            return
        }
        
        if book.needsUpload(remote: remote) || files.count > 1 {
            let written = try await writeState(book, name: key + ".json", files: files)
            versions = [written.id: written.version]
            remote = book
        }
        
        if store.state.books[key]!.pending, try store.loadBook(key: key, remote: remote) == book {
            store.state.books[key]!.pending = false
            try store.save()
        }
        remoteBooks[key] = (versions, remote!)
        cache.bookVersions[key] = versions
        try saveCache()
    }
    
    private func fileVersions(_ files: [GoogleDriveFile]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.version) })
    }
    
    private func unchanged(_ key: String, files: [GoogleDriveFile]) -> Bool {
        files.count == 1 && store.state.books[key]?.pending == false && cache.bookVersions[key] == fileVersions(files)
    }
    
    private func prefetch(_ remote: RemoteChanges, keys: [String]) async {
        let downloads = keys.compactMap { key -> (key: String, files: [GoogleDriveFile])? in
            guard let files = remote.files(key), !files.isEmpty, !unchanged(key, files: files),
                  remoteBooks[key]?.versions != fileVersions(files) else {
                return nil
            }
            return (key, files)
        }
        for start in stride(from: 0, to: downloads.count, by: 8) {
            await withTaskGroup(of: (String, [GoogleDriveFile], SyncBook?).self) { group in
                for download in downloads[start..<min(start + 8, downloads.count)] {
                    group.addTask {
                        (download.key, download.files, try? await self.readState(download.files, merge: SyncBook.merge))
                    }
                }
                for await (key, files, book) in group {
                    if let book {
                        remoteBooks[key] = (fileVersions(files), book)
                    }
                }
            }
        }
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
        
        var local = try store.loadBook(key: key, remote: remote)!
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
    
    private func uploadFile(key: String, fileType: SyncFileType, folders: inout Folders) async throws {
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
        
        let folder = try await fileFolder(&folders, key: key, generation: record.generation, create: true)
        if listedFiles[folder!]?[name] == nil {
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
    
    private func fileFolder(_ folders: inout Folders, key: String, generation: Int, create: Bool) async throws -> String? {
        if let folder = folders[key]?[generation] {
            return folder
        }
        var folder = listedFiles[cache.bookFolder]?[key].flatMap { listedFiles[$0.id]?[String(generation)] }?.id
        if folder == nil {
            folder = try await drive.fileFolder(books: cache.bookFolder, key: key, generation: generation, create: create)
        }
        folders[key, default: [:]][generation] = folder
        return folder
    }
    
    private func canPublish(key: String, fileType: SyncFileType, source: Int64, generation: Int) -> Bool {
        let record = store.state.books[key]!
        return record.generation == generation && record.sources[fileType] == source
            && (!record.deleted || fileType == .cover)
            && (record.files[fileType]?.modified ?? .min) <= source
    }
    
    private func downloadFile(key: String, fileType: SyncFileType, folders: inout Folders, onProgress: @MainActor @Sendable @escaping (Double) -> Void = { _ in }) async throws {
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
        
        let folder = try await fileFolder(&folders, key: key, generation: record.generation, create: false)
        
        let data = try await drive.download(fileName: name, folder: folder, listed: folder.flatMap { listedFiles[$0]?[name] }, onProgress: onProgress)
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
    
    private func cleanupFiles(key: String, folders: inout Folders) async throws {
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
            
            let folder = try await fileFolder(&folders, key: key, generation: generation, create: false)
            
            var recent = false
            if let folder, generation < book.generation {
                try await GoogleDriveClient.shared.trashFile(fileId: folder)
                folders[key]?[generation] = nil
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
