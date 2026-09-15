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
    static func process(document: EPUBDocument) -> BookInfo {
        var chapterInfo: [String: BookInfo.ChapterInfo] = [:]
        var images: [String] = []
        var seenImages: Set<String> = []
        var total = 0
        let tocFragments = collectTOCFragments(document.tableOfContents)
        for (index, item) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            let path = document.contentDirectory.appendingPathComponent(manifestItem.path)
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                let count = content.filtered().count
                let offsets = tocFragments[manifestItem.path].map { fragmentOffsets(in: content, fragments: $0) }
                chapterInfo[manifestItem.path] = BookInfo.ChapterInfo(spineIndex: index, currentTotal: total, chapterCount: count, fragmentOffsets: offsets)
                total += count
                for image in imagePaths(in: content, path: path, contentDirectory: document.contentDirectory) {
                    if !seenImages.contains(image) {
                        images.append(image)
                        seenImages.insert(image)
                    }
                }
            }
        }
        return BookInfo(characterCount: total, chapterInfo: chapterInfo, images: images)
    }
    
    private static func collectTOCFragments(_ toc: EPUBTableOfContents) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        func walk(_ node: EPUBTableOfContents) {
            if let item = node.item, let hash = item.firstIndex(of: "#") {
                let base = String(item[..<hash])
                let fragment = String(item[item.index(after: hash)...])
                map[base, default: []].insert(fragment)
            }
            node.subTable?.forEach(walk)
        }
        walk(toc)
        return map
    }
    
    private static func fragmentOffsets(in content: String, fragments: Set<String>) -> [String: Int] {
        guard let open = content.range(of: "<body[^>]*>", options: .regularExpression) else {
            return [:]
        }
        let body = content[open.upperBound...]
        var offsets: [String: Int] = [:]
        for fragment in fragments {
            guard let id = body.range(of: "id=\"\(fragment)\""),
                  let tag = body[..<id.lowerBound].range(of: "<", options: .backwards) else {
                continue
            }
            offsets[fragment] = String(body[..<tag.lowerBound]).filtered().count
        }
        return offsets
    }
    
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png"]
    private static let imageRegex = #/<(?:img|image)\b(?![^>]*\bclass="[^"]*\bgaiji)[^>]*?(?:src|xlink:href)="([^"]+)"/#
    
    private static func imagePaths(in html: String, path: URL, contentDirectory: URL) -> [String] {
        let chapterPath = path.deletingLastPathComponent()
        let base = contentDirectory.standardizedFileURL.path(percentEncoded: false)
        return html.matches(of: imageRegex).compactMap { match in
            let imagePath = URL(fileURLWithPath: String(match.output.1), relativeTo: chapterPath).standardizedFileURL
            let fullPath = imagePath.path(percentEncoded: false)
            guard imageExtensions.contains(imagePath.pathExtension.lowercased()),
                  FileManager.default.fileExists(atPath: fullPath) else {
                return nil
            }
            return String(fullPath.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }
}
