//
//  Anki.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct AnkiResponse: Decodable {
    let profiles: [NameItem]
    let decks: [NameItem]
    let notetypes: [NoteTypeItem]
    
    struct NameItem: Decodable { let name: String }
    struct NoteTypeItem: Decodable {
        let name: String
        let fields: [NameItem]
    }
}

struct AnkiNoteType: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let fields: [String]
}

struct AnkiCardFormat: Codable, Identifiable {
    let id: UUID
    var name: String
    var icon: String
    var selectedDeck: String?
    var selectedNoteType: String?
    var fieldMappings: [String: String]
    var tags: String
    
    static let icons = ["plus.square", "plus.square.small", "plus.circle", "plus.circle.small", "plus.diamond", "plus.diamond.small"]
    static let duplicateIcons: [String: String] = [
        "plus.square": "plus.square.on.square",
        "plus.circle": "plus.circle.fill",
        "plus.diamond": "plus.diamond.fill",
    ]
}

struct AnkiConfig: Codable {
    var cardFormats: [AnkiCardFormat]?
    let allowDupes: Bool
    let disableShowNotes: Bool?
    let compactGlossaries: Bool?
    let embedMedia: Bool?
    let availableDecks: [String]
    let availableNoteTypes: [AnkiNoteType]
    let useAnkiConnect: Bool?
    let ankiConnectConfig: AnkiConnectConfig?
    let selectedGlossaryFallback: String?
    let showAllHandlebars: Bool?
}

struct LegacyAnkiFields: Decodable {
    let selectedDeck: String?
    let selectedNoteType: String?
    let fieldMappings: [String: String]?
    let tags: String?
}

enum DuplicateScope: String, Codable, CaseIterable {
    case collection
    case deck
    case deckroot
}

struct AnkiConnectConfig: Codable {
    var url: String?
    var timeout: Int
    var duplicateScope: DuplicateScope
    var checkAllModels: Bool? = false
    var forceSync: Bool
    var apiKey: String?
}

struct MiningContext {
    let sentence: String
    var clozeOffset: Int? = nil
    let documentTitle: String?
    let coverURL: URL?
    var sasayakiAudioData: Data? = nil
}

struct DictionaryMedia: Decodable {
    let dictionary: String
    let path: String
    let filename: String
}

enum Handlebars: String, CaseIterable {
    case expression = "{expression}"
    case reading = "{reading}"
    case furiganaPlain = "{furigana-plain}"
    case audio = "{audio}"
    case glossary = "{glossary}"
    case glossaryBrief = "{glossary-brief}"
    case glossaryNoDictionary = "{glossary-no-dictionary}"
    case glossaryFirst = "{glossary-first}"
    case glossaryFirstBrief = "{glossary-first-brief}"
    case glossaryFirstNoDictionary = "{glossary-first-no-dictionary}"
    case monolingualDefinition = "{monolingual-definition}"
    case monolingualDefinitionBrief = "{monolingual-definition-brief}"
    case monolingualDefinitionNoDictionary = "{monolingual-definition-no-dictionary}"
    case bilingualDefinition = "{bilingual-definition}"
    case bilingualDefinitionBrief = "{bilingual-definition-brief}"
    case bilingualDefinitionNoDictionary = "{bilingual-definition-no-dictionary}"
    case monolingualDefinitionFallback = "{monolingual-definition-fallback}"
    case monolingualDefinitionFallbackBrief = "{monolingual-definition-fallback-brief}"
    case monolingualDefinitionFallbackNoDictionary = "{monolingual-definition-fallback-no-dictionary}"
    case bilingualDefinitionFallback = "{bilingual-definition-fallback}"
    case bilingualDefinitionFallbackBrief = "{bilingual-definition-fallback-brief}"
    case bilingualDefinitionFallbackNoDictionary = "{bilingual-definition-fallback-no-dictionary}"
    case selectedGlossary = "{selected-glossary}"
    case selectedGlossaryBrief = "{selected-glossary-brief}"
    case selectedGlossaryNoDictionary = "{selected-glossary-no-dictionary}"
    case popupSelectionText = "{popup-selection-text}"
    case sentence = "{sentence}"
    case clozePrefix = "{cloze-prefix}"
    case clozeBody = "{cloze-body}"
    case clozeSuffix = "{cloze-suffix}"
    case frequencies = "{frequencies}"
    case frequencyHarmonicRank = "{frequency-harmonic-rank}"
    case pitchPositions = "{pitch-accent-positions}"
    case pitchCategories = "{pitch-accent-categories}"
    case pitchAccentGraphs = "{pitch-accent-graphs}"
    case pitchAccentGraphsFirst = "{pitch-accent-graphs-first}"
    case documentTitle = "{document-title}"
    case bookCover = "{book-cover}"
    case sasayakiAudio = "{sasayaki-audio}"
    
    static let singleGlossaryPrefix = "{single-glossary-"
    
    static let advanced: Set<Handlebars> = [
        .glossaryBrief,
        .glossaryNoDictionary,
        .glossaryFirstBrief,
        .glossaryFirstNoDictionary,
        .monolingualDefinition,
        .monolingualDefinitionBrief,
        .monolingualDefinitionNoDictionary,
        .bilingualDefinition,
        .bilingualDefinitionBrief,
        .bilingualDefinitionNoDictionary,
        .monolingualDefinitionFallback,
        .monolingualDefinitionFallbackBrief,
        .monolingualDefinitionFallbackNoDictionary,
        .bilingualDefinitionFallback,
        .bilingualDefinitionFallbackBrief,
        .bilingualDefinitionFallbackNoDictionary,
        .selectedGlossaryBrief,
        .selectedGlossaryNoDictionary,
        .clozePrefix,
        .clozeBody,
        .clozeSuffix,
        .pitchAccentGraphsFirst
    ]
}

struct AnkiFieldTemplate {
    let noteType: String
    let mappings: [String: String]
    
    static let templates: [AnkiFieldTemplate] = [
        AnkiFieldTemplate(noteType: "Lapis", mappings: [
            "Expression": Handlebars.expression.rawValue,
            "ExpressionFurigana": Handlebars.furiganaPlain.rawValue,
            "ExpressionReading": Handlebars.reading.rawValue,
            "ExpressionAudio": Handlebars.audio.rawValue,
            "SelectionText": Handlebars.popupSelectionText.rawValue,
            "MainDefinition": Handlebars.glossaryFirst.rawValue,
            "Sentence": Handlebars.sentence.rawValue,
            "Picture": Handlebars.bookCover.rawValue,
            "Glossary": Handlebars.glossary.rawValue,
            "PitchPosition": Handlebars.pitchPositions.rawValue,
            "PitchCategories": Handlebars.pitchCategories.rawValue,
            "Frequency": Handlebars.frequencies.rawValue,
            "FreqSort": Handlebars.frequencyHarmonicRank.rawValue,
            "MiscInfo": Handlebars.documentTitle.rawValue,
        ]),
        AnkiFieldTemplate(noteType: "Kiku", mappings: [
            "Expression": Handlebars.expression.rawValue,
            "ExpressionFurigana": Handlebars.furiganaPlain.rawValue,
            "ExpressionReading": Handlebars.reading.rawValue,
            "ExpressionAudio": Handlebars.audio.rawValue,
            "SelectionText": Handlebars.popupSelectionText.rawValue,
            "MainDefinition": Handlebars.glossaryFirst.rawValue,
            "Sentence": Handlebars.sentence.rawValue,
            "Picture": Handlebars.bookCover.rawValue,
            "Glossary": Handlebars.glossary.rawValue,
            "PitchPosition": Handlebars.pitchPositions.rawValue,
            "PitchCategories": Handlebars.pitchCategories.rawValue,
            "Frequency": Handlebars.frequencies.rawValue,
            "FreqSort": Handlebars.frequencyHarmonicRank.rawValue,
            "MiscInfo": Handlebars.documentTitle.rawValue,
        ]),
        AnkiFieldTemplate(noteType: "Senren", mappings: [
            "word": Handlebars.expression.rawValue,
            "reading": Handlebars.reading.rawValue,
            "sentence": "<span class=\"group\">\(Handlebars.clozePrefix.rawValue)<span class=\"highlight\">\(Handlebars.clozeBody.rawValue)</span>\(Handlebars.clozeSuffix.rawValue)</span>",
            "selectionText": Handlebars.popupSelectionText.rawValue,
            "definition": Handlebars.glossaryFirst.rawValue,
            "wordAudio": Handlebars.audio.rawValue,
            "picture": Handlebars.bookCover.rawValue,
            "glossary": Handlebars.glossary.rawValue,
            "pitchPositions": Handlebars.pitchPositions.rawValue,
            "pitchCategories": Handlebars.pitchCategories.rawValue,
            "frequencies": Handlebars.frequencies.rawValue,
            "freqSort": Handlebars.frequencyHarmonicRank.rawValue,
            "miscInfo": Handlebars.documentTitle.rawValue,
        ])
    ]
}
