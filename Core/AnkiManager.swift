//
//  AnkiManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit

@Observable
@MainActor
class AnkiManager {
    static let shared = AnkiManager()
    
    var selectedDeck: String?
    var selectedNoteType: String?
    var fieldMappings: [String: String] = [:]
    var tags: String = ""
    
    var availableDecks: [String] = []
    var availableNoteTypes: [AnkiNoteType] = []
    
    var allowDupes: Bool = false
    
    var errorMessage: String?
    
    var isConnected: Bool { !availableDecks.isEmpty }
    
    var needsAudio: Bool {
        fieldMappings.values.contains(Handlebars.audio.rawValue)
    }
    
    private static let scheme = "hoshi://"
    private static let fetchCallback = scheme + "ankiFetch"
    private static let successCallback = scheme + "ankiSuccess"
    
    private static let pasteboardType = "net.ankimobile.json"
    private static let infoCallback = "anki://x-callback-url/infoForAdding"
    private static let addNoteCallback = "anki://x-callback-url/addnote"
    
    private static let ankiConfig = "anki_config.json"
    
    private static let handlebarRegex = /\{.*?\}/
    
    private init() { load() }
    
    func requestInfo() {
        var urlComponents = URLComponents(string: Self.infoCallback)
        urlComponents?.queryItems = [
            URLQueryItem(name: "x-success", value: Self.fetchCallback)
        ]
        
        if let url = urlComponents?.url {
            UIApplication.shared.open(url)
        }
    }
    
    func fetch(retryCount: Int = 0) {
        let delay = 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.performFetch(retryCount: retryCount)
        }
    }
    
    private func performFetch(retryCount: Int) {
        guard let data = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType) else {
            if retryCount < 3 {
                fetch(retryCount: retryCount + 1)
                return
            }
            errorMessage = "No data received from Anki. Please try again."
            return
        }
        UIPasteboard.general.setData(Data(), forPasteboardType: Self.pasteboardType)
        
        guard let response = try? JSONDecoder().decode(AnkiResponse.self, from: data) else {
            let rawString = String(data: data, encoding: .utf8) ?? "Unable to read data"
            errorMessage = "Failed to decode Anki response:\n\n\(rawString)"
            return
        }
        availableDecks = response.decks.map(\.name)
        availableNoteTypes = response.notetypes.map { AnkiNoteType(name: $0.name, fields: $0.fields.map(\.name)) }
        
        if let deck = availableDecks.first(where: { $0.caseInsensitiveCompare("Default") != .orderedSame }) {
            selectedDeck = deck
        } else {
            selectedDeck = availableDecks.first
        }
        
        if let noteType = availableNoteTypes.first {
            selectedNoteType = noteType.name
            fieldMappings.removeAll()
        } else {
            selectedNoteType = nil
            fieldMappings.removeAll()
        }
        
        save()
    }
    
    func addNote(content: [String: String], context: MiningContext) {
        guard let deck = selectedDeck,
              let noteType = selectedNoteType else {
            return
        }
        
        let singleGlossaries: [String: String]
        if let json = content["singleGlossaries"],
           let data = json.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            singleGlossaries = parsed
        } else {
            singleGlossaries = [:]
        }
        
        var urlComponents = URLComponents(string: Self.addNoteCallback)
        var queryItems = [
            URLQueryItem(name: "deck", value: deck),
            URLQueryItem(name: "type", value: noteType)
        ]
        
        for (field, fieldContent) in fieldMappings {
            let value = fieldContent.replacing(Self.handlebarRegex) { match in
                return handlebarToValue(handlebar: String(match.0), context: context, content: content, singleGlossaries: singleGlossaries)
            }
            queryItems.append(URLQueryItem(name: "fld" + field, value: value))
        }
        
        if !tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: tags))
        }
        
        if allowDupes {
            queryItems.append(URLQueryItem(name: "dupes", value: "1"))
        }
        
        queryItems.append(URLQueryItem(name: "x-success", value: Self.successCallback))
        
        urlComponents?.queryItems = queryItems
        
        if let url = urlComponents?.url {
            UIApplication.shared.open(url)
        }
    }
    
    func save() {
        let data = AnkiConfig(
            selectedDeck: selectedDeck,
            selectedNoteType: selectedNoteType,
            allowDupes: allowDupes,
            fieldMappings: fieldMappings,
            tags: tags,
            availableDecks: availableDecks,
            availableNoteTypes: availableNoteTypes
        )
        
        guard let directory = try? BookStorage.getDocumentsDirectory() else {
            return
        }
        try? BookStorage.save(data, inside: directory, as: Self.ankiConfig)
    }
    
    private func handlebarToValue(handlebar: String, context: MiningContext, content: [String: String], singleGlossaries: [String: String]) -> String {
        let error = String(handlebar.dropLast()) + "-render-error}"
        if handlebar.hasPrefix(Handlebars.singleGlossaryPrefix) {
            let dictName = String(handlebar.dropFirst(Handlebars.singleGlossaryPrefix.count).dropLast())
            return singleGlossaries[dictName] ?? error
        } else if let standardHandlebar = Handlebars(rawValue: handlebar) {
            switch standardHandlebar {
            case .expression:
                return content["expression"] ?? ""
            case .reading:
                return content["reading"] ?? ""
            case .furiganaPlain:
                return content["furiganaPlain"] ?? ""
            case .glossary:
                return content["glossary"] ?? ""
            case .glossaryFirst:
                return content["glossaryFirst"] ?? ""
            case .frequencies:
                return content["frequenciesHtml"] ?? ""
            case .frequencyHarmonicRank:
                return content["freqHarmonicRank"] ?? ""
            case .pitchPositions:
                return content["pitchPositions"] ?? ""
            case .pitchCategories:
                return content["pitchCategories"] ?? ""
            case .sentence:
                guard let matched = content["matched"] else { return context.sentence }
                return context.sentence.replacingOccurrences(of: matched, with: "<b>\(matched)</b>")
            case .documentTitle:
                return context.documentTitle ?? ""
            case .popupSelectionText:
                return content["popupSelectionText"] ?? ""
            case .bookCover:
                var coverPath: String?
                if let coverURL = context.coverURL {
                    try? LocalFileServer.shared.setCover(file: coverURL)
                    coverPath = "http://localhost:\(LocalFileServer.port)/cover/cover.\(coverURL.pathExtension)"
                }
                return coverPath ?? ""
            case .audio:
                return content["audio"] ?? ""
            }
        }
        return error
    }
    
    private func load() {
        guard let directory = try? BookStorage.getDocumentsDirectory() else {
            return
        }
        let url = directory.appendingPathComponent(Self.ankiConfig)
        
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AnkiConfig.self, from: data) else {
            return
        }
        
        selectedDeck = config.selectedDeck
        selectedNoteType = config.selectedNoteType
        allowDupes = config.allowDupes
        fieldMappings = config.fieldMappings
        tags = config.tags ?? ""
        availableDecks = config.availableDecks
        availableNoteTypes = config.availableNoteTypes
    }
}
