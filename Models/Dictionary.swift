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
    var customCSS: String
    
    init(id: UUID = UUID(), name: String, path: URL, isEnabled: Bool = true, order: Int = 0, customCSS: String = "") {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.order = order
        self.customCSS = customCSS
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case isEnabled
        case order
        case customCSS
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(URL.self, forKey: .path)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.order = try container.decode(Int.self, forKey: .order)
        self.customCSS = try container.decodeIfPresent(String.self, forKey: .customCSS) ?? ""
    }
    
    static let defaultCSS = """
        :host {
            /* Put light mode css here */
            div {}
        }

        @media (prefers-color-scheme: dark) {
            :host {
                /* Put dark mode css here */
                div {}
            }
        }
        """
    
    static func dictionaryInfo(of name: String, in infos: [DictionaryInfo]) -> DictionaryInfo? {
        let matchedIndices = infos.indices { dictionaryInfo in
            dictionaryInfo.name == name
        }
        let matchedDictionaryInfos = infos[matchedIndices]
        if (matchedDictionaryInfos.count == 0) || (matchedDictionaryInfos.count > 1) {
            return nil
        }
        return matchedDictionaryInfos.first!
    }
    
    static func appendCustomCSS(dictionaryStyles: [String: String], for dictionaryInfos: [DictionaryInfo]) -> [String: String] {
        var fullDictionaryStyles: [String: String] = [:]
        for (name, css) in dictionaryStyles {
            let matchedDictionaryInfo = Self.dictionaryInfo(of: name, in: dictionaryInfos)
            if let matchedDictionaryInfo {
                fullDictionaryStyles.updateValue(matchedDictionaryInfo.customCSS + css, forKey: name)
            }
        }
        return fullDictionaryStyles
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
    let definitionTags: [String]
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
    let url: String
    var isEnabled: Bool
    let isDefault: Bool

    init(url: String, isEnabled: Bool = true, isDefault: Bool = false) {
        self.url = url
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }
}
