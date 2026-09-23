//
//  StatisticsEditView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct StatisticsEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionEntries: [SessionEntry] = []
    @State private var selectedEntry: SessionEntry?
    @State private var showDeleteConfirmation = false
    let book: BookMetadata
    
    var body: some View {
        List {
            Section("Sessions") {
                ForEach(sessionEntries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    entry.startedAt,
                                    format: .dateTime.day().month(.abbreviated).year().hour().minute()
                                )
                                    .font(.subheadline)
                                Text(entry.session.charactersRead.formatted(.number))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            
                            Spacer()
                            
                            Text(entry.session.readingTime.formattedDuration)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    deleteSessions(
                        ids: offsets.map {
                            sessionEntries[$0].id
                        }
                    )
                }
            }
            
            Section {
                Button("Delete All Statistics", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(book.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            SessionEditView(entry: entry) { characters, time in
                StatisticsStorage.edit(id: entry.id, folder: book.folder, charactersRead: characters, readingTime: time)
                loadSessions()
            }
        }
        .alert("Delete All Statistics?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSessions(ids: sessionEntries.map(\.id))
                dismiss()
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all recorded statistics for this book.")
        }
        .onAppear {
            loadSessions()
        }
    }
    
    private func loadSessions() {
        sessionEntries = StatisticsStorage.load(folder: book.folder).compactMap { id, change in
            guard let session = change.value else {
                return nil
            }
            return SessionEntry(id: id, session: session)
        }.sorted { first, second in
            if first.session.startedAt == second.session.startedAt {
                return first.id < second.id
            }
            return first.session.startedAt < second.session.startedAt
        }
    }
    
    private func deleteSessions(ids: [String]) {
        StatisticsStorage.delete(ids: ids, folder: book.folder)
        loadSessions()
    }
}

private struct SessionEntry: Identifiable {
    let id: String
    let session: ReadingSession
    
    var startedAt: Date {
        Date(milliseconds: session.startedAt)
    }
}

private struct SessionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var charactersRead: Int
    @State private var hours: Int
    @State private var minutes: Int
    let entry: SessionEntry
    let onSave: (Int?, Double?) -> Void
    
    init(entry: SessionEntry, onSave: @escaping (Int?, Double?) -> Void) {
        self.entry = entry
        self.onSave = onSave
        
        charactersRead = entry.session.charactersRead
        let totalMinutes = Int((entry.session.readingTime / 60).rounded())
        hours = totalMinutes / 60
        minutes = totalMinutes % 60
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Characters Read") {
                    TextField("Characters Read", value: $charactersRead, format: .number)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                }
                
                Section("Reading Time") {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $hours) {
                            ForEach(0..<24) {
                                Text("\($0)h").tag($0)
                            }
                        }
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60) {
                                Text("\($0)m").tag($0)
                            }
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
            }
            .navigationTitle(entry.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let totalMinutes = hours * 60 + minutes
                        let readingTime =
                            totalMinutes == Int((entry.session.readingTime / 60).rounded())
                            ? entry.session.readingTime : Double(totalMinutes * 60)
                        let characters = max(charactersRead, 0)
                        
                        onSave(
                            characters == entry.session.charactersRead ? nil : characters,
                            readingTime == entry.session.readingTime ? nil : readingTime
                        )
                        
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
