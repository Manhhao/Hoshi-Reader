//
//  AnkiQueueView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AnkiQueueView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var ankiQueue = AnkiQueue.shared

    var body: some View {
        List {
            Section {
                let items = Array(ankiQueue.items.reversed())
                ForEach(items) { item in
                    QueuedNoteRow(item: item)
                }
                .onDelete { offsets in
                    offsets.map { items[$0].id }.forEach { ankiQueue.delete(id: $0) }
                }
                .deleteDisabled(ankiQueue.isFlushing)
            }

            if !ankiQueue.items.isEmpty {
                Section {
                    Button {
                        Task { await ankiManager.pingAnkiConnect() }
                    } label: {
                        Text("Send Now", tableName: "Dictionaries")
                    }
                    .disabled(ankiQueue.isFlushing || !ankiManager.isAnkiConnectReachable)
                } footer: {
                    if !ankiManager.isAnkiConnectReachable {
                        Text("AnkiConnect can't be reached right now. Queued cards will be sent automatically once it can.", tableName: "Dictionaries")
                    }
                }
            }
        }
        .overlay {
            if ankiQueue.items.isEmpty {
                ContentUnavailableView(String(localized: "No Queued Cards", table: "Dictionaries"), systemImage: "tray")
            }
        }
        .navigationTitle(String(localized: "Queued Cards", table: "Dictionaries"))
        .task {
            await ankiManager.pingAnkiConnect()
        }
    }
}

struct QueuedNoteRow: View {
    let item: QueuedAnkiNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.word)
            if let lastError = item.lastError {
                Text(verbatim: lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
