//
//  Book.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case title = "Title"
    
    var id: String { self.rawValue }
    var icon: String {
        switch self {
        case .recent: return "clock"
        case .title: return "textformat"
        }
    }
}

struct BookMetadata: Codable, Identifiable {
    let id: UUID
    let title: String?
    let cover: String?
    let folder: String?
    var lastAccess: Date
    
    init(id: UUID = UUID(), title: String?, cover: String?, folder: String?, lastAccess: Date) {
        self.id = id
        self.title = title
        self.cover = cover
        self.folder = folder
        self.lastAccess = lastAccess
    }
}

struct Bookmark: Codable {
    let chapterIndex: Int
    let progress: Double
    let characterCount: Int
    var lastModified: Date?
}

struct BookInfo: Codable {
    let characterCount: Int
    let chapterInfo: [String: ChapterInfo]
    
    struct ChapterInfo: Codable {
        let currentTotal: Int
        let chapterCount: Int
    }
}
