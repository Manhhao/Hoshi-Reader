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
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    var currentShelf: String?
    var onSelect: () -> Void
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
            BookView(book: book, progress: viewModel.progress(for: book), isSelected: isSelecting && isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu(isSelecting ? nil : ContextMenu {
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
            
            if userConfig.enableSync {
                if userConfig.syncMode == .manual {
                    Menu {
                        Button {
                            viewModel.syncBook(book: book, direction: .importFromTtu, syncStats: userConfig.enableSync && userConfig.statisticsEnableSync, statsSyncMode: userConfig.statisticsSyncMode)
                        } label: {
                            Label("Import", systemImage: "arrow.down")
                        }
                        Button {
                            viewModel.syncBook(book: book, direction: .exportToTtu, syncStats: userConfig.enableSync && userConfig.statisticsEnableSync, statsSyncMode: userConfig.statisticsSyncMode)
                        } label: {
                            Label("Export", systemImage: "arrow.up")
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                } else {
                    Button {
                        viewModel.syncBook(book: book, direction: nil, syncStats: userConfig.enableSync && userConfig.statisticsEnableSync, statsSyncMode: userConfig.statisticsSyncMode)
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        })
        .confirmationDialog(
            "Delete \"\(book.title ?? "")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteBook(book)
            }
        }
    }
}
