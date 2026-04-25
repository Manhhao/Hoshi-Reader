//
//  AnkiConnectView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AnkiConnectView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var isImporting = false
    
    var body: some View {
        List {
            Section {
                Toggle("Use AnkiConnect", isOn: $ankiManager.useAnkiConnect)
                    .onChange(of: ankiManager.useAnkiConnect) { _, _ in ankiManager.save() }
            } footer: {
                Text("This will replace AnkiMobile callbacks with AnkiConnect requests.")
            }
            Section {
                if ankiManager.useAnkiConnect {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Address", text: Binding(
                            get: { ankiManager.ankiConnectConfig?.url ?? "" },
                            set: { ankiManager.ankiConnectConfig?.url = $0 }
                        ))
                        .onSubmit { ankiManager.save() }
                    }
                    Button("Connect") { Task { await ankiManager.pingAnkiConnect() } }
                }
            } header: {
                Text("Connection")
            } footer: {
                if ankiManager.useAnkiConnect {
                    Text("Status: \(ankiManager.isConnected ? String(localized: "Connected") : String(localized: "Not connected"))")
                }
            }
            
            if ankiManager.useAnkiConnect && ankiManager.isConnected {
                Section("Settings") {
                    Picker("Duplicate Scope", selection: Binding(
                        get: { ankiManager.ankiConnectConfig?.duplicateScope ?? .collection },
                        set: { value in
                            ankiManager.ankiConnectConfig?.duplicateScope = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Collection").tag(DuplicateScope.collection)
                        Text("Deck").tag(DuplicateScope.deck)
                        Text("Deck Root").tag(DuplicateScope.deckroot)
                    }
                    
                    Toggle("Check All Models", isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.checkAllModels ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.checkAllModels = value
                            ankiManager.save()
                        }
                    ))
                    
                    Toggle("Force Sync on adding card", isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.forceSync ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.forceSync = value
                            ankiManager.save()
                        }
                    ))
                }
            }
        }
        .navigationTitle("AnkiConnect")
    }
}
