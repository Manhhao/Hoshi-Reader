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
                    Toggle("ッツ Sync", isOn: $userConfig.statisticsEnableSync)
                    Picker("Sync Behaviour", selection: $userConfig.statisticsSyncMode) {
                        ForEach(StatisticsSyncMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Determines if statistics will be merged entry by entry or replaced completely on a sync.")
                }
            }
        }
        .navigationTitle("Statistics")
    }
}
