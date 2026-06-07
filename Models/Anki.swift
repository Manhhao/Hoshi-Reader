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

struct AnkiConfig: Codable {
    let selectedDeck: String?
    let selectedNoteType: String?
    let allowDupes: Bool
    let compactGlossaries: Bool?
    let embedMedia: Bool?
    let fieldMappings: [String: String]
    var tags: String?
    let availableDecks: [String]
    let availableNoteTypes: [AnkiNoteType]
    let useAnkiConnect: Bool?
    let ankiConnectConfig: AnkiConnectConfig?
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
    case selectedGlossary = "{selected-glossary}"
    case selectedGlossaryFallback = "{selected-glossary-fallback}"
    case selectedGlossaryBrief = "{selected-glossary-brief}"
    case selectedGlossaryBriefFallback = "{selected-glossary-brief-fallback}"
    case selectedGlossaryNoDictionary = "{selected-glossary-no-dictionary}"
    case selectedGlossaryNoDictionaryFallback = "{selected-glossary-no-dictionary-fallback}"
    case popupSelectionText = "{popup-selection-text}"
    case sentence = "{sentence}"
    case frequencies = "{frequencies}"
    case frequencyHarmonicRank = "{frequency-harmonic-rank}"
    case pitchPositions = "{pitch-accent-positions}"
    case pitchCategories = "{pitch-accent-categories}"
    case documentTitle = "{document-title}"
    case bookCover = "{book-cover}"
    case sasayakiAudio = "{sasayaki-audio}"
    
    static let singleGlossaryPrefix = "{single-glossary-"
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
            "sentence": Handlebars.sentence.rawValue,
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
