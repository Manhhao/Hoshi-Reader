//
//  BackupView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers
import ZipArchive

struct HoshiArchive: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "hoshi") ?? .zip]
    }
    
    var data: Data
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var document: HoshiArchive?
    @State private var fileName = ""
    @State private var target = ""
    @State private var isLoading = false
    @State private var loadingString = ""
    
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
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: UTType(filenameExtension: "hoshi")!,
            defaultFilename: fileName
        ) { _ in }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType(filenameExtension: "hoshi")!]
            ) { result in
                if case .success(let url) = result {
                    restoreFolder(from: url, to: target)
                }
            }
            .overlay {
                if isLoading {
                    LoadingOverlay(loadingString)
                }
            }
            .navigationTitle("Backup")
    }
    
    private func backupFolder(folder: String) {
        isLoading = true
        loadingString = "Archiving..."
        let directory = try! BookStorage.getDocumentsDirectory().appendingPathComponent(folder)
        Task.detached {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("hoshi")
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            SSZipArchive.createZipFile(atPath: tempURL.path(percentEncoded: false), withContentsOfDirectory: directory.path(percentEncoded: false))
            guard let data = try? Data(contentsOf: tempURL) else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            await MainActor.run {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                fileName = "\(folder)_\(formatter.string(from: Date())).hoshi"
                document = HoshiArchive(data: data)
                isLoading = false
                isExporting = true
            }
        }
    }
    
    private func restoreFolder(from url: URL, to folder: String) {
        guard url.startAccessingSecurityScopedResource() else { return }
        isLoading = true
        loadingString = "Restoring..."
        let destination = try! BookStorage.getDocumentsDirectory().appendingPathComponent(folder)
        Task.detached {
            defer { url.stopAccessingSecurityScopedResource() }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            SSZipArchive.unzipFile(atPath: url.path(percentEncoded: false), toDestination: destination.path(percentEncoded: false))
            await MainActor.run {
                isLoading = false
                DictionaryManager.shared.loadDictionaries()
                DictionaryManager.shared.rebuildLookupQuery()
            }
        }
    }
}
