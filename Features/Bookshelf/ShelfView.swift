//
//  ShelfView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ShelfView: View {
    @Namespace private var namespace
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(UserConfig.self) var userConfig
    @State private var selectedBook: BookMetadata?
    @State private var isCollapsed = true
    @State private var compactRowCount = 4
    var viewModel: BookshelfViewModel
    var section: ShelfSection
    var showTitle: Bool = true
    var isSelecting: Bool = false
    @Binding var selectedBooks: Set<BookMetadata>
    @Binding var pendingLookup: String?
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    private let compactColumns = [
        GridItem(.adaptive(minimum: 80), spacing: 12)
    ]
    
    var body: some View {
        VStack {
            if section.books.count > 0 {
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
                        .padding(.top, 10)
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
                                if let coverURL = book.coverURL,
                                   let image = UIImage(contentsOfFile: coverURL.path(percentEncoded: false)) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(0.709, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .shadow(color: .primary.opacity(0.3), radius: 5)
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                        .aspectRatio(0.709, contentMode: .fit)
                                }
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
                                onSelect: { selectedBook = book },
                                isSelecting: isSelecting,
                                selectedBooks: $selectedBooks
                            )
                            .matchedTransitionSource(id: book.id, in: namespace)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .fullScreenCover(item: $selectedBook) { book in
            ReaderLoader(book: book)
                .navigationTransition(.zoom(sourceID: book.id, in: namespace))
                .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : (userConfig.theme.colorScheme ?? systemColorScheme))
        }
        .onChange(of: selectedBook) { old, new in
            if old != nil && new == nil {
                viewModel.loadBooks()
            }
        }
        .onChange(of: pendingLookup) { _, text in
            if text != nil && selectedBook != nil {
                selectedBook = nil
            }
        }
    }
}
