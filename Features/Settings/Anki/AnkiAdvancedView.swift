//
//  AnkiAdvancedView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AnkiAdvancedView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    
    private static let fallbackOptions = [
        Handlebars.glossaryFirst.rawValue,
        Handlebars.monolingualDefinition.rawValue,
        Handlebars.bilingualDefinition.rawValue,
        Handlebars.monolingualDefinitionFallback.rawValue,
        Handlebars.bilingualDefinitionFallback.rawValue,
    ]
    
    var body: some View {
        List {
            Section {
                if !ankiManager.useAnkiConnect {
                    VStack {
                        Toggle(String(localized: "Embed Dictionary Media", table: "Dictionaries"), isOn: $ankiManager.embedMedia)
                            .onChange(of: ankiManager.embedMedia) { _, _ in ankiManager.save() }
                        Text("Embedding media will increase size of glossaries (AnkiMobile).", tableName: "Dictionaries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { ankiManager.showAllHandlebars },
                    set: { ankiManager.showAllHandlebars = $0; ankiManager.save() }
                )) {
                    Text("Show All Handlebars", tableName: "Dictionaries")
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("{selected-glossary} Fallback", tableName: "Dictionaries")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        TextField(text: Binding(
                            get: { ankiManager.selectedGlossaryFallback },
                            set: { ankiManager.selectedGlossaryFallback = $0 }
                        ), prompt: Text("None", tableName: "Dictionaries")) {
                            Text("None", tableName: "Dictionaries")
                        }
                        .submitLabel(.done)
                        .onSubmit { ankiManager.save() }
                        
                        Menu {
                            Button {
                                ankiManager.selectedGlossaryFallback = ""
                                ankiManager.save()
                            } label: {
                                Text("None", tableName: "Dictionaries")
                            }
                            Divider()
                            ForEach(Self.fallbackOptions, id: \.self) { option in
                                Button {
                                    ankiManager.selectedGlossaryFallback = option
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
            
            Section {
                ForEach(dictionaryManager.termDictionaries) { dict in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: dict.index.title)
                            .lineLimit(1)
                        
                        Picker(selection: Binding(
                            get: { dict.category },
                            set: { dictionaryManager.setDictionaryCategory(id: dict.id, category: $0) }
                        )) {
                            ForEach(DictionaryCategory.allCases) { category in
                                Text(verbatim: category.label).tag(category)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Categorize Dictionaries", tableName: "Dictionaries")
            }
        }
        .navigationTitle(String(localized: "Advanced", table: "Dictionaries"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
