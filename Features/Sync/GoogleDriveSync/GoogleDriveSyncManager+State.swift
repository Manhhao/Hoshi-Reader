import Foundation

private struct RemoteChanges {
    var listed: [String: [GoogleDriveFile]]?
    var changed: [String: [GoogleDriveFile]]
    var cursor: String
    
    func contains(_ key: String) -> Bool {
        changed[key] != nil || listed?[key] != nil
    }
    
    static func cachedFiles(_ key: String, versions: [String: String]?) -> [String: GoogleDriveFile]? {
        versions?.reduce(into: [:]) { files, version in
            files[version.key] = GoogleDriveFile(id: version.key, name: key + ".json", mimeType: "", md5Checksum: version.value, createdTime: "")
        }
    }
    
    func files(_ key: String, cached: [String: String]?) -> [GoogleDriveFile]? {
        let changed = changed[key]
        if changed == nil, let listed {
            return listed[key] ?? []
        }
        guard var files = Self.cachedFiles(key, versions: cached) else { return nil }
        for file in changed ?? [] {
            files[file.id] = file.trashed == true ? nil : file
        }
        return files.values.sorted { $0.id < $1.id }
    }
}

extension GoogleDriveSyncManager {
    func runSync(book: BookMetadata?) async throws {
        do {
            try await syncState(book: book)
        } catch {
            try? saveCache()
            throw error
        }
        try saveCache()
    }
    
    private func syncState(book: BookMetadata?) async throws {
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
        let keys = Set(remote.changed.keys).union(pending).union((remote.listed ?? [:]).keys).subtracting([".shelves"]).sorted()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                if index >= 8 {
                    try await group.next()
                }
                let files = remote.files(key, cached: cache.bookVersions[key])
                group.addTask {
                    try await self.syncState(key, files: files)
                }
            }
            try await group.waitForAll()
        }
        let failed = keys.contains { bookErrors[BookErrorKey(key: $0, phase: .state)] != nil }
        if !failed && !store.state.books.values.contains(where: { !$0.attached && !$0.deleted }) {
            if remote.contains(".shelves") || store.state.shelvesPending {
                try await syncShelves()
            }
            cache.cursor = remote.cursor
            lastSync = .now
            unsupportedFormat = false
        }
    }
    
    private func syncState(_ key: String, files: [GoogleDriveFile]?) async throws {
        try await recordBook(key, phase: .state) {
            try await syncBook(key, files: files)
        }
    }
    
    private func changes() async throws -> RemoteChanges {
        var listed: [String: [GoogleDriveFile]]?
        var changed: [String: [GoogleDriveFile]] = [:]
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
            for change in page.changes where !change.removed {
                if let file = change.file, file.parents?.contains(cache.stateFolder) == true,
                   let key = file.stateKey {
                    changed[key, default: []].append(file)
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
    
    private func remoteState(_ key: String, files listed: [GoogleDriveFile]?) async throws -> (files: [GoogleDriveFile], book: SyncBook?)? {
        guard let files = listed else {
            let cached = RemoteChanges.cachedFiles(key, versions: cache.bookVersions[key]).map { Array($0.values) }
            let files = if let cached { cached } else { try await drive.children(parent: cache.stateFolder, name: key + ".json") }
            try Task.checkCancellation()
            cache.bookVersions[key] = nil
            do {
                return (files, try await readState(files, merge: SyncBook.merge))
            } catch GoogleDriveError.apiError {
                let files = try await drive.children(parent: cache.stateFolder, name: key + ".json")
                return (files, try await readState(files, merge: SyncBook.merge))
            }
        }
        try Task.checkCancellation()
        
        let versions = fileVersions(files)
        if files.count == 1, store.state.books[key]?.pending == false, cache.bookVersions[key] == versions {
            return nil
        }
        cache.bookVersions[key] = nil
        
        if let cached = remoteBooks[key], cached.versions == versions {
            return (files, cached.book)
        }
        return (files, try await readState(files, merge: SyncBook.merge))
    }
    
    private func syncBook(_ key: String, files listed: [GoogleDriveFile]? = nil) async throws {
        guard let (files, state) = try await remoteState(key, files: listed) else { return }
        var remote = state
        var versions = fileVersions(files)
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
            versions = [written.id: written.md5Checksum ?? ""]
            remote = book
        }
        
        if store.state.books[key]!.pending, try store.loadBook(key: key, remote: remote) == book {
            store.state.books[key]!.pending = false
            try store.save()
        }
        remoteBooks[key] = (versions, remote!)
        cache.bookVersions[key] = versions
    }
    
    private func fileVersions(_ files: [GoogleDriveFile]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.md5Checksum ?? "") })
    }
    
    func readState<T: Codable & Sendable>(_ files: [GoogleDriveFile], merge: (T, T) -> T) async throws -> T? {
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
    
    func mergeBook(_ key: String, remote: SyncBook?) throws {
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
}
