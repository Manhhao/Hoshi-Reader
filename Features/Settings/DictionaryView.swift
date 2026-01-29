//
//  DictionaryView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UniformTypeIdentifiers
import SwiftUI

struct DictionaryView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var isImporting = false
    @State private var importType: DictionaryType = .term
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Max Results")
                    Spacer()
                    Text("\(userConfig.maxResults)")
                        .fontWeight(.semibold)
                    Stepper("", value: Bindable(userConfig).maxResults, in: 1...50)
                        .labelsHidden()
                }
                Toggle("Auto-collapse Dictionaries", isOn: Bindable(userConfig).collapseDictionaries)
            } header: {
                Text("Lookup Settings")
            } footer: {
                Text("Yomitan term and frequency dictionaries (.zip) are supported")
            }
            
            Section("Term Dictionaries") {
                ForEach(dictionaryManager.termDictionaries) { dict in
                    Toggle(dict.name, isOn: Binding(
                        get: { dict.isEnabled },
                        set: { dictionaryManager.toggleDictionary(index: dict.order, enabled: $0, type: .term) }
                    ))
                }
                .onMove { from, to in
                    dictionaryManager.moveDictionary(from: from, to: to, type: .term)
                }
                .onDelete { indexSet in
                    dictionaryManager.deleteDictionary(indexSet: indexSet, type: .term)
                }
            }
            
            Section("Frequency Dictionaries") {
                ForEach(dictionaryManager.frequencyDictionaries) { dict in
                    Toggle(dict.name, isOn: Binding(
                        get: { dict.isEnabled },
                        set: { dictionaryManager.toggleDictionary(index: dict.order, enabled: $0, type: .frequency) }
                    ))
                }
                .onMove { from, to in
                    dictionaryManager.moveDictionary(from: from, to: to, type: .frequency)
                }
                .onDelete { indexSet in
                    dictionaryManager.deleteDictionary(indexSet: indexSet, type: .frequency)
                }
            }
            
            Section("Pitch Dictionaries") {
                ForEach(dictionaryManager.pitchDictionaries) { dict in
                    Toggle(dict.name, isOn: Binding(
                        get: { dict.isEnabled },
                        set: { dictionaryManager.toggleDictionary(index: dict.order, enabled: $0, type: .pitch) }
                    ))
                }
                .onMove { from, to in
                    dictionaryManager.moveDictionary(from: from, to: to, type: .pitch)
                }
                .onDelete { indexSet in
                    dictionaryManager.deleteDictionary(indexSet: indexSet, type: .pitch)
                }
            }
        }
        .onAppear {
            dictionaryManager.loadDictionaries()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        importType = .term
                        isImporting = true
                    } label: {
                        Label("Term", systemImage: "character.book.closed")
                    }
                    
                    Button {
                        importType = .frequency
                        isImporting = true
                    } label: {
                        Label("Frequency", systemImage: "numbers.rectangle")
                    }
                    
                    Button {
                        importType = .pitch
                        isImporting = true
                    } label: {
                        Label("Pitch", systemImage: "underline")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.zip],
                    onCompletion: { result in
                        if case .success(let url) = result {
                            dictionaryManager.importDictionary(from: url, type: importType)
                        }
                    }
                )
                .disabled(dictionaryManager.isImporting)
            }
        }
        .overlay {
            if dictionaryManager.isImporting {
                LoadingOverlay("Importing...")
            }
        }
        .navigationTitle("Dictionaries")
        .alert("Error", isPresented: $dictionaryManager.shouldShowError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictionaryManager.errorMessage)
        }
    }
}
