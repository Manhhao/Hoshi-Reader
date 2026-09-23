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
    @State private var isAuthenticated = GoogleDriveAuth.shared.isAuthenticated(for: UserConfig.shared.syncProvider)
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showClearCacheConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var isConnecting = false
    
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Toggle("Enable", isOn: $userConfig.enableSync)
                Picker(
                    "Provider",
                    selection: Binding(
                        get: { userConfig.syncProvider },
                        set: changeProvider
                    )
                ) {
                    Text("Google Drive").tag(SyncProvider.gdrive)
                    Text("ッツ/yatsu").tag(SyncProvider.ttu)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync your library between Hoshi Reader devices.")
                    
                    if userConfig.enableSync && userConfig.syncProvider == .ttu {
                        Text("A **custom [Google Cloud project](https://github.com/Manhhao/Hoshi-Reader/blob/main/TTUSYNC.md)** is necessary for syncing to ッツ/yatsu. If you're only syncing between Hoshi Reader, it's highly recommended to use one of the alternative options.")
                    }
                }
            }
            
            if userConfig.enableSync {
                if userConfig.syncProvider == .ttu {
                    Section("Client ID") {
                        TextField("Required", text: $userConfig.googleClientId)
                            .disabled(isAuthenticated)
                            .opacity(isAuthenticated ? 0.6 : 1)
                    }
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
                        Button("Connect Google Drive", action: handleSignIn)
                            .disabled(isConnecting)
                    }
                }
                
                if isAuthenticated {
                    if userConfig.syncProvider == .ttu {
                        Section("Behaviour") {
                            Picker("Direction", selection: $userConfig.syncMode) {
                                ForEach(SyncMode.allCases, id: \.self) { mode in
                                    textOfSyncMode(mode).tag(mode)
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
                            Toggle("Sync Stats", isOn: $userConfig.statisticsEnableSync)
                            VStack {
                                Picker("Sync Behaviour", selection: $userConfig.statisticsSyncMode) {
                                    ForEach(StatisticsSyncMode.allCases, id: \.self) { mode in
                                        textOfStatisticsSyncMode(mode).tag(mode)
                                    }
                                }
                                Text("Determines if statistics will be merged entry by entry or replaced completely on a sync.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Toggle("Sync Audiobook Progress", isOn: $userConfig.sasayakiEnableSync)
                        }
                    } else {
                        Section {
                            if let lastSync = GoogleDriveSyncManager.shared.lastSync {
                                HStack {
                                    Text("Last Sync")
                                    Spacer()
                                    Text(lastSync, format: .dateTime.month().day().hour().minute())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Button("Sync Now") {
                                Task {
                                    await GoogleDriveSyncManager.shared.sync()
                                }
                            }
                            .disabled(GoogleDriveSyncManager.shared.isSyncing)
                        } footer: {
                            if let errorMessage = GoogleDriveSyncManager.shared.errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: userConfig.enableSync) { _, enabled in
            if enabled {
                GoogleDriveSyncManager.shared.start()
            } else {
                Task {
                    await GoogleDriveSyncManager.shared.stop()
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
                Task {
                    do {
                        try await GoogleDriveSyncManager.shared.clearCache()
                        TtuDriveHandler.clearCache()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear cached folder ids and book covers.")
        }
        .onAppear {
            isAuthenticated = GoogleDriveAuth.shared.isAuthenticated(for: UserConfig.shared.syncProvider)
        }
        .alert("Sign out?", isPresented: $showSignOutConfirmation) {
            Button("Confirm", role: .destructive) {
                Task {
                    do {
                        try await GoogleDriveSyncManager.shared.signOut()
                        isAuthenticated = false
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Signing out will clear authorization tokens, cached folder ids and book covers.")
        }
    }
    
    private func handleSignIn() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await GoogleDriveAuth.shared.authenticate(provider: userConfig.syncProvider)
                isAuthenticated = GoogleDriveAuth.shared.isAuthenticated(
                    for: UserConfig.shared.syncProvider
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func changeProvider(_ provider: SyncProvider) {
        Task {
            await GoogleDriveSyncManager.shared.stop()
            
            TtuDriveHandler.clearCache()
            userConfig.syncProvider = provider
            isAuthenticated = GoogleDriveAuth.shared.isAuthenticated(for: provider)
            GoogleDriveSyncManager.shared.start()
        }
    }
    
    private func textOfSyncMode(_ mode: SyncMode) -> some View {
        switch mode {
        case .auto:
            Text("Auto")
        case .manual:
            Text("Manual")
        }
    }
    
    private func textOfStatisticsSyncMode(_ mode: StatisticsSyncMode) -> some View {
        switch mode {
        case .merge:
            Text("Merge")
        case .replace:
            Text("Replace")
        }
    }
}
