//
//  BookSearch.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation

nonisolated struct SearchChapter: Sendable {
    let url: URL
    let label: String
    let start: Int
}

nonisolated struct SearchResult: Identifiable, Sendable {
    let id: Int
    let chapter: String
    let character: Int
    let prefix: String
    let match: String
    let suffix: String
}

nonisolated enum BookSearch {
    private static let limit = 100
    private static let sentenceDelimiters: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n", "\r"]
    private static let trailingSentenceChars: Set<Character> = ["。", "、", "！", "？", "」", "』", "）", ")", "】", "〉", "》", "〕", "｝", "}", "］", "]"]
    private static let brackets: [Character: Character] = [
        "「": "」", "『": "』", "（": "）", "(": ")", "【": "】", "〈": "〉",
        "《": "》", "〔": "〕", "｛": "｝", "{": "}", "［": "］", "[": "]"
    ]
    
    @MainActor
    static func chapters(document: EPUBDocument, bookInfo: BookInfo) -> [SearchChapter] {
        let labels = document.chapterLabels
        var label = ""
        var chapters: [SearchChapter] = []
        for (index, item) in document.spine.items.enumerated() {
            label = labels[index] ?? label
            guard let manifestItem = document.manifest.items[item.idref],
                  let info = bookInfo.chapterInfo[manifestItem.path] else {
                continue
            }
            chapters.append(SearchChapter(
                url: document.contentDirectory.appendingPathComponent(manifestItem.path),
                label: label,
                start: info.currentTotal
            ))
        }
        return chapters
    }
    
    static func search(chapters: [SearchChapter], query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        for chapter in chapters {
            guard let content = try? String(contentsOf: chapter.url, encoding: .utf8) else {
                continue
            }
            var offset = chapter.start
            for paragraph in plainText(content).components(separatedBy: "\n") {
                let line = paragraph.trimmingCharacters(in: .whitespaces)
                var cursor = line.startIndex
                while let range = line.range(of: query, options: .caseInsensitive, range: cursor..<line.endIndex) {
                    let bounds = sentence(in: line, around: range)
                    results.append(SearchResult(
                        id: results.count,
                        chapter: chapter.label,
                        character: offset + String(line[..<range.lowerBound]).filtered().count,
                        prefix: String(line[bounds.lowerBound..<range.lowerBound]),
                        match: String(line[range]),
                        suffix: String(line[range.upperBound..<bounds.upperBound])
                    ))
                    if results.count >= limit {
                        return results
                    }
                    cursor = range.upperBound
                }
                offset += line.filtered().count
            }
        }
        return results
    }
    
    private static func sentence(in line: String, around range: Range<String.Index>) -> Range<String.Index> {
        var start = range.lowerBound
        while start > line.startIndex, !sentenceDelimiters.contains(line[line.index(before: start)]) {
            start = line.index(before: start)
        }
        
        var end = range.upperBound
        while end < line.endIndex, !sentenceDelimiters.contains(line[end]) {
            end = line.index(after: end)
        }
        if end < line.endIndex {
            end = line.index(after: end)
            while end < line.endIndex, trailingSentenceChars.contains(line[end]) {
                end = line.index(after: end)
            }
        }
        
        start = trimmedStart(line, from: start, limit: range.lowerBound)
        end = trimmedEnd(line, from: end, limit: range.upperBound)
        
        var stack: [Character] = []
        var unmatched: [Character] = []
        var index = start
        while index < end {
            let character = line[index]
            if brackets[character] != nil {
                stack.append(character)
            } else if brackets.values.contains(character) {
                if let open = stack.last, brackets[open] == character {
                    stack.removeLast()
                } else {
                    unmatched.append(character)
                }
            }
            index = line.index(after: index)
        }
        
        while let open = stack.first, start < range.lowerBound, line[start] == open {
            stack.removeFirst()
            start = line.index(after: start)
        }
        
        var cursor = end
        while let close = unmatched.last, cursor > range.upperBound {
            let previous = line.index(before: cursor)
            if line[previous] == close {
                unmatched.removeLast()
                end = previous
            } else if !sentenceDelimiters.contains(line[previous]) {
                break
            }
            cursor = previous
        }
        
        return trimmedStart(line, from: start, limit: range.lowerBound)..<trimmedEnd(line, from: end, limit: range.upperBound)
    }
    
    private static func trimmedStart(_ line: String, from index: String.Index, limit: String.Index) -> String.Index {
        var index = index
        while index < limit, line[index].isWhitespace {
            index = line.index(after: index)
        }
        return index
    }
    
    private static func trimmedEnd(_ line: String, from index: String.Index, limit: String.Index) -> String.Index {
        var index = index
        while index > limit, line[line.index(before: index)].isWhitespace {
            index = line.index(before: index)
        }
        return index
    }
    
    private static func plainText(_ html: String) -> String {
        var text = html.body()
        text = text.replacingOccurrences(of: "(?s)<(rt|rp)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "(?i)<br[^>]*>|</(p|div|h[1-6]|li|blockquote|section|td|tr)>",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&#[xX]?[0-9A-Fa-f]+;", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        return text
    }
}
