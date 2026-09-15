//
//  Dictionary.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum DictionaryCategory: String, Codable, CaseIterable, Identifiable {
    case none, monolingual, bilingual, exclude
    
    var id: String { self.rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .monolingual: return "Monolingual"
        case .bilingual: return "Bilingual"
        case .exclude: return "Exclude"
        }
    }
}

struct DictionaryInfo: Identifiable, Codable {
    let id: UUID
    let index: DictionaryIndex
    let path: URL
    var isEnabled: Bool
    var order: Int
    var category: DictionaryCategory
    
    init(id: UUID = UUID(), index: DictionaryIndex, path: URL, isEnabled: Bool = true, order: Int = 0, category: DictionaryCategory = .none) {
        self.id = id
        self.index = index
        self.path = path
        self.isEnabled = isEnabled
        self.order = order
        self.category = category
    }
}

struct DictionaryConfig: Codable {
    var termDictionaries: [DictionaryEntry]
    var frequencyDictionaries: [DictionaryEntry]
    var pitchDictionaries: [DictionaryEntry]
    var kanjiDictionaries: [DictionaryEntry]?
    
    struct DictionaryEntry: Codable {
        let fileName: String
        var isEnabled: Bool
        var order: Int
        var category: DictionaryCategory?
    }
}

nonisolated struct DictionaryIndex: Codable {
    let title: String
    let revision: String
    let isUpdatable: Bool?
    let indexUrl: String?
    let downloadUrl: String?
}

struct AudioSource: Codable, Identifiable {
    var id: String { url }
    var name: String
    let url: String
    var isEnabled: Bool
    let isDefault: Bool
    
    init(name: String = "", url: String, isEnabled: Bool = true, isDefault: Bool = false) {
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }
}
