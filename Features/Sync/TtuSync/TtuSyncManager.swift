//
//  TtuSyncManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum TtuSyncResult {
    case synced(title: String)
    case imported(title: String, characterCount: Int)
    case exported(title: String, characterCount: Int)
    case skipped
}

@MainActor
class TtuSyncManager {
    static let shared = TtuSyncManager()
    private init() {}
    
    func syncBook(
        book: BookMetadata,
        direction: TtuSyncDirection?,
        syncBookData: Bool,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool,
        importOnly: Bool = false
    ) async throws -> TtuSyncResult {
        do {
            return try await syncBookOnce(
                book: book,
                direction: direction,
                syncBookData: syncBookData,
                syncStats: syncStats,
                statsSyncMode: statsSyncMode,
                syncAudioBook: syncAudioBook,
                importOnly: importOnly
            )
        } catch let error as GoogleDriveError where error.isStaleCacheError {
            TtuDriveHandler.clearCache()
            return try await syncBookOnce(
                book: book,
                direction: direction,
                syncBookData: syncBookData,
                syncStats: syncStats,
                statsSyncMode: statsSyncMode,
                syncAudioBook: syncAudioBook,
                importOnly: importOnly
            )
        }
    }
    
    private func syncBookOnce(
        book: BookMetadata,
        direction: TtuSyncDirection?,
        syncBookData: Bool,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool,
        importOnly: Bool
    ) async throws -> TtuSyncResult {
        let connection = GoogleDriveClient.shared.connectionId
        let root = try await TtuDriveHandler.shared.findRootFolder()
        
        let coverPath = book.cover
        let driveFolderId = try await TtuDriveHandler.shared.ensureBookFolder(
            bookTitle: book.title,
            rootFolder: root,
            coverImageDataProvider: coverPath.map { path in
                return {
                    guard let appDirectory = try? BookStorage.getAppDirectory() else { return nil }
                    let coverURL = appDirectory.appendingPathComponent(path)
                    guard FileManager.default.fileExists(atPath: coverURL.path(percentEncoded: false)) else { return nil }
                    return try? Data(contentsOf: coverURL)
                }
            }
        )
        
        let directory = try BookStorage.getBooksDirectory()
        let url = directory.appendingPathComponent(book.folder)
        let localBookmark = BookStorage.loadBookmark(root: url)
        
        let syncFiles = try await TtuDriveHandler.shared.listSyncFiles(folderId: driveFolderId)
        
        let progressFileId = syncFiles.progress?.id
        let statsFileId = syncStats ? syncFiles.statistics?.id : nil
        let audioBookFileId = syncAudioBook ? syncFiles.audioBook?.id : nil
        
        if syncBookData && !importOnly && direction != .importFromTtu && syncFiles.bookData == nil {
            try await exportBookData(bookFolder: url, driveFolderId: driveFolderId)
        }
        
        let syncDirection = direction ?? determineSyncDirection(local: localBookmark, remoteProgressFile: syncFiles.progress)
        if syncDirection == .synced {
            return .synced(title: book.displayTitle)
        }
        if importOnly && syncDirection != .importFromTtu {
            return .skipped
        }
        
        async let fetchedProgress: TtuProgress? = fetchProgress(fileId: progressFileId)
        async let fetchedStats: [TtuStatistics]? = fetchStats(fileId: statsFileId)
        async let fetchedAudioBook: TtuAudioBook? = fetchAudioBook(fileId: audioBookFileId)
        
        let playbackData = syncAudioBook ? BookStorage.loadSasayakiPlayback(root: url) : nil
        
        let ttuProgress = try await fetchedProgress
        let ttuStats = try await fetchedStats
        let ttuAudioBook = try await fetchedAudioBook
        try GoogleDriveClient.shared.checkConnection(connection)
        
        switch syncDirection {
        case .importFromTtu:
            guard let ttuProgress else { return .skipped }
            importProgress(ttuProgress: ttuProgress, to: url)
            if syncStats {
                TtuStatistics.importHistory(ttuStats ?? [], key: book.folder, mode: statsSyncMode)
            }
            if syncAudioBook, let ttuAudioBook {
                importAudioBook(ttuAudioBook: ttuAudioBook, to: url)
            }
            return .imported(title: book.displayTitle, characterCount: ttuProgress.exploredCharCount)
        case .exportToTtu:
            guard let localBookmark else { return .skipped }
            
            let localStats = syncStats ?
            TtuStatistics.export(
                StatisticsStorage.load(folder: book.folder),
                title: book.displayTitle) : nil
            let statsToExport: [TtuStatistics]? = syncStats ?
            mergeStatistics(
                localStatistics: ttuStats ?? [],
                externalStatistics: localStats ?? [],
                syncMode: statsSyncMode) : nil
            
            async let exportedProgress: Void = exportProgress(
                localBookmark: localBookmark,
                ttuProgress: ttuProgress,
                folderId: driveFolderId,
                fileId: progressFileId,
                url: url
            )
            async let exportedStats: Void = exportStats(
                stats: statsToExport,
                folderId: driveFolderId,
                fileId: statsFileId
            )
            async let exportedAudioBook: Void = exportAudioBook(
                title: book.title,
                playbackData: playbackData,
                folderId: driveFolderId,
                fileId: audioBookFileId
            )
            
            try await exportedProgress
            try await exportedStats
            try await exportedAudioBook
            return .exported(title: book.displayTitle, characterCount: localBookmark.characterCount)
        case .synced:
            return .synced(title: book.displayTitle)
        }
    }
    
    func importGoogleDriveBook(
        syncFiles: TtuSyncFiles,
        syncStats: Bool,
        syncAudioBook: Bool,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard UserConfig.shared.syncProvider == .ttu, GoogleDriveAuth.shared.isAuthenticated(for: .ttu) else {
            throw GoogleDriveAuthError.notAuthenticated
        }
        
        let connection = GoogleDriveClient.shared.connectionId
        
        guard let bookData = syncFiles.bookData else {
            throw GoogleDriveError.invalidResponse
        }
        
        async let downloadedData = GoogleDriveClient.shared.downloadFile(fileId: bookData.id, fileSize: bookData.size.flatMap(Int64.init)!, onProgress: onProgress)
        async let ttuProgress = fetchProgress(fileId: syncFiles.progress?.id)
        async let ttuStats = fetchStats(fileId: syncStats ? syncFiles.statistics?.id : nil)
        async let ttuAudioBook = fetchAudioBook(fileId: syncAudioBook ? syncFiles.audioBook?.id : nil)
        
        let data = try await downloadedData
        let progress = try await ttuProgress
        let statistics = try await ttuStats
        let audioBook = try await ttuAudioBook
        try GoogleDriveClient.shared.checkConnection(connection)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let booksDir = try BookStorage.getBooksDirectory()
        let bookFolder = try TtuConverter.convertFromTtu(bookData: tempURL, to: booksDir)
        let metadata = BookStorage.loadMetadata(root: bookFolder)!
        try SyncStorage.shared.handleBookImport(book: metadata, root: bookFolder)
        
        if let progress {
            importProgress(ttuProgress: progress, to: bookFolder)
        }
        
        if let stats = statistics, !stats.isEmpty {
            TtuStatistics.importHistory(stats, key: metadata.folder)
        }
        
        if let audioBook {
            importAudioBook(ttuAudioBook: audioBook, to: bookFolder)
        }
        return bookFolder
    }
    
    private func determineSyncDirection(local: Bookmark?, remoteProgressFile: TtuDriveFile?) -> TtuSyncDirection {
        let localModified = local?.lastModified
        let remoteModified = remoteProgressFile.flatMap(parseProgressTimestamp)
        
        switch (localModified, remoteModified) {
        case (nil, nil):
            return .synced
        case (nil, _):
            return .importFromTtu
        case (_, nil):
            return .exportToTtu
        case let (l?, r?):
            if l > r { return .exportToTtu }
            if r > l { return .importFromTtu }
            return .synced
        }
    }
    
    private func parseProgressTimestamp(from file: TtuDriveFile) -> Date? {
        guard file.name.hasPrefix("progress_") else { return nil }
        let parts = file.name.split(separator: "_")
        guard parts.count > 4, let timestamp = Int(parts[3]) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
    
    private func importProgress(ttuProgress: TtuProgress, to url: URL) {
        guard let bookInfo = BookStorage.loadBookInfo(root: url) else { return }
        
        let resolved = bookInfo.resolveCharacterPosition(ttuProgress.exploredCharCount)
        
        let bookmark = Bookmark(
            chapterIndex: resolved?.spineIndex ?? 0,
            progress: resolved?.progress ?? 0,
            characterCount: ttuProgress.exploredCharCount,
            lastModified: ttuProgress.lastBookmarkModified
        )
        
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
        try? SyncStorage.shared.handleBookChange(folder: url.lastPathComponent)
    }
    
    private func fetchProgress(fileId: String?) async throws -> TtuProgress? {
        guard let fileId else { return nil }
        return try await TtuDriveHandler.shared.getProgressFile(fileId: fileId)
    }
    
    private func fetchStats(fileId: String?) async throws -> [TtuStatistics]? {
        guard let fileId else { return nil }
        return try await TtuDriveHandler.shared.getStatsFile(fileId: fileId)
    }
    
    private func fetchAudioBook(fileId: String?) async throws -> TtuAudioBook? {
        guard let fileId else { return nil }
        return try await TtuDriveHandler.shared.getAudioBookFile(fileId: fileId)
    }
    
    private func exportBookData(bookFolder: URL, driveFolderId: String) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        guard let bookDataURL = try TtuConverter.convertToTtu(bookFolder: bookFolder, to: tempDir) else { return }
        try await TtuDriveHandler.shared.uploadBookData(
            folderId: driveFolderId,
            fileURL: bookDataURL,
            fileName: bookDataURL.lastPathComponent
        )
    }
    
    private func exportProgress(localBookmark: Bookmark, ttuProgress: TtuProgress?, folderId: String, fileId: String?, url: URL) async throws {
        let connection = GoogleDriveClient.shared.connectionId
        
        guard let bookInfo = BookStorage.loadBookInfo(root: url),
              let lastModified = localBookmark.lastModified else { return }
        
        let unixTimestamp = Int(lastModified.timeIntervalSince1970 * 1000)
        let roundedDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp) / 1000.0)
        
        let progress = TtuProgress(
            dataId: ttuProgress?.dataId ?? 0,
            exploredCharCount: localBookmark.characterCount,
            progress: bookInfo.characterCount > 0 ? Double(localBookmark.characterCount) / Double(bookInfo.characterCount) : 0,
            lastBookmarkModified: roundedDate
        )
        
        try await TtuDriveHandler.shared.updateProgressFile(
            folderId: folderId,
            fileId: fileId,
            progress: progress
        )
        
        try GoogleDriveClient.shared.checkConnection(connection)
        guard BookStorage.loadBookmark(root: url)?.lastModified == lastModified else { return }
        let bookmark = Bookmark(
            chapterIndex: localBookmark.chapterIndex,
            progress: localBookmark.progress,
            characterCount: localBookmark.characterCount,
            lastModified: roundedDate
        )
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
    }
    
    private func exportStats(stats: [TtuStatistics]?, folderId: String, fileId: String?) async throws {
        guard let stats, !stats.isEmpty else { return }
        try await TtuDriveHandler.shared.updateStatsFile(folderId: folderId, fileId: fileId, stats: stats)
    }
    
    private func mergeStatistics(localStatistics: [TtuStatistics], externalStatistics: [TtuStatistics], syncMode: StatisticsSyncMode) -> [TtuStatistics] {
        if syncMode == .replace {
            return externalStatistics
        }
        return TtuStatistics.merged(localStatistics + externalStatistics)
    }
    
    private func importAudioBook(ttuAudioBook: TtuAudioBook, to url: URL) {
        var playback = BookStorage.loadSasayakiPlayback(root: url) ?? SasayakiPlaybackData(lastPosition: 0)
        playback.lastPosition = ttuAudioBook.playbackPosition
        if (try? BookStorage.savePlayback(&playback, root: url)) == true {
            try? SyncStorage.shared.handleBookChange(folder: url.lastPathComponent)
        }
    }
    
    private func exportAudioBook(title: String, playbackData: SasayakiPlaybackData?, folderId: String, fileId: String?) async throws {
        guard let playbackData else { return }
        let audioBook = TtuAudioBook(
            title: title,
            playbackPosition: playbackData.lastPosition,
            lastAudioBookModified: Int(Date().timeIntervalSince1970 * 1000)
        )
        try await TtuDriveHandler.shared.updateAudioBookFile(
            folderId: folderId,
            fileId: fileId,
            audioBook: audioBook
        )
    }
}
