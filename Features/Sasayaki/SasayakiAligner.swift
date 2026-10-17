//
//  SasayakiAligner.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated struct SasayakiAligner {
    private struct Timing {
        let start: Double
        let end: Double
        let exact: Bool
    }
    
    private struct Speech {
        let characters: [Character]
        let timings: [Timing]
        
        init(tokens: [SasayakiToken]) {
            var characters: [Character] = []
            var timings: [Timing] = []
            for token in tokens {
                let text = token.text as NSString
                SasayakiSource.ttuRegex.enumerateMatches(
                    in: token.text,
                    range: NSRange(location: 0, length: text.length)
                ) { match, _, _ in
                    guard let match else {
                        return
                    }
                    
                    characters.append(SasayakiAligner.normalize(Character(text.substring(with: match.range))))
                    timings.append(Timing(start: token.start, end: token.end, exact: false))
                }
            }
            self.characters = characters
            self.timings = timings
        }
    }
    
    private struct Anchor {
        let speech: Int
        let book: Int
    }
    
    private struct Span {
        let from: Double
        let to: Double
        let lower: Int
        let upper: Int
    }
    
    private static let probeLength = 12
    private static let probeStride = 100
    private static let maxBlock = 2000
    private static let maxSecondsPerCharacter = 0.7
    private static let durationOverhead = 1.0
    private static let maxEdge = 12
    private static let maxInterpolated = 8
    private static let maxInterpolatedGap = 2.5
    private static let endPadding = 0.3
    private static let leadingGap = 0.5
    private static let characterSpan = 0.15
    private static let startLead = 0.2
    private static let exactWindow = 20
    private static let exactShare = 4
    
    static func align(source: SasayakiSource, tokens: [SasayakiToken]) -> SasayakiMatchData {
        let book = source.text.map(normalize)
        let speech = Speech(tokens: tokens)
        var times = [Timing?](repeating: nil, count: book.count)
        let anchors = SasayakiAligner.anchors(speech: speech, book: book, chapters: source.chapters)
        for (anchor, next) in zip(anchors, anchors.dropFirst()) {
            guard next.speech > anchor.speech, next.book > anchor.book else {
                continue
            }
            
            let bounded = Anchor(
                speech: min(next.speech, anchor.speech + maxBlock),
                book: min(next.book, anchor.book + maxBlock)
            )
            assign(speech: speech, book: book, from: anchor, to: bounded, into: &times)
            let tail = Anchor(
                speech: max(next.speech - maxBlock, anchor.speech),
                book: max(next.book - maxBlock, anchor.book)
            )
            if next.book < book.count, tail.speech > anchor.speech || tail.book > anchor.book {
                assign(speech: speech, book: book, from: tail, to: next, into: &times)
            }
        }
        
        return cut(source: source, times: times)
    }
    
    private static func normalize(_ character: Character) -> Character {
        let mapped = String(character).precomposedStringWithCompatibilityMapping.lowercased()
        let scalar = mapped.unicodeScalars.first!
        if scalar.value >= 0x30A1, scalar.value <= 0x30F6 {
            return Character(Unicode.Scalar(scalar.value - 0x60)!)
        }
        return Character(scalar)
    }
    
    private static func anchors(
        speech: Speech,
        book: [Character],
        chapters: [SasayakiSource.Chapter]
    ) -> [Anchor] {
        var anchors = [Anchor(speech: 0, book: 0)]
        if let chapter = chapters.first(where: { $0.length >= probeLength }) {
            let probe = Array(book[chapter.start..<(chapter.start + probeLength)])
            if let found = SasayakiSource.findText(
                source: speech.characters,
                text: probe,
                start: 0,
                end: speech.characters.count
            ) {
                anchors[0] = Anchor(speech: found, book: chapter.start)
            }
        }
        
        var cursor = 0
        var hit = 0
        for index in stride(from: 0, through: speech.characters.count - probeLength, by: probeStride) {
            let probe = Array(speech.characters[index..<(index + probeLength)])
            let limit = cursor == 0 ? book.count : min(book.count, cursor + maxBlock + probeLength + index - hit)
            guard let found = SasayakiSource.findText(source: book, text: probe, start: cursor, end: limit) else {
                continue
            }
            if SasayakiSource.findText(source: book, text: probe, start: found + 1, end: limit) != nil {
                continue
            }
            
            cursor = found + probeLength
            hit = index
            let previous = anchors.last!
            if index > previous.speech, found > previous.book {
                anchors.append(Anchor(speech: index, book: found))
            }
        }
        for chapter in chapters where chapter.length >= probeLength {
            let probe = Array(book[chapter.start..<(chapter.start + probeLength)])
            let after = anchors.firstIndex { $0.book > chapter.start } ?? anchors.count
            if anchors[after - 1].book == chapter.start {
                continue
            }
            let low = anchors[after - 1].speech + 1
            let high = after < anchors.count ? anchors[after].speech : speech.characters.count
            guard let found = SasayakiSource.findText(source: speech.characters, text: probe, start: low, end: high) else {
                continue
            }
            if SasayakiSource.findText(source: speech.characters, text: probe, start: found + 1, end: high) != nil {
                continue
            }
            anchors.insert(Anchor(speech: found, book: chapter.start), at: after)
        }
        anchors.append(Anchor(speech: speech.characters.count, book: book.count))
        return anchors
    }
    
    private static func assign(
        speech: Speech,
        book: [Character],
        from anchor: Anchor,
        to next: Anchor,
        into times: inout [Timing?]
    ) {
        let spoken = Array(speech.characters[anchor.speech..<next.speech])
        let written = Array(book[anchor.book..<next.book])
        var removed = [Bool](repeating: false, count: spoken.count)
        var inserted = [Bool](repeating: false, count: written.count)
        for change in written.difference(from: spoken) {
            switch change {
            case .remove(let offset, _, _):
                removed[offset] = true
            case .insert(let offset, _, _):
                inserted[offset] = true
            }
        }
        
        var offset = 0
        for index in removed.indices {
            if !removed[index] {
                while offset < inserted.count, inserted[offset] {
                    offset += 1
                }
            }
            
            let target = anchor.book + min(offset, written.count - 1)
            if times[target] == nil {
                let timing = speech.timings[anchor.speech + index]
                times[target] = Timing(start: timing.start, end: timing.end, exact: !removed[index])
            }
            
            let substitution = offset < inserted.count && inserted[offset]
            if !removed[index] || substitution {
                offset += 1
            }
        }
    }
    
    private static func cut(source: SasayakiSource, times: [Timing?]) -> SasayakiMatchData {
        var matches: [SasayakiMatch] = []
        var unmatched = 0
        for chapter in source.chapters {
            var start = chapter.start
            for index in chapter.start..<chapter.end {
                guard isBoundary(source: source, chapter: chapter, start: start, index: index) else {
                    continue
                }
                
                if let span = time(start: start, index: index, chapter: chapter, times: times, previous: matches.last) {
                    matches.append(
                        SasayakiMatch(
                            id: "\(chapter.chapterIndex)-\(span.lower - chapter.start)",
                            startTime: span.from,
                            endTime: span.to,
                            text: String(source.text[span.lower...span.upper]),
                            chapterIndex: chapter.chapterIndex,
                            start: span.lower - chapter.start,
                            length: span.upper - span.lower + 1
                        )
                    )
                } else {
                    unmatched += 1
                }
                start = index + 1
            }
        }
        
        matches.sort { $0.startTime < $1.startTime }
        for index in matches.indices {
            let limit = index + 1 < matches.count ? matches[index + 1].startTime : .infinity
            matches[index].endTime = max(matches[index].endTime, min(matches[index].endTime + endPadding, limit))
        }
        
        return SasayakiMatchData(matches: matches, unmatched: unmatched, images: source.images)
    }
    
    private static func isBoundary(
        source: SasayakiSource,
        chapter: SasayakiSource.Chapter,
        start: Int,
        index: Int
    ) -> Bool {
        if source.sentenceEnds[index] || index == chapter.end - 1 {
            return true
        }
        
        return source.segmentEnds[index]
        && index > start
        && index + 2 < chapter.end
        && !source.sentenceEnds[index + 1]
    }
    
    private static func time(
        start: Int,
        index: Int,
        chapter: SasayakiSource.Chapter,
        times: [Timing?],
        previous: SasayakiMatch?
    ) -> Span? {
        let low = max(start - exactWindow, chapter.start)
        let high = min(index + exactWindow, chapter.end - 1)
        let exact = (low...high).filter { times[$0]?.exact == true }.count
        if exact * exactShare < high - low + 1 {
            return nil
        }
        let timed = (start...index).filter { times[$0] != nil }
        guard let first = timed.first, let last = timed.last else {
            return interpolate(start: start, index: index, chapter: chapter, times: times, previous: previous)
        }
        
        let firstTiming = times[first]!
        let to = times[last]!.end
        let lower = first - start <= maxEdge ? start : first
        let upper = index - last <= maxEdge ? index : last
        var from = firstTiming.start
        if timed.count >= 2, times[timed[1]]!.start - firstTiming.end > leadingGap {
            from = times[timed[1]]!.start
        } else {
            from = max(from, firstTiming.end - characterSpan)
        }
        from -= startLead
        
        guard withinBudget(from: from, to: to, span: upper - lower + 1) else {
            return trim(start: start, index: index, timed: timed, times: times)
            ?? interpolate(start: start, index: index, chapter: chapter, times: times, previous: previous)
        }
        
        return Span(from: from, to: to, lower: lower, upper: upper)
    }
    
    private static func trim(start: Int, index: Int, timed: [Int], times: [Timing?]) -> Span? {
        let at = { (position: Int) in times[timed[position]]! }
        var first = 0
        var last = timed.count - 1
        while first < last, at(first + 1).start - at(first).end > leadingGap {
            first += 1
        }
        while last > first, at(last).start - at(last - 1).end > leadingGap {
            last -= 1
        }
        
        let lower = timed[first] - start <= maxEdge ? start : timed[first]
        let upper = index - timed[last] <= maxEdge ? index : timed[last]
        let from = max(at(first).start, at(first).end - characterSpan) - startLead
        let to = at(last).end
        guard withinBudget(from: from, to: to, span: upper - lower + 1) else {
            return nil
        }
        
        return Span(from: from, to: to, lower: lower, upper: upper)
    }
    
    private static func interpolate(
        start: Int,
        index: Int,
        chapter: SasayakiSource.Chapter,
        times: [Timing?],
        previous: SasayakiMatch?
    ) -> Span? {
        let length = index - start + 1
        guard length <= maxInterpolated, start > chapter.start, index + 1 < chapter.end,
              let previousEnd = times[start - 1]?.end,
              let nextStart = times[index + 1]?.start,
              nextStart > previousEnd, nextStart - previousEnd <= maxInterpolatedGap else {
            return nil
        }
        
        var from = min(previousEnd + endPadding, nextStart)
        if let previous {
            from = max(from, previous.endTime)
        }
        
        guard withinBudget(from: from, to: nextStart, span: length) else {
            return nil
        }
        
        return Span(from: from, to: nextStart, lower: start, upper: index)
    }
    
    private static func withinBudget(from: Double, to: Double, span: Int) -> Bool {
        to > from && (to - from) <= durationOverhead + maxSecondsPerCharacter * Double(span)
    }
}
