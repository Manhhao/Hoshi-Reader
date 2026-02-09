//
//  AudioView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var nameInput = ""
    @State private var urlInput = ""
    @State private var isImporting = false
    @State private var importedSize: String?
    
    var body: some View {
        List {
            Section("Sources") {
                ForEach(Array(userConfig.audioSources.enumerated()), id: \.element.id) { index, source in
                    Toggle(isOn: Binding(
                        get: { source.isEnabled },
                        set: { userConfig.audioSources[index].isEnabled = $0 }
                    )) {
                        VStack(alignment: .leading) {
                            Text(source.name)
                                .lineLimit(1)
                            if !source.isDefault && source.url != UserConfig.localAudioSource.url {
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .deleteDisabled(source.isDefault || source.url == UserConfig.localAudioSource.url)
                }
                .onDelete { indexSet in
                    userConfig.audioSources.remove(atOffsets: indexSet)
                }
                .onMove { source, destination in
                    userConfig.audioSources.move(fromOffsets: source, toOffset: destination)
                }
            }
            
            Section("Add Source") {
                TextField("Name", text: $nameInput)
                HStack {
                    TextField("URL", text: $urlInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        let trimmedURL = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedURL.isEmpty && !userConfig.audioSources.contains(where: { $0.url == trimmedURL }) {
                            userConfig.audioSources.append(AudioSource(name: trimmedName, url: trimmedURL))
                            nameInput = ""
                            urlInput = ""
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(urlInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty || nameInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                }
            }
            
            Section {
                Toggle("Enable", isOn: Bindable(userConfig).enableLocalAudio)
                if userConfig.enableLocalAudio {
                    Button("Import") {
                        isImporting = true
                    }
                    if let importedSize {
                        Button("Delete android.db (\(importedSize))", role: .destructive) {
                            deleteAudioDb()
                        }
                    }
                }
            } header: {
                Text("Local Audio")
            } footer: {
                Text("Import an [android.db](https://github.com/KamWithK/AnkiconnectAndroid?tab=readme-ov-file#additional-instructions-local-audio) generated for Ankiconnect Android. The local audio source is automatically added when enabled.")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "db")!]
        ) { result in
            importAudioDb(result: result)
        }
        .onAppear {
            calcAudioDbSize()
        }
        .navigationTitle("Audio")
    }
    
    private let audioDbURL: URL = {
        let docs = try! BookStorage.getDocumentsDirectory()
        return docs.appendingPathComponent(LocalFileServer.localAudioPath)
    }()
    
    private func deleteAudioDb() {
        try? BookStorage.delete(at: audioDbURL)
        importedSize = nil
    }
    
    private func importAudioDb(result: Result<URL, Error>) {
        guard let sourceURL = try? result.get(),
              let _ = try? BookStorage.copySecurityScopedFile(from: sourceURL, to: LocalFileServer.localAudioPath) else {
            return
        }
        calcAudioDbSize()
    }
    
    private func calcAudioDbSize() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: audioDbURL.path(percentEncoded: false)),
              let size = attributes[.size] as? Int64 else {
            importedSize = nil
            return
        }
        importedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
