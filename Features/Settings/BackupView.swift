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

struct BackupView: View {
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportURL: URL?
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
        loadingString = String(localized: "Archiving...")
        let directory = try! BookStorage.getDocumentsDirectory().appendingPathComponent(folder)
        Task.detached {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let archiveName = "\(folder)_\(formatter.string(from: Date())).hoshi"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(archiveName)
            guard SSZipArchive.createZipFile(
                atPath: tempURL.path(percentEncoded: false),
                withContentsOfDirectory: directory.path(percentEncoded: false)
            ) else {
                await MainActor.run {
                    isLoading = false
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
        loadingString = String(localized: "Restoring...")
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
