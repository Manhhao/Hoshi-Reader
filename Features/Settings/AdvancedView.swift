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
            NavigationLink {
                AudioView()
            } label: {
                Label("Audio", systemImage: "speaker.wave.2")
            }
            .foregroundStyle(.primary)
            
            NavigationLink {
                SyncView()
            } label: {
                Label("ッツ Sync", systemImage: "cloud")
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Advanced")
    }
}
