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
    
    struct BookErrorKey: Hashable {
        var key: String
        var phase: Phase
    }
    
    struct BookError {
        var title: String
        var message: String
    }
    
    static let shared = GoogleDriveSyncManager()
    var errorMessage: String?
    var lastSync: Date?
    let store = SyncStorage.shared
    let drive = GoogleDriveSyncHandler.shared
    private let pathMonitor = NWPathMonitor()
    var cache = GoogleDriveSyncCache()
    var remoteBooks: [String: (versions: [String: String], book: SyncBook)] = [:]
    
    private var stateTask: Task<Void, Never>?
    private var fileTransferTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    var downloadTask: Task<Void, Never>?
    private var stopped = false
    var unsupportedFormat = false
    var transfers: [QueueItem] = []
    var progress: Progress?
    var bookErrors: [BookErrorKey: BookError] = [:]
    
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
                try await runSync(book: book)
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
    
    func recordBook(_ key: String, phase: Phase, _ operation: () async throws -> Void) async throws {
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
    
    func bookTitle(_ key: String, deleted: Bool) -> String {
        (try? SyncStorage.bookDirectory(folder: key, archived: deleted)).flatMap { BookStorage.loadMetadata(root: $0) }?.title ?? key
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
    
    func saveCache() throws {
        try SyncFormat.encode(cache).write(to: cacheURL(), options: .atomic)
    }
}
