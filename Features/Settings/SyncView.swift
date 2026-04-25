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
    @State private var isAuthenticated = GoogleDriveAuth.shared.isAuthenticated
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Toggle("Enable", isOn: $userConfig.enableSync)
            } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync bookmarks and statistics with ッツ Reader or between Hoshi Reader devices via Google Drive.")
                        if userConfig.enableSync {
                            Text("A **[Google Cloud project](https://github.com/ttu-ttu/ebook-reader?tab=readme-ov-file#storage-sources)** is necessary for syncing.")
                            Text("1. After the initial setup, create another **OAuth client ID** in the same project.")
                            Text("2. Select **iOS** as the **Application type** and set the **Bundle ID** to '**de.manhhao.hoshi**'.")
                            Text("3. Paste the **Client ID** in the textbox below and press '**Connect Google Drive**'.")
                            Text("4. You can sync individual books by long-pressing and selecting '**Sync**'.")
                        }
                    }
            }
            
            if userConfig.enableSync {
                Section {
                    Picker("Direction", selection: $userConfig.syncMode) {
                        ForEach(SyncMode.allCases, id: \.self) { mode in
                            Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                        }
                    }
                }
                
                Section("Client ID") {
                    TextField("Required", text: $userConfig.googleClientId)
                }
                
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(isAuthenticated ? String(localized: "Connected") : String(localized: "Not connected"))
                            .foregroundStyle(.secondary)
                    }
                    if isAuthenticated {
                        Button(role: .destructive) {
                            TokenStorage.clear()
                            isAuthenticated = false
                        } label: {
                            Text("Sign out")
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    try await GoogleDriveAuth.shared.authenticate(clientId: userConfig.googleClientId)
                                    isAuthenticated = GoogleDriveAuth.shared.isAuthenticated
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        } label: {
                            Text("Connect Google Drive")
                        }
                    }
                }
            }
        }
        .navigationTitle("Syncing")
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}
