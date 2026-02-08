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
    @State private var showAdvanced = false
    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()
    @State private var showShelfManagement = false
    @Binding var pendingImportURL: URL?
    @Binding var pendingLookup: String?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Books", systemImage: "books.vertical", value: 0) {
                NavigationStack(path: $navigationPath) {
                    ScrollView {
                        let sections = viewModel.shelfSections(sortedBy: userConfig.bookshelfSortOption)
                        ForEach(sections, id: \.shelf?.name) { section in
                            ShelfView(viewModel: viewModel, section: section, showTitle: sections.count > 1)
                        }
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
                    .navigationDestination(for: LookupDestination.self) { dest in
                        DictionarySearchView(initialQuery: dest.query)
                    }
                    .sheet(isPresented: $showShelfManagement) {
                        ShelfManagementView(viewModel: viewModel)
                    }
                }
                .onChange(of: pendingImportURL) { _, url in
                    if let url {
                        navigationPath = NavigationPath()
                        viewModel.importBook(result: .success(url))
                        pendingImportURL = nil
                    }
                }
                .onChange(of: pendingLookup) { _, text in
                    if let text {
                        selectedTab = 0
                        navigationPath.append(LookupDestination(query: text))
                        pendingLookup = nil
                    }
                }
            }
            
            Tab("Dictionary", systemImage: "character.magnify.ja", value: 1) {
                NavigationStack {
                    DictionarySearchView()
                        .navigationTitle("Dictionary")
                }
            }
            
            Tab("Settings", systemImage: "gearshape", value: 2) {
                NavigationStack {
                    List {
                        Button {
                            showDictionaries = true
                        } label: {
                            Label("Dictionaries", systemImage: "character.book.closed.ja")
                        }
                        .foregroundStyle(.primary)
                        Button {
                            showAnkiSettings = true
                        } label: {
                            Label("Anki", systemImage: "tray.full")
                        }
                        .foregroundStyle(.primary)
                        Button {
                            showAppearance = true
                        } label: {
                            Label("Appearance", systemImage: "paintbrush.pointed")
                        }
                        .foregroundStyle(.primary)
                        Button {
                            showAdvanced = true
                        } label: {
                            Label("Advanced", systemImage: "gearshape.2")
                        }
                        .foregroundStyle(.primary)
                    }
                    .navigationTitle("Settings")
                    .navigationDestination(isPresented: $showDictionaries) {
                        DictionaryView()
                    }
                    .navigationDestination(isPresented: $showAnkiSettings) {
                        AnkiView()
                    }
                    .navigationDestination(isPresented: $showAdvanced) {
                        AdvancedView()
                    }
                    .sheet(isPresented: $showAppearance) {
                        AppearanceView(userConfig: userConfig)
                            .presentationDetents([.medium])
                            .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
                    }
                }
            }
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
            Button { showShelfManagement = true } label: {
                Image(systemName: "folder.badge.gearshape")
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Button { viewModel.isImporting = true } label: {
                Image(systemName: "plus")
            }
        }
        
    }
}

struct BookCell: View {
    @Environment(UserConfig.self) var userConfig
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    var onSelect: () -> Void
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            BookView(book: book, progress: viewModel.progress(for: book))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu {
                Button {
                    viewModel.moveBook(book.id, to: nil)
                } label: {
                    Label("None", systemImage: "tray")
                }
                ForEach(viewModel.shelves, id: \.name) { shelf in
                    Button {
                        viewModel.moveBook(book.id, to: shelf.name)
                    } label: {
                        Label(shelf.name, systemImage: "folder")
                    }
                }
            } label: {
                Label("Move to Shelf", systemImage: "folder")
            }
            
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

struct LookupDestination: Hashable {
    let query: String
}
