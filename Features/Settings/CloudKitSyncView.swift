//
//  SyncView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CloudKit

struct CloudKitSyncView: View {
    @Environment(UserConfig.self) var userConfig
    @AppStorage("cloudKitStatus") private var cloudKitStatus = CloudKitStatus.none
    
    @State private var iCloudAvailable = false
    @State private var showUploadLocalBooksConfirmation = false
    @State private var showClearLocalBooksConfirmation = false
    @State private var showClearCloudKitConfirmation = false
    
    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Toggle("Enable", isOn: $userConfig.enableCloudKitSync)
                    .disabled(!iCloudAvailable)
                
                HStack {
                    Text("Status")
                    
                    Spacer()
                    
                    Group {
                        if !iCloudAvailable {
                            if cloudKitStatus != .none {
                                Text(cloudKitStatus.title)
                            } else {
                                Text("Not Available")
                            }
                        } else {
                            if userConfig.enableCloudKitSync {
                                Text("Signed In")
                            } else {
                                Text("Off")
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            } footer: {
                if !iCloudAvailable {
                    if cloudKitStatus != .none {
                        Text(cloudKitStatus.message)
                    } else {
                        Text("Log in to an iCloud account to sync with iCloud.")
                    }
                } else {
                    if userConfig.enableCloudKitSync {
                        Text("You have logged in to an iCloud account. You can upload local books to iCloud server")
                    } else {
                        Text("Switch on to sync with iCloud")
                    }
                }
            }
            if userConfig.enableCloudKitSync {
                Section {
                    Button("Upload Unsynced Local Books") {
                        showUploadLocalBooksConfirmation.toggle()
                    }
                    
                    Button("Clear Unsynced Local Books", role: .destructive) {
                        showClearLocalBooksConfirmation.toggle()
                    }
                    
                    Button("Clear iCloud data", role: .destructive) {
                        showClearCloudKitConfirmation.toggle()
                    }
                }
            }
        }
        .task {
            await iCloudStatusRefresh()
            let onChanged: @MainActor (CloudKitSyncManager.Event) -> Void = { event in
                guard case .account = event else { return }

                Task {
                    await self.iCloudStatusRefresh()
                }
            }
            await CloudKitSyncManager.shared.observeEvents(onChanged)
        }
        .navigationTitle("iCloud Syncing")
        .alert("Upload local books?", isPresented: $showUploadLocalBooksConfirmation) {
            Button("Confirm") {
                Task {
                    try? await CloudKitSyncManager.shared.uploadUnmanagedBooks()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will upload local only books to iCloud server.")
        }
        .alert("Clear local books?", isPresented: $showClearLocalBooksConfirmation) {
            Button("Confirm", role: .destructive) {
                Task {
                    try await CloudKitSyncManager.shared.deleteLocalBooks(isManaged: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all data of local only books")
        }
        .alert("Clear iCloud data?", isPresented: $showClearCloudKitConfirmation) {
            Button("Confirm", role: .destructive) {
                Task {
                    await CloudKitSyncManager.shared.deleteServerData()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all data on iCloud server.")
        }
    }
    
    private func iCloudStatusRefresh() async {
        do {
            let accountStatus = try await CloudKitSyncManager.container.accountStatus()
            iCloudAvailable = accountStatus == .available
        } catch {
            iCloudAvailable = false
        }
    }
}
