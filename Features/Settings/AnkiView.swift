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
    
    private var availableHandlebars: [String] {
        var options = Handlebars.allCases.map(\.rawValue)
        for dict in dictionaryManager.termDictionaries {
            options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)}")
        }
        return options
    }
    
    var body: some View {
        List {
            Section {
                Button("Fetch decks and models from Anki") {
                    if !ankiManager.useAnkiConnect {
                        ankiManager.requestInfo()
                    } else {
                        Task { await ankiManager.fetchAnkiConnect() }
                    }
                }
            } footer: {
                if !ankiManager.isConnected {
                    Text("AnkiMobile or a hosted AnkiConnect instance is required to mine words.")
                }
            }
            
            if ankiManager.isConnected {
                Section {
                    Picker("Deck", selection: $ankiManager.selectedDeck) {
                        ForEach(ankiManager.availableDecks, id: \.self) { deck in
                            Text(deck).tag(deck as String?)
                        }
                    }
                    .onChange(of: ankiManager.selectedDeck) { _, _ in ankiManager.save() }
                    
                    Picker("Model", selection: $ankiManager.selectedNoteType) {
                        ForEach(ankiManager.availableNoteTypes) { noteType in
                            Text(noteType.name).tag(noteType.name as String?)
                        }
                    }
                    .onChange(of: ankiManager.selectedNoteType) { _, _ in ankiManager.save() }
                    
                    Toggle("Allow Duplicates", isOn: $ankiManager.allowDupes)
                        .onChange(of: ankiManager.allowDupes) { _, _ in ankiManager.save() }
                    
                    Toggle("Compact Glossaries", isOn: $ankiManager.compactGlossaries)
                        .onChange(of: ankiManager.compactGlossaries) { _, _ in ankiManager.save() }
                    
                    if !ankiManager.useAnkiConnect {
                        Button("Import .colpkg (Stored Words: \(ankiManager.savedWords.count.formatted(.number.grouping(.never))))") {
                            isImporting = true
                        }
                    }
                } header: {
                    Text("Settings");
                } footer: {
                    if !ankiManager.useAnkiConnect {
                        Text("Importing a .colpkg backup from Anki will allow duplicate checks before sending to Anki. It's recommended to do this periodically to reduce drift.")
                    }
                }
            }
            
            if ankiManager.isConnected,
               let typeName = ankiManager.selectedNoteType,
               let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                Section("Fields") {
                    ForEach(noteType.fields, id: \.self) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                TextField("None", text: Binding(
                                    get: { ankiManager.fieldMappings[field] ?? "" },
                                    set: { value in
                                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            ankiManager.fieldMappings.removeValue(forKey: field)
                                        } else {
                                            ankiManager.fieldMappings[field] = value
                                        }
                                    }
                                ))
                                .submitLabel(.done)
                                .onSubmit {
                                    ankiManager.save()
                                }
                                
                                Menu {
                                    Button("-") {
                                        ankiManager.fieldMappings.removeValue(forKey: field)
                                        ankiManager.save()
                                    }
                                    Divider()
                                    ForEach(availableHandlebars, id: \.self) { option in
                                        Button(option) {
                                            ankiManager.fieldMappings[field] = option
                                            ankiManager.save()
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
                        Text("Tags")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        TextField("None", text: $ankiManager.tags)
                            .submitLabel(.done)
                            .onSubmit {
                                ankiManager.save()
                            }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "colpkg")!]
        ) { result in
            if case .success(let url) = result {
                do {
                    try ankiManager.importColpkg(from: url)
                } catch {
                    ankiManager.errorMessage = error.localizedDescription
                }
            }
        }
        .navigationTitle("Anki")
        .alert("Error", isPresented: .init(
            get: { ankiManager.errorMessage != nil },
            set: { if !$0 { ankiManager.errorMessage = nil } }
        )) {
            Button("OK") { ankiManager.errorMessage = nil }
        } message: {
            Text(ankiManager.errorMessage ?? "")
        }
    }
}
