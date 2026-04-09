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
    var compactGlossaries: Bool?
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
}

struct MiningContext {
    let sentence: String
    let documentTitle: String?
    let coverURL: URL?
    var sasayakiAudioData: Data? = nil
}

enum Handlebars: String, CaseIterable {
    case expression = "{expression}"
    case reading = "{reading}"
    case furiganaPlain = "{furigana-plain}"
    case audio = "{audio}"
    case glossary = "{glossary}"
    case glossaryFirst = "{glossary-first}"
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
