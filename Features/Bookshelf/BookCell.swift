//
//  BookCell.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
import SwiftUI

struct BookCell: View {
    @Environment(UserConfig.self) var userConfig
    @State private var showDeleteConfirmation = false
    @State private var markReadConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var downloaded = true
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    var currentShelf: String?
    var hideMove: Bool = false
    var onSelect: () -> Void
    var onMatch: () -> Void
    var isSelecting: Bool = false
    @Binding var selectedBooks: Set<BookMetadata>
    
    private var isSelected: Bool {
        selectedBooks.contains(book)
    }
    
    var body: some View {
        Button {
            if isSelecting {
                withAnimation(.default.speed(2)) {
                    if isSelected {
                        selectedBooks.remove(book)
                    } else {
                        selectedBooks.insert(book)
                    }
                }
            } else {
                onSelect()
            }
        } label: {
            BookView(book: book, progress: viewModel.progress(for: book), downloaded: downloaded, isSelected: isSelecting && isSelected)
        }
        .task(id: userConfig.enableCloudKitSync) {
            refreshEpubState(book: book)
            guard userConfig.enableCloudKitSync else { return }

            let refresh: @MainActor (CloudKitSyncManager.Event) -> Void = { event in
                if case let .epubDownloaded(uuid: uuid) = event,
                   uuid == book.id {
                    self.refreshEpubState(book: book)
                }
            }
            await CloudKitSyncManager.shared.observeEvents(refresh)
        }
        .buttonStyle(.plain)
        .contextMenu(isSelecting ? nil : ContextMenu {
            if !hideMove {
                Menu {
                    Button {
                        viewModel.moveBook(book.id, to: nil)
                    } label: {
                        Label("None", systemImage: "tray")
                    }
                    .disabled(currentShelf == nil)
                    ForEach(viewModel.shelves, id: \.name) { shelf in
                        Button {
                            viewModel.moveBook(book.id, to: shelf.name)
                        } label: {
                            Label(shelf.name, systemImage: "folder")
                        }
                        .disabled(shelf.name == currentShelf)
                    }
                } label: {
                    Label("Move", systemImage: "folder")
                }
            }
            
            if userConfig.enableCloudKitSync && !downloaded {
                Button {
                    Task {
                        guard let cloudEpub = CloudKitBookEpub(from: book) else { return }
                        await CloudKitSyncManager.shared.downloadCloudEpub(cloudEpub)
                    }
                } label: {
                    Label("Download from iCloud", systemImage: "icloud")
                }
            }
            
            if userConfig.enableSync {
                if userConfig.syncMode == .manual {
                    Menu {
                        Button {
                            viewModel.syncBook(
                                book: book,
                                direction: .importFromTtu,
                                syncBookData: userConfig.enableSync && userConfig.syncUploadBooks,
                                syncStats: userConfig.enableSync && userConfig.statisticsEnableSync,
                                statsSyncMode: userConfig.statisticsSyncMode,
                                syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync
                            )
                        } label: {
                            Label("Import", systemImage: "arrow.down")
                        }
                        Button {
                            viewModel.syncBook(
                                book: book,
                                direction: .exportToTtu,
                                syncBookData: userConfig.enableSync && userConfig.syncUploadBooks,
                                syncStats: userConfig.enableSync && userConfig.statisticsEnableSync,
                                statsSyncMode: userConfig.statisticsSyncMode,
                                syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync
                            )
                        } label: {
                            Label("Export", systemImage: "arrow.up")
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                } else {
                    Button {
                        viewModel.syncBook(
                            book: book,
                            direction: nil,
                            syncBookData: userConfig.enableSync && userConfig.syncUploadBooks,
                            syncStats: userConfig.enableSync && userConfig.statisticsEnableSync,
                            statsSyncMode: userConfig.statisticsSyncMode,
                            syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync
                        )
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            
            if userConfig.enableSasayaki {
                Button {
                    onMatch()
                } label: {
                    Label("Match", systemImage: "waveform.badge.magnifyingglass")
                }
            }
            
            Button {
                markReadConfirmation = true
            } label: {
                Label("Mark Read", systemImage: "checkmark")
            }
            
            Button {
                renameText = book.displayTitle
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam.ja")
            }
            
            if let epub = book.epub,
               let booksDir = try? BookStorage.getBooksDirectory() {
                ShareLink(item: booksDir.appendingPathComponent(book.folder).appendingPathComponent(epub)) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        })
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Save") {
                viewModel.renameBook(book, title: renameText.trimmingCharacters(in: .whitespaces))
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Delete \"\(book.displayTitle)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteBook(book)
            }
        }
        .confirmationDialog(
            "Mark \"\(book.displayTitle)\" as read?",
            isPresented: $markReadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                viewModel.markRead(book: book)
            }
        }
    }
    
    func refreshEpubState(book: BookMetadata) {
        Task.detached {
            guard let fileName = book.epub,
                  let booksDir = try? BookStorage.getBooksDirectory() else {
                return
            }
            let epubURL = booksDir.appending(path: book.folder).appending(path: fileName)
            let downloaded = FileManager.default.fileExists(atPath: epubURL.path(percentEncoded: false))
            await MainActor.run {
                self.downloaded = downloaded
            }
        }
    }
}
