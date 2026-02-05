//
//  DictionaryView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UniformTypeIdentifiers
import SwiftUI
import SwiftData

struct DictionaryView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var isImporting = false
    @State private var importType: DictionaryType = .term
    @State private var selectedDictionary: DictionaryInfo?
    
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
                Toggle("Compact Glossaries", isOn: Bindable(userConfig).compactGlossaries)
            } header: {
                Text("Lookup Settings")
            } footer: {
                Text("Yomitan term and frequency dictionaries (.zip) are supported")
            }
            
            Section("Term Dictionaries") {
                ForEach(dictionaryManager.termDictionaries) { dict in
                    Toggle(isOn: Binding(
                        get: { dict.isEnabled },
                        set: { dictionaryManager.toggleDictionary(index: dict.order, enabled: $0, type: .term) }
                    ), label: {
                        Text(dict.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    })
                    .onTapGesture {
                        selectedDictionary = dict
                    }
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
        .sheet(item: $selectedDictionary, content: { dictionary in
            DictionaryDetailSettingView(dictionaryInfo: dictionary) {
                selectedDictionary = nil
            }
            .presentationDetents([.large])
        })
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

struct DictionaryDetailSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var dictionaryDetailInfos: [DictionaryDetailInfo]
    @FocusState private var focusState
    let dictionaryInfo: DictionaryInfo
    @State var customCSS: String = ""
    let onDismiss: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    @Bindable var bindableDetailInfos: DictionaryDetailInfo = dictionaryDetailInfos.first!
                    TextEditor(text: $bindableDetailInfos.customCSS)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusState)
                } header: {
                    Text("Custom CSS")
                }
            }
            .onAppear(perform: {
                if dictionaryDetailInfos.count == 0 {
                    modelContext.insert(DictionaryDetailInfo(name: dictionaryInfo.name, customCSS: DictionaryDetailInfo.defaultCSS))
                }
            })
            .toolbar(content: {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Reset", role: .destructive) {
                        @Bindable var bindableDetailInfos: DictionaryDetailInfo = dictionaryDetailInfos.first!
                        bindableDetailInfos.customCSS = DictionaryDetailInfo.defaultCSS
                    }
                    .tint(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button("Done") {
                        focusState = false
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            })
            .padding()
        }
    }
    
    init(dictionaryInfo: DictionaryInfo, onDismiss: (() -> Void)?) {
        self.dictionaryInfo = dictionaryInfo
        self.onDismiss = onDismiss
    }
}
