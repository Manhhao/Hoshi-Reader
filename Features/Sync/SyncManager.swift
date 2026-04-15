//
//  SyncManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum SyncResult {
    case synced(title: String)
    case imported(title: String, characterCount: Int)
    case exported(title: String, characterCount: Int)
    case skipped
}

@MainActor
class SyncManager {
    static let shared = SyncManager()
    private init() {}
    
    func syncBook(
        book: BookMetadata,
        direction: SyncDirection?,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool
    ) async throws -> SyncResult {
        do {
            return try await syncBookOnce(
                book: book,
                direction: direction,
                syncStats: syncStats,
                statsSyncMode: statsSyncMode,
                syncAudioBook: syncAudioBook
            )
        } catch let error as GoogleDriveError where error.isStaleCacheError {
            GoogleDriveHandler.clearCache()
            return try await syncBookOnce(
                book: book,
                direction: direction,
                syncStats: syncStats,
                statsSyncMode: statsSyncMode,
                syncAudioBook: syncAudioBook
            )
        }
    }
    
    private func syncBookOnce(
        book: BookMetadata,
        direction: SyncDirection?,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool
    ) async throws -> SyncResult {
        guard let title = book.title,
              let bookFolder = book.folder else {
            return .skipped
        }
        
        let root = try await GoogleDriveHandler.shared.findRootFolder()
        
        let coverPath = book.cover
        let driveFolderId = try await GoogleDriveHandler.shared.ensureBookFolder(
            bookTitle: title,
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
        let url = directory.appendingPathComponent(bookFolder)
        let localBookmark = BookStorage.loadBookmark(root: url)
        
        let syncFiles = try await GoogleDriveHandler.shared.listSyncFiles(folderId: driveFolderId)
        
        let progressFileId = syncFiles.progress?.id
        let statsFileId = syncStats ? syncFiles.statistics?.id : nil
        let audioBookFileId = syncAudioBook ? syncFiles.audioBook?.id : nil
        
        let syncDirection = direction ?? determineSyncDirection(local: localBookmark, remoteProgressFile: syncFiles.progress)
        if syncDirection == .synced {
            return .synced(title: title)
        }
        
        async let fetchedProgress: TtuProgress? = fetchProgress(fileId: progressFileId)
        async let fetchedStats: [Statistics]? = fetchStats(fileId: statsFileId)
        async let fetchedAudioBook: TtuAudioBook? = fetchAudioBook(fileId: audioBookFileId)
        
        let localStats = syncStats ? BookStorage.loadStatistics(root: url) : nil
        let playbackData = syncAudioBook ? BookStorage.loadSasayakiPlayback(root: url) : nil
        
        let ttuProgress = try await fetchedProgress
        let ttuStats = try await fetchedStats
        let ttuAudioBook = try await fetchedAudioBook
        
        switch syncDirection {
        case .importFromTtu:
            guard let ttuProgress else { return .skipped }
            importProgress(ttuProgress: ttuProgress, to: url)
            if syncStats {
                let mergedStats = mergeStatistics(localStatistics: localStats ?? [], externalStatistics: ttuStats ?? [], syncMode: statsSyncMode)
                if !mergedStats.isEmpty {
                    try? BookStorage.save(mergedStats, inside: url, as: FileNames.statistics)
                }
            }
            if syncAudioBook, let ttuAudioBook {
                importAudioBook(ttuAudioBook: ttuAudioBook, to: url)
            }
            return .imported(title: title, characterCount: ttuProgress.exploredCharCount)
        case .exportToTtu:
            guard let localBookmark else { return .skipped }
            let statsToExport: [Statistics]? = syncStats ? mergeStatistics(localStatistics: ttuStats ?? [], externalStatistics: localStats ?? [], syncMode: statsSyncMode) : nil
            
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
                title: title,
                playbackData: playbackData,
                folderId: driveFolderId,
                fileId: audioBookFileId
            )
            
            try await exportedProgress
            try await exportedStats
            try await exportedAudioBook
            return .exported(title: title, characterCount: localBookmark.characterCount)
        case .synced:
            return .synced(title: title)
        }
    }
    
    private func determineSyncDirection(local: Bookmark?, remoteProgressFile: DriveFile?) -> SyncDirection {
        let remoteModified: Date? = {
            guard let file = remoteProgressFile, file.name.hasPrefix("progress_") else {
                return nil
            }
            let parts = file.name.split(separator: "_")
            guard parts.count > 4, let timestamp = Int(parts[3]) else {
                return nil
            }
            return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        }()
        
        guard let local = local, let lastModified = local.lastModified else {
            if remoteModified != nil {
                return .importFromTtu
            } else {
                return .synced
            }
        }
        
        guard let remoteModified else {
            return .exportToTtu
        }
        
        if lastModified > remoteModified {
            return .exportToTtu
        } else if remoteModified > lastModified {
            return .importFromTtu
        } else {
            return .synced
        }
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
    }
    
    private func fetchProgress(fileId: String?) async throws -> TtuProgress? {
        guard let fileId else { return nil }
        return try await GoogleDriveHandler.shared.getProgressFile(fileId: fileId)
    }
    
    private func fetchStats(fileId: String?) async throws -> [Statistics]? {
        guard let fileId else { return nil }
        return try await GoogleDriveHandler.shared.getStatsFile(fileId: fileId)
    }
    
    private func fetchAudioBook(fileId: String?) async throws -> TtuAudioBook? {
        guard let fileId else { return nil }
        return try await GoogleDriveHandler.shared.getAudioBookFile(fileId: fileId)
    }
    
    private func exportProgress(localBookmark: Bookmark, ttuProgress: TtuProgress?, folderId: String, fileId: String?, url: URL) async throws {
        guard let bookInfo = BookStorage.loadBookInfo(root: url),
              let lastModified = localBookmark.lastModified else { return }
        
        let unixTimestamp = Int(lastModified.timeIntervalSince1970 * 1000)
        let roundedDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp) / 1000.0)
        
        let progress = TtuProgress(
            dataId: ttuProgress?.dataId ?? 0,
            exploredCharCount: localBookmark.characterCount,
            progress: Double(localBookmark.characterCount) / Double(bookInfo.characterCount),
            lastBookmarkModified: roundedDate
        )
        
        try await GoogleDriveHandler.shared.updateProgressFile(
            folderId: folderId,
            fileId: fileId,
            progress: progress
        )
        
        let bookmark = Bookmark(
            chapterIndex: localBookmark.chapterIndex,
            progress: localBookmark.progress,
            characterCount: localBookmark.characterCount,
            lastModified: roundedDate
        )
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
    }
    
    private func exportStats(stats: [Statistics]?, folderId: String, fileId: String?) async throws {
        guard let stats, !stats.isEmpty else { return }
        try await GoogleDriveHandler.shared.updateStatsFile(folderId: folderId, fileId: fileId, stats: stats)
    }
    
    private func mergeStatistics(localStatistics: [Statistics], externalStatistics: [Statistics], syncMode: StatisticsSyncMode) -> [Statistics] {
        if syncMode == .replace {
            return externalStatistics
        }
        
        var grouped: [String: Statistics] = [:]
        
        for stat in localStatistics {
            grouped[stat.dateKey] = stat
        }
        
        for stat in externalStatistics {
            if let existing = grouped[stat.dateKey] {
                if stat.lastStatisticModified > existing.lastStatisticModified {
                    grouped[stat.dateKey] = stat
                }
            } else {
                grouped[stat.dateKey] = stat
            }
        }
        
        return Array(grouped.values)
    }
    
    private func importAudioBook(ttuAudioBook: TtuAudioBook, to url: URL) {
        var playback = BookStorage.loadSasayakiPlayback(root: url) ?? SasayakiPlaybackData(lastPosition: 0)
        playback.lastPosition = ttuAudioBook.playbackPosition
        try? BookStorage.save(playback, inside: url, as: FileNames.sasayakiPlayback)
    }
    
    private func exportAudioBook(title: String, playbackData: SasayakiPlaybackData?, folderId: String, fileId: String?) async throws {
        guard let playbackData else { return }
        let audioBook = TtuAudioBook(
            title: title,
            playbackPosition: playbackData.lastPosition,
            lastAudioBookModified: Int(Date().timeIntervalSince1970 * 1000)
        )
        try await GoogleDriveHandler.shared.updateAudioBookFile(
            folderId: folderId,
            fileId: fileId,
            audioBook: audioBook
        )
    }
}
