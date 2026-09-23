//
//  BackupView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct BackupView: View {
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isImportingTtu = false
    @State private var exportURL: URL?
    @State private var target = ""
    @State private var isLoading = false
    @State private var loadingString = ""
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        List {
            Section("Books") {
                Button("Backup") {
                    backupFolder(folder: "Books")
                }
                Button("Restore") {
                    target = "Books";
                    isImporting = true
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType(filenameExtension: "hoshi")!]
            ) { result in
                if case .success(let url) = result {
                    restoreFolder(from: url, to: target)
                }
            }
            
            Section {
                Button("Backup") {
                    backupFolder(folder: "Dictionaries")
                }
                Button("Restore") {
                    target = "Dictionaries";
                    isImporting = true
                }
            } header: {
                Text("Dictionaries")
            } footer: {
                Text("Restoring will overwrite the current collection.")
            }
            
            Section {
                Button("Export") {
                    exportTtuBookData()
                }
                Button("Import") {
                    isImportingTtu = true
                }
            } header: {
                Text("ッツ Backup")
            } footer: {
                Text("Importing a backup adds new books and overwrites the statistics and reading progress of books already present.")
            }
            .fileImporter(
                isPresented: $isImportingTtu,
                allowedContentTypes: [.zip]
            ) { result in
                if case .success(let url) = result {
                    importTtuBookData(from: url)
                }
            }
        }
        .fileMover(isPresented: $isExporting, file: exportURL) { result in
            switch result {
            case .success:
                exportURL = nil
            case .failure:
                cleanup()
            }
        } onCancellation: {
            cleanup()
        }
        .overlay {
            if isLoading {
                LoadingOverlay(loadingString)
            }
        }
        .navigationTitle("Backup")
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func backupFolder(folder: String) {
        isLoading = true
        loadingString = "Archiving..."
        let directory = try! BookStorage.getAppDirectory().appendingPathComponent(folder)
        Task.detached {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let archiveName = "\(folder)_\(formatter.string(from: Date())).hoshi"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(archiveName)
            do {
                try FileManager.default.zipItem(at: directory, to: tempURL, shouldKeepParent: false, compressionMethod: .deflate)
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
                return
            }
            
            await MainActor.run {
                exportURL = tempURL
                isLoading = false
                isExporting = true
            }
        }
    }
    
    private func cleanup() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
        }
        exportURL = nil
    }
    
    private func restoreFolder(from url: URL, to folder: String) {
        guard url.startAccessingSecurityScopedResource() else { return }
        isLoading = true
        loadingString = "Restoring..."
        let destination = try! BookStorage.getAppDirectory().appendingPathComponent(folder)
        Task.detached {
            defer { url.stopAccessingSecurityScopedResource() }
            if folder == "Books" {
                await GoogleDriveSyncManager.shared.stop()
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try FileManager.default.unzipItem(at: url, to: destination)
                if folder == "Books" {
                    try await GoogleDriveSyncManager.shared.resetConnection(restoringBackup: true)
                }
            } catch {
                await MainActor.run {
                    if folder == "Books" {
                        UserConfig.shared.enableSync = false
                        GoogleDriveSyncManager.shared.start()
                    }
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
                return
            }
            await MainActor.run {
                isLoading = false
                if folder == "Books" {
                    GoogleDriveSyncManager.shared.start()
                } else if folder == "Dictionaries" {
                    DictionaryManager.shared.loadDictionaries()
                    DictionaryManager.shared.rebuildLookupQuery()
                }
            }
        }
    }
    
    private func importTtuBookData(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        isLoading = true
        loadingString = "Importing..."
        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                isLoading = false
            }
            do {
                let booksDirectory = try BookStorage.getBooksDirectory()
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temp) }
                try FileManager.default.unzipItem(at: url, to: temp)
                
                let contents = try FileManager.default.contentsOfDirectory(
                    at: temp,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                for folder in contents {
                    let resources = try folder.resourceValues(forKeys: [.isDirectoryKey])
                    guard resources.isDirectory == true else { continue }
                    
                    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    guard let bookdataZip = files.first(where: { $0.lastPathComponent.hasPrefix("bookdata_") && $0.pathExtension == "zip" }) else { continue }
                    
                    let bookFolder = try TtuConverter.convertFromTtu(bookData: bookdataZip, to: booksDirectory)
                    
                    let metadata = BookStorage.loadMetadata(root: bookFolder)!
                    try SyncStorage.shared.handleBookImport(book: metadata, root: bookFolder)
                    
                    if let statsFile = files.first(where: { $0.lastPathComponent.hasPrefix("statistics_") }) {
                        let statsData = try Data(contentsOf: statsFile)
                        let stats = try JSONDecoder().decode([TtuStatistics].self, from: statsData)
                        TtuStatistics.importHistory(stats, key: metadata.folder, mode: .replace)
                    }
                    
                    if let progressFile = files.first(where: { $0.lastPathComponent.hasPrefix("progress_") }) {
                        let progressData = try Data(contentsOf: progressFile)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .millisecondsSince1970
                        let progress = try decoder.decode(TtuProgress.self, from: progressData)
                        if let bookInfo = BookStorage.loadBookInfo(root: bookFolder) {
                            let resolved = bookInfo.resolveCharacterPosition(progress.exploredCharCount)
                            let bookmark = Bookmark(
                                chapterIndex: resolved?.spineIndex ?? 0,
                                progress: resolved?.progress ?? 0,
                                characterCount: progress.exploredCharCount,
                                lastModified: progress.lastBookmarkModified
                            )
                            try BookStorage.save(bookmark, inside: bookFolder, as: FileNames.bookmark)
                            try SyncStorage.shared.handleBookChange(folder: metadata.folder)
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func exportTtuBookData() {
        isLoading = true
        loadingString = "Exporting..."
        Task {
            defer { isLoading = false }
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            do {
                let booksDirectory = try BookStorage.getBooksDirectory()
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                let contents = try FileManager.default.contentsOfDirectory(
                    at: booksDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let archiveName = "hoshi_ttu_export_\(formatter.string(from: Date())).zip"
                let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(archiveName)
                let archive = try Archive(url: archiveURL, accessMode: .create, pathEncoding: .utf8)
                
                let books = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                for (index, folder) in books.enumerated() {
                    guard let metadata = BookStorage.loadMetadata(root: folder), metadata.epub != nil else { continue }
                    loadingString = "Exporting \(index + 1)/\(books.count)"
                    await Task.yield()
                    
                    let bookDir = tempDir.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
                    guard let bookData = try TtuConverter.convertToTtu(bookFolder: folder, to: bookDir) else { continue }
                    
                    let canonicalTitle = TtuDriveHandler.sanitizeTtuFilename(metadata.displayTitle)
                        .precomposedStringWithCanonicalMapping
                    try archive.addEntry(with: "\(canonicalTitle)/\(bookData.lastPathComponent)", fileURL: bookData, compressionMethod: .deflate)
                    if let coverURL = metadata.coverURL {
                        try archive.addEntry(with: "\(canonicalTitle)/cover_1_6.\(coverURL.pathExtension)", fileURL: coverURL, compressionMethod: .deflate)
                    }
                    
                    let stats = TtuStatistics.export(
                        StatisticsStorage.load(root: folder),
                        title: metadata.displayTitle
                    )
                    
                    if !stats.isEmpty {
                        let statsFileName = TtuDriveHandler.getStatisticsFileName(stats: stats)
                        let statsData = try JSONEncoder().encode(stats)
                        let statsURL = bookDir.appendingPathComponent(statsFileName)
                        try statsData.write(to: statsURL)
                        try archive.addEntry(with: "\(canonicalTitle)/\(statsFileName)", fileURL: statsURL, compressionMethod: .deflate)
                    }
                    if let bookmark = BookStorage.loadBookmark(root: folder),
                       let bookInfo = BookStorage.loadBookInfo(root: folder) {
                        let lastModified = bookmark.lastModified ?? metadata.lastAccess
                        let unixTimestamp = Int(lastModified.timeIntervalSince1970 * 1000)
                        let roundedDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp) / 1000.0)
                        let progress = TtuProgress(
                            dataId: 0,
                            exploredCharCount: bookmark.characterCount,
                            progress: bookInfo.characterCount > 0 ? Double(bookmark.characterCount) / Double(bookInfo.characterCount) : 0,
                            lastBookmarkModified: roundedDate
                        )
                        let progressFileName = "progress_1_6_\(unixTimestamp)_\(progress.progress).json"
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .millisecondsSince1970
                        let progressData = try encoder.encode(progress)
                        let progressURL = bookDir.appendingPathComponent(progressFileName)
                        try progressData.write(to: progressURL)
                        try archive.addEntry(with: "\(canonicalTitle)/\(progressFileName)", fileURL: progressURL, compressionMethod: .deflate)
                    }
                }
                
                exportURL = archiveURL
                isExporting = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
