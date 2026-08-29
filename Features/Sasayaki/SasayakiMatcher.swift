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
    private static let searchWindow = 200
    private static let maxMisses = 4
    
    private enum MatchError: Error {
        case missingEpub
    }
    
    private struct Chapter {
        let chapterIndex: Int
        let start: Int
        let length: Int
        var end: Int { start + length }
    }
    
    static func match(rootURL: URL, cues: [SasayakiCue]) throws -> SasayakiMatchData {
        guard let epub = BookStorage.loadMetadata(root: rootURL)?.epub else {
            throw MatchError.missingEpub
        }
        
        let document = try BookStorage.loadEpub(rootURL.appendingPathComponent(epub))
        let guideTocPaths: Set<String> = Set(
            (document.guide?.references ?? [])
                .filter { $0.type.lowercased() == "toc" }
                .map { $0.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? $0.href }
        )
        let imageTag = /<(?:img|image)\b/
        var source: [Character] = []
        var chapters: [Chapter] = []
        var images: [SasayakiImage] = []
        for (spineIndex, item) in document.spine.items.enumerated() {
            guard item.linear, let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            if manifestItem.property?.contains("nav") == true {
                continue
            }
            if guideTocPaths.contains(manifestItem.path) {
                continue
            }
            
            let url = document.contentDirectory.appendingPathComponent(manifestItem.path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            
            let body = content.body()
            for (imageIndex, match) in body.matches(of: imageTag).enumerated() {
                let offset = String(body[..<match.range.lowerBound]).filtered().count
                images.append(SasayakiImage(chapterIndex: spineIndex, imageIndex: imageIndex, offset: offset))
            }
            
            let chapterText = Array(body.filtered())
            chapters.append(Chapter(chapterIndex: spineIndex, start: source.count, length: chapterText.count))
            source.append(contentsOf: chapterText)
        }
        
        var candidates: [Int] = []
        for cue in cues.prefix(15) {
            if cue.text.hasPrefix("＊") {
                continue
            }
            
            let text = Array(cue.text.filtered())
            if text.count < 6 {
                continue
            }
            if let index = findText(source: source, text: text, start: 0, end: source.count) {
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
            
            var found = findText(source: source, text: chars, start: cursor, end: min(source.count, cursor + chars.count + searchWindow))
            if found == nil, misses >= maxMisses, chars.count >= 10 {
                found = findUnique(source: source, text: chars, start: cursor)
            }
            guard let index = found else {
                unmatched += 1
                misses += 1
                continue
            }
            
            let end = index + chars.count
            let range = chapters.first(where: { index >= $0.start && index < $0.end })!
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
            images: images
        )
    }
    
    private static func findUnique(source: [Character], text: [Character], start: Int) -> Int? {
        guard let index = findText(source: source, text: text, start: start, end: source.count) else {
            return nil
        }
        guard findText(source: source, text: text, start: index + 1, end: source.count) == nil else {
            return nil
        }
        return index
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
