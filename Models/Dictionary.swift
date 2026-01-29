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
    let name: String
    let path: URL
    var isEnabled: Bool
    var order: Int
    
    init(id: UUID = UUID(), name: String, path: URL, isEnabled: Bool = true, order: Int = 0) {
        self.id = id
        self.name = name
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

struct GlossaryData: Encodable {
    let dictionary: String
    let content: String
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
}

struct DeinflectionTag: Encodable {
    let name: String
    let description: String
}

struct FrequencyTag: Encodable {
    let value: Int
    let displayValue: String
}
