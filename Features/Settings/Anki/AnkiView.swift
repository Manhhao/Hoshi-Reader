//
//  AnkiView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AnkiView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var isImporting = false
    @State private var confirmFetch = false
    
    private let maxFormats = 3
    
    var body: some View {
        List {
            Section {
                if ankiManager.useAnkiConnect && !ankiManager.isConnected {
                    Button {
                        Task { await ankiManager.pingAnkiConnect() }
                    } label: {
                        Text("Connect", tableName: "Dictionaries")
                    }
                } else {
                    Button {
                        confirmFetch = true
                    } label: {
                        Text("Fetch decks and models from Anki", tableName: "Dictionaries")
                    }
                }
                if !ankiManager.useAnkiConnect && ankiManager.isConnected {
                    Button {
                        isImporting = true
                    } label: {
                        Text("Import Anki Backup (Stored Words: \(ankiManager.savedWords.count.formatted(.number.grouping(.never))))", tableName: "Dictionaries")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !ankiManager.isConnected {
                        Text("AnkiMobile or an AnkiConnect instance is required to mine words.", tableName: "Dictionaries")
                    }
                    if ankiManager.useAnkiConnect {
                        Text("AnkiConnect Status: \(ankiConnectReachabilityStatus)", tableName: "Dictionaries")
                    }
                    if !ankiManager.useAnkiConnect && ankiManager.isConnected {
                        if !ankiManager.useAnkiConnect {
                            Text("Importing a .colpkg/.apkg backup from Anki will allow Hoshi Reader to check for duplicates immediately. It's recommended to do this periodically to reduce drift.", tableName: "Dictionaries")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: ["colpkg", "apkg"].map { UTType(filenameExtension: $0)! }
            ) { result in
                if case .success(let url) = result {
                    do {
                        try ankiManager.importAnkiBackup(from: url)
                    } catch {
                        ankiManager.errorMessage = error.localizedDescription
                    }
                }
            }
            
            if ankiManager.isConnected {
                Section {
                    ForEach(ankiManager.cardFormats) { cardFormat in
                        NavigationLink {
                            AnkiCardFormatView(formatId: cardFormat.id)
                        } label: {
                            Label {
                                Text(verbatim: cardFormat.name)
                            } icon: {
                                AnkiCardFormatIcon(icon: cardFormat.icon)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { ankiManager.cardFormats[$0].id }
                        for id in ids {
                            ankiManager.deleteCardFormat(id: id)
                        }
                    }
                    .deleteDisabled(ankiManager.cardFormats.count <= 1)
                    
                    Button {
                        ankiManager.addCardFormat()
                    } label: {
                        Text("Add Format", tableName: "Dictionaries")
                    }
                    .disabled(ankiManager.cardFormats.count >= maxFormats)
                } header: {
                    Text("Formats", tableName: "Dictionaries")
                }
                
                Section {
                    Toggle(isOn: $ankiManager.allowDupes) {
                        Text("Allow Duplicates", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.allowDupes) { _, _ in ankiManager.save() }
                    
                    Toggle(isOn: $ankiManager.disableShowNotes) {
                        Text("Disable Show Notes Button", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.disableShowNotes) { _, _ in ankiManager.save() }
                    
                    Toggle(isOn: $ankiManager.compactGlossaries) {
                        Text("Compact Glossaries", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.compactGlossaries) { _, _ in ankiManager.save() }
                    
                    NavigationLink {
                        AnkiAdvancedView()
                    } label: {
                        Text("Advanced", tableName: "Dictionaries")
                    }
                } header: {
                    Text("Settings", tableName: "Dictionaries")
                }
            }
        }
        .navigationTitle(String(localized: "Anki", table: "Dictionaries"))
        .onDisappear { ankiManager.save() }
        .alert(String(localized: "Fetch from Anki?", table: "Dictionaries"), isPresented: $confirmFetch) {
            Button {
                if ankiManager.useAnkiConnect {
                    Task { await ankiManager.fetchAnkiConnect() }
                } else {
                    ankiManager.requestInfo()
                }
            } label: {
                Text("OK", tableName: "Dictionaries")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", tableName: "Dictionaries")
            }
        } message: {
            Text("This will clear your current mappings.", tableName: "Dictionaries")
        }
        .alert(String(localized: "Error", table: "Dictionaries"), isPresented: .init(
            get: { ankiManager.errorMessage != nil },
            set: { if !$0 { ankiManager.errorMessage = nil } }
        )) {
            Button {
                ankiManager.errorMessage = nil
            } label: {
                Text("OK", tableName: "Dictionaries")
            }
        } message: {
            Text(verbatim: ankiManager.errorMessage ?? "")
        }
    }
    
    private var ankiConnectReachabilityStatus: String {
        if ankiManager.isAnkiConnectReachable {
            String(localized: "Connected", table: "Dictionaries")
        } else {
            String(localized: "Not Connected", table: "Dictionaries")
        }
    }
}

struct AnkiCardFormatIcon: View {
    let icon: String
    
    var body: some View {
        if icon.hasSuffix(".small") {
            Image(systemName: String(icon.dropLast(".small".count)))
                .imageScale(.small)
        } else {
            Image(systemName: icon)
        }
    }
}
