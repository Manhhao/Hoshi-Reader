//
//  ChapterListViewModel.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct ChapterRow: Identifiable {
    let id = UUID()
    let label: String
    let spineIndex: Int
    let fragment: String?
    let characterCount: Int?
    var isCurrent: Bool
    let indentLevel: Int
}

@Observable
@MainActor
class ChapterListViewModel {
    var rows: [ChapterRow] = []
    var currentRow: ChapterRow.ID? {
        rows.first(where: { $0.isCurrent })?.id
    }
    
    private let document: EPUBDocument
    private let bookInfo: BookInfo
    private let currentCharacter: Int
	
    init(document: EPUBDocument, bookInfo: BookInfo, currentCharacter: Int) {
        self.document = document
        self.bookInfo = bookInfo
        self.currentCharacter = currentCharacter
        
        self.rows = generateRows()
    }
    
    private func generateRows() -> [ChapterRow] {
        var spineIndices: [String: Int] = [:]
        for (index, item) in document.spine.items.enumerated() {
            if let path = document.manifest.items[item.idref]?.path, spineIndices[path] == nil {
                spineIndices[path] = index
            }
        }
        var rows = flattenTOC(document.tableOfContents.subTable ?? [], indentLevel: 0, spineIndices: spineIndices)
        if let current = rows.indices.last(where: { (rows[$0].characterCount ?? .max) <= currentCharacter }) {
            rows[current].isCurrent = true
        }
        return rows
    }
    
    private func flattenTOC(_ items: [EPUBTableOfContents], indentLevel: Int, spineIndices: [String: Int]) -> [ChapterRow] {
        items.flatMap { item -> [ChapterRow] in
            let row: [ChapterRow]
            if let path = item.item?.components(separatedBy: "#").first,
               let index = spineIndices[path] {
                let parts = item.item?.split(separator: "#", maxSplits: 1)
                let fragment = (parts?.count ?? 0) > 1 ? String(parts![1]) : nil
                row = [ChapterRow(
                    label: item.label,
                    spineIndex: index,
                    fragment: fragment,
                    characterCount: getCharacterCount(for: item),
                    isCurrent: false,
                    indentLevel: indentLevel
                )]
            } else {
                row = []
            }
            return row + flattenTOC(item.subTable ?? [], indentLevel: indentLevel + 1, spineIndices: spineIndices)
        }
    }
    
    private func getCharacterCount(for item: EPUBTableOfContents) -> Int? {
        guard let tocPath = item.item else {
            return nil
        }
        let parts = tocPath.components(separatedBy: "#")
        let basePath = parts.first ?? tocPath
        guard let info = bookInfo.chapterInfo[basePath] else {
            return nil
        }
        let fragment = parts.count > 1 ? parts[1] : nil
        let offset = fragment.flatMap { info.fragmentOffsets?[$0] } ?? 0
        return info.currentTotal + offset
    }
}
