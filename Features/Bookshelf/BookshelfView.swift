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
    @Environment(UserConfig.self) var userConfig
    @State private var viewModel = BookshelfViewModel()
    @State private var showDictionaries = false
    @State private var showAnkiSettings = false
    @State private var showAppearance = false
    @State private var showAdvanced = false
    @State private var showAbout = false
    @State private var showShelfManagement = false
    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()
    @State private var dictionaryRoute = DictionaryRoute()
    @State private var isSelecting = false
    @State private var selectedBooks = Set<BookMetadata>()
    @State private var showBulkDeleteConfirmation = false
    @Binding var pendingImportURL: URL?
    @Binding var pendingLookup: String?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Books", systemImage: "books.vertical", value: 0) {
                NavigationStack(path: $navigationPath) {
                    ScrollView {
                        let sections = viewModel.shelfSections(sortedBy: userConfig.bookshelfSortOption)
                        ForEach(sections, id: \.shelf?.name) { section in
                            if section.books.count > 0 {
                                ShelfView(
                                    viewModel: viewModel,
                                    section: section,
                                    showTitle: sections.count > 1,
                                    isSelecting: isSelecting,
                                    selectedBooks: $selectedBooks,
                                    pendingLookup: $pendingLookup
                                )
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
                        onCompletion: viewModel.importBook
                    )
                    .sheet(isPresented: $showShelfManagement) {
                        ShelfManagementView(viewModel: viewModel)
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
                .onChange(of: pendingImportURL) { _, url in
                    if let url {
                        navigationPath = NavigationPath()
                        viewModel.importBook(result: .success(url))
                        pendingImportURL = nil
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
                        initialAutofocus: dictionaryRoute.autofocus
                    )
                    .id(dictionaryRoute.id)
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
                            Label("Anki Integration", systemImage: "tray.full")
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
                    .sheet(isPresented: $showAppearance) {
                        AppearanceView(userConfig: userConfig)
                            .presentationDetents([.medium])
                            .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : (userConfig.theme.colorScheme ?? systemColorScheme))
                    }
                }
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
