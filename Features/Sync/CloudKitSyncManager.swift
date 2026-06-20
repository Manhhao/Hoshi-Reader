//
//  CloudKitSyncManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CloudKit
import OSLog

actor CloudKitSyncManager {
    
    static let shared: CloudKitSyncManager = .init()
    
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CloudKitSync"
    )
    
    static var container: CKContainer { CKContainer(identifier: "iCloud.de.manhhao.hoshi") }
    
    private static let prioritizedZoneIDs = [CKRecordZone.ID(zoneName: CloudKitBookFile.zoneName)]
    
    nonisolated private var logger: Logger { Self.logger }
    
    private var eventHandlers: [UUID: @MainActor (CloudKitSyncManager.Event) -> Void] = [:]
    
    private var cloudKitData: CloudKitData {
        didSet {
            do {
                try persistCloudKitData()
            } catch {
                logger.error("Failed to persist CloudKit state: \(error, privacy: .public)")
            }
        }
    }
    
    private var _syncEngine: CKSyncEngine? = nil
    
    private var syncEngine: CKSyncEngine {
        if _syncEngine == nil {
            initializeSyncEngineWithoutCheck()
        }
        return _syncEngine!
    }
    
    private init() {
        do {
            let cloudKitData = try BookStorage.load(CloudKitData.self, from: Self.cloudKitDataURL)
            self.cloudKitData = cloudKitData ?? CloudKitData()
        } catch {
            self.cloudKitData = CloudKitData()
            logger.error("Failed to load CloudKit state from stroage: \(error)")
        }
    }
    
    private func initializeSyncEngineWithoutCheck() {
        let configuration = CKSyncEngine.Configuration(
            database: Self.container.privateCloudDatabase,
            stateSerialization: cloudKitData.stateSerialization,
            delegate: self
        )
        _syncEngine = CKSyncEngine(configuration)
        logger.debug("CKSyncEngine initialized")
    }
    
    func initialize() async {
        do {
            let allMetadata = try BookStorage.loadAllBooks()
            try await resolveUUIDConflicts(books: allMetadata)
            initializeSyncEngineWithoutCheck()
            try await uploadLocalOnlyData()
        } catch {
            logger.error("Failed to initialize sync manager: \(error)")
        }
    }
    
    func disableSync() {
        do {
            try persistCloudKitData()
        } catch {
            logger.error("Failed to persist CloudKit state when disabling CKSyncEngine: \(error, privacy: .public)")
        }
        _syncEngine = nil
        logger.debug("CKSyncEngine disabled")
    }
}

// MARK: - CKSyncEngineDelegate
extension CloudKitSyncManager: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            handleStateUpdate(stateUpdate)
        case .fetchedRecordZoneChanges(let fetchedRecordZoneChanges):
            handleFetchedRecordZoneChanges(fetchedRecordZoneChanges)
        case .sentRecordZoneChanges(let sentRecordZoneChanges):
            handleSentRecordZoneChanges(sentRecordZoneChanges)
        case .accountChange(let accountChange):
            handleAccountChange(accountChange)
        case .fetchedDatabaseChanges, .sentDatabaseChanges:
            break
        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges, .didFetchChanges, .didFetchRecordZoneChanges, .didSendChanges:
            break
        @unknown default:
            logger.info("Received unknown CKSyncEngine event: \(event, privacy: .public)")
        }
    }
    
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pendingRecordZoneChanges = syncEngine.state.pendingRecordZoneChanges
        let filteredChanges = pendingRecordZoneChanges.filter { scope.contains($0) }
        
        let books = self.cloudKitData.books
        let shelves = self.cloudKitData.shelves
        
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: filteredChanges) { recordID in
            let (uuid, fileType): (UUID, CloudKitFileType)
            do {
                (uuid, fileType) = try CKRecord.parseRecordName(recordID.recordName)
            } catch {
                logger.error("Failed to parse record name \(recordID.recordName, privacy: .public): \(error, privacy: .public)")
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            do {
                if fileType == .shelves {
                    return try shelves.makeRecord()
                }
                guard let cloudFile = books[uuid]?[fileType] else {
                    logger.log("CloudKit file of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public) had become stale before sending to iCloud server")
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    return nil
                }
                let record = try cloudFile.makeRecord()
                return record
            } catch {
                logger.error("Failed to generate CKRecord from file of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public): \(error, privacy: .public)")
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
        }
    }
    
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.scope = .zoneIDs([CloudKitBookFile.zoneID])
        return options
    }
}

// MARK: - Event Handling
private extension CloudKitSyncManager {
    private func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        cloudKitData.stateSerialization = stateUpdate.stateSerialization
    }
    
    private func handleFetchedRecordZoneChanges(_ fetchedRecordZoneChanges: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        for modification in fetchedRecordZoneChanges.modifications {
            let modifiedRecord = modification.record
            let (uuid, fileType): (UUID, CloudKitFileType)
            do {
                (uuid, fileType) = try CKRecord.parseRecordName(modifiedRecord.recordID.recordName)
            } catch {
                logger.error("Failed to parse record name \(modifiedRecord.recordID.recordName, privacy: .public): \(error, privacy: .public)")
                continue
            }
            do {
                try onFetchedRecord(modifiedRecord)
                fire(event: .fetched(uuid: uuid))
            } catch {
                logger.error("Failed to merge new record of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public) when fetching from server: \(error, privacy: .public)")
            }
        }
        
        for deletion in fetchedRecordZoneChanges.deletions {
            let deletedRecordID = deletion.recordID
            let (uuid, fileType): (UUID, CloudKitFileType)
            do {
                (uuid, fileType) = try CKRecord.parseRecordName(deletedRecordID.recordName)
            } catch {
                logger.error("Failed to parse record name: \(deletedRecordID.recordName, privacy: .public): \(error, privacy: .public)")
                continue
            }
            do {
                if fileType == .metadata,
                   let metadata = try cloudKitData.books[uuid]?[fileType]?.decode(to: BookMetadata.self) {
                    try deleteLocal(books: [metadata])
                }
                cloudKitData.books[uuid]?[fileType] = nil
                fire(event: .delete(.book(uuid: uuid)))
            } catch {
                logger.error("Failed to delete local file of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public) when fetching deletion: \(error, privacy: .public)")
            }
        }
    }
    
    private func handleSentRecordZoneChanges(_ sentRecordZoneChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        
        var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
        
        // save
        let savedRecords = sentRecordZoneChanges.savedRecords
        
        for savedRecord in savedRecords {
            let (uuid, fileType): (UUID, CloudKitFileType)
            do {
                (uuid, fileType) = try CKRecord.parseRecordName(savedRecord.recordID.recordName)
            } catch {
                logger.error("Failed to parse record name: \(savedRecord.recordID.recordName, privacy: .public): \(error, privacy: .public)")
                continue
            }
            if fileType == .shelves {
                self.cloudKitData.shelves.setLastKnownRecordIfNewer(savedRecord)
            } else {
                self.cloudKitData.books[uuid]?[fileType]?.setLastKnownRecordIfNewer(savedRecord)
            }
            fire(event: .sent(uuid: uuid, success: true))
        }
        
        for failedRecordSave in sentRecordZoneChanges.failedRecordSaves {
            let failedRecord = failedRecordSave.record
            let (uuid, fileType): (UUID, CloudKitFileType)
            do {
                (uuid, fileType) = try CKRecord.parseRecordName(failedRecord.recordID.recordName)
            } catch {
                logger.error("Failed to parse record name: \(failedRecord.recordID.recordName, privacy: .public): \(error, privacy: .public)")
                continue
            }
            let error = failedRecordSave.error
            
            switch error.code {
            case .serverRecordChanged:
                let serverRecord = error.serverRecord
                guard let serverRecord else {
                    logger.error("CloudKit reported a conflict without a server record for \(failedRecord.recordID.recordName, privacy: .public)")
                    continue
                }
                do {
                    try onFetchedRecord(serverRecord)
                    if fileType == .shelves {
                        self.cloudKitData.shelves.localModificationDate = .now
                    } else {
                        self.cloudKitData.books[uuid]?[fileType]?.localModificationDate = .now
                    }
                    pendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                } catch {
                    logger.error("Failed to merge new record of record name \(serverRecord.recordID.recordName, privacy: .public) when solving merge conflicts: \(error, privacy: .public)")
                }
            case .zoneNotFound:
                let recordZoneID = failedRecord.recordID.zoneID
                pendingDatabaseChanges.append(.saveZone(CKRecordZone(zoneID: recordZoneID)))
                fallthrough
            case .unknownItem:
                pendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                if fileType == .shelves {
                    self.cloudKitData.shelves.lastKnownRecord = nil
                } else {
                    self.cloudKitData.books[uuid]?[fileType]?.lastKnownRecord = nil
                }
            case .quotaExceeded:
                fire(event: .error(.quotaExceeded))
            default:
                logger.error("Saving record \(failedRecord.recordID.recordName, privacy: .public) failed with unhandled error: \(error, privacy: .public)")
            }
            
        }
        syncEngine.state.add(pendingRecordZoneChanges: pendingRecordZoneChanges)
        syncEngine.state.add(pendingDatabaseChanges: pendingDatabaseChanges)
        
        // why do we need this??? Without it the `CKSyncEngine` will not send pending database changes. Probably bug
        if !pendingDatabaseChanges.isEmpty {
            Task.detached {
                try? await self.syncEngine.sendChanges()
            }
        }
    }
    
    private func handleAccountChange(_ accountChange: CKSyncEngine.Event.AccountChange) {
        switch accountChange.changeType {
        case .signIn:
            syncEngine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneName: CloudKitBookFile.zoneName)),
            ])
            fire(event: .account(.signIn))
        case .signOut:
            do {
                try deleteLocalBooksWithoutEpub()
            } catch {
                logger.error("Failed to delete books without epub file when logging out")
            }
            disableSync()
            self.cloudKitData = CloudKitData()
            fire(event: .account(.signOut))
        case .switchAccounts(previousUser: let previousRecordID, currentUser: let currentRecordID):
            guard previousRecordID.recordName != currentRecordID.recordName else { return }
            do {
                try deleteLocalBooksWithoutEpub()
            } catch {
                logger.error("Failed to delete books without epub file when switching accounts")
            }
            self.cloudKitData = CloudKitData()
            disableSync()
            fire(event: .account(.accountChanged))
            Task {
                await initialize()
            }
        @unknown default:
            break
        }
    }
}

// MARK: - Fetching Data
extension CloudKitSyncManager {
    
    enum InternalError: LocalizedError {
        case unmanagedFile(UUID, CloudKitFileType)
    }
    
    private func onFetchedRecord(_ record: CKRecord) throws {
        let (uuid, fileType) = try CKRecord.parseRecordName(record.recordID.recordName)
        if fileType != .shelves, cloudKitData.books[uuid] == nil {
            cloudKitData.books[uuid] = [:]
        }
        
        if fileType != .shelves, cloudKitData.books[uuid]![fileType] == nil {
            try replaceIfNewer(record: record)
            return
        }
        
        switch fileType {
        case .shelves:
            try mergeShelves(record: record)
        case .statistics:
            try mergeStats(record: record)
        case .highlights:
            try mergeHighlights(record: record)
        default:
            try replaceIfNewer(record: record)
        }
    }
    
    private func replaceIfNewer(record: CKRecord) throws {
        let (uuid, fileType) = try CKRecord.parseRecordName(record.recordID.recordName)
        let localFile = cloudKitData.books[uuid]![fileType]
        
        var shouldReplace = false
        if let localFile {
            shouldReplace = try record.localModificationDate > localFile.localModificationDate
        } else {
            shouldReplace = true
        }
        
        if shouldReplace {
            let fileURL = try record.fileURL
            let directoryURL = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data: Data
            if fileType.isAssetType {
                let assetURL = try record.assetURL
                data = try Data(contentsOf: assetURL)
            } else {
                data = try record.contentData
            }
            try data.write(to: fileURL, options: .atomic)
            cloudKitData.books[uuid]![fileType] = try CloudKitBookFile(record: record)
        } else {
            cloudKitData.books[uuid]![fileType]!.setLastKnownRecordIfNewer(record)
        }
    }
    
    private func mergeStats(record: CKRecord) throws {
        let remoteStats = try record.mapData(to: [Statistics].self)
        let (uuid, fileType) = try CKRecord.parseRecordName(record.recordID.recordName)
        let fileURL = try record.fileURL
        guard var localFile = cloudKitData.books[uuid]![fileType] else {
            throw InternalError.unmanagedFile(uuid, fileType)
        }
        
        let localStats = try localFile.decode(to: [Statistics].self)
        let mergedStats = Merger.mergeStatistics(localStatistics: localStats, externalStatistics: remoteStats, syncMode: .merge)
        
        try BookStorage.saveLocal(mergedStats, url: fileURL)
        localFile.setLastKnownRecordIfNewer(record)
        cloudKitData.books[uuid]![fileType] = localFile
    }
    
    private func mergeHighlights(record: CKRecord) throws {
        let remoteHighlights = try record.mapData(to: [Highlight].self)
        let (uuid, fileType) = try CKRecord.parseRecordName(record.recordID.recordName)
        let fileURL = try record.fileURL
        guard var localFile = cloudKitData.books[uuid]![fileType] else {
            throw InternalError.unmanagedFile(uuid, fileType)
        }
        
        let localHighlights = try localFile.decode(to: [Highlight].self)
        let ancestorHighlights = try localFile.lastKnownRecord?.mapData(to: [Highlight].self) ?? []
        let mergedStats = Merger.mergeArray(
            local: localHighlights,
            remote: remoteHighlights,
            ancestor: ancestorHighlights,
            id: \.id,
            isOnlyOrderChanged: { Set($0.values) == Set($1.values) },
            mergeTwoNew: { localHlt, _ in localHlt },
            threeWayMerge: { localHlt, _, _ in localHlt}
        )
        
        try BookStorage.saveLocal(mergedStats, url: fileURL)
        localFile.setLastKnownRecordIfNewer(record)
        cloudKitData.books[uuid]![fileType] = localFile
    }
    
    private func mergeShelves(record: CKRecord) throws {
        // We need to design the UI so that each operation by User corresponds to one atomic CKSyncEngine modification. But there is a problem: the jobs submitted to the serial executor may be re-ordered.
        guard let localShelves = try self.cloudKitData.shelves.decode() else {
            let remoteShelves = try record.mapData(to: [BookShelf].self)
            let fileURL = try record.fileURL
            try BookStorage.saveLocal(remoteShelves, url: fileURL)
            self.cloudKitData.shelves.setLastKnownRecordIfNewer(record)
            self.cloudKitData.shelves.localModificationDate = try record.localModificationDate
            return
        }
        
        let remoteShelves = try record.mapData(to: [BookShelf].self)
        let ancestorShelves = try self.cloudKitData.shelves.lastKnownRecord?.mapData(to: [BookShelf].self) ?? []
        var mergedShelves = Merger.mergeArray(
            local: localShelves,
            remote: remoteShelves,
            ancestor: ancestorShelves,
            id: \.name,
            isOnlyOrderChanged: Merger.shelvesOnlyOrderChanged(local:remote:),
            mergeTwoNew: { localShelf, remoteShelf in
                BookShelf(
                    name: localShelf.name,
                    bookIds: Array(Set(localShelf.bookIds).union(Set(remoteShelf.bookIds)))
                )
            },
            threeWayMerge: { localShelf, remoteShelf, ancestorShelf in
                BookShelf(
                    name: localShelf.name,
                    bookIds: Merger.mergeBookIds(
                        local: localShelf.bookIds,
                        remote: remoteShelf.bookIds,
                        ancestor: ancestorShelf.bookIds
                    )
                )
            }
        )
        
        // deduplicate: after three way merging, there may be cases where one book are placed under two shelves
        let allBookIds = self.cloudKitData.books.keys
        for bookId in allBookIds {
            let localContainingShelf = localShelves.first(where: {$0.bookIds.contains(bookId)})
            let remoteContainingShelf = remoteShelves.first(where: {$0.bookIds.contains(bookId)})
            guard let localContainingShelf,
                  let remoteContainingShelf,
                  localContainingShelf.name != remoteContainingShelf.name else {
                continue
            }
            let remoteModificationDate = try record.localModificationDate
            let losingShelfName = self.cloudKitData.shelves.localModificationDate > remoteModificationDate
                ? remoteContainingShelf.name
                : localContainingShelf.name
            if let losingShelfIndex = mergedShelves.firstIndex(where: { $0.name == losingShelfName }) {
                mergedShelves[losingShelfIndex].bookIds.removeAll(where: { $0 == bookId })
            }
        }
        
        let shouldSaveMergedShelves = !Merger.shelvesAreEquivalent(mergedShelves, remoteShelves)
        let fileURL = try record.fileURL
        try BookStorage.saveLocal(mergedShelves, url: fileURL)
        
        self.cloudKitData.shelves.setLastKnownRecordIfNewer(record)
        if shouldSaveMergedShelves {
            self.cloudKitData.shelves.localModificationDate = .now
            syncEngine.state.add(pendingRecordZoneChanges: [
                .saveRecord(self.cloudKitData.shelves.recordID)
            ])
        } else {
            self.cloudKitData.shelves.localModificationDate = try record.localModificationDate
        }
    }
}

// MARK: - Sending Data
extension CloudKitSyncManager {
    func saveCloudFile(uuid: UUID, fileType: CloudKitFileType, fileName: String, folderName: String) {
        if self.cloudKitData.books[uuid] == nil {
            self.cloudKitData.books[uuid] = [:]
        }
        if let cloudFile = self.cloudKitData.books[uuid]?[fileType] {
            self.cloudKitData.books[uuid]?[fileType]!.localModificationDate = .now
            syncEngine.state.add(pendingRecordZoneChanges: [
                .saveRecord(cloudFile.recordID)
            ])
        } else {
            let newCloudKitBookFile = CloudKitBookFile(uuid: uuid, type: fileType, fileName: fileName, folderName: folderName, lastKnownRecordData: nil, localModificationDate: .now)
            self.cloudKitData.books[uuid]![fileType] = newCloudKitBookFile
            syncEngine.state.add(pendingRecordZoneChanges: [
                .saveRecord(newCloudKitBookFile.recordID)
            ])
        }
    }
    
    /// delete a book stored in iCloud server. If this book is not synced, no-op
    func deleteCloudBook(_ book: BookMetadata) {
        guard let files = self.cloudKitData.books[book.id] else { return }
        self.cloudKitData.books[book.id] = nil
        syncEngine.state.add(pendingRecordZoneChanges: files.map({ (_, cloudKitBookFile) in
                .deleteRecord(cloudKitBookFile.recordID)
        }))
        if let epub = CloudKitBookEpub(from: book) {
            Task {
                await deleteCloudEpub(epub)
            }
        }
    }
    
    func saveCloudShelves() {
        self.cloudKitData.shelves.localModificationDate = .now
        syncEngine.state.add(pendingRecordZoneChanges: [
            .saveRecord(
                self.cloudKitData.shelves.recordID
            )
        ])
    }
}

// MARK: - Epub
// Epubs are managed manually instead of `CKSyncEngine`
// Be careful with reentrancy. There may be unexpected behaviors for unexpected user behaviors.
extension CloudKitSyncManager {
    
    private func fetchRecords(folderName: String, fileType: CloudKitFileType, fullDownload: Bool = false) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "folderName == %@", argumentArray: [folderName])
        let query = CKQuery(recordType: fileType.rawValue, predicate: predicate)
        let database = Self.container.privateCloudDatabase
        let (matchResults, _) = try await database.records(
            matching: query,
            inZoneWith: fileType == .book ? CloudKitBookEpub.zoneID : CloudKitBookFile.zoneID,
            desiredKeys: (fileType == .book && fullDownload) ? nil : []
        )
        var records = [CKRecord]()
        for (_, recordResult) in matchResults {
            switch recordResult {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                Self.logger.error("Failed to fetch records of folder name \(folderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return records
    }
    
    private func checkCloudShelvesExist() async throws -> Bool {
        let query = CKQuery(recordType: self.cloudKitData.shelves.recordType, predicate: NSPredicate(value: true))
        let database = Self.container.privateCloudDatabase
        let (matchResults, _) = try await database.records(
            matching: query,
            inZoneWith: CloudKitBookShelves.zoneID,
            desiredKeys: []
        )
        var records = [CKRecord]()
        for (_, recordResult) in matchResults {
            switch recordResult {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                Self.logger.error("Failed to fetch records of bookshelves: \(error)")
            }
        }
        return !records.isEmpty
    }
    
    private func resolveUUIDConflicts(books: [BookMetadata]) async throws {
        let collisions = try await withThrowingTaskGroup { group in
            for book in books {
                group.addTask {
                    let records = try await self.fetchRecords(folderName: book.folder, fileType: .metadata)
                    return (book, records)
                }
            }
            
            var collisions = [BookMetadata: UUID]()
            for try await (book, records) in group {
                if records.isEmpty { continue }
                let firstRecord = records.first!
                do {
                    let (remoteUUID, _) = try CKRecord.parseRecordName(firstRecord.recordID.recordName)
                    let localUUID = book.id
                    if localUUID == remoteUUID { continue }
                    collisions[book] = remoteUUID
                } catch {
                    Self.logger.error("Failed to parse record name \(firstRecord.recordID.recordName, privacy: .public)")
                    continue
                }
            }
            return collisions
        }
        
        await withTaskGroup { group in
            for (metadata, newUUID) in collisions {
                group.addTask {
                    let newMetaData = BookMetadata(
                        id: newUUID,
                        title: metadata.title,
                        epub: metadata.epub,
                        cover: metadata.cover,
                        folder: metadata.folder,
                        lastAccess: metadata.lastAccess
                    )
                    do {
                        let booksDir = try BookStorage.getBooksDirectory()
                        let metadataURL = booksDir.appending(path: metadata.folder).appending(path: FileNames.metadata)
                        try BookStorage.saveLocal(newMetaData, url: metadataURL)
                    } catch {
                        Self.logger.log("Failed to save book metadata of uuid: \(newUUID, privacy: .public)")
                    }
                }
            }
        }
    }
    
    func saveCloudEpub(_ epub: CloudKitBookEpub) async {
        let database = Self.container.privateCloudDatabase
        do {
            let serverRecords = try await fetchRecords(folderName: epub.folderName, fileType: .book)
            if !serverRecords.isEmpty { return }
            let newRecord = try epub.makeNewRecord()
            try await database.save(newRecord)
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try? await database.save(CKRecordZone(zoneName: CloudKitBookEpub.zoneName))
            await saveCloudEpub(epub)
        } catch {
            logger.error("Failed to save epub file of book \(epub.uuid, privacy: .public): \(error.localizedDescription)")
        }
    }
    
    func downloadCloudEpub(_ epub: CloudKitBookEpub) async {
        do {
            if FileManager.default.fileExists(atPath: try epub.fileURL.path(percentEncoded: false)) { return }
            let records = try await fetchRecords(folderName: epub.folderName, fileType: .book, fullDownload: true)
            guard let record = records.first else { return }
            let assetURL = try record.assetURL
            let data = try Data(contentsOf: assetURL)
            let fileURL = try epub.fileURL
            try data.write(to: fileURL, options: .atomic)
            fire(event: .epubDownloaded(uuid: epub.uuid))
            logger.log("Saved epub file \(epub.uuid, privacy: .public) to \(epub.folderName, privacy: .public)/\(epub.fileName, privacy: .public)")
        } catch {
            logger.log("Failed to download epub file \(epub.uuid, privacy: .public) to \(epub.folderName, privacy: .public)/\(epub.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func deleteCloudEpub(_ epub: CloudKitBookEpub) async {
        let records: [CKRecord]
        do {
            records = try await fetchRecords(folderName: epub.folderName, fileType: .book)
        } catch {
            Self.logger.error("Failed to fetch epub of book \(epub.uuid, privacy: .public): \(error)")
            return
        }
        let database = Self.container.privateCloudDatabase
        await withTaskGroup { group in
            for record in records {
                group.addTask {
                    do {
                        try await database.deleteRecord(withID: record.recordID)
                    } catch {
                        Self.logger.error("Failed to delete epub \(record.recordID.recordName, privacy: .public) on iCloud server: \(error)")
                    }
                }
            }
        }
    }
    
    private func uploadLocalOnlyData() async throws {
        let localBooks = try BookStorage.loadAllBooks()
        let localBooksMap = Dictionary(localBooks.map({ ($0.id, $0) })) { old, new in
            new
        }
        let localOnlyBooks = try await withThrowingTaskGroup { group in
            for (uuid, metadata) in localBooksMap {
                group.addTask {
                    return (uuid, try await self.fetchRecords(folderName: metadata.folder, fileType: .metadata))
                }
            }
            
            var localOnlyBooks = [BookMetadata]()
            for try await (uuid, records) in group {
                if records.isEmpty {
                    localOnlyBooks.append(localBooksMap[uuid]!)
                }
            }
            
            return localOnlyBooks
        }
        let booksRootDir = try BookStorage.getBooksDirectory()
        for book in localOnlyBooks {
            let bookDir = booksRootDir.appending(path: book.folder)
            let bookFileURLs: [URL]
            do {
                bookFileURLs = try FileManager.default.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: nil)
            } catch {
                logger.error("Failed to get directory contents of book \(book.id, privacy: .public): \(error)")
                continue
            }
            for fileName in bookFileURLs.map({ $0.lastPathComponent }) {
                guard let fileType = CloudKitFileType(fileName: fileName) else { continue }
                saveCloudFile(
                    uuid: book.id,
                    fileType: fileType,
                    fileName: fileName,
                    folderName: book.folder,
                )
            }
            if let coverName = (book.cover as? NSString)?.lastPathComponent {
                saveCloudFile(
                    uuid: book.id,
                    fileType: .cover,
                    fileName: coverName,
                    folderName: book.folder,
                )
            }
            if let epub = CloudKitBookEpub(from: book) {
                Task {
                    await saveCloudEpub(epub)
                }
            }
        }
        if try await !checkCloudShelvesExist() && self.cloudKitData.shelves.data != nil {
            saveCloudShelves()
        }
    }
}

// MARK: - Local Data processing
extension CloudKitSyncManager {
    
    private static let cloudKitDataFileName = "cloudkit.json"
    
    private static var cloudKitDataURL: URL {
        get throws {
            let cloudKitDirURl = try BookStorage.getCloudKitSyncDirectory()
            let cloudKitDataURL = cloudKitDirURl.appending(path: Self.cloudKitDataFileName)
            return cloudKitDataURL
        }
    }
    
    private func persistCloudKitData() throws {
        let cloudKitDirURl = try BookStorage.getCloudKitSyncDirectory()
        try? FileManager.default.createDirectory(at: cloudKitDirURl, withIntermediateDirectories: true)
        let fileURL = cloudKitDirURl.appending(path: Self.cloudKitDataFileName)
        try BookStorage.saveLocal(cloudKitData, url: fileURL)
    }
    
    func deleteLocal(books: [BookMetadata]) throws {
        let bookRootDir = try BookStorage.getBooksDirectory()
        for book in books {
            let bookDir = bookRootDir.appending(path: book.folder)
            try BookStorage.delete(at: bookDir)
        }
        guard var shelves = BookStorage.loadShelves() else { return }
        for book in books {
            for i in shelves.indices {
                shelves[i].bookIds.removeAll { $0 == book.id }
            }
        }
        try BookStorage.saveLocal(shelves, url: bookRootDir.appending(path: FileNames.shelves))
    }
    
    func deleteLocalBooksWithoutEpub() throws {
        let books = try BookStorage.loadAllBooks()
        let booksWithoutEpub = try books.filter { book in
            guard let fileName = book.epub else { return true }
            let booksDir = try BookStorage.getBooksDirectory()
            let epubURL = booksDir.appending(path: book.folder).appending(path: fileName)
            return !FileManager.default.fileExists(atPath: epubURL.path(percentEncoded: false))
        }
        try deleteLocal(books: booksWithoutEpub)
    }
}

// MARK: - callbacks
extension CloudKitSyncManager {
    nonisolated enum Event {
        enum AccountEvent {
            case signIn
            case signOut
            case accountChanged
        }
        
        enum DeleteEvent {
            case book(uuid: UUID)
            case zones
        }
        
        enum SyncError: LocalizedError {
            case quotaExceeded
        }
        
        case fetched(uuid: UUID)
        case sent(uuid: UUID, success: Bool)
        case epubDownloaded(uuid: UUID)
        case delete(DeleteEvent)
        case account(AccountEvent)
        case error(SyncError)
    }
    
    func observeEvents(_ eventHandler: @escaping @MainActor (CloudKitSyncManager.Event) -> Void) async {
        let id = UUID()
        eventHandlers[id] = eventHandler
        defer { eventHandlers[id] = nil }
        try? await Task.sleep(for: .seconds(Int32.max))
    }
    
    private func fire(event: CloudKitSyncManager.Event) {
        Task {
            let allCallbacks = Array(self.eventHandlers.values)
            await MainActor.run {
                for callBack in allCallbacks {
                    callBack(event)
                }
            }
        }
    }
}
