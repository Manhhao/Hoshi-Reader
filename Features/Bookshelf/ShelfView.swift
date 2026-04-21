//
//  ShelfView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ShelfView: View {
    @State private var isCollapsed: Bool
    @State private var compactRowCount = 4
    var viewModel: BookshelfViewModel
    var section: ShelfSection
    var showTitle: Bool = true
    var isSelecting: Bool = false
    @Binding var selectedBooks: Set<BookMetadata>
    var onSelect: (BookMetadata) -> Void
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
        onSelect: @escaping (BookMetadata) -> Void,
        onMatch: @escaping (BookMetadata) -> Void
    ) {
        self.viewModel = viewModel
        self.section = section
        self.showTitle = showTitle
        self.isSelecting = isSelecting
        self._selectedBooks = selectedBooks
        self.onSelect = onSelect
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
                            Text(section.shelf!.name)
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
                        BookCell(
                            book: book,
                            viewModel: viewModel,
                            currentShelf: section.shelf?.name,
                            hideMove: section.isReading,
                            onSelect: { onSelect(book) },
                            onMatch: { onMatch(book) },
                            isSelecting: isSelecting,
                            selectedBooks: $selectedBooks
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
