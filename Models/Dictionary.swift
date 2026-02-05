//
//  Dictionary.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftData

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


@Model
class DictionaryDetailInfo {
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
    @MainActor
    static func appendCustomCSS(dictionaryStyles: [String: String], modelContext: ModelContext) -> [String: String] {
        var fullDictionaryStyles: [String: String] = [:]
        for (name, css) in dictionaryStyles {
            let matchedDetailInfos = modelContext.getDetailInfosBy(name: name)
            if (matchedDetailInfos.count == 0) || (matchedDetailInfos.count > 1) {
                continue
            }
            let matchedDetailInfo = matchedDetailInfos.first!
            fullDictionaryStyles.updateValue(matchedDetailInfo.customCSS + css, forKey: name)
        }
        return fullDictionaryStyles
    }
    
    var name: String
    var customCSS: String
    
    init(name: String, customCSS: String = DictionaryDetailInfo.defaultCSS) {
        self.name = name
        self.customCSS = customCSS
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

extension ModelContext {
    func getDetailInfosBy(name: String) -> [DictionaryDetailInfo] {
        let dictionaryDetailPredicate = #Predicate<DictionaryDetailInfo> { detailSetting in
            detailSetting.name == name
        }
        let descriptor = FetchDescriptor<DictionaryDetailInfo>(predicate: dictionaryDetailPredicate)
        let dictionaryDetailInfos = try! fetch(descriptor)
        return dictionaryDetailInfos
    }
}
