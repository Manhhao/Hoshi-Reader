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
    @State private var ankiQueue = AnkiQueue.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $ankiManager.useAnkiConnect) {
                    Text("Use AnkiConnect", tableName: "Dictionaries")
                }
                .onChange(of: ankiManager.useAnkiConnect) { _, _ in ankiManager.save() }
            } footer: {
                Text("This will replace AnkiMobile callbacks with AnkiConnect requests.", tableName: "Dictionaries")
            }
            if ankiManager.useAnkiConnect {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(text: Binding(
                            get: { ankiManager.ankiConnectConfig?.url ?? "" },
                            set: { ankiManager.ankiConnectConfig?.url = $0 }
                        ), prompt: Text("Address", tableName: "Dictionaries")) {
                            Text("Address", tableName: "Dictionaries")
                        }
                        .onSubmit { ankiManager.save() }
                    }
                    SecureField(text: Binding(
                        get: { ankiManager.ankiConnectConfig?.apiKey ?? "" },
                        set: { ankiManager.ankiConnectConfig?.apiKey = $0 }
                    ), prompt: Text("API Key (optional)", tableName: "Dictionaries")) {
                        Text("API Key (optional)", tableName: "Dictionaries")
                    }
                    .onSubmit { ankiManager.save() }
                    Button {
                        Task { await ankiManager.pingAnkiConnect() }
                    } label: {
                        Text("Connect", tableName: "Dictionaries")
                    }
                } header: {
                    Text("Connection", tableName: "Dictionaries")
                } footer: {
                    if ankiManager.useAnkiConnect {
                        Text("Status: \(connectionStatus)", tableName: "Dictionaries")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.queueOffline ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.queueOffline = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Queue Cards While Offline", tableName: "Dictionaries")
                    }
                    let recentItems = Array(ankiQueue.items.suffix(3).reversed())
                    ForEach(recentItems) { item in
                        QueuedNoteRow(item: item)
                    }
                    .onDelete { offsets in
                        offsets.map { recentItems[$0].id }.forEach { ankiQueue.delete(id: $0) }
                    }
                    .deleteDisabled(ankiQueue.isFlushing)
                    if ankiQueue.items.count > recentItems.count {
                        NavigationLink {
                            AnkiQueueView()
                        } label: {
                            Text("See All (\(ankiQueue.items.count))", tableName: "Dictionaries")
                        }
                    }
                    if !ankiQueue.items.isEmpty {
                        Button {
                            Task { await ankiManager.pingAnkiConnect() }
                        } label: {
                            Text("Send Now", tableName: "Dictionaries")
                        }
                        .disabled(ankiQueue.isFlushing || !ankiManager.isAnkiConnectReachable)
                    }
                } header: {
                    Text("Offline Queue", tableName: "Dictionaries")
                } footer: {
                    Text("Cards mined while AnkiConnect is unreachable are saved on this device and sent once it can be reached again.", tableName: "Dictionaries")
                }
            }

            if ankiManager.useAnkiConnect && ankiManager.isConnected {
                Section {
                    Picker(selection: Binding(
                        get: { ankiManager.ankiConnectConfig?.duplicateScope ?? .collection },
                        set: { value in
                            ankiManager.ankiConnectConfig?.duplicateScope = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Collection", tableName: "Dictionaries").tag(DuplicateScope.collection)
                        Text("Deck", tableName: "Dictionaries").tag(DuplicateScope.deck)
                        Text("Deck Root", tableName: "Dictionaries").tag(DuplicateScope.deckroot)
                    } label: {
                        Text("Duplicate Scope", tableName: "Dictionaries")
                    }
                    
                    Toggle(isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.checkAllModels ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.checkAllModels = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Check All Models", tableName: "Dictionaries")
                    }
                    
                    Toggle(isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.forceSync ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.forceSync = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Force Sync on adding card", tableName: "Dictionaries")
                    }
                } header: {
                    Text("Settings", tableName: "Dictionaries")
                }
            }
        }
        .navigationTitle(String(localized: "AnkiConnect", table: "Dictionaries"))
        .task {
            // refresh reachability so the queue controls reflect the current state
            if ankiManager.useAnkiConnect {
                await ankiManager.pingAnkiConnect()
            }
        }
    }
    
    private var connectionStatus: String {
        if ankiManager.isConnected {
            String(localized: "Connected", table: "Dictionaries")
        } else {
            String(localized: "Not connected", table: "Dictionaries")
        }
    }
}
