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
        for (index, item) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            let path = document.contentDirectory.appendingPathComponent(manifestItem.path)
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                let count = content.filtered().count
                chapterInfo[manifestItem.path] = BookInfo.ChapterInfo(spineIndex: index, currentTotal: total, chapterCount: count)
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
