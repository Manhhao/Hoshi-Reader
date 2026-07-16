//
//  CloudKitFile.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CloudKit
import OSLog

nonisolated struct CloudKitData: Codable {
    var books: [UUID: [CloudKitFileType: CloudKitBookFile]] = [:]
    var shelves: CloudKitBookShelves = .init(localModificationDate: .distantPast)
    var stateSerialization: CKSyncEngine.State.Serialization?
}

// MARK: - FileType
nonisolated enum CloudKitFileType: String, Codable, CustomStringConvertible {
    case metadata = "metadata"
    case bookmark = "bookmark"
    case bookinfo = "bookinfo"
    case shelves = "shelves"
    case statistics = "statistics"
    case sasayakiPlayback = "sasayaki_playback"
    case highlights = "highlights"
    case cover = "cover"
    case book = "book"
    
    var description: String { self.rawValue }
    
    var isAssetType: Bool { self == .cover || self == .book }
    
    init?(fileName: String) {
        switch fileName {
        case FileNames.bookinfo:
            self = .bookinfo
        case FileNames.bookmark:
            self = .bookmark
        case FileNames.highlights:
            self = .highlights
        case FileNames.metadata:
            self = .metadata
        case FileNames.sasayakiPlayback:
            self = .sasayakiPlayback
        case FileNames.shelves:
            self = .shelves
        case FileNames.statistics:
            self = .statistics
        default:
            return nil
        }
    }
    
    var fileName: String? {
        switch self {
        case .metadata:
            FileNames.metadata
        case .bookmark:
            FileNames.bookmark
        case .bookinfo:
            FileNames.bookinfo
        case .shelves:
            FileNames.shelves
        case .statistics:
            FileNames.statistics
        case .sasayakiPlayback:
            FileNames.sasayakiPlayback
        case .highlights:
            FileNames.highlights
        case .cover:
            nil
        case .book:
            nil
        }
    }
}

// MARK: - File Protocol
nonisolated protocol CloudKitFile {
    
    var localModificationDate: Date { get set }
    var lastKnownRecordData: Data? { get set }
    var lastKnownRecord: CKRecord? { get set }
    
    static var zoneName: String { get }
    static var zoneID: CKRecordZone.ID { get }
    var recordType: CKRecord.RecordType { get }
    var recordName: String { get }
    var recordID: CKRecord.ID { get }
    
    var type: CloudKitFileType { get }
    func populateFields(record: CKRecord) throws
}

nonisolated extension CloudKitFile {
    
    static var zoneName: String { "HoshiBooks" }
    static var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }
    
    var recordType: CKRecord.RecordType { type.rawValue }
    var recordID: CKRecord.ID { .init(recordName: recordName, zoneID: Self.zoneID) }
    
    @discardableResult
    mutating func setLastKnownRecordIfNewer(_ otherRecord: CKRecord) -> Bool {
        if let localDate = self.lastKnownRecord?.modificationDate {
            if let otherDate = otherRecord.modificationDate,
               localDate < otherDate {
                self.lastKnownRecord = otherRecord
                return true
            }
            return false
        } else {
            self.lastKnownRecord = otherRecord
            return true
        }
    }
    
    var lastKnownRecord: CKRecord? {
        get {
            if let data = self.lastKnownRecordData {
                do {
                    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
                    return CKRecord(coder: unarchiver)
                } catch {
                    CloudKitSyncManager.logger.error("Failed to decode last known CKRecord")
                    return nil
                }
            } else {
                return nil
            }
        }
        
        set {
            if let newValue {
                let archiver = NSKeyedArchiver(requiringSecureCoding: false)
                newValue.encode(with: archiver)
                self.lastKnownRecordData = archiver.encodedData
            } else {
                self.lastKnownRecordData = nil
            }
        }
    }
    
    mutating func resetLastKnownRecord() { lastKnownRecord = nil}
    
    func makeRecord() throws -> CKRecord {
        if let lastKnownRecordData {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: lastKnownRecordData)
            if let record = CKRecord(coder: decoder) {
                try populateFields(record: record)
                return record
            }
        }
        let record = CKRecord(recordType: recordType, recordID: recordID)
        try populateFields(record: record)
        return record
    }
}

// MARK: - Book files
nonisolated struct CloudKitBookFile: Codable {
    let uuid: UUID
    let type: CloudKitFileType
    var fileName: String
    var folderName: String
    var lastKnownRecordData: Data?
    var localModificationDate: Date
    
    init(uuid: UUID, type: CloudKitFileType, fileName: String, folderName: String, lastKnownRecordData: Data? = nil, localModificationDate: Date) {
        self.uuid = uuid
        self.type = type
        self.fileName = fileName
        self.folderName = folderName
        self.lastKnownRecordData = lastKnownRecordData
        self.localModificationDate = localModificationDate
    }
    
    init(record: CKRecord) throws {
        let (uuid, fileType) = try CKRecord.parseRecordName(record.recordID.recordName)
        let fileName = try record.fileName
        let folderName = try record.folderName
        var newFile = CloudKitBookFile(
            uuid: uuid,
            type: fileType,
            fileName: fileName,
            folderName: folderName,
            lastKnownRecordData: nil,
            localModificationDate: .distantPast
        )
        newFile.setLastKnownRecordIfNewer(record)
        newFile.localModificationDate = try record.localModificationDate
        self = newFile
    }
}

nonisolated extension CloudKitBookFile: CloudKitFile {
    
    var recordName: String { "\(uuid.uuidString)___\(type.rawValue)" }
    
    var fileURL: URL {
        get throws {
            let booksDir = try BookStorage.getBooksDirectory()
            return booksDir.appending(path: folderName).appending(path: fileName)
        }
    }
    
    var data: Data {
        get throws {
            return try Data(contentsOf: fileURL)
        }
    }
    
    func decode<T: Decodable>(to type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
    
    func populateFields(record: CKRecord) throws {
        record[.fileName] = fileName
        record[.folderName] = folderName
        if type.isAssetType {
            record[.asset] = CKAsset(fileURL: try fileURL)
        } else {
            record[.contentData] = try data
        }
        record[.localModificationDate] = localModificationDate
    }
}

// MARK: - EPUB
nonisolated struct CloudKitBookEpub {
    static let type: CloudKitFileType = .book
    static let recordType: CKRecord.RecordType = type.rawValue
    static let zoneName = "HoshiBookEpubs"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName)
    
    let uuid: UUID
    let fileName: String
    let folderName: String
    
    init(uuid: UUID, fileName: String, folderName: String) {
        self.uuid = uuid
        self.fileName = fileName
        self.folderName = folderName
    }
    
    init?(from metadata: BookMetadata) {
        guard let fileName = metadata.epub else {
            return nil
        }
        self.uuid = metadata.id
        self.fileName = fileName
        self.folderName = metadata.folder
    }
    
    var recordName: String { "\(uuid.uuidString)___\(Self.type.rawValue)" }
    var recordID: CKRecord.ID { .init(recordName: recordName, zoneID: Self.zoneID) }
    var fileURL: URL {
        get throws {
            let booksDir = try BookStorage.getBooksDirectory()
            return booksDir.appending(path: folderName).appending(path: fileName)
        }
    }
    
    func makeNewRecord() throws -> CKRecord {
        let newRecord = CKRecord(recordType: CloudKitBookEpub.recordType, recordID: recordID)
        newRecord[.asset] = CKAsset(fileURL: try fileURL)
        newRecord[.fileName] = fileName
        newRecord[.folderName] = folderName
        return newRecord
    }
}

// MARK: - Bookshelves
nonisolated struct CloudKitBookShelves: Codable, CloudKitFile {
    
    /// This is necessary when the device is offline, in which case, the metadata in `CKRecord` cannot be updated
    /// because it will be only updated after `sentRecordZoneChanges`
    var localModificationDate: Date = .distantPast
    var lastKnownRecordData: Data? = nil
    
    init(localModificationDate: Date, lastKnownRecordData: Data? = nil) {
        self.localModificationDate = localModificationDate
        self.lastKnownRecordData = lastKnownRecordData
    }
    
    init(record: CKRecord) throws {
        var newShelves = CloudKitBookShelves(localModificationDate: .distantPast, lastKnownRecordData: nil)
        newShelves.setLastKnownRecordIfNewer(record)
        newShelves.localModificationDate = try record.localModificationDate
        self = newShelves
    }
    
    func populateFields(record: CKRecord) throws {
        if let data = try data {
            record[.contentData] = data
        }
        record[.localModificationDate] = localModificationDate
    }
    
    var fileURL: URL {
        get throws {
            let booksDir = try BookStorage.getBooksDirectory()
            return booksDir.appending(path: FileNames.shelves)
        }
    }
    
    var data: Data? {
        get throws {
            let fileURL = try fileURL
            if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                return nil
            }
            return try Data(contentsOf: fileURL)
        }
    }
    
    func decode() throws -> [BookShelf]? {
        guard let data = try self.data else {
            return nil
        }
        return try JSONDecoder().decode([BookShelf].self, from: data)
    }
    
    static let type = CloudKitFileType.shelves
    static let recordName: String = type.rawValue
    
    // conformance
    var recordName: String { Self.recordName }
    var type: CloudKitFileType { Self.type }
}

// MARK: - CKRecord
nonisolated extension CKRecord.FieldKey {
    static let fileName = "fileName"
    static let folderName = "folderName"
    static let contentData = "contentData"
    static let asset = "asset"
    static let localModificationDate = "localModificationDate"
}

enum CloudKitFileError: LocalizedError {
    case invalidRecordName
    case invalidContentData
    case invalidFolderName
    case invalidFileName
    case invalidAssetURL
    case invalidLocalModificationDate
}

nonisolated extension CKRecord {
    
    var fileType: CloudKitFileType {
        get throws(CloudKitFileError) {
            guard let (_, fileType) = try? Self.parseRecordName(recordID.recordName) else {
                throw .invalidRecordName
            }
            return fileType
        }
    }
    
    var contentData: Data {
        get throws(CloudKitFileError) {
            guard try !fileType.isAssetType,
                  let data = self[.contentData] as? Data else {
                throw .invalidContentData
            }
            return data
        }
    }
    
    func mapData<T: Decodable>(to type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: contentData)
    }
    
    var folderName: String {
        get throws(CloudKitFileError) {
            guard let folderName = self[.folderName] as? String else {
                throw .invalidFolderName
            }
            return folderName
        }
    }
    
    var fileName: String {
        get throws(CloudKitFileError) {
            guard let fileName = self[.fileName] as? String else {
                throw .invalidFileName
            }
            return fileName
        }
    }
    
    var fileURL: URL {
        get throws {
            let booksDir = try BookStorage.getBooksDirectory()
            if try fileType == .shelves {
                return booksDir.appending(path: FileNames.shelves)
            }
            return try booksDir.appending(path: folderName).appending(path: fileName)
        }
    }
    
    var assetURL: URL {
        get throws(CloudKitFileError) {
            guard try fileType.isAssetType,
                  let asset = self[.asset] as? CKAsset,
                  let assetURL = asset.fileURL else {
                throw .invalidAssetURL
            }
            return assetURL
        }
    }
    
    var localModificationDate: Date {
        get throws(CloudKitFileError) {
            guard let date = self[.localModificationDate] as? Date else {
                throw .invalidLocalModificationDate
            }
            return date
        }
    }
    
    static func parseRecordName(_ recordName: String) throws(CloudKitFileError) -> (UUID, CloudKitFileType) {
        if recordName == CloudKitBookShelves.recordName {
            return (UUID(), .shelves)
        }
        let recordNameSplit = recordName.split(separator: "___")
        if recordNameSplit.count != 2 {
            throw .invalidRecordName
        }
        let (uuid, fileTypeRaw) = (UUID(uuidString: String(recordNameSplit[0])), String(recordNameSplit[1]))
        guard let fileType = CloudKitFileType(rawValue: fileTypeRaw),
              let uuid else {
            throw .invalidRecordName
        }
        return (uuid, fileType)
    }
}

// MARK: - UI
nonisolated enum CloudKitStatus: String, Codable {
    case none
    case signOut
    case quotaExceeded
    
    var title: String {
        switch self {
        case .none:
            ""
        case .signOut:
            String(localized:"Signed Out")
        case .quotaExceeded:
            String(localized:"Quota Exceeded")
        }
    }
    
    var message: String {
        switch self {
        case .none:
            ""
        case .signOut:
            String(localized: "You have logged out of iCloud account.")
        case .quotaExceeded:
            String(localized: "iCloud syncing has been disabled because you have run out of iCloud space. Please free up space or upgrade your storage.")
        }
    }
}
