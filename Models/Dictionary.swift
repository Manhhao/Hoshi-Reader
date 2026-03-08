//
//  Dictionary.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct DictionaryInfo: Identifiable, Codable {
    let id: UUID
    let index: DictionaryIndex
    let path: URL
    var isEnabled: Bool
    var order: Int
    
    init(id: UUID = UUID(), index: DictionaryIndex, path: URL, isEnabled: Bool = true, order: Int = 0) {
        self.id = id
        self.index = index
        self.path = path
        self.isEnabled = isEnabled
        self.order = order
    }
}

struct DictionaryConfig: Codable {
    var termDictionaries: [DictionaryEntry]
    var frequencyDictionaries: [DictionaryEntry]
    var pitchDictionaries: [DictionaryEntry]
    
    struct DictionaryEntry: Codable {
        let fileName: String
        var isEnabled: Bool
        var order: Int
    }
}

struct DictionaryIndex: Codable {
    let title: String
    let format: Int
    let revision: String
    let isUpdatable: Bool
    let indexUrl: String
    let downloadUrl: String
}

struct GlossaryData: Encodable {
    let dictionary: String
    let content: String
    let definitionTags: String
    let termTags: String
}

struct FrequencyData: Encodable {
    let dictionary: String
    let frequencies: [FrequencyTag]
}

struct PitchData: Encodable {
    let dictionary: String
    let pitchPositions: [Int]
}

struct EntryData: Encodable {
    let expression: String
    let reading: String
    let matched: String
    let deinflectionTrace: [DeinflectionTag]
    let glossaries: [GlossaryData]
    let frequencies: [FrequencyData]
    let pitches: [PitchData]
    let rules: [String]
}

struct DeinflectionTag: Encodable {
    let name: String
    let description: String
}

struct FrequencyTag: Encodable {
    let value: Int
    let displayValue: String
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
