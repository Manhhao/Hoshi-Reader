//
//  AdvancedView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AdvancedView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    AudioView()
                } label: {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                .foregroundStyle(.primary)
                
                NavigationLink {
                    StatisticsSettingsView()
                } label: {
                    Label("Statistics", systemImage: "chart.xyaxis.line")
                }
                .foregroundStyle(.primary)
                
                NavigationLink {
                    SasayakiSettingsView()
                } label: {
                    Label("Sasayaki (Audiobooks)", systemImage: "waveform")
                }
                .foregroundStyle(.primary)
            }
            
            Section {
                NavigationLink {
                    SyncView()
                } label: {
                    Label("ッツ Sync", systemImage: "cloud")
                }
                .foregroundStyle(.primary)
                
                NavigationLink {
                    AnkiConnectView()
                } label: {
                    Label("AnkiConnect", systemImage: "app.connected.to.app.below.fill")
                }
                .foregroundStyle(.primary)
            }
            
            Section {
                NavigationLink {
                    BackupView()
                } label: {
                    Label("Backup", systemImage: "externaldrive")
                }
                .foregroundStyle(.primary)
            }
            
        }
        .navigationTitle("Advanced")
    }
}
