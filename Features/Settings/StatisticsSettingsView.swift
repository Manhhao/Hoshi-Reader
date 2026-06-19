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
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Toggle("Enable", isOn: $userConfig.enableStatistics)
            } footer: {
                Text("Statistics can be accessed from the Reader's context menu.")
            }
            
            if userConfig.enableStatistics {
                Section {
                    Picker("Autostart", selection: $userConfig.statisticsAutostartMode) {
                        ForEach(StatisticsAutostartMode.allCases, id: \.self) { mode in
                            textOfAutoRestartMode(mode).tag(mode)
                        }
                    }
                }
                
                Section {
                    Picker("Reset Time", selection: $userConfig.statisticsResetTime) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formattedTime(hour)).tag(hour)
                        }
                    }
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
            }
        }
        .navigationTitle("Statistics")
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
    
    private func formattedTime(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
