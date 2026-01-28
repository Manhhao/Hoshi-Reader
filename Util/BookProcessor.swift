//
//  BookProcessor.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation

struct BookProcessor {
    static func process(document: EPUBDocument) -> BookInfo? {
        var chapterInfo: [String: BookInfo.ChapterInfo] = [:]
        var total = 0
        for (index, item) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            let path = document.contentDirectory.appendingPathComponent(manifestItem.path)
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                let count = content.characterCount()
                chapterInfo[manifestItem.path] = BookInfo.ChapterInfo(spineIndex: index, currentTotal: total, chapterCount: count)
                total += count
            }
        }
        return BookInfo(characterCount: total, chapterInfo: chapterInfo)
    }
}
