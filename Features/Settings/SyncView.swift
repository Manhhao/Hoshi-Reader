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
            
            Button {
                Task {
                    guard let accessToken = userConfig.accessToken,
                          let root = try? await GoogleDriveHandler.shared.findRootFolder(accessToken: accessToken)
                    else { return }
                    
                    let books = try? await GoogleDriveHandler.shared.listBooks(accessToken: accessToken, rootFolder: root)
                    guard let books else { return }
                    
                    await withTaskGroup(of: (String, TtuProgress?).self) { group in
                        for book in books {
                            group.addTask {
                                let progress = try? await GoogleDriveHandler.shared.getProgress(accessToken: accessToken, folderId: book.id)
                                return (book.name, progress)
                            }
                        }
                        
                        for await (bookName, progressData) in group {
                            if let p = progressData {
                                print("\(bookName): \(p.lastBookmarkModified) \(p.progress)")
                            }
                        }
                    }
                }
            } label: {
                Text("Test API")
            }
        }
        .navigationTitle("Syncing")
    }
}
