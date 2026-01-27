//
//  SyncView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct SyncView: View {
    @Environment(UserConfig.self) var userConfig
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Toggle("Enable Sync", isOn: $userConfig.enableSync)
                Text("Status")
            }
            
            Section {
                TextField("Client ID", text: $userConfig.googleClientId)
            }
            
            Button {
                Task {
                    try await GoogleDriveAuth.shared.authenticate(
                         clientId: userConfig.googleClientId,
                         config: userConfig
                    )
                }
            } label: {
                Text("Log in to Google")
            }
        }
        .navigationTitle("Syncing")
    }
}
