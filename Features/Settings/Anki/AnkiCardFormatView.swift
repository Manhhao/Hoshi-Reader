//
//  AnkiCardFormatView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AnkiCardFormatView: View {
    let formatId: UUID
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    
    private var formatIndex: Int? {
        ankiManager.cardFormats.firstIndex { $0.id == formatId }
    }
    
    private var availableHandlebars: [String] {
        let showAll = ankiManager.showAllHandlebars
        var options = Handlebars.allCases
            .filter { showAll || !Handlebars.advanced.contains($0) }
            .map(\.rawValue)
        for dict in dictionaryManager.termDictionaries {
            options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)}")
            if showAll {
                options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)-brief}")
                options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)-no-dictionary}")
            }
        }
        return options
    }
    
    private func iconLabel(_ icon: String) -> String {
        switch icon {
        case "plus.square": String(localized: "Square", table: "Dictionaries")
        case "plus.square.small": String(localized: "Square Small", table: "Dictionaries")
        case "plus.circle": String(localized: "Circle", table: "Dictionaries")
        case "plus.circle.small": String(localized: "Circle Small", table: "Dictionaries")
        case "plus.diamond": String(localized: "Diamond", table: "Dictionaries")
        case "plus.diamond.small": String(localized: "Diamond Small", table: "Dictionaries")
        default: icon
        }
    }
    
    var body: some View {
        List {
            if let index = formatIndex {
                Section {
                    TextField(text: $ankiManager.cardFormats[index].name, prompt: Text("Name", tableName: "Dictionaries")) {
                        Text("Name", tableName: "Dictionaries")
                    }
                    .submitLabel(.done)
                    .onSubmit { ankiManager.save() }
                    
                    Picker(selection: $ankiManager.cardFormats[index].icon) {
                        ForEach(AnkiCardFormat.icons, id: \.self) { icon in
                            Text(verbatim: iconLabel(icon)).tag(icon)
                        }
                    } label: {
                        Text("Icon", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.cardFormats[index].icon) { _, _ in ankiManager.save() }
                    
                    Picker(selection: $ankiManager.cardFormats[index].selectedDeck) {
                        ForEach(ankiManager.availableDecks, id: \.self) { deck in
                            Text(verbatim: deck).tag(deck as String?)
                        }
                    } label: {
                        Text("Deck", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.cardFormats[index].selectedDeck) { _, _ in ankiManager.save() }
                    
                    Picker(selection: $ankiManager.cardFormats[index].selectedNoteType) {
                        ForEach(ankiManager.availableNoteTypes) { noteType in
                            Text(verbatim: noteType.name).tag(noteType.name as String?)
                        }
                    } label: {
                        Text("Model", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.cardFormats[index].selectedNoteType) { _, _ in
                        ankiManager.autofillFieldMappings(formatId: formatId)
                        ankiManager.save()
                    }
                } header: {
                    Text("Config", tableName: "Dictionaries")
                }
                
                if let typeName = ankiManager.cardFormats[index].selectedNoteType,
                   let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                    Section {
                        ForEach(noteType.fields, id: \.self) { field in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: field)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                HStack {
                                    TextField(text: Binding(
                                        get: { ankiManager.cardFormats[index].fieldMappings[field] ?? "" },
                                        set: { value in
                                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if trimmed.isEmpty {
                                                ankiManager.cardFormats[index].fieldMappings.removeValue(forKey: field)
                                            } else {
                                                ankiManager.cardFormats[index].fieldMappings[field] = value
                                            }
                                        }
                                    ), prompt: Text("None", tableName: "Dictionaries")) {
                                        Text("None", tableName: "Dictionaries")
                                    }
                                    .submitLabel(.done)
                                    .onSubmit { ankiManager.save() }
                                    
                                    Menu {
                                        Button {
                                            ankiManager.cardFormats[index].fieldMappings.removeValue(forKey: field)
                                            ankiManager.save()
                                        } label: {
                                            Text(verbatim: "-")
                                        }
                                        Divider()
                                        ForEach(availableHandlebars, id: \.self) { option in
                                            Button {
                                                ankiManager.cardFormats[index].fieldMappings[field] = option
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
                            
                            TextField(text: $ankiManager.cardFormats[index].tags, prompt: Text("None", tableName: "Dictionaries")) {
                                Text("None", tableName: "Dictionaries")
                            }
                            .submitLabel(.done)
                            .onSubmit { ankiManager.save() }
                        }
                    } header: {
                        Text("Fields", tableName: "Dictionaries")
                    }
                }
            }
        }
        .navigationTitle(formatIndex.map { ankiManager.cardFormats[$0].name } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { ankiManager.save() }
    }
}
