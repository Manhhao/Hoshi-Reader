//
//  SearchResultsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct SearchResultsView: View {
    let results: [SearchResult]?
    let query: String
    let onJump: (SearchResult) -> Void
    
    var body: some View {
        List(results ?? []) { result in
            Button {
                onJump(result)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(snippet(result))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text(result.chapter)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(result.character)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if query.isEmpty {
                EmptyView()
            } else if let results {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ProgressView()
            }
        }
    }
    
    private func snippet(_ result: SearchResult) -> AttributedString {
        var match = AttributedString(result.match)
        match.font = .body.bold()
        return AttributedString(result.prefix) + match + AttributedString(result.suffix)
    }
}
