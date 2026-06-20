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
