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
    @State private var showCSSEditor = false
    @State private var showDownloadConfirmation = false
    @State private var showUpdateConfirmation = false
    @State private var selectedType: DictionaryType = .term
    
    private var dictionaries: [DictionaryInfo] {
        switch selectedType {
        case .term: return dictionaryManager.termDictionaries
        case .frequency: return dictionaryManager.frequencyDictionaries
        case .pitch: return dictionaryManager.pitchDictionaries
        }
    }
    
    private var lastUpdate: String {
        guard let date = UserDefaults.standard.object(forKey: "lastDictionaryUpdate") as? Date else {
            return "Never"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    
    var body: some View {
        List {
            Section {
                Button("Download Recommended Dictionaries") {
                    showDownloadConfirmation = true
                }
                .disabled(dictionaryManager.isImporting)
                .alert("Download Dictionaries", isPresented: $showDownloadConfirmation) {
                    Button("Download") {
                        dictionaryManager.importRecommendedDictionaries()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will download the latest version of the following dictionaries (33 MB):\nJMdict (Term)\nJMnedict (Term)\nJiten (Frequency)")
                }
            } footer: {
                Text("Yomitan term, frequency and pitch dictionaries (.zip) are supported")
            }
            
            if (dictionaryManager.updatableDictionaries.count > 0) {
                Section("Updates") {
                    Toggle("Update Automatically", isOn: Bindable(userConfig).autoUpdateDictionaries)
                    if userConfig.autoUpdateDictionaries {
                        Picker("Interval", selection: Bindable(userConfig).dictionaryUpdateInterval) {
                            ForEach(DictionaryUpdateInterval.allCases, id: \.self) { interval in
                                Text(interval.rawValue).tag(interval)
                            }
                        }
                    }
                    LabeledContent("Last Update", value: lastUpdate)
                    Button("Update") {
                        showUpdateConfirmation = true
                    }
                    .alert("Update Dictionaries", isPresented: $showUpdateConfirmation) {
                        Button("Update") {
                            dictionaryManager.updateDictionaries()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will check for and install updates for these dictionaries:\n\(dictionaryManager.updatableDictionaries.map(\.0.index.title).joined(separator: "\n"))")
                    }
                }
            }
            
            Section {
                Toggle("Default to Dictionary Tab", isOn: Bindable(userConfig).dictionaryTabDefault)
                NavigationLink("Settings") {
                    DictionarySettingsView()
                }
            }
            
            Section {
                ForEach(dictionaries) { dict in
                    Toggle(isOn: Binding(
                        get: { dict.isEnabled },
                        set: { dictionaryManager.toggleDictionary(id: dict.id, enabled: $0, type: selectedType) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dict.index.title)
                            Text(dict.index.revision)
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { from, to in
                    dictionaryManager.moveDictionary(from: from, to: to, type: selectedType)
                }
                .onDelete { indexSet in
                    dictionaryManager.deleteDictionary(indexSet: indexSet, type: selectedType)
                }
            } header: {
                Picker("Type", selection: $selectedType) {
                    Text("Term").tag(DictionaryType.term)
                    Text("Frequency").tag(DictionaryType.frequency)
                    Text("Pitch").tag(DictionaryType.pitch)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showCSSEditor) {
            DictionaryDetailSettingView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("", systemImage: "curlybraces") {
                    showCSSEditor = true
                }
                .disabled(dictionaryManager.isImporting || dictionaryManager.isUpdating)
            }
            
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.zip],
                    allowsMultipleSelection: true,
                    onCompletion: { result in
                        if case .success(let urls) = result {
                            dictionaryManager.importDictionary(from: urls)
                        }
                    }
                )
                .disabled(dictionaryManager.isImporting || dictionaryManager.isUpdating)
            }
        }
        .overlay {
            if dictionaryManager.isImporting || dictionaryManager.isUpdating {
                LoadingOverlay(dictionaryManager.currentImport)
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

struct DictionarySettingsView: View {
    @Environment(UserConfig.self) private var userConfig
    
    var body: some View {
        List {
            Section("Lookup") {
                Toggle("Scan Non-Japanese Text", isOn: Bindable(userConfig).scanNonJapaneseText)
                HStack {
                    Text("Max Results")
                    Spacer()
                    Text("\(userConfig.maxResults)")
                        .fontWeight(.semibold)
                    Stepper("", value: Bindable(userConfig).maxResults, in: 1...50)
                        .labelsHidden()
                }
                HStack {
                    Text("Scan Length")
                    Spacer()
                    Text("\(userConfig.scanLength)")
                        .fontWeight(.semibold)
                    Stepper("", value: Bindable(userConfig).scanLength, in: 1...64)
                        .labelsHidden()
                }
            }
            
            Section("Collapse Dictionaries") {
                Picker("Mode", selection: Bindable(userConfig).collapseMode) {
                    ForEach(CollapseMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                if userConfig.collapseMode != .expandAll {
                    Toggle("Expand First Dictionary", isOn: Bindable(userConfig).expandFirstDictionary)
                }
                if userConfig.collapseMode == .custom {
                    NavigationLink("Configure") {
                        CollapsedDictionariesView()
                    }
                }
            }
            
            Section("Behaviour") {
                Toggle("Compact Glossaries", isOn: Bindable(userConfig).compactGlossaries)
                Toggle("Show Expression Tags", isOn: Bindable(userConfig).showExpressionTags)
                Toggle("Harmonic Frequency", isOn: Bindable(userConfig).harmonicFrequency)
                Toggle("Deduplicate Pitch Accents", isOn: Bindable(userConfig).deduplicatePitchAccents)
                Toggle("Compact Pitch Accents", isOn: Bindable(userConfig).compactPitchAccents)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CollapsedDictionariesView: View {
    @State private var dictionaryManager = DictionaryManager.shared
    
    var body: some View {
        List {
            ForEach(dictionaryManager.termDictionaries) { dict in
                HStack {
                    Image(systemName: dictionaryManager.collapsedDictionaries.contains(dict.index.title) ? "chevron.right" : "chevron.down")
                        .foregroundStyle(dictionaryManager.collapsedDictionaries.contains(dict.index.title) ? .secondary : .primary)
                        .frame(width: 16)
                    Text(dict.index.title)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dictionaryManager.toggleCollapsedDictionary(title: dict.index.title)
                }
            }
        }
        .navigationTitle("Collapse Dictionaries")
        .navigationBarTitleDisplayMode(.inline)
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
