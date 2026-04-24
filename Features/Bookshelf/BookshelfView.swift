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
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel = BookshelfViewModel()
    @State private var showDictionaries = false
    @State private var showAnkiSettings = false
    @State private var showAppearance = false
    @State private var showAdvanced = false
    @State private var showAbout = false
    @State private var showShelfManagement = false
    @State private var selectedTab = 0
    @State private var focusDictionarySearch = false
    @State private var setInitialTab = false
    @State private var navigationPath = NavigationPath()
    @State private var dictionaryRoute = DictionaryRoute()
    @State private var isSelecting = false
    @State private var selectedBooks = Set<BookMetadata>()
    @State private var showBulkDeleteConfirmation = false
    @State private var sasayakiBook: BookMetadata?
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    @Binding var pendingLookup: String?
    @Binding var pendingTab: Int?
    
    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: { newTab in
            if newTab == 1 && selectedTab == 1 {
                focusDictionarySearch.toggle()
            }
            selectedTab = newTab
        })) {
            Tab("Books", systemImage: "books.vertical", value: 0) {
                NavigationStack(path: $navigationPath) {
                    ScrollView {
                        let sections = viewModel.shelfSections(sortedBy: userConfig.bookshelfSortOption, showReading: userConfig.bookshelfShowReading)
                        if viewModel.books.isEmpty {
                            ContentUnavailableView {
                                Label("No Books", systemImage: "books.vertical")
                            } description: {
                                Text("Import an EPUB using the \(Image(systemName: "plus")) button to start reading.")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 160)
                        } else {
                            ForEach(sections) { section in
                                if section.books.count > 0 {
                                    ShelfView(
                                        viewModel: viewModel,
                                        section: section,
                                        showTitle: sections.count > 1,
                                        isSelecting: isSelecting,
                                        selectedBooks: $selectedBooks,
                                        pendingLookup: $pendingLookup,
                                        pendingTab: $pendingTab,
                                        onMatch: { sasayakiBook = $0 }
                                    )
                                }
                            }
                        }
                    }
                    .navigationTitle("Books")
                    .scrollIndicators(.hidden)
                    .toolbar {
                        toolbarContent
                    }
                    .onAppear {
                        viewModel.loadBooks()
                    }
                    .fileImporter(
                        isPresented: $viewModel.isImporting,
                        allowedContentTypes: [.epub],
                        allowsMultipleSelection: true,
                        onCompletion: viewModel.importBooks
                    )
                    .sheet(isPresented: $showShelfManagement) {
                        ShelfManagementView(viewModel: viewModel)
                    }
                    .sheet(item: $sasayakiBook) { book in
                        SasayakiMatchView(book: book, viewModel: viewModel)
                    }
                    .alert(
                        "Delete \(selectedBooks.count) book(s)?",
                        isPresented: $showBulkDeleteConfirmation
                    ) {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteBooks(selectedBooks)
                            clearSelection()
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                }
                .onChange(of: selectedTab) {
                    clearSelection()
                }
            }
            
            Tab("Dictionary", systemImage: "character.magnify.ja", value: 1) {
                NavigationStack {
                    DictionarySearchView(
                        initialQuery: dictionaryRoute.query,
                        initialAutofocus: dictionaryRoute.autofocus,
                        shouldFocus: focusDictionarySearch
                    )
                    .id(dictionaryRoute.id)
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
                            Label("Appearance", systemImage: "paintpalette")
                        }
                        .foregroundStyle(.primary)
                        Button {
                            showAdvanced = true
                        } label: {
                            Label("Advanced", systemImage: "gearshape.2")
                        }
                        .foregroundStyle(.primary)
                        
                        Section {
                            Link(destination: URL(string: "https://github.com/Manhhao/Hoshi-Reader/issues")!) {
                                Label("Report an Issue", systemImage: "exclamationmark.bubble")
                            }
                            Button {
                                showAbout = true
                            } label: {
                                Label("About", systemImage: "info.circle")
                            }
                            .foregroundStyle(.primary)
                        }
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
                    .navigationDestination(isPresented: $showAbout) {
                        AboutView()
                    }
                    .navigationDestination(isPresented: $showAppearance) {
                        AppearanceView(userConfig: userConfig, showDismiss: false)
                    }
                }
            }
        }
        .onChange(of: pendingTab) { _, tab in
            if let tab {
                selectedTab = tab
                pendingTab = nil
            }
        }
        .onChange(of: pendingLookup) { _, text in
            if let text {
                selectedTab = 1
                dictionaryRoute = DictionaryRoute(
                    query: text,
                    autofocus: text.isEmpty
                )
                pendingLookup = nil
            }
        }
        .onChange(of: pendingImportURL) { _, url in
            if let url {
                navigationPath = NavigationPath()
                if url.pathExtension == "colpkg" || url.pathExtension == "apkg" {
                    do {
                        try AnkiManager.shared.importAnkiBackup(from: url)
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                        viewModel.shouldShowError = true
                    }
                } else {
                    viewModel.importBook(result: .success(url))
                }
                viewModel.clearInbox()
                pendingImportURL = nil
            }
        }
        .onChange(of: pendingRemoteImportURL) { _, url in
            if let url {
                navigationPath = NavigationPath()
                viewModel.importRemoteBook(from: url)
                pendingRemoteImportURL = nil
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
            if viewModel.isDownloading {
                LoadingOverlay("Downloading EPUB...")
            }
        }
        .onAppear {
            guard !setInitialTab else {
                return
            }
            selectedTab = userConfig.dictionaryTabDefault ? 1 : 0
            setInitialTab = true
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    clearSelection()
                }
                .fontWeight(.semibold)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.moveBooks(selectedBooks, to: nil)
                        clearSelection()
                    } label: {
                        Label("None", systemImage: "tray")
                    }
                    ForEach(viewModel.shelves, id: \.name) { shelf in
                        Button {
                            viewModel.moveBooks(selectedBooks, to: shelf.name)
                            clearSelection()
                        } label: {
                            Label(shelf.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(selectedBooks.isEmpty)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBulkDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedBooks.isEmpty)
            }
        } else {
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
            
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.default.speed(2)) {
                        isSelecting = true
                    }
                } label: {
                    Image(systemName: "checklist")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShelfManagement = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    private func clearSelection() {
        withAnimation(.default.speed(2)) {
            isSelecting = false
            selectedBooks.removeAll()
        }
    }
}

private struct DictionaryRoute {
    let id = UUID()
    let query: String
    let autofocus: Bool
    
    init(query: String = "", autofocus: Bool = true) {
        self.query = query
        self.autofocus = autofocus
    }
}
