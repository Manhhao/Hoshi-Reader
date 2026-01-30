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
    let fieldMappings: [String: String]
    var tags: String?
    let availableDecks: [String]
    let availableNoteTypes: [AnkiNoteType]
}

enum Handlebars: String, CaseIterable {
    case expression = "{expression}"
    case reading = "{reading}"
    case furiganaPlain = "{furigana-plain}"
    case glossary = "{glossary}"
    case glossaryFirst = "{glossary-first}"
    case sentence = "{sentence}"
    case frequencies = "{frequencies}"
    case frequencyHarmonicRank = "{frequency-harmonic-rank}"
    case pitchPositions = "{pitch-accent-positions}"
    case pitchCategories = "{pitch-accent-categories}"
    
    static let singleGlossaryPrefix = "{single-glossary-"
}
