//
//  BookshelfView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit
import UniformTypeIdentifiers

struct BookshelfView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var viewModel = BookshelfViewModel()
    @State private var showDictionaries = false
    @State private var showAnkiSettings = false
    @State private var showAppearance = false
    @State private var showSync = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.sortedBooks(by: userConfig.bookshelfSortOption)) { book in
                        BookCell(book: book, viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Books")
            .toolbar {
                toolbarContent
            }
            .onAppear {
                viewModel.loadBooks()
            }
            .fileImporter(
                isPresented: $viewModel.isImporting,
                allowedContentTypes: [.epub],
                onCompletion: viewModel.importBook
            )
            .navigationDestination(isPresented: $showDictionaries) {
                DictionaryView()
            }
            .navigationDestination(isPresented: $showAnkiSettings) {
                AnkiView()
            }
            .navigationDestination(isPresented: $showSync) {
                SyncView()
            }
            .sheet(isPresented: $showAppearance) {
                AppearanceView(userConfig: userConfig)
                    .presentationDetents([.medium])
                    .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
            }
            .alert("Error", isPresented: $viewModel.shouldShowError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("", isPresented: $viewModel.shouldShowSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.successMessage)
            }
            .overlay {
                if viewModel.isSyncing {
                    LoadingOverlay("Syncing...")
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Section {
                    Text("Sorting by...")
                        .foregroundStyle(.secondary)
                    Picker("Sort", selection: Bindable(userConfig).bookshelfSortOption) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Button { viewModel.isImporting = true } label: {
                Image(systemName: "plus")
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showDictionaries = true
                } label: {
                    Label("Dictionaries", systemImage: "books.vertical")
                }
                Button {
                    showAnkiSettings = true
                } label: {
                    Label("Anki", systemImage: "tray.full")
                }
                Button {
                    showSync = true
                } label: {
                    Label("ッツ Sync", systemImage: "cloud")
                }
                Button {
                    showAppearance = true
                } label: {
                    Label("Appearance", systemImage: "paintbrush.pointed")
                }
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}

struct BookCell: View {
    @Environment(UserConfig.self) var userConfig
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationLink {
            ReaderLoader(book: book)
        } label: {
            BookView(book: book, progress: viewModel.progress(for: book))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if userConfig.enableSync {
                Button {
                    viewModel.syncBook(book: book)
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
