//
//  HighlightListView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct HighlightSection: Identifiable {
    let id: Int
    let label: String
    let highlights: [Highlight]
}

struct HighlightListView: View {
    let document: EPUBDocument
    let bookInfo: BookInfo
    let highlights: [Highlight]
    let onJump: (Highlight) -> Void
    let onDelete: (Highlight) -> Void
    
    private var sections: [HighlightSection] {
        let labels = chapterLabels()
        let grouped = Dictionary(grouping: highlights) {
            var spine = bookInfo.resolveCharacterPosition($0.character)?.spineIndex ?? -1
            while spine > 0 && labels[spine] == nil { spine -= 1 }
            return spine
        }
        return grouped.map { spineIndex, list in
            let label = labels[spineIndex] ?? ""
            let sorted = list.sorted { $0.character < $1.character }
            return HighlightSection(id: spineIndex, label: label, highlights: sorted)
        }.sorted { $0.id < $1.id }
    }
    
    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.label) {
                    ForEach(section.highlights) { highlight in
                        Button {
                            onJump(highlight)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(markedText(highlight))
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 8) {
                                    Text(dateLabel(highlight.createdAt))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 8)
                                    Text("\(highlight.character)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { onDelete(section.highlights[$0]) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if highlights.isEmpty {
                ContentUnavailableView("No Highlights", systemImage: "highlighter")
            }
        }
    }
    
    private func markedText(_ highlight: Highlight) -> AttributedString {
        var attributed = AttributedString(highlight.text.trimmingCharacters(in: .whitespacesAndNewlines))
        attributed.backgroundColor = highlight.color.swatch.opacity(highlight.color.rgba.a)
        return attributed
    }
    
    private func dateLabel(_ date: Date) -> String {
        let relative = date.formatted(.relative(presentation: .named))
        return relative.prefix(1).uppercased() + relative.dropFirst()
    }
    
    private func chapterLabels() -> [Int: String] {
        var pathToSpine: [String: Int] = [:]
        for (i, item) in document.spine.items.enumerated() {
            if let manifest = document.manifest.items[item.idref] {
                pathToSpine[manifest.path] = i
            }
        }
        
        var labels: [Int: String] = [:]
        func walk(_ items: [EPUBTableOfContents], topLabel: String?) {
            for item in items {
                let label = topLabel ?? item.label
                if let raw = item.item {
                    let path = raw.components(separatedBy: "#").first ?? raw
                    if let index = pathToSpine[path], labels[index] == nil {
                        labels[index] = label
                    }
                }
                walk(item.subTable ?? [], topLabel: label)
            }
        }
        walk(document.tableOfContents.subTable ?? [], topLabel: nil)
        return labels
    }
}
