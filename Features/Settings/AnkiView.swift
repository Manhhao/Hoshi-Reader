//
//  AnkiView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AnkiView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    
    private var availableHandlebars: [String] {
        var options = Handlebars.allCases.map(\.rawValue)
        for dict in dictionaryManager.termDictionaries {
            options.append("\(Handlebars.singleGlossaryPrefix)\(dict.name)}")
        }
        return options
    }
    
    var body: some View {
        List {
            Section {
                Button("Fetch decks and models from Anki") { ankiManager.requestInfo() }
            }
            
            if ankiManager.isConnected {
                Section("Settings") {
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
                }
            }
            
            if let typeName = ankiManager.selectedNoteType,
               let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                Section("Fields") {
                    ForEach(noteType.fields, id: \.self) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                TextField("-", text: Binding(
                                    get: { ankiManager.fieldMappings[field] ?? "" },
                                    set: { newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            ankiManager.fieldMappings.removeValue(forKey: field)
                                        } else {
                                            ankiManager.fieldMappings[field] = newValue
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
