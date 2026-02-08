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
    @Environment(UserConfig.self) var userConfig
    @State private var selectedBook: BookMetadata?
    var viewModel: BookshelfViewModel
    var section: ShelfSection
    var showTitle: Bool = true
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        VStack {
            if showTitle {
                Text(section.shelf?.name ?? "Unshelved")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(section.books) { book in
                    BookCell(book: book, viewModel: viewModel) {
                        selectedBook = book
                    }
                    .matchedTransitionSource(id: book.id, in: namespace)
                }
            }
            .padding(.horizontal)
        }
        .fullScreenCover(item: $selectedBook) { book in
            ReaderLoader(book: book)
                .navigationTransition(.zoom(sourceID: book.id, in: namespace))
                .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : userConfig.theme.colorScheme)
        }
        .onChange(of: selectedBook) { old, new in
            if old != nil && new == nil {
                viewModel.loadBooks()
            }
        }
    }
}
