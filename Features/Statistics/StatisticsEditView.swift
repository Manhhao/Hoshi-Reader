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
    @State private var statistics: [Statistics] = []
    @State private var selectedStatistic: Statistics?
    @State private var showDeleteConfirmation = false
    let book: BookMetadata
    
    var body: some View {
        List {
            Section("Days") {
                ForEach(statistics) { statistic in
                    Button {
                        selectedStatistic = statistic
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(statistic.date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.subheadline)
                                Text(statistic.charactersRead.formatted(.number))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            
                            Spacer()
                            
                            Text(statistic.readingTime.formattedDuration)
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
                    statistics.remove(atOffsets: offsets)
                    StatisticsStorage.save(statistics, folder: book.folder)
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
        .sheet(item: $selectedStatistic) { statistic in
            DayEditView(statistic: statistic) { updated in
                if let index = statistics.firstIndex(where: { $0.dateKey == updated.dateKey }) {
                    statistics[index] = updated
                }
                StatisticsStorage.save(statistics, folder: book.folder)
            }
        }
        .alert("Delete All Statistics?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                statistics = []
                StatisticsStorage.save(statistics, folder: book.folder)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all recorded statistics for this book.")
        }
        .onAppear {
            statistics = StatisticsStorage.load(folder: book.folder)
        }
    }
}

private struct DayEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var charactersRead: Int
    @State private var hours: Int
    @State private var minutes: Int
    let statistic: Statistics
    let onSave: (Statistics) -> Void
    
    init(statistic: Statistics, onSave: @escaping (Statistics) -> Void) {
        self.statistic = statistic
        self.onSave = onSave
        charactersRead = statistic.charactersRead
        let totalMinutes = Int((statistic.readingTime / 60).rounded())
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
            .navigationTitle(statistic.date.formatted(.dateTime.day().month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = statistic
                        updated.update(charactersRead: charactersRead, readingTime: Double(hours * 3600 + minutes * 60))
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
