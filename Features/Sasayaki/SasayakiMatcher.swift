//
//  SasayakiMatcher.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation

struct SasayakiMatcher {
    private struct Chapter {
        let chapterIndex: Int
        let start: Int
        let length: Int
        var end: Int { start + length }
    }
    
    static func match(rootURL: URL, cues: [SasayakiCue], searchWindow: Int) throws -> SasayakiMatchData {
        let document = try BookStorage.loadEpub(rootURL)
        var source: [Character] = []
        var chapters: [Chapter] = []
        for (spineIndex, item) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            
            let url = document.contentDirectory.appendingPathComponent(manifestItem.path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            
            let chapterText = Array(content.filtered())
            chapters.append(Chapter(chapterIndex: spineIndex, start: source.count, length: chapterText.count))
            source.append(contentsOf: chapterText)
        }
        
        var start = 0
        for cue in cues.prefix(15) {
            let text = Array(cue.text.filtered())
            if text.count < 6 {
                continue
            }
            if let index = findText(source: source, text: text, start: 0, end: source.count) {
                start = index
                break
            }
        }
        
        var matches: [SasayakiMatch] = []
        var unmatched = 0
        var cursor = start
        
        for cue in cues {
            let text = cue.text.filtered()
            guard !text.isEmpty else {
                unmatched += 1
                continue
            }
            
            let chars = Array(text)
            guard let index = findText(source: source, text: chars, start: cursor, end: min(source.count, cursor + searchWindow)) else {
                unmatched += 1
                continue
            }
            
            let end = index + chars.count
            let range = chapters.first(where: { index >= $0.start && index < $0.end })!
            guard end <= range.end else {
                unmatched += 1
                continue
            }
            
            cursor = end
            matches.append(
                SasayakiMatch(
                    id: cue.id,
                    startTime: cue.startTime,
                    endTime: cue.endTime,
                    text: cue.text,
                    chapterIndex: range.chapterIndex,
                    start: index - range.start,
                    length: chars.count
                )
            )
        }
        
        return SasayakiMatchData(
            matches: matches,
            unmatched: unmatched
        )
    }
    
    private static func findText(source: [Character], text: [Character], start: Int, end: Int) -> Int? {
        var index = start
        while index <= end - text.count {
            if source[index..<(index + text.count)].elementsEqual(text) {
                return index
            }
            index += 1
        }
        return nil
    }
}
