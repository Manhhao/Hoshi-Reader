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
    @State private var showCSSEditor = false
    @State private var showDownloadConfirmation = false
    
    var body: some View {
        List {
            Section {
                Button("Get recommended dictionaries") {
                    showDownloadConfirmation = true
                }
                .disabled(dictionaryManager.isImporting)
                .alert("Download Dictionaries", isPresented: $showDownloadConfirmation) {
                    Button("Download") {
                        dictionaryManager.importRecommendedDictionaries()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will download the latest JMdict Yomitan (Term) and Jiten.moe (Frequency) dictionaries.")
                }
            }
            
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
                Toggle("Compact Glossaries", isOn: Bindable(userConfig).compactGlossaries)
            } header: {
                Text("Lookup Settings")
            } footer: {
                Text("Yomitan term, frequency and pitch dictionaries (.zip) are supported")
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
        .sheet(isPresented: $showCSSEditor) {
            DictionaryDetailSettingView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("", systemImage: "paintbrush") {
                    showCSSEditor = true
                }
                Menu {
                    Button {
                        importType = .term
                        isImporting = true
                    } label: {
                        Label("Term", systemImage: "character.text.justify.ja")
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
                        Label("Pitch", systemImage: "textformat.characters.dottedunderline.ja")
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

struct DictionaryDetailSettingView: View {
    @Environment(UserConfig.self) var userConfig
    @Environment(\.dismiss) private var dismiss
    @State private var customCSS: String = ""

    var body: some View {
        NavigationStack {
            CSSEditorView(text: $customCSS)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(Color(.secondarySystemBackground).ignoresSafeArea())
                .navigationTitle("Custom CSS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Reset", role: .destructive) {
                            customCSS = ""
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
        }
        .onAppear {
            customCSS = userConfig.customCSS
        }
        .onDisappear {
            userConfig.customCSS = customCSS
        }
    }
}
