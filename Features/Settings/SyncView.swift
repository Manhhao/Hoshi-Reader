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
    @State private var showClearCacheConfirmation = false
    @State private var showSignOutConfirmation = false
    
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
                Section("Client ID") {
                    TextField("Required", text: $userConfig.googleClientId)
                        .disabled(isAuthenticated)
                        .opacity(isAuthenticated ? 0.6 : 1)
                }
                
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(isAuthenticated ? "Connected" : "Not connected")
                            .foregroundStyle(.secondary)
                    }
                    if isAuthenticated {
                        Button(role: .destructive) {
                            showClearCacheConfirmation = true
                        } label: {
                            Text("Clear Cache")
                        }
                        Button(role: .destructive) {
                            showSignOutConfirmation = true
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
                
                Section("Behaviour") {
                    Picker("Direction", selection: $userConfig.syncMode) {
                        ForEach(SyncMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("Auto Sync", isOn: $userConfig.enableAutoSync)
                }
                
                Section("Data") {
                    VStack {
                        Toggle("Upload Books", isOn: $userConfig.syncUploadBooks)
                        Text("Uploads books on first sync if no bookdata is stored on Google Drive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if userConfig.enableStatistics {
                        Toggle("Sync Stats", isOn: $userConfig.statisticsEnableSync)
                    }
                    
                    if userConfig.enableSasayaki {
                        Toggle("Sync Audiobook Progress", isOn: $userConfig.sasayakiEnableSync)
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
        .alert("Clear Cache?", isPresented: $showClearCacheConfirmation) {
            Button("Clear", role: .destructive) {
                GoogleDriveHandler.clearCache()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear cached folder ids and book covers.")
        }
        .alert("Sign out?", isPresented: $showSignOutConfirmation) {
            Button("Confirm", role: .destructive) {
                TokenStorage.clear()
                GoogleDriveHandler.clearCache()
                isAuthenticated = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Signing out will clear authorization tokens, cached folder ids and book covers.")
        }
    }
}
