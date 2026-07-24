//
//  ChapterListView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct ChapterListView: View {
    let document: EPUBDocument
    let bookInfo: BookInfo
    let currentCharacter: Int
    let onJumpToChapter: (Int, String?) -> Void
    
    @State private var viewModel: ChapterListViewModel?
    
    var body: some View {
        List {
            if let vm = viewModel {
                ForEach(vm.rows) { row in
                    ChapterView(row: row) {
                        onJumpToChapter(row.spineIndex, row.fragment)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onAppear {
            if viewModel == nil {
                viewModel = ChapterListViewModel(
                    document: document,
                    bookInfo: bookInfo,
                    currentCharacter: currentCharacter
                )
            }
        }
    }
}

struct ChapterView: View {
    let row: ChapterRow
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Text(row.label)
                    .font(row.indentLevel > 0 ? .subheadline : .subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let count = row.characterCount {
                    Text("\(count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, CGFloat(row.indentLevel) * 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(row.isCurrent ? Color(uiColor: .systemGray5) : Color.clear)
                .padding(.horizontal, 12)
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            row.indentLevel > 0 ? dimensions[.leading] + 16 : dimensions[.leading]
        }
    }
}
