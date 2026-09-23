//
//  TtuDriveHandler.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum TtuSyncDirection: Equatable {
    case importFromTtu
    case exportToTtu
    case synced
}

struct TtuDriveFileList: Codable {
    let files: [TtuDriveFile]
    let nextPageToken: String?
}

struct TtuDriveFile: Codable {
    let id: String
    let name: String
    var size: String?
    var parents: [String]?
    var thumbnailLink: String?
}

struct TtuSyncFiles {
    let bookData: TtuDriveFile?
    let cover: TtuDriveFile?
    let progress: TtuDriveFile?
    let statistics: TtuDriveFile?
    let audioBook: TtuDriveFile?
    
    nonisolated var lastAccess: Date? {
        let modified = [progress, audioBook].compactMap { file -> Int? in
            guard let parts = file?.name.split(separator: "_"), parts.count > 4 else { return nil }
            return Int(parts[3])
        }
        if let latest = modified.max() {
            return Date(timeIntervalSince1970: TimeInterval(latest) / 1000.0)
        }
        if let parts = bookData.map({ $0.name.split(separator: "_") }), parts.count > 5,
           let timestamp = Int(parts[5].dropLast(4)) {
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        }
        return nil
    }
    
    init(files: [TtuDriveFile]) {
        bookData = files.first { $0.name.hasPrefix("bookdata_") }
        cover = files.first { $0.name.hasPrefix("cover_") }
        progress = files.first { $0.name.hasPrefix("progress_") }
        statistics = files.first { $0.name.hasPrefix("statistics_") }
        audioBook = files.first { $0.name.hasPrefix("audioBook_") }
    }
}

struct TtuProgress: Codable {
    let dataId: Int
    let exploredCharCount: Int
    let progress: Double
    let lastBookmarkModified: Date
}

struct TtuAudioBook: Codable {
    let title: String
    let playbackPosition: Double
    let lastAudioBookModified: Int
}

@MainActor
class TtuDriveHandler {
    static let shared = TtuDriveHandler()
    private let client = GoogleDriveClient.shared
    private static let rootFolderIdKey = "GoogleDriveHandler.rootFolderId"
    
    private var rootFolderId: String?
    private var titleToFolderId: [String: String] = [:]
    
    private init() {
        rootFolderId = UserDefaults.standard.string(forKey: Self.rootFolderIdKey)
    }
    
    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: rootFolderIdKey)
        shared.rootFolderId = nil
        shared.titleToFolderId = [:]
        
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("gdrive-covers") {
            try? FileManager.default.removeItem(at: cacheDir)
        }
    }
    
    func findRootFolder() async throws -> String {
        guard UserConfig.shared.syncProvider == .ttu, GoogleDriveAuth.shared.isAuthenticated(for: .ttu) else {
            throw GoogleDriveAuthError.notAuthenticated
        }
        
        if let rootFolderId {
            return rootFolderId
        }
        
        let query = "trashed=false and 'root' in parents and mimeType='application/vnd.google-apps.folder' and name = 'ttu-reader-data'"
        let data = try await client.request("files", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ])
        let list = try JSONDecoder().decode(TtuDriveFileList.self, from: data)
        let folderId: String
        if let existingFolderId = list.files.first?.id {
            folderId = existingFolderId
        } else {
            folderId = try await createRootFolder()
        }
        rootFolderId = folderId
        UserDefaults.standard.set(folderId, forKey: Self.rootFolderIdKey)
        return folderId
    }
    
    private func createRootFolder() async throws -> String {
        let data = try await client.request(
            "files",
            query: [URLQueryItem(name: "fields", value: "id")],
            method: "POST",
            body: JSONSerialization.data(withJSONObject: [
                "name": "ttu-reader-data",
                "mimeType": "application/vnd.google-apps.folder",
                "parents": ["root"]
            ])
        )
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let folderId = response["id"] as? String else {
            throw GoogleDriveError.invalidResponse
        }
        return folderId
    }
    
    func listBooks(rootFolder: String) async throws -> [TtuDriveFile] {
        let query = "trashed=false and '\(rootFolder)' in parents and mimeType='application/vnd.google-apps.folder'"
        var allFiles: [TtuDriveFile] = []
        var pageToken: String?
        
        repeat {
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "fields", value: "nextPageToken, files(id, name)")
            ]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let data = try await client.request("files", query: items)
            let list = try JSONDecoder().decode(TtuDriveFileList.self, from: data)
            allFiles.append(contentsOf: list.files)
            pageToken = list.nextPageToken
        } while pageToken != nil
        
        return allFiles
    }
    
    func listSyncFiles(folderId: String) async throws -> TtuSyncFiles {
        let result = try await listSyncFiles(folderIds: [folderId])
        return result[folderId] ?? TtuSyncFiles(files: [])
    }
    
    func listSyncFiles(folderIds: [String]) async throws -> [String: TtuSyncFiles] {
        var grouped: [String: [TtuDriveFile]] = [:]
        
        for start in stride(from: 0, to: folderIds.count, by: 50) {
            let chunk = Array(folderIds[start..<min(start + 50, folderIds.count)])
            let parentsQuery = chunk.map { "'\($0)' in parents" }.joined(separator: " or ")
            let query = "trashed=false and (\(parentsQuery)) and mimeType != 'application/vnd.google-apps.folder'"
            var pageToken: String?
            
            repeat {
                var items = [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "fields", value: "nextPageToken, files(id, name, size, parents, thumbnailLink)")
                ]
                if let pageToken {
                    items.append(URLQueryItem(name: "pageToken", value: pageToken))
                }
                
                let data = try await client.request("files", query: items)
                let list = try JSONDecoder().decode(TtuDriveFileList.self, from: data)
                
                for file in list.files {
                    guard let parent = file.parents?.first else { continue }
                    grouped[parent, default: []].append(file)
                }
                pageToken = list.nextPageToken
            } while pageToken != nil
        }
        
        return grouped.mapValues { TtuSyncFiles(files: $0) }
    }
    
    func getProgressFile(fileId: String) async throws -> TtuProgress {
        let data = try await client.request("files/\(fileId)", query: [URLQueryItem(name: "alt", value: "media")])
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(TtuProgress.self, from: data)
    }
    
    func getStatsFile(fileId: String) async throws -> [TtuStatistics] {
        let data = try await client.request("files/\(fileId)", query: [URLQueryItem(name: "alt", value: "media")])
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode([TtuStatistics].self, from: data)
    }
    
    func getAudioBookFile(fileId: String) async throws -> TtuAudioBook {
        let data = try await client.request("files/\(fileId)", query: [URLQueryItem(name: "alt", value: "media")])
        return try JSONDecoder().decode(TtuAudioBook.self, from: data)
    }
    
    func uploadBookData(folderId: String, fileURL: URL, fileName: String) async throws {
        let data = try Data(contentsOf: fileURL)
        try await client.write(data: data, name: fileName, parent: folderId, contentType: "application/zip")
    }
    
    func updateProgressFile(folderId: String, fileId: String?, progress: TtuProgress) async throws {
        let timestamp = Int(progress.lastBookmarkModified.timeIntervalSince1970 * 1000)
        let fileName = "progress_1_6_\(timestamp)_\(progress.progress).json"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(progress)
        try await client.write(data: data, name: fileName, parent: folderId, fileId: fileId, contentType: "application/json")
    }
    
    func updateStatsFile(folderId: String, fileId: String?, stats: [TtuStatistics]) async throws {
        let fileName = Self.getStatisticsFileName(stats: stats)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(stats)
        try await client.write(data: data, name: fileName, parent: folderId, fileId: fileId, contentType: "application/json")
    }
    
    func updateAudioBookFile(folderId: String, fileId: String?, audioBook: TtuAudioBook) async throws {
        let fileName = "audioBook_1_6_\(audioBook.lastAudioBookModified)_\(audioBook.playbackPosition).json"
        let data = try JSONEncoder().encode(audioBook)
        try await client.write(data: data, name: fileName, parent: folderId, fileId: fileId, contentType: "application/json")
    }
    
    // https://github.com/ttu-ttu/ebook-reader/blob/d7d1dc1fd1151e067db218b8ff7eecf1c14d2276/apps/web/src/lib/data/storage/handler/gdrive-handler.ts#L102
    func ensureBookFolder(bookTitle: String, rootFolder: String, coverImageDataProvider: (() -> Data?)? = nil) async throws -> String {
        let sanitizedTitle = Self.sanitizeTtuFilename(bookTitle)
        
        if let cachedId = titleToFolderId[sanitizedTitle] {
            return cachedId
        }
        
        let searchQuery = "trashed=false and '\(rootFolder)' in parents and mimeType='application/vnd.google-apps.folder' and name=\"\(sanitizedTitle)\""
        let searchData = try await client.request("files", query: [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ])
        let searchResult = try JSONDecoder().decode(TtuDriveFileList.self, from: searchData)
        
        if let existingFolder = searchResult.files.first {
            titleToFolderId[sanitizedTitle] = existingFolder.id
            return existingFolder.id
        }
        
        let folderData = try await client.request(
            "files",
            method: "POST",
            body: JSONSerialization.data(withJSONObject: [
                "name": sanitizedTitle,
                "mimeType": "application/vnd.google-apps.folder",
                "parents": [rootFolder]
            ])
        )
        
        guard let folderResponse = try? JSONSerialization.jsonObject(with: folderData) as? [String: Any],
              let folderId = folderResponse["id"] as? String else {
            throw GoogleDriveError.invalidResponse
        }
        
        titleToFolderId[sanitizedTitle] = folderId
        
        if let coverData = coverImageDataProvider?() {
            _ = Task {
                try await uploadCoverImage(folderId: folderId, coverData: coverData)
            }
        }
        
        return folderId
    }
    
    // https://github.com/ttu-ttu/ebook-reader/blob/d7d1dc1fd1151e067db218b8ff7eecf1c14d2276/apps/web/src/lib/data/storage/handler/base-handler.ts#L244
    static func getStatisticsFileName(stats: [TtuStatistics]) -> String {
        var readingTime: Double = 0
        var charactersRead: Int = 0
        var minReadingSpeed: Int = 0
        var altMinReadingSpeed: Int = 0
        var maxReadingSpeed: Int = 0
        var weightedSum: Int = 0
        var validReadingDays: Int = 0
        var lastStatisticModified: Int = 0
        
        for stat in stats {
            readingTime += stat.readingTime
            charactersRead += stat.charactersRead
            minReadingSpeed = minReadingSpeed > 0 ? min(minReadingSpeed, stat.minReadingSpeed) : stat.minReadingSpeed
            altMinReadingSpeed = altMinReadingSpeed > 0 ? min(altMinReadingSpeed, stat.altMinReadingSpeed) : stat.altMinReadingSpeed
            maxReadingSpeed = max(maxReadingSpeed, stat.lastReadingSpeed)
            weightedSum += Int(stat.readingTime) * stat.charactersRead
            lastStatisticModified = max(lastStatisticModified, stat.lastStatisticModified)
            if stat.readingTime > 0 {
                validReadingDays += 1
            }
        }
        
        let averageReadingTime = validReadingDays > 0 ? ceil(readingTime / Double(validReadingDays)) : 0
        let averageWeightedReadingTime = charactersRead > 0 ? ceil(Double(weightedSum) / Double(charactersRead)) : 0
        let averageCharactersRead = validReadingDays > 0 ? ceil(Double(charactersRead) / Double(validReadingDays)) : 0
        let averageWeightedCharactersRead = readingTime > 0 ? ceil(Double(weightedSum) / Double(readingTime)) : 0
        let lastReadingSpeed = readingTime > 0 ? ceil((3600.0 * Double(charactersRead)) / readingTime) : 0
        let averageReadingSpeed = averageReadingTime > 0 ? ceil((3600 * averageCharactersRead) / averageReadingTime) : 0
        let averageWeightedReadingSpeed = averageWeightedReadingTime > 0 ? ceil((3600 * averageWeightedCharactersRead) / averageWeightedReadingTime) : 0
        return "statistics_1_6_\(lastStatisticModified)_\(charactersRead)_\(readingTime)_\(minReadingSpeed)_\(altMinReadingSpeed)_\(lastReadingSpeed)_\(maxReadingSpeed)_\(averageReadingTime)_\(averageWeightedReadingTime)_\(averageCharactersRead)_\(averageWeightedCharactersRead)_\(averageReadingSpeed)_\(averageWeightedReadingSpeed)_na.json"
    }
    
    // https://github.com/ttu-ttu/ebook-reader/blob/d7d1dc1fd1151e067db218b8ff7eecf1c14d2276/apps/web/src/lib/data/storage/handler/base-handler.ts#L642
    static func sanitizeTtuFilename(_ title: String) -> String {
        var result = title
        if result.hasSuffix(" ") {
            result = String(result.dropLast())
            result += "~ttu-spc~"
        }
        if result.hasSuffix(".") {
            result = String(result.dropLast())
            result += "~ttu-dend~"
        }
        result = result.replacingOccurrences(of: "*", with: "~ttu-star~")
        result = result.replacing(/[\/?\<>\\:*|%"]/) { match in
            match.output.unicodeScalars.map { scalar in
                let value = scalar.value
                return String(format: "%%%02X", value)
            }.joined()
        }
        
        return result
    }
    
    static func desanitizeTtuFilename(_ title: String) -> String {
        (title.removingPercentEncoding ?? title)
            .replacingOccurrences(of: "~ttu-star~", with: "*")
            .replacingOccurrences(of: "~ttu-dend~", with: ".")
            .replacingOccurrences(of: "~ttu-spc~", with: " ")
    }
    
    private func uploadCoverImage(folderId: String, coverData: Data) async throws {
        // https://github.com/ttu-ttu/ebook-reader/blob/d7d1dc1fd1151e067db218b8ff7eecf1c14d2276/apps/web/src/lib/data/storage/handler/base-handler.ts#L764
        let mimeType: String
        let fileExtension: String
        
        if coverData.count >= 4 {
            let magic = [UInt8](coverData.prefix(4))
            if magic[0] == 0x89 && magic[1] == 0x50 && magic[2] == 0x4E && magic[3] == 0x47 {
                mimeType = "image/png"
                fileExtension = "png"
            } else if magic[0] == 0x47 && magic[1] == 0x49 && magic[2] == 0x46 && magic[3] == 0x38 {
                mimeType = "image/gif"
                fileExtension = "gif"
            } else if magic[0] == 0x42 && magic[1] == 0x4D {
                mimeType = "image/bmp"
                fileExtension = "bmp"
            } else if magic[0] == 0x52 && magic[1] == 0x49 && magic[2] == 0x46 && magic[3] == 0x46 {
                mimeType = "image/webp"
                fileExtension = "webp"
            } else {
                mimeType = "image/jpeg"
                fileExtension = "jpeg"
            }
        } else {
            mimeType = "image/jpeg"
            fileExtension = "jpeg"
        }
        
        // https://github.com/ttu-ttu/ebook-reader/blob/d7d1dc1fd1151e067db218b8ff7eecf1c14d2276/apps/web/src/lib/data/storage/handler/base-handler.ts#L703
        let fileName = "cover_1_6.\(fileExtension)"
        try await client.write(data: coverData, name: fileName, parent: folderId, contentType: mimeType)
    }
}
