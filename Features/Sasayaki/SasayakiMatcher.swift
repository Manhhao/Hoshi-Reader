//
//  SasayakiMatcher.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct SasayakiMatcher {
    private static let searchWindow = 200
    private static let maxMisses = 4
    
    static func match(rootURL: URL, cues: [SasayakiCue]) throws -> SasayakiMatchData {
        let source = try SasayakiSource.build(rootURL: rootURL)
        var candidates: [Int] = []
        for cue in cues.prefix(15) {
            if cue.text.hasPrefix("＊") {
                continue
            }
            
            let text = Array(cue.text.filtered())
            if text.count < 6 {
                continue
            }
            if let index = SasayakiSource.findText(source: source.text, text: text, start: 0, end: source.text.count) {
                candidates.append(index)
            }
        }
        
        var start = 0
        var bestVotes = 0
        for candidate in candidates {
            let votes = candidates.filter { $0 >= candidate && $0 <= candidate + 2000 }.count
            if votes > bestVotes {
                bestVotes = votes
                start = candidate
            }
        }
        
        var matches: [SasayakiMatch] = []
        var unmatched = 0
        var cursor = start
        var misses = 0
        
        for cue in cues {
            let text = cue.text.filtered()
            guard !text.isEmpty else {
                unmatched += 1
                continue
            }
            
            let chars = Array(text)
            if cue.text.hasPrefix("＊") && chars.count < 5 {
                unmatched += 1
                continue
            }
            
            var found = SasayakiSource.findText(
                source: source.text,
                text: chars,
                start: cursor,
                end: min(source.text.count, cursor + chars.count + searchWindow)
            )
            if found == nil, misses >= maxMisses, chars.count >= 10 {
                found = findUnique(source: source.text, text: chars, start: cursor)
            }
            guard let index = found else {
                unmatched += 1
                misses += 1
                continue
            }
            
            let end = index + chars.count
            let range = source.chapters.first { index >= $0.start && index < $0.end }!
            guard end <= range.end else {
                unmatched += 1
                misses += 1
                continue
            }
            
            cursor = end
            misses = 0
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
            unmatched: unmatched,
            images: source.images
        )
    }
    
    private static func findUnique(source: [Character], text: [Character], start: Int) -> Int? {
        guard let index = SasayakiSource.findText(source: source, text: text, start: start, end: source.count) else {
            return nil
        }
        guard SasayakiSource.findText(source: source, text: text, start: index + 1, end: source.count) == nil else {
            return nil
        }
        return index
    }
}
