//
//  ShelfView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ShelfView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var selectedBook: BookMetadata?
    @State private var readerWindow = ReaderWindow()
    @State private var isCollapsed: Bool
    @State private var compactRowCount = 4
    var viewModel: BookshelfViewModel
    var section: ShelfSection
    var showTitle: Bool = true
    var isSelecting: Bool = false
    @Binding var selectedBooks: Set<BookMetadata>
    @Binding var pendingLookup: String?
    @Binding var pendingTab: Int?
    var onMatch: (BookMetadata) -> Void
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    private let compactColumns = [
        GridItem(.adaptive(minimum: 80), spacing: 12)
    ]
    
    init(
        viewModel: BookshelfViewModel,
        section: ShelfSection,
        showTitle: Bool = true,
        isSelecting: Bool = false,
        selectedBooks: Binding<Set<BookMetadata>>,
        pendingLookup: Binding<String?>,
        pendingTab: Binding<Int?>,
        onMatch: @escaping (BookMetadata) -> Void
    ) {
        self.viewModel = viewModel
        self.section = section
        self.showTitle = showTitle
        self.isSelecting = isSelecting
        self._selectedBooks = selectedBooks
        self._pendingLookup = pendingLookup
        self._pendingTab = pendingTab
        self.onMatch = onMatch
        self._isCollapsed = State(initialValue: !section.isReading)
    }
    
    var body: some View {
        VStack {
            if showTitle {
                if section.shelf != nil {
                    Button {
                        withAnimation(.default.speed(1.5)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        HStack {
                            Group {
                                if section.isReading {
                                    Text("Reading")
                                } else {
                                    Text(section.shelf!.name)
                                }
                            }
                            .font(.title3.bold())
                            .lineLimit(1)
                            Text("\(section.books.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text("Unshelved")
                            .font(.title3.bold())
                        Text("\(section.books.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
            }
            
            if isCollapsed && section.shelf != nil {
                LazyVGrid(columns: compactColumns, spacing: 12) {
                    ForEach(section.books.prefix(compactRowCount)) { book in
                        Button {
                            withAnimation(.default.speed(1.5)) {
                                isCollapsed = false
                            }
                        } label: {
                            BookCover(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onGeometryChange(for: Int.self) { proxy in
                    max(1, Int((proxy.size.width + 12) / (80 + 12)))
                } action: { count in
                    compactRowCount = count
                }
                .padding(.horizontal)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(section.books) { book in
                        if section.isGoogleDrive {
                            DriveBookCell(
                                book: book,
                                progress: viewModel.progress(for: book),
                                isDownloading: viewModel.downloadingBooks[book.id] != nil,
                                downloadProgress: viewModel.downloadingBooks[book.id] ?? 0,
                                onImport: {
                                    viewModel.importGoogleDriveBook(book, syncStats: userConfig.enableSync && userConfig.statisticsEnableSync, syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync)
                                },
                                onDelete: {
                                    viewModel.deleteGoogleDriveBook(book)
                                }
                            )
                        } else {
                            BookCell(
                                book: book,
                                viewModel: viewModel,
                                currentShelf: section.shelf?.name,
                                hideMove: section.isReading,
                                onSelect: { selectedBook = book },
                                onMatch: { onMatch(book) },
                                isSelecting: isSelecting,
                                selectedBooks: $selectedBooks
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .opacity(section.isGoogleDrive && isSelecting ? 0.4 : 1)
        .allowsHitTesting(!section.isGoogleDrive || !isSelecting)
        .onChange(of: isSelecting) {
            if isSelecting && section.isGoogleDrive {
                withAnimation(.default.speed(1.5)) {
                    isCollapsed = true
                }
            }
        }
        .onChange(of: selectedBook) { old, new in
            if let book = new {
                readerWindow.present(content: {
                    ReaderLoader(book: book)
                        .environment(userConfig)
                }) {
                    if selectedBook?.id == book.id {
                        selectedBook = nil
                    }
                }
            } else if old != nil {
                viewModel.loadBooks()
                readerWindow.dismiss()
            }
        }
        .onChange(of: pendingLookup) { _, text in
            if text != nil && selectedBook != nil {
                selectedBook = nil
            }
        }
        .onChange(of: pendingTab) { _, tab in
            if tab != nil && selectedBook != nil {
                selectedBook = nil
            }
        }
    }
}

private struct DriveBookCell: View {
    @State private var showDeleteConfirmation = false
    let book: BookMetadata
    let progress: Double
    let isDownloading: Bool
    let downloadProgress: Double
    let onImport: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button {
            onImport()
        } label: {
            VStack(spacing: 6) {
                BookCover(book: book, progress: progress)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.displayTitle)
                        .font(.system(size: 16))
                        .lineLimit(isDownloading ? 1 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isDownloading {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(.caption, weight: .semibold))
                            ProgressView(value: downloadProgress)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 40, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete from Google Drive", systemImage: "trash")
            }
            .disabled(isDownloading)
        }
        .confirmationDialog(
            "Delete \"\(book.displayTitle)\" from Google Drive?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}
