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
    
    private var availableHandlebars: [String] {
        let hidden: Set<Handlebars> = [
            .glossaryNoDictionary,
            .glossaryFirstBrief,
            .glossaryFirstNoDictionary,
            .selectedGlossaryBrief,
            .selectedGlossaryBriefFallback,
            .selectedGlossaryNoDictionary,
            .selectedGlossaryNoDictionaryFallback
        ]
        var options = Handlebars.allCases
            .filter { !hidden.contains($0) }
            .map(\.rawValue)
        for dict in dictionaryManager.termDictionaries {
            options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)}")
        }
        return options
    }
    
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
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !ankiManager.isConnected {
                        Text("AnkiMobile or an AnkiConnect instance is required to mine words.", tableName: "Dictionaries")
                    }
                    if ankiManager.useAnkiConnect {
                        Text("AnkiConnect Status: \(ankiConnectReachabilityStatus)", tableName: "Dictionaries")
                    }
                }
            }
            
            if ankiManager.isConnected {
                Section {
                    Picker(selection: $ankiManager.selectedDeck) {
                        ForEach(ankiManager.availableDecks, id: \.self) { deck in
                            Text(verbatim: deck).tag(deck as String?)
                        }
                    } label: {
                        Text("Deck", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.selectedDeck) { _, _ in ankiManager.save() }
                    
                    Picker(selection: $ankiManager.selectedNoteType) {
                        ForEach(ankiManager.availableNoteTypes) { noteType in
                            Text(verbatim: noteType.name).tag(noteType.name as String?)
                        }
                    } label: {
                        Text("Model", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.selectedNoteType) { _, _ in ankiManager.save() }
                    
                    if !ankiManager.useAnkiConnect {
                        Button {
                            isImporting = true
                        } label: {
                            Text("Import Anki Backup (Stored Words: \(ankiManager.savedWords.count.formatted(.number.grouping(.never))))", tableName: "Dictionaries")
                        }
                    }
                } header: {
                    Text("Config", tableName: "Dictionaries")
                } footer: {
                    if !ankiManager.useAnkiConnect {
                        Text("Importing a .colpkg/.apkg backup from Anki will allow Hoshi Reader to check for duplicates immediately. It's recommended to do this periodically to reduce drift.", tableName: "Dictionaries")
                    }
                }
                
                Section {
                    Toggle(isOn: $ankiManager.allowDupes) {
                        Text("Allow Duplicates", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.allowDupes) { _, _ in ankiManager.save() }
                    
                    Toggle(isOn: $ankiManager.compactGlossaries) {
                        Text("Compact Glossaries", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.compactGlossaries) { _, _ in ankiManager.save() }
                    
                    if !ankiManager.useAnkiConnect {
                        VStack {
                            Toggle("Embed Dictionary Media", isOn: $ankiManager.embedMedia)
                                .onChange(of: ankiManager.embedMedia) { _, _ in ankiManager.save() }
                            Text("Embedding media will increase size of glossaries (AnkiMobile).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    Text("Settings")
                }
            }
            
            if ankiManager.isConnected,
               let typeName = ankiManager.selectedNoteType,
               let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                Section {
                    ForEach(noteType.fields, id: \.self) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: field)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                TextField(text: Binding(
                                    get: { ankiManager.fieldMappings[field] ?? "" },
                                    set: { value in
                                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            ankiManager.fieldMappings.removeValue(forKey: field)
                                        } else {
                                            ankiManager.fieldMappings[field] = value
                                        }
                                    }
                                ), prompt: Text("None", tableName: "Dictionaries")) {
                                    Text("None", tableName: "Dictionaries")
                                }
                                .submitLabel(.done)
                                .onSubmit {
                                    ankiManager.save()
                                }
                                
                                Menu {
                                    Button {
                                        ankiManager.fieldMappings.removeValue(forKey: field)
                                        ankiManager.save()
                                    } label: {
                                        Text(verbatim: "-")
                                    }
                                    Divider()
                                    ForEach(availableHandlebars, id: \.self) { option in
                                        Button {
                                            ankiManager.fieldMappings[field] = option
                                            ankiManager.save()
                                        } label: {
                                            Text(verbatim: option)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tags", tableName: "Dictionaries")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        TextField(text: $ankiManager.tags, prompt: Text("None", tableName: "Dictionaries")) {
                            Text("None", tableName: "Dictionaries")
                        }
                        .submitLabel(.done)
                        .onSubmit {
                            ankiManager.save()
                        }
                    }
                } header: {
                    Text("Fields", tableName: "Dictionaries")
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
