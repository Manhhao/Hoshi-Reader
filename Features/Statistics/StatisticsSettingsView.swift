//
//  StatisticsSettingsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct StatisticsSettingsView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var archivedBooks: [BookStatistics] = []
    @State private var showClearArchiveConfirmation = false
    
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Picker("Autostart", selection: $userConfig.statisticsAutostartMode) {
                    ForEach(StatisticsAutostartMode.allCases, id: \.self) { mode in
                        textOfAutoRestartMode(mode).tag(mode)
                    }
                }
            } footer: {
                Text("Statistics can be accessed from the Reader's context menu.")
            }
            
            Section {
                DatePicker("Reset Time", selection: resetTimeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
            }
            
            if userConfig.enableSync {
                Section {
                    Toggle("ッツ Sync", isOn: $userConfig.statisticsEnableSync)
                    Picker("Sync Behaviour", selection: $userConfig.statisticsSyncMode) {
                        ForEach(StatisticsSyncMode.allCases, id: \.self) { mode in
                            textOfAutoSyncMode(mode).tag(mode)
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Determines if statistics will be merged entry by entry or replaced completely on a sync.")
                }
            }
            
            if !archivedBooks.isEmpty {
                Section {
                    Button("Clear Archive", role: .destructive) {
                        showClearArchiveConfirmation = true
                    }
                } header: {
                    Text("Archive")
                } footer: {
                    Text("\(archivedBooks.count) books")
                }
            }
        }
        .navigationTitle("Statistics")
        .alert("Clear Archive?", isPresented: $showClearArchiveConfirmation) {
            Button("Clear", role: .destructive) {
                StatisticsStorage.clearArchive()
                archivedBooks = []
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete the statistics of \(archivedBooks.count) deleted books.")
        }
        .onAppear {
            archivedBooks = StatisticsStorage.loadArchived()
        }
    }
    
    private func textOfAutoRestartMode(_ mode: StatisticsAutostartMode) -> some View {
        switch mode {
        case .off:
            Text("Off")
        case .pageturn:
            Text("Page Turn")
        case .on:
            Text("On")
        }
    }
    
    private var resetTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: userConfig.statisticsResetTime / 60, minute: userConfig.statisticsResetTime % 60)) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            userConfig.statisticsResetTime = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }
    
    private func textOfAutoSyncMode(_ mode: StatisticsSyncMode) -> some View {
        switch mode {
        case .merge:
            Text("Merge")
        case .replace:
            Text("Replace")
        }
    }
}
