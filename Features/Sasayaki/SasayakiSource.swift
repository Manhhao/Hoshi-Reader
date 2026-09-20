//
//  SasayakiSource.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation

nonisolated struct SasayakiSource: Sendable {
    struct Chapter: Sendable {
        let chapterIndex: Int
        let start: Int
        let length: Int
        var end: Int { start + length }
    }
    
    enum SourceError: Error {
        case missingEpub
    }
    
    let text: [Character]
    let sentenceEnds: [Bool]
    let segmentEnds: [Bool]
    let chapters: [Chapter]
    let images: [SasayakiImage]
    
    static let characterClass = "0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ가-힣ㄱ-ㆎ\\p{Radical}\\p{Unified_Ideograph}"
    static let ttuRegex = try! NSRegularExpression(pattern: "[" + characterClass + "]")
    private static let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", "…", "」", "』", "「", "『", "（"]
    private static let segmentBreaks: Set<Character> = ["、", ",", "，", "\u{2500}"]
    private static let blockBreak: Character = "\u{1}"
    
    @MainActor
    static func build(rootURL: URL) throws -> SasayakiSource {
        guard let epub = BookStorage.loadMetadata(root: rootURL)?.epub else {
            throw SourceError.missingEpub
        }
        
        let document = try BookStorage.loadEpub(rootURL.appendingPathComponent(epub))
        let guideTocPaths: Set<String> = Set(
            (document.guide?.references ?? [])
                .filter { $0.type.lowercased() == "toc" }
                .map { $0.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? $0.href }
        )
        let imageTag = /<(?:img|image)\b/
        var text: [Character] = []
        var sentenceEnds: [Bool] = []
        var segmentEnds: [Bool] = []
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
            let path = manifestItem.path.lowercased()
            if path.contains("toc") || path.contains("caution") || path.contains("colophon") {
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
            
            let (chapterText, chapterEnds, chapterSegments) = flatten(content)
            chapters.append(Chapter(chapterIndex: spineIndex, start: text.count, length: chapterText.count))
            text.append(contentsOf: chapterText)
            sentenceEnds.append(contentsOf: chapterEnds)
            segmentEnds.append(contentsOf: chapterSegments)
        }
        
        return SasayakiSource(
            text: text,
            sentenceEnds: sentenceEnds,
            segmentEnds: segmentEnds,
            chapters: chapters,
            images: images
        )
    }
    
    static func findText(source: [Character], text: [Character], start: Int, end: Int) -> Int? {
        var index = start
        while index <= end - text.count {
            if source[index..<(index + text.count)].elementsEqual(text) {
                return index
            }
            index += 1
        }
        return nil
    }
    
    static func strip(_ html: String, blockBreak: Character? = nil) -> String {
        var text = html.body()
        text = text.replacingOccurrences(of: "(?s)<(rt|rp)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        if let blockBreak {
            text = text.replacingOccurrences(
                of: "</?(?:p|div|h[1-6]|li|ul|ol|blockquote|section|article|table|tr|td|th|hr|br|img|image)\\b[^>]*>",
                with: String(blockBreak),
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&#[xX]?[0-9A-Fa-f]+;", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        return text.replacingOccurrences(of: "&gt;", with: ">")
    }
    
    static func flatten(_ html: String) -> ([Character], [Bool], [Bool]) {
        autoreleasepool {
            let markup = strip(html, blockBreak: blockBreak)
            let string = markup as NSString
            let matches = ttuRegex.matches(in: markup, range: NSRange(location: 0, length: string.length))
            var text: [Character] = []
            var sentenceEnds: [Bool] = []
            var segmentEnds: [Bool] = []
            for (index, match) in matches.enumerated() {
                text.append(Character(string.substring(with: match.range)))
                let gapEnd = index + 1 < matches.count ? matches[index + 1].range.location : string.length
                let gap = string.substring(with: NSRange(match.range.upperBound..<gapEnd))
                let sentenceEnd = gap.contains { sentenceEnders.contains($0) || $0 == blockBreak }
                sentenceEnds.append(sentenceEnd)
                segmentEnds.append(!sentenceEnd && gap.contains { segmentBreaks.contains($0) })
            }
            return (text, sentenceEnds, segmentEnds)
        }
    }
}
