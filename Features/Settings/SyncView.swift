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
                Toggle("Enable Sync", isOn: $userConfig.enableSync)
            } footer: {
                Text("A [Google Cloud project](https://github.com/ttu-ttu/ebook-reader?tab=readme-ov-file#storage-sources) is necessary for syncing with ッツ Reader.\nAfter the intial setup, create another OAuth client ID in the same project, select iOS as the Application type and set the Bundle ID to 'de.manhhao.hoshi'. Paste the Client ID in the textbox below and and press on 'Sign in with Google'.\nYou can now sync individual books by long-pressing and selecting 'Sync'.")
            }
            
            if userConfig.enableSync {
                Section("Client ID") {
                    TextField("Required", text: $userConfig.googleClientId)
                }
                
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(isAuthenticated ? "Signed in" : "Not signed in")
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
                            Text("Sign in with Google")
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
