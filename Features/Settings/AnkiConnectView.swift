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
                Text("Will disable AnkiMobile integration.")
            }
            Section {
                if ankiManager.useAnkiConnect {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Address", text: Binding(
                            get: { ankiManager.ankiConnectConfig?.url ?? "" },
                            set: { value in
                                ankiManager.ankiConnectConfig?.url = value
                            }
                        ))
                    }
                    Button("Connect") { Task { await ankiManager.checkConnection() } }
                }
            } header: {
                Text("Connection")
            } footer: {
                if ankiManager.useAnkiConnect {
                    Text("Status: \(ankiManager.isConnected ? "Connected" : "Not connected")")
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
