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
    @State private var showDownloadAllConfirmation = false
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
                        Text(isAuthenticated ? (userConfig.syncProvider == .gdrive && GoogleDriveSyncManager.shared.cache.attachPending == true ? "Choice needed" : "Connected") : "Not connected")
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
                            
                            let queue = GoogleDriveSyncManager.shared.queue
                            let progress = GoogleDriveSyncManager.shared.progress
                            let failed = queue.filter { $0.error != nil }.count
                            NavigationLink {
                                SyncQueueView()
                            } label: {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Queue")
                                        Spacer()
                                        if let progress {
                                            Text("\(progress.done) / \(progress.total)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        } else if failed > 0 {
                                            Text("\(failed) failed")
                                                .foregroundStyle(.red)
                                        } else if !queue.isEmpty {
                                            Text("\(queue.count)")
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Empty")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    let upload = GoogleDriveSyncManager.shared.uploadSummary
                                    let download = GoogleDriveSyncManager.shared.downloadSummary
                                    if let progress, upload == nil, download == nil {
                                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                                    }
                                    if let upload {
                                        SyncFlowView(label: "Uploading", summary: upload)
                                    }
                                    if let download {
                                        SyncFlowView(label: "Downloading", summary: download)
                                    }
                                }
                            }
                            
                            Button("Sync Now") {
                                GoogleDriveSyncManager.shared.attachDismissed = false
                                Task {
                                    await GoogleDriveSyncManager.shared.sync()
                                }
                            }
                            .disabled(GoogleDriveSyncManager.shared.isSyncing)
                            
                            Button("Download All Books") {
                                showDownloadAllConfirmation = true
                            }
                            .disabled(GoogleDriveSyncManager.shared.missingBooks.isEmpty)
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
        .alert("Download All Books?", isPresented: $showDownloadAllConfirmation) {
            Button("Download") {
                GoogleDriveSyncManager.shared.downloadAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will download \(GoogleDriveSyncManager.shared.missingBooks.count) book(s) from Google Drive.")
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

struct SyncQueueView: View {
    var body: some View {
        let queue = GoogleDriveSyncManager.shared.queue
        let current = GoogleDriveSyncManager.shared.progress?.current ?? []
        let failed = queue.filter { $0.error != nil }
        let inProgress = queue.filter { $0.error == nil && ($0.transfer != nil || current.contains($0.key)) }
        let upNext = queue.filter { item in item.error == nil && !inProgress.contains { $0.key == item.key } }
        List {
            if !inProgress.isEmpty {
                Section("Syncing") {
                    ForEach(inProgress) { item in
                        row(item, active: current.contains(item.key))
                    }
                }
            }
            if !upNext.isEmpty {
                Section("Waiting") {
                    ForEach(upNext.prefix(5)) { item in
                        row(item, active: false)
                    }
                    if upNext.count > 5 {
                        Text("\(upNext.count - 5) more")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !failed.isEmpty {
                Section("Failed") {
                    ForEach(failed) { item in
                        row(item, active: false)
                    }
                }
            }
        }
        .overlay {
            if queue.isEmpty {
                ContentUnavailableView("All Books Synced", systemImage: "checkmark.icloud")
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func row(_ item: GoogleDriveSyncManager.QueueItem, active: Bool) -> some View {
        let direction = item.transfer.flatMap { $0.state == .interrupted ? nil : $0.direction } ?? item.direction
        return HStack(spacing: 12) {
            CoverImage(url: item.coverURL, maxPixelSize: 120) { image in
                image
                    .resizable()
                    .aspectRatio(0.709, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } placeholder: {
                CoverFallback(title: item.title, aspectRatio: 0.709, cornerRadius: 4)
            }
            .frame(width: 34)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let direction {
                        Image(systemName: imageOfDirection(direction))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if item.transfer == nil, item.error == nil, let size = item.size {
                    Text(syncByteSize(size))
                        .font(.footnote)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .monospacedDigit()
                }
                if let transfer = item.transfer {
                    ProgressView(value: Double(transfer.done), total: Double(max(transfer.total, 1)))
                        .tint(transfer.state == .interrupted ? .gray : .accentColor)
                    HStack {
                        Text(transferText(transfer))
                            .lineLimit(1)
                            .foregroundStyle(Color(.tertiaryLabel))
                        Spacer()
                        Text("\(Int(Double(transfer.done) / Double(max(transfer.total, 1)) * 100))%")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
                if let error = item.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            if item.transfer == nil, active {
                ProgressView()
            }
        }
    }
    
    private func transferText(_ transfer: GoogleDriveSyncManager.Transfer) -> String {
        switch transfer.state {
        case .interrupted:
            return String(localized: "Connection lost")
        case .moving:
            return syncByteAmount(transfer.done, transfer.total)
        }
    }
    
    private func imageOfDirection(_ direction: GoogleDriveSyncManager.Direction) -> String {
        switch direction {
        case .upload:
            "arrow.up"
        case .download:
            "arrow.down"
        case .both:
            "arrow.up.arrow.down"
        }
    }
}

struct SyncFlowView: View {
    let label: LocalizedStringKey
    let summary: GoogleDriveSyncManager.FlowSummary
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(syncByteSpeed(summary.speed))
                    .monospacedDigit()
            }
            ProgressView(value: Double(summary.done), total: Double(max(summary.total, 1)))
            HStack {
                Text(syncByteAmount(summary.done, summary.total))
                    .monospacedDigit()
                Spacer()
                if let remaining = summary.remaining {
                    Text(remaining < 60 ? "less than 1 min left" : "about \(Int((remaining / 60).rounded(.up))) min left")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private func syncByteAmount(_ done: Int64, _ total: Int64) -> String {
    if total >= 1_000_000 {
        return String(localized: "\(String(format: "%.1f", Double(done) / 1e6)) of \(String(format: "%.1f", Double(total) / 1e6)) MB")
    }
    return String(localized: "\(Int((Double(done) / 1e3).rounded())) of \(max(1, Int((Double(total) / 1e3).rounded()))) KB")
}

private func syncByteSize(_ bytes: Int64) -> String {
    bytes >= 1_000_000 ? String(format: "%.1f MB", Double(bytes) / 1e6) : "\(max(1, Int((Double(bytes) / 1e3).rounded()))) KB"
}

private func syncByteSpeed(_ bytes: Double) -> String {
    bytes >= 1e6 ? String(format: "%.1f MB/s", bytes / 1e6) : String(format: "%.0f KB/s", bytes / 1e3)
}

struct SyncAttachAlert: ViewModifier {
    let active: Bool
    @State private var attaching = false
    @State private var confirmation: GoogleDriveSyncManager.AttachChoice?
    
    private var manager: GoogleDriveSyncManager { GoogleDriveSyncManager.shared }
    
    func body(content: Content) -> some View {
        content
            .alert("Merge Libraries?", isPresented: Binding(
                get: { active && !attaching && confirmation == nil && !manager.attachDismissed && manager.cache.attachPending == true },
                set: { _ in }
            )) {
                Button("Merge") {
                    attach(.merge)
                }
                Button("Download from Google Drive", role: .destructive) {
                    confirmation = .cloud
                }
                Button("Upload to Google Drive", role: .destructive) {
                    confirmation = .device
                }
                Button("Cancel", role: .cancel) {
                    manager.attachDismissed = true
                }
            } message: {
                Text("Google Drive already has a library. Merging combines changes from both libraries.")
            }
            .alert(confirmation == .device ? "Upload to Google Drive?" : "Download from Google Drive?", isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ), presenting: confirmation) { choice in
                Button("Replace", role: .destructive) {
                    attach(choice)
                }
                Button("Cancel", role: .cancel) { }
            } message: { choice in
                if choice == .device {
                    Text("This will permanently delete the library on Google Drive and replace it with the library from this device. Anything not on this device will be lost.")
                } else {
                    Text("This will permanently delete the library on this device and replace it with the library from Google Drive. Anything not on Google Drive will be lost.")
                }
            }
    }
    
    private func attach(_ choice: GoogleDriveSyncManager.AttachChoice) {
        attaching = true
        Task {
            do {
                try await manager.attach(choice)
            } catch {
                manager.errorMessage = error.localizedDescription
            }
            attaching = false
        }
    }
}
