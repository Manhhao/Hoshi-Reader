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
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                let books = viewModel.sortedBooks(by: userConfig.bookshelfSortOption)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(books) { book in
                        BookCell(book: book, viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Books")
            .toolbar {
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
                    Button { 
                        viewModel.isImporting = true 
                    } label: {
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
                            showAppearance = true
                        } label: {
                            Label("Appearance", systemImage: "paintbrush.pointed")
                        }
                        
                        Button {
                            showSync = true
                        } label: {
                            Label("Syncing", systemImage: "cloud")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
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
            }
            .alert("Error", isPresented: $viewModel.shouldShowError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}

struct BookCell: View {
    let book: BookMetadata
    var viewModel: BookshelfViewModel
    
    var body: some View {
        NavigationLink {
            ReaderLoader(book: book)
        } label: {
            BookView(book: book, progress: viewModel.progress(for: book))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteBook(book)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
