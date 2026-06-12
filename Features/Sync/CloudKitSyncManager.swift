//
//  CloudKitSyncHanlder.swift
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
    
    static var container: CKContainer { CKContainer(identifier: "iCloud.com.youwu.hoshi") }
    
    private static let prioritizedZoneIDs = [CKRecordZone.ID(zoneName: CloudKitBookFile.zoneName)]
    
    nonisolated private var logger: Logger { Self.logger }
    
    private var eventHandlers: [@MainActor (CloudKitSyncManager.Event) -> Void] = []
    
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
            initializeSyncEngine()
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
    
    func initializeSyncEngine() {
        let configuration = CKSyncEngine.Configuration(
            database: Self.container.privateCloudDatabase,
            stateSerialization: cloudKitData.stateSerialization,
            delegate: self
        )
        _syncEngine = CKSyncEngine(configuration)
        logger.debug("CKSyncEngine initialized")
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
        case .fetchedDatabaseChanges(let fetchedDatabaseChanges):
            handleFetchedDatabaseChanges(fetchedDatabaseChanges)
        case .fetchedRecordZoneChanges(let fetchedRecordZoneChanges):
            handleFetchedRecordZoneChanges(fetchedRecordZoneChanges)
        case .sentDatabaseChanges(let sentDatabaseChanges):
            handleSentDatabaseChanges(sentDatabaseChanges)
        case .sentRecordZoneChanges(let sentRecordZoneChanges):
            handleSentRecordZoneChanges(sentRecordZoneChanges)
        case .accountChange(let accountChange):
            handleAccountChange(accountChange)
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
                return nil
            }
            do {
                if fileType == .shelves {
                    return try shelves.makeRecord()
                }
                guard let cloudFile = books[uuid]?[fileType] else {
                    logger.log("CloudKit file of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public) had become stale before sending to iCloud server")
                    return nil
                }
                let record = try cloudFile.makeRecord()
                return record
            } catch {
                logger.error("Failed to generate CKRecord from file of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
    }
    
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.prioritizedZoneIDs = Self.prioritizedZoneIDs
        return options
    }
}

// MARK: - Event Handling
private extension CloudKitSyncManager {
    private func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        cloudKitData.stateSerialization = stateUpdate.stateSerialization
    }
    
    private func handleFetchedDatabaseChanges(_ fetchedDatabaseChanges: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in fetchedDatabaseChanges.deletions {
            let zoneName = deletion.zoneID.zoneName
            if zoneName == CloudKitBookFile.zoneName || zoneName == CloudKitBookFile.assetZoneName {
                self.cloudKitData.books = [:]
                self.cloudKitData.shelves = .init(localModificationDate: .distantPast)
                fire(event: .delete(.zones))
            }
        }
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
                try deleteLocal(recordID: deletedRecordID)
                cloudKitData.books[uuid]?[fileType] = nil
                fire(event: .delete(.book(uuid: uuid)))
            } catch {
                logger.error("Failed to delete local file of uuid \(uuid, privacy: .public) and type \(fileType, privacy: .public) when fetching deletion: \(error, privacy: .public)")
            }
        }
    }
    
    private func handleSentDatabaseChanges(_ sentDatabaseChanges: CKSyncEngine.Event.SentDatabaseChanges) {
        let deletedZoneIds = sentDatabaseChanges.deletedZoneIDs
        var shouldDeleteCloudKitData = false
        for deletedZoneId in deletedZoneIds {
            if deletedZoneId.zoneName == CloudKitBookFile.zoneName || deletedZoneId.zoneName == CloudKitBookFile.assetZoneName {
                shouldDeleteCloudKitData = true
            }
        }
        if shouldDeleteCloudKitData {
            self.cloudKitData.books = [:]
            self.cloudKitData.shelves = .init(localModificationDate: .distantPast)
            fire(event: .delete(.zones))
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
                    self.cloudKitData.books[uuid]?[fileType]?.localModificationDate = .now
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
                .saveZone(CKRecordZone(zoneName: CloudKitBookFile.assetZoneName)),
            ])
            fire(event: .account(.signIn))
        case .signOut:
            let managedBooks: [BookMetadata]
            do {
                managedBooks = try getBooks(isManaged: true)
            } catch {
                managedBooks = []
                logger.error("Failed to get managed books of previous user when signing out")
            }
            disableSync()
            self.cloudKitData = CloudKitData()
            fire(event: .account(.signOut(managedBooks: managedBooks)))
        case .switchAccounts(previousUser: let previousRecordID, currentUser: let currentRecordID):
            guard previousRecordID.recordName != currentRecordID.recordName else { return }
            self.cloudKitData = CloudKitData()
            initializeSyncEngine()
            fire(event: .account(.accountChanged))
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
        case .metadata:
            try replaceIfNewer(record: record)
        case .bookmark:
            try replaceIfNewer(record: record)
        case .bookinfo:
            try replaceIfNewer(record: record)
        case .shelves:
            try mergeShelves(record: record)
        case .statistics:
            try mergeStats(record: record)
        case .sasayakiPlayback:
            try replaceIfNewer(record: record)
        case .highlights:
            try mergeHighlights(record: record)
        case .cover:
            try replaceIfNewer(record: record)
        case .book:
            try replaceIfNewer(record: record)
        }
    }
    
    private func replaceIfNewer(record: CKRecord) throws {
        let (uuid, fileType) = try CKRecord.parseRecordName(record.recordID.recordName)
        let localFile = cloudKitData.books[uuid]![fileType]
        
        var shouldReplace = false
        if let localFile {
            shouldReplace = try {
                let localModified = localFile.localModificationDate
                let remoteModified = try record.localModificationDate
                if localModified > remoteModified { return false }
                if remoteModified > localModified { return true }
                return false
            }()
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
            if self.cloudKitData.shelves.localModificationDate > remoteModificationDate {
                let remoteIndex = mergedShelves.firstIndex(where: {$0.name == remoteContainingShelf.name})!
                mergedShelves[remoteIndex].bookIds.removeAll(where: {$0 == bookId})
            } else {
                let localIndex = mergedShelves.firstIndex(where: {$0.name == localContainingShelf.name})!
                mergedShelves[localIndex].bookIds.removeAll(where: {$0 == bookId})
            }
        }
        
        let fileURL = try record.fileURL
        try BookStorage.saveLocal(mergedShelves, url: fileURL)
        
        self.cloudKitData.shelves.setLastKnownRecordIfNewer(record)
        self.cloudKitData.shelves.localModificationDate = try record.localModificationDate
    }
}

// MARK: - Sending Data
extension CloudKitSyncManager {
    // a tricky point: when should we modify `self.cloudKitData`? Before `state.add` or after `sentRecordZoneChanges`? Here we choose the way like example in Apple example repo
    
    /// - Parameters:
    ///     - createCloudBook: If this book is not managed by iCloud, should we continue saving this file?
    func saveCloudFile(uuid: UUID, fileType: CloudKitFileType, fileName: String, folderName: String, createCloudBook: Bool = false) {
        if self.cloudKitData.books[uuid] == nil {
            if createCloudBook {
                self.cloudKitData.books[uuid] = [:]
            } else {
                return
            }
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
    func deleteCloudBook(uuid: UUID) {
        guard let files = self.cloudKitData.books[uuid] else { return }
        self.cloudKitData.books[uuid] = nil
        syncEngine.state.add(pendingRecordZoneChanges: files.map({ (_, cloudKitBookFile) in
                .deleteRecord(cloudKitBookFile.recordID)
        }))
    }
    
    func saveCloudShelves() {
        self.cloudKitData.shelves.localModificationDate = .now
        syncEngine.state.add(pendingRecordZoneChanges: [
            .saveRecord(
                CloudKitBookShelves.recordID
            )
        ])
    }
    
    func deleteServerData() {
        syncEngine.state.add(pendingDatabaseChanges: [
            .deleteZone(CKRecordZone.ID(zoneName: CloudKitBookFile.zoneName)),
            .deleteZone(CKRecordZone.ID(zoneName: CloudKitBookFile.assetZoneName))
        ])
    }
    
    func refresh() {
        Task {
            var fetchChangesOptions = CKSyncEngine.FetchChangesOptions()
            fetchChangesOptions.prioritizedZoneIDs = Self.prioritizedZoneIDs
            try? await syncEngine.fetchChanges(fetchChangesOptions)
            try? await syncEngine.sendChanges()
        }
    }
    
    func uploadUnmanagedBooks() throws {
        let unmanagedBooks = try getBooks(isManaged: false)
        for book in unmanagedBooks {
            try uploadUnmanagedBook(book)
        }
    }
    
    func uploadUnmanagedBook(_ book: BookMetadata) throws {
        if self.cloudKitData.books[book.id] != nil { return }
        let booksRootDir = try BookStorage.getBooksDirectory()
        let bookDir = booksRootDir.appending(path: book.folder)
        let bookFileURLs = try FileManager.default.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: nil)
        for fileName in bookFileURLs.map({ $0.lastPathComponent }) {
            guard let fileType = CloudKitFileType(fileName: fileName) else { continue }
            saveCloudFile(
                uuid: book.id,
                fileType: fileType,
                fileName: fileName,
                folderName: book.folder,
                createCloudBook: true
            )
        }
        if let coverName = (book.cover as? NSString)?.lastPathComponent {
            saveCloudFile(
                uuid: book.id,
                fileType: .cover,
                fileName: coverName,
                folderName: book.folder,
                createCloudBook: true
            )
        }
        if let bookName = book.epub {
            saveCloudFile(
                uuid: book.id,
                fileType: .book,
                fileName: bookName,
                folderName: book.folder,
                createCloudBook: true
            )
        }
    }
}

// MARK: - Local Data processing
extension CloudKitSyncManager {
    
    private static let cloudKitDataFileName = "cloudkit.json"
    
    private func getBooks(isManaged: Bool) throws -> [BookMetadata] {
        let managedBookIds = Set(self.cloudKitData.books.keys)
        let localBooks = try BookStorage.loadAllBooks()
        let targetBooks = localBooks.filter({ managedBookIds.contains($0.id) == isManaged })
        return targetBooks
    }
    
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
    
    // Deleting the whole shelf file is not supported
    private func deleteLocal(recordID: CKRecord.ID) throws {
        let recordName = recordID.recordName
        let (uuid, fileType) = try CKRecord.parseRecordName(recordName)
        let fileURL = try cloudKitData.books[uuid]?[fileType]?.fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try BookStorage.delete(at: fileURL)
        }
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
    
    func deleteLocalBooks(isManaged: Bool) throws {
        let targetBooks = try getBooks(isManaged: isManaged)
        try deleteLocal(books: targetBooks)
    }
}

// MARK: - other internal APIs
extension CloudKitSyncManager {
    func isManaged(uuid: UUID) -> Bool { cloudKitData.books[uuid] != nil }
}

// MARK: - callbacks
extension CloudKitSyncManager {
    nonisolated enum Event {
        enum AccountEvent {
            case signIn
            case signOut(managedBooks: [BookMetadata])
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
        case delete(DeleteEvent)
        case account(AccountEvent)
        case error(SyncError)
    }
    
    func addEventHandlers(_ eventHandlers: [@MainActor (CloudKitSyncManager.Event) -> Void]) {
        self.eventHandlers.append(contentsOf: eventHandlers)
    }
    
    private func fire(event: CloudKitSyncManager.Event) {
        Task {
            let allCallbacks = self.eventHandlers
            await MainActor.run {
                for callBack in allCallbacks {
                    callBack(event)
                }
            }
        }
    }
}
