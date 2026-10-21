import Foundation
import Network

nonisolated struct GoogleDriveSyncCache: Codable {
    var cursor: String?
    var root = ""
    var stateFolder = ""
    var bookFolder = ""
    var bookVersions: [String: [String: String]] = [:]
    var bookFolders: [String: String]?
    var attachPending: Bool?
    var replacedRoot: Bool?
    var uploadSessions: [String: String]?
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
        var transfer: Transfer?
        var coverURL: URL?
        var size: Int64?
        
        var id: String { key }
    }
    
    enum TransferState {
        case moving
        case interrupted
    }
    
    struct Transfer {
        var direction: Direction
        var done: Int64
        var total: Int64
        var state: TransferState
    }
    
    struct Moving {
        var direction: Direction
        var done: Int64 = 0
        var total: Int64
    }
    
    struct Flow {
        var done: Int64 = 0
        var total: Int64 = 0
        var counted: Set<String> = []
        var speed: Double = 0
        var sampled: (date: Date, done: Int64)?
        var started: Date?
    }
    
    struct FlowSummary {
        var done: Int64
        var total: Int64
        var speed: Double
        var remaining: TimeInterval?
    }
    
    struct Progress {
        var done: Int
        var total: Int
        var current: Set<String> = []
    }
    
    struct Job: Equatable {
        var key: String
        var epub: Bool
    }
    
    struct BookErrorKey: Hashable {
        var key: String
        var phase: Phase
    }
    
    struct BookError {
        var title: String
        var message: String
    }
    
    enum AttachChoice: String {
        case merge
        case device
        case cloud
    }
    
    struct AttachPending: Error {}
    
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
    private var stopped = false
    var unsupportedFormat = false
    var attachDismissed = false
    var transfers: [QueueItem] = []
    var progress: Progress?
    var bookErrors: [BookErrorKey: BookError] = [:]
    var jobs: [Job] = []
    var active = 0
    var epubs = 0
    var priority = 0
    var downloads: Set<String> = []
    var busy: Set<String> = []
    var moving: [String: Moving] = [:]
    var interrupted: [String: Transfer] = [:]
    var uploadFlow = Flow()
    var downloadFlow = Flow()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    
    var isSyncing: Bool { stateTask != nil || fileTransferTask != nil }
    
    var queue: [QueueItem] {
        var queue = transfers
        for index in queue.indices {
            queue[index].transfer = transfer(queue[index].key)
        }
        for (id, error) in bookErrors.sorted(by: { ($0.key.key, $0.key.phase) < ($1.key.key, $1.key.phase) }) {
            if let index = queue.firstIndex(where: { $0.key == id.key }) {
                queue[index].error = queue[index].error ?? error.message
            } else {
                queue.append(QueueItem(key: id.key, title: error.title, direction: nil, error: error.message))
            }
        }
        return queue
    }
    
    var uploadSummary: FlowSummary? {
        summary(uploadFlow, direction: .upload)
    }
    
    var downloadSummary: FlowSummary? {
        summary(downloadFlow, direction: .download)
    }
    
    private func transfer(_ key: String) -> Transfer? {
        if let moving = moving[key] {
            return Transfer(direction: moving.direction, done: min(moving.done, moving.total), total: moving.total, state: .moving)
        }
        return interrupted[key]
    }
    
    private func movingBytes(_ direction: Direction) -> Int64 {
        moving.values.filter { $0.direction == direction }.reduce(0) { $0 + $1.done }
    }
    
    private func summary(_ flow: Flow, direction: Direction) -> FlowSummary? {
        guard progress != nil else { return nil }
        let done = min(flow.done + movingBytes(direction), flow.total)
        guard done < flow.total else { return nil }
        let remaining = flow.started.flatMap { started -> TimeInterval? in
            guard Date().timeIntervalSince(started) >= 60, flow.speed > 1 else { return nil }
            return Double(flow.total - done) / flow.speed
        }
        return FlowSummary(done: done, total: flow.total, speed: flow.speed, remaining: remaining)
    }
    
    func sampleFlows() {
        sample(&uploadFlow, moving: movingBytes(.upload))
        sample(&downloadFlow, moving: movingBytes(.download))
    }
    
    private func sample(_ flow: inout Flow, moving: Int64) {
        let now = Date()
        let done = flow.done + moving
        if let sampled = flow.sampled {
            let elapsed = now.timeIntervalSince(sampled.date)
            if elapsed > 0 {
                let rate = Double(max(done - sampled.done, 0)) / elapsed
                flow.speed += (rate - flow.speed) * min(elapsed / 30, 1)
            }
        }
        if done > 0, flow.started == nil {
            flow.started = now
        }
        flow.sampled = (now, done)
    }
    
    var enabled: Bool {
        UserConfig.shared.enableSync && UserConfig.shared.syncProvider == .gdrive
        && GoogleDriveAuth.shared.isAuthenticated(for: .gdrive) && !stopped && cache.attachPending != true
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
        cancelFileTransfers()
        
        await GoogleDriveClient.shared.stop()
        await stateTask?.value
        await fileTransferTask?.value
        
        stateTask = nil
        fileTransferTask = nil
        downloads = []
        transfers = []
        progress = nil
        bookErrors = [:]
        moving = [:]
        interrupted = [:]
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
        cache = GoogleDriveSyncCache(root: cache.root, attachPending: cache.attachPending, replacedRoot: cache.replacedRoot)
        try saveCache()
        
        start()
    }
    
    func setAttachPending() {
        cache.attachPending = true
        attachDismissed = false
        cancelFileTransfers()
    }
    
    func attach(_ choice: AttachChoice) async throws {
        await stop()
        GoogleDriveClient.shared.resume()
        defer { start() }
        
        if choice == .device {
            cache.attachPending = nil
            cache.replacedRoot = true
            try saveCache()
            do {
                try await drive.renameRoot()
            } catch {
                cache.attachPending = true
                try saveCache()
                throw error
            }
            try store.removeDeletionRecords()
        }
        let layout = try await drive.layout()
        if choice == .cloud {
            try clearLibrary()
        }
        cache.root = layout.root
        cache.stateFolder = layout.state
        cache.bookFolder = layout.books
        cache.attachPending = nil
        try saveCache()
    }
    
    private func clearLibrary() throws {
        if let reader = ReaderIntentBridge.shared.reader {
            reader.stopTracking()
            reader.sasayakiPlayer.teardown()
            reader.bookDeleted = true
        }
        
        let books = try BookStorage.getBooksDirectory()
        try FileManager.default.removeItem(at: books)
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        try store.reload()
        NotificationCenter.default.post(name: SyncStorage.booksChangedNotification, object: nil)
    }
    
    func resetConnection(restoringBackup: Bool = false) throws {
        if restoringBackup {
            try store.reload()
        }
        
        try store.prepareLibrary()
        try removePlaceholders()
        try store.resetSyncState()
        cache = GoogleDriveSyncCache(replacedRoot: cache.replacedRoot)
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
        if book != nil {
            previous?.cancel()
        }
        
        let task = Task {
            await previous?.value
            
            do {
                try await runSync(book: book)
            } catch {
                if !Task.isCancelled {
                    failRun(error)
                    cancelFileTransfers()
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
            startFileSync()
        }
    }
    
    func startFileSync() {
        guard enabled, !unsupportedFormat, errorMessage == nil, stateTask == nil, !cache.bookFolder.isEmpty else { return }
        if fileTransferTask != nil {
            enqueue(reset: false)
            return
        }
        fileTransferTask = Task {
            var published = false
            do {
                published = try await runFileSync()
            } catch {
                if !Task.isCancelled {
                    failRun(error)
                }
            }
            fileTransferTask = nil
            progress = nil
            let queued = !jobs.isEmpty
            jobs = []
            guard !Task.isCancelled else { return }
            if published {
                Task {
                    await sync()
                }
            } else if queued {
                startFileSync()
            }
        }
    }
    
    func downloadAll() {
        downloads.formUnion(missingBooks)
        startFileSync()
    }
    
    func wait() async {
        await withCheckedContinuation { waiting.append($0) }
    }
    
    func wake() {
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume() }
    }
    
    private func cancelFileTransfers() {
        fileTransferTask?.cancel()
        wake()
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
