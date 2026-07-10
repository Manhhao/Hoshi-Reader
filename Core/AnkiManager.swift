//
//  AnkiManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SQLite3
import libzstd
import UIKit
import ZIPFoundation

@Observable
@MainActor
class AnkiManager {
    static let shared = AnkiManager()
    
    var cardFormats: [AnkiCardFormat] = []
    
    var availableDecks: [String] = []
    var availableNoteTypes: [AnkiNoteType] = []
    
    var allowDupes: Bool = false
    var disableShowNotes: Bool = false
    var compactGlossaries: Bool = false
    var embedMedia: Bool = false
    
    var selectedGlossaryFallback: String = ""
    var showAllHandlebars: Bool = false
    
    var errorMessage: String?
    
    var savedWords: Set<String> = []
    
    var isConnected: Bool {
        if useAnkiConnect {
            isAnkiConnectReachable
        }
        else {
            !availableDecks.isEmpty
        }
    }
    
    var needsAudio: Bool {
        cardFormats.contains { $0.fieldMappings.values.contains(Handlebars.audio.rawValue) }
    }
    
    var needsSasayakiAudio: Bool {
        cardFormats.contains { $0.fieldMappings.values.contains(Handlebars.sasayakiAudio.rawValue) }
    }
    
    var validFormatFlags: [Bool] {
        cardFormats.map { format in
            guard let noteTypeName = format.selectedNoteType,
                  let noteType = availableNoteTypes.first(where: { $0.name == noteTypeName }),
                  let firstField = noteType.fields.first else {
                return false
            }
            return format.fieldMappings[firstField] != nil
        }
    }
    
    var useAnkiConnect: Bool = false
    var ankiConnectConfig: AnkiConnectConfig? = AnkiConnectConfig(url: nil, timeout: 10, duplicateScope: .collection, forceSync: false)
    var isAnkiConnectReachable = false
    
    static let wordAddedNotification = Notification.Name("hoshiWordAdded")
    
    private static let scheme = "hoshi://"
    private static let fetchCallback = scheme + "ankiFetch"
    private static let successCallback = scheme + "ankiSuccess"
    
    private static let pasteboardType = "net.ankimobile.json"
    private static let infoCallback = "anki://x-callback-url/infoForAdding"
    private static let addNoteCallback = "anki://x-callback-url/addnote"
    private static let searchCallback = "anki://x-callback-url/search"
    
    private static let ankiConfig = "anki_config.json"
    private static let ankiWords = "anki_words.json"
    
    private static let handlebarRegex = /\{.*?\}/
    
    private init() {
        load()
        loadWords()
        if ankiConnectConfig?.url != nil {
            Task { await pingAnkiConnect() }
        }
    }
    
    func requestInfo() {
        var urlComponents = URLComponents(string: Self.infoCallback)
        urlComponents?.queryItems = [
            URLQueryItem(name: "x-success", value: Self.fetchCallback)
        ]
        
        if let url = urlComponents?.url {
            UIApplication.shared.open(url)
        }
    }
    
    func pingAnkiConnect() async {
        do {
            _ = try await ankiConnectRequest(action: "version")
            isAnkiConnectReachable = true
            save()
        } catch {
            isAnkiConnectReachable = false
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
            errorMessage = String(localized: "No data received from Anki. Please try again.")
            return
        }
        UIPasteboard.general.setData(Data(), forPasteboardType: Self.pasteboardType)
        
        guard let response = try? JSONDecoder().decode(AnkiResponse.self, from: data) else {
            let rawString = String(data: data, encoding: .utf8) ?? "Unable to read data"
            errorMessage = String(localized: "Failed to decode Anki response:\n\n\(rawString)")
            return
        }
        availableDecks = response.decks.map(\.name)
        availableNoteTypes = response.notetypes.map { AnkiNoteType(name: $0.name, fields: $0.fields.map(\.name)) }
        
        resetCardFormats()
        save()
    }
    
    func fetchAnkiConnect() async {
        do {
            guard let decks = try await ankiConnectRequest(action: "deckNames") as? [String],
                  let models = try await ankiConnectRequest(action: "modelNames") as? [String] else {
                return
            }
            
            var noteTypes: [AnkiNoteType] = []
            for model in models {
                if let fields = try await ankiConnectRequest(action: "modelFieldNames", params: ["modelName": model]) as? [String] {
                    noteTypes.append(AnkiNoteType(name: model, fields: fields))
                }
            }
            
            availableDecks = decks
            availableNoteTypes = noteTypes
            
            resetCardFormats()
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addNote(content: [String: String], context: MiningContext, formatId: UUID) async -> Bool {
        guard let format = cardFormats.first(where: { $0.id == formatId }),
              let deck = format.selectedDeck,
              let noteType = format.selectedNoteType else {
            return false
        }
        
        if useAnkiConnect {
            return await addNoteAnkiConnect(content: content, context: context, deck: deck, noteType: noteType, format: format)
        }
        
        let singleGlossaries: [String: String]
        if let singleGlossariesJson = content["singleGlossaries"],
           let singleGlossariesData = singleGlossariesJson.data(using: .utf8),
           let singleGlossariesParsed = try? JSONDecoder().decode([String: String].self, from: singleGlossariesData) {
            singleGlossaries = singleGlossariesParsed
        } else {
            singleGlossaries = [:]
        }
        
        var urlComponents = URLComponents(string: Self.addNoteCallback)
        var queryItems = [
            URLQueryItem(name: "deck", value: deck),
            URLQueryItem(name: "type", value: noteType)
        ]
        
        var dictionaryMedia: [String: String] = [:]
        if embedMedia {
            if let json = content["dictionaryMedia"] {
                let dictMedia = (try? JSONDecoder().decode([DictionaryMedia].self, from: Data(json.utf8))) ?? []
                for media in dictMedia {
                    let mediaData = LookupEngine.shared.getMediaFile(dictName: media.dictionary, mediaPath: media.path)
                    let mimeType = mimeType(for: media.path)
                    dictionaryMedia[media.filename] = "data:\(mimeType);base64,\(mediaData.base64EncodedString())"
                }
            }
        }
        
        for (field, fieldContent) in format.fieldMappings {
            var value = fieldContent.replacing(Self.handlebarRegex) { match in
                return handlebarToValue(handlebar: String(match.0), context: context, content: content, singleGlossaries: singleGlossaries)
            }
            if !value.isEmpty {
                if embedMedia {
                    for (filename, data) in dictionaryMedia {
                        value = value.replacingOccurrences(of: filename, with: data)
                    }
                }
                queryItems.append(URLQueryItem(name: "fld" + field, value: value))
            }
        }
        
        if !format.tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: format.tags))
        }
        
        if allowDupes {
            queryItems.append(URLQueryItem(name: "dupes", value: "1"))
        }
        
        let word = firstFieldWord(format: format) {
            handlebarToValue(handlebar: $0, context: context, content: content, singleGlossaries: singleGlossaries)
        } ?? ""
        let successURL = Self.successCallback + "?expression=" + (word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)
        queryItems.append(URLQueryItem(name: "x-success", value: successURL))
        
        urlComponents?.queryItems = queryItems
        
        if let url = urlComponents?.url {
            await UIApplication.shared.open(url)
        }
        
        return false
    }
    
    private func addNoteAnkiConnect(content: [String: String], context: MiningContext, deck: String, noteType: String, format: AnkiCardFormat) async -> Bool {
        let singleGlossaries: [String: String]
        if let singleGlossariesJson = content["singleGlossaries"],
           let singleGlossariesData = singleGlossariesJson.data(using: .utf8),
           let singleGlossariesParsed = try? JSONDecoder().decode([String: String].self, from: singleGlossariesData) {
            singleGlossaries = singleGlossariesParsed
        } else {
            singleGlossaries = [:]
        }
        
        var fields: [String: String] = [:]
        var audioFields: [String] = []
        var sasayakiAudioFields: [String] = []
        var pictureFields: [String] = []
        
        for (field, fieldContent) in format.fieldMappings {
            if fieldContent == Handlebars.audio.rawValue {
                audioFields.append(field)
            } else if fieldContent == Handlebars.sasayakiAudio.rawValue {
                sasayakiAudioFields.append(field)
            } else if fieldContent == Handlebars.bookCover.rawValue {
                pictureFields.append(field)
            } else {
                fields[field] = fieldContent.replacing(Self.handlebarRegex) { match in
                    handlebarToValue(handlebar: String(match.0), context: context, content: content, singleGlossaries: singleGlossaries)
                }
            }
        }
        
        var options = duplicateOptions(deck: deck)
        options["allowDuplicate"] = allowDupes
        var note: [String: Any] = [
            "deckName": deck,
            "modelName": noteType,
            "fields": fields,
            "options": options
        ]
        
        var audio: [[String: Any]] = []
        if !audioFields.isEmpty, let audioURL = content["audio"],
           let url = URL(string: audioURL),
           let audioData = try? await URLSession.shared.data(from: url).0 {
            audio.append([
                "data": audioData.base64EncodedString(),
                "filename": "hoshi_audio_\(audioData.sha1).mp3",
                "fields": audioFields
            ])
        }
        if !sasayakiAudioFields.isEmpty, let audioData = context.sasayakiAudioData {
            audio.append([
                "data": audioData.base64EncodedString(),
                "filename": "hoshi_sasayaki_\(audioData.sha1).mp3",
                "fields": sasayakiAudioFields
            ])
        }
        if !audio.isEmpty {
            note["audio"] = audio
        }
        
        if !pictureFields.isEmpty, let coverURL = context.coverURL,
           let coverData = try? Data(contentsOf: coverURL) {
            note["picture"] = [[
                "data": coverData.base64EncodedString(),
                "filename": "hoshi_cover_\(coverData.sha1).\(coverURL.pathExtension)",
                "fields": pictureFields
            ]]
        }
        
        if let json = content["dictionaryMedia"],
           let dictionaryMedia = try? JSONDecoder().decode([DictionaryMedia].self, from: Data(json.utf8)) {
            for media in dictionaryMedia {
                let mediaData = LookupEngine.shared.getMediaFile(dictName: media.dictionary, mediaPath: media.path)
                let ext = media.path.split(separator: ".").last!
                let filename = "hoshi_dict_\(mediaData.sha1).\(ext)"
                fields = fields.mapValues { $0.replacingOccurrences(of: media.filename, with: filename) }
                _ = try? await ankiConnectRequest(action: "storeMediaFile", params: [
                    "filename": filename,
                    "data": mediaData.base64EncodedString()
                ])
            }
            note["fields"] = fields
        }
        
        let tagList = format.tags.split(separator: " ").map(String.init)
        if !tagList.isEmpty {
            note["tags"] = tagList
        }
        
        do {
            _ = try await ankiConnectRequest(action: "addNote", params: ["note": note])
            addWord(firstFieldWord(format: format) {
                handlebarToValue(handlebar: $0, context: context, content: content, singleGlossaries: singleGlossaries)
            } ?? "")
            LocalFileServer.shared.clearMedia()
            
            if ankiConnectConfig?.forceSync == true {
                await syncAnkiConnect()
            }
            return true
        } catch {
            return false
        }
    }
    
    func checkDuplicates(fields: [String: String]) async -> [Bool] {
        let words = cardFormats.map { format in
            firstFieldWord(format: format) {
                fields[$0]
            }
        }
        
        var results = words.map { word in
            word.map { savedWords.contains($0) } ?? false
        }
        
        guard useAnkiConnect else {
            return results
        }
        
        var notes: [[String: Any]] = []
        var noteIndices: [Int] = []
        for (index, word) in words.enumerated() {
            guard let word, !word.isEmpty else {
                continue
            }
            
            let format = cardFormats[index]
            guard let noteTypeName = format.selectedNoteType,
                  let noteType = availableNoteTypes.first(where: { $0.name == noteTypeName }),
                  let firstField = noteType.fields.first,
                  let deck = format.selectedDeck else {
                continue
            }
            notes.append([
                "deckName": deck,
                "modelName": noteTypeName,
                "fields": [firstField: word],
                "options": duplicateOptions(deck: deck)
            ])
            noteIndices.append(index)
        }
        
        guard !notes.isEmpty else {
            return results
        }
        
        do {
            if let noteResults = try await ankiConnectRequest(action: "canAddNotesWithErrorDetail", params: ["notes": notes]) as? [[String: Any]] {
                for (index, noteResult) in zip(noteIndices, noteResults) {
                    guard let canAdd = noteResult["canAdd"] as? Bool else {
                        continue
                    }
                    results[index] = !canAdd
                    if !canAdd, let word = words[index] {
                        savedWords.insert(word)
                    }
                }
            }
        } catch {}
        
        return results
    }
    
    func showNotes(fields: [String: String], formatIndex: Int) async {
        guard cardFormats.indices.contains(formatIndex) else {
            return
        }
        let format = cardFormats[formatIndex]
        guard let noteTypeName = format.selectedNoteType,
              let noteType = availableNoteTypes.first(where: { $0.name == noteTypeName }),
              let firstField = noteType.fields.first,
              let deck = format.selectedDeck,
              let word = firstFieldWord(format: format, resolve: { fields[$0] }),
              !word.isEmpty else {
            return
        }
        
        let escapedWord = word.replacingOccurrences(of: "\"", with: "")
        
        if useAnkiConnect {
            var search: [String] = []
            search.append("\"\(firstField):\(escapedWord)\"")
            if ankiConnectConfig?.checkAllModels != true {
                search.append("\"note:\(noteTypeName)\"")
            }
            switch ankiConnectConfig?.duplicateScope ?? .collection {
            case .collection:
                break
            case .deck:
                search.append("\"deck:\(deck)\"")
            case .deckroot:
                let rootDeck = deck.split(separator: "::", maxSplits: 1).first.map(String.init) ?? deck
                search.append("\"deck:\(rootDeck)\"")
            }
            _ = try? await ankiConnectRequest(action: "guiBrowse", params: ["query": search.joined(separator: " ")])
        } else {
            var urlComponents = URLComponents(string: Self.searchCallback)
            urlComponents?.queryItems = [
                URLQueryItem(name: "query", value: "\(firstField):\"\(escapedWord)\"")
            ]
            
            if let url = urlComponents?.url {
                await UIApplication.shared.open(url)
            }
        }
    }
    
    func syncAnkiConnect() async  {
        do {
            _ = try await ankiConnectRequest(action: "sync")
        } catch {}
    }
    
    func updateHandlebar(old: String, new: String) {
        guard old != new else { return }
        let prefix = Handlebars.singleGlossaryPrefix
        for index in cardFormats.indices {
            cardFormats[index].fieldMappings = cardFormats[index].fieldMappings.mapValues {
                $0.replacingOccurrences(of: "\(prefix)\(old)}", with: "\(prefix)\(new)}")
                    .replacingOccurrences(of: "\(prefix)\(old)-brief}", with: "\(prefix)\(new)-brief}")
                    .replacingOccurrences(of: "\(prefix)\(old)-no-dictionary}", with: "\(prefix)\(new)-no-dictionary}")
            }
        }
        
        save()
    }
    
    func save() {
        let data = AnkiConfig(
            cardFormats: cardFormats,
            allowDupes: allowDupes,
            disableShowNotes: disableShowNotes,
            compactGlossaries: compactGlossaries,
            embedMedia: embedMedia,
            availableDecks: availableDecks,
            availableNoteTypes: availableNoteTypes,
            useAnkiConnect: useAnkiConnect,
            ankiConnectConfig: ankiConnectConfig,
            selectedGlossaryFallback: selectedGlossaryFallback,
            showAllHandlebars: showAllHandlebars
        )
        
        guard let directory = try? BookStorage.getAppDirectory() else {
            return
        }
        try? BookStorage.save(data, inside: directory, as: Self.ankiConfig)
    }
    
    func autofillFieldMappings(formatId: UUID) {
        guard let index = cardFormats.firstIndex(where: { $0.id == formatId }),
              let noteTypeName = cardFormats[index].selectedNoteType,
              let template = AnkiFieldTemplate.templates.first(where: { $0.noteType == noteTypeName }),
              let noteType = availableNoteTypes.first(where: { $0.name == noteTypeName }),
              !noteType.fields.contains(where: { cardFormats[index].fieldMappings[$0] != nil }) else {
            return
        }
        for field in noteType.fields {
            if let mapping = template.mappings[field] {
                cardFormats[index].fieldMappings[field] = mapping
            }
        }
    }
    
    func addCardFormat() {
        let icon = AnkiCardFormat.icons[0]
        let format = AnkiCardFormat(
            id: UUID(),
            name: "Format \(cardFormats.count + 1)",
            icon: icon,
            selectedDeck: availableDecks.first { $0.caseInsensitiveCompare("Default") != .orderedSame } ?? availableDecks.first,
            selectedNoteType: availableNoteTypes.first?.name,
            fieldMappings: [:],
            tags: ""
        )
        
        cardFormats.append(format)
        autofillFieldMappings(formatId: format.id)
        save()
    }
    
    func deleteCardFormat(id: UUID) {
        cardFormats.removeAll { $0.id == id }
        save()
    }
    
    private func duplicateOptions(deck: String) -> [String: Any] {
        var options: [String: Any] = [:]
        if ankiConnectConfig?.duplicateScope == .collection {
            options["duplicateScope"] = "collection"
        } else {
            options["duplicateScope"] = "deck"
            if ankiConnectConfig?.duplicateScope == .deckroot {
                let rootDeck = deck.split(separator: "::", maxSplits: 1).first.map(String.init) ?? deck
                options["duplicateScopeOptions"] = [
                    "deckName": rootDeck,
                    "checkChildren": true
                ]
            }
        }
        if ankiConnectConfig?.checkAllModels == true {
            var duplicateScopeOptions = options["duplicateScopeOptions"] as? [String: Any] ?? [:]
            duplicateScopeOptions["checkAllModels"] = true
            options["duplicateScopeOptions"] = duplicateScopeOptions
        }
        return options
    }
    
    private func resetCardFormats() {
        if cardFormats.isEmpty {
            cardFormats = [AnkiCardFormat(
                id: UUID(),
                name: "Default",
                icon: AnkiCardFormat.icons[0],
                selectedDeck: nil,
                selectedNoteType: nil,
                fieldMappings: [:],
                tags: ""
            )]
        }
        
        let deck = availableDecks.first { $0.caseInsensitiveCompare("Default") != .orderedSame } ?? availableDecks.first
        for index in cardFormats.indices {
            cardFormats[index].selectedDeck = deck
            cardFormats[index].selectedNoteType = availableNoteTypes.first?.name
            cardFormats[index].fieldMappings.removeAll()
            autofillFieldMappings(formatId: cardFormats[index].id)
        }
    }
    
    private func firstFieldWord(format: AnkiCardFormat, resolve: (String) -> String?) -> String? {
        guard let noteTypeName = format.selectedNoteType,
              let noteType = availableNoteTypes.first(where: { $0.name == noteTypeName }),
              let firstField = noteType.fields.first,
              let handlebar = format.fieldMappings[firstField] else {
            return nil
        }
        return resolve(handlebar)
    }
    
    private func firstGlossary(ofCategory category: DictionaryCategory? = nil, singleGlossaries: [String: String]) -> String {
        for dict in DictionaryManager.shared.termDictionaries {
            guard dict.category != .exclude, category == nil || dict.category == category, let glossary = singleGlossaries[dict.index.title] else {
                continue
            }
            return glossary
        }
        return ""
    }
    
    private static let selectedGlossaryFallbackHandlebars: Set<String> = [
        Handlebars.selectedGlossary.rawValue,
        Handlebars.selectedGlossaryBrief.rawValue,
        Handlebars.selectedGlossaryNoDictionary.rawValue,
    ]
    
    private func resolveSelectedGlossaryFallback(context: MiningContext, content: [String: String], singleGlossaries: [String: String]) -> String {
        guard !Self.selectedGlossaryFallbackHandlebars.contains(selectedGlossaryFallback) else { return "" }
        return handlebarToValue(handlebar: selectedGlossaryFallback, context: context, content: content, singleGlossaries: singleGlossaries)
    }
    
    private func handlebarToValue(handlebar: String, context: MiningContext, content: [String: String], singleGlossaries: [String: String]) -> String {
        if handlebar.hasPrefix(Handlebars.singleGlossaryPrefix) {
            let dictName = String(handlebar.dropFirst(Handlebars.singleGlossaryPrefix.count).dropLast())
            if dictName.hasSuffix("-brief") {
                let baseDictName = String(dictName.dropLast("-brief".count))
                return Self.stripGlossaryHeaders(singleGlossaries[baseDictName] ?? "")
            }
            if dictName.hasSuffix("-no-dictionary") {
                let baseDictName = String(dictName.dropLast("-no-dictionary".count))
                return Self.stripDictionaryName(singleGlossaries[baseDictName] ?? "")
            }
            return singleGlossaries[dictName] ?? ""
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
            case .glossaryBrief:
                return Self.stripGlossaryHeaders(content["glossary"] ?? "")
            case .glossaryNoDictionary:
                return Self.stripDictionaryName(content["glossary"] ?? "")
            case .glossaryFirst:
                return firstGlossary(singleGlossaries: singleGlossaries)
            case .glossaryFirstBrief:
                return Self.stripGlossaryHeaders(firstGlossary(singleGlossaries: singleGlossaries))
            case .glossaryFirstNoDictionary:
                return Self.stripDictionaryName(firstGlossary(singleGlossaries: singleGlossaries))
            case .selectedGlossary:
                return singleGlossaries[content["selectedDictionary"] ?? ""] ?? resolveSelectedGlossaryFallback(context: context, content: content, singleGlossaries: singleGlossaries)
            case .selectedGlossaryBrief:
                let selected = singleGlossaries[content["selectedDictionary"] ?? ""] ?? resolveSelectedGlossaryFallback(context: context, content: content, singleGlossaries: singleGlossaries)
                return Self.stripGlossaryHeaders(selected)
            case .selectedGlossaryNoDictionary:
                let selected = singleGlossaries[content["selectedDictionary"] ?? ""] ?? resolveSelectedGlossaryFallback(context: context, content: content, singleGlossaries: singleGlossaries)
                return Self.stripDictionaryName(selected)
            case .monolingualDefinition:
                return firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries)
            case .monolingualDefinitionBrief:
                return Self.stripGlossaryHeaders(firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries))
            case .monolingualDefinitionNoDictionary:
                return Self.stripDictionaryName(firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries))
            case .bilingualDefinition:
                return firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries)
            case .bilingualDefinitionBrief:
                return Self.stripGlossaryHeaders(firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries))
            case .bilingualDefinitionNoDictionary:
                return Self.stripDictionaryName(firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries))
            case .monolingualDefinitionFallback:
                let primary = firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries)
                return primary.isEmpty ? firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries) : primary
            case .monolingualDefinitionFallbackBrief:
                let primary = firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries)
                return Self.stripGlossaryHeaders(primary.isEmpty ? firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries) : primary)
            case .monolingualDefinitionFallbackNoDictionary:
                let primary = firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries)
                return Self.stripDictionaryName(primary.isEmpty ? firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries) : primary)
            case .bilingualDefinitionFallback:
                let primary = firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries)
                return primary.isEmpty ? firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries) : primary
            case .bilingualDefinitionFallbackBrief:
                let primary = firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries)
                return Self.stripGlossaryHeaders(primary.isEmpty ? firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries) : primary)
            case .bilingualDefinitionFallbackNoDictionary:
                let primary = firstGlossary(ofCategory: .bilingual, singleGlossaries: singleGlossaries)
                return Self.stripDictionaryName(primary.isEmpty ? firstGlossary(ofCategory: .monolingual, singleGlossaries: singleGlossaries) : primary)
            case .frequencies:
                return content["frequenciesHtml"] ?? ""
            case .frequencyHarmonicRank:
                return content["freqHarmonicRank"] ?? ""
            case .pitchPositions:
                return content["pitchPositions"] ?? ""
            case .pitchCategories:
                return content["pitchCategories"] ?? ""
            case .pitchAccentGraphs:
                return content["pitchAccentGraphs"] ?? ""
            case .pitchAccentGraphsFirst:
                return Self.firstPitchAccentGraph(content["pitchAccentGraphs"] ?? "")
            case .sentence:
                let parts = Self.clozeParts(sentence: context.sentence, matched: content["matched"] ?? "", offset: context.clozeOffset)
                return "\(parts.prefix)<b>\(parts.body)</b>\(parts.suffix)"
            case .clozePrefix:
                return Self.clozeParts(sentence: context.sentence, matched: content["matched"] ?? "", offset: context.clozeOffset).prefix
            case .clozeBody:
                return Self.clozeParts(sentence: context.sentence, matched: content["matched"] ?? "", offset: context.clozeOffset).body
            case .clozeSuffix:
                return Self.clozeParts(sentence: context.sentence, matched: content["matched"] ?? "", offset: context.clozeOffset).suffix
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
            case .sasayakiAudio:
                guard let data = context.sasayakiAudioData else { return "" }
                LocalFileServer.shared.setSasayakiAudio(data)
                return "http://localhost:\(LocalFileServer.port)/sasayaki/audio.mp3"
            }
        }
        return ""
    }
    
    private func load() {
        guard let directory = try? BookStorage.getAppDirectory() else {
            return
        }
        let url = directory.appendingPathComponent(Self.ankiConfig)
        
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AnkiConfig.self, from: data) else {
            return
        }
        
        allowDupes = config.allowDupes
        disableShowNotes = config.disableShowNotes ?? (UserDefaults.standard.object(forKey: "disableShowNotes") as? Bool ?? false)
        compactGlossaries = config.compactGlossaries ?? false
        embedMedia = config.embedMedia ?? false
        availableDecks = config.availableDecks
        availableNoteTypes = config.availableNoteTypes
        useAnkiConnect = config.useAnkiConnect ?? false
        ankiConnectConfig = config.ankiConnectConfig ?? AnkiConnectConfig(url: nil, timeout: 10, duplicateScope: .collection, forceSync: false)
        selectedGlossaryFallback = config.selectedGlossaryFallback ?? ""
        showAllHandlebars = config.showAllHandlebars ?? false
        
        cardFormats = config.cardFormats ?? []
        if cardFormats.isEmpty, let legacy = try? JSONDecoder().decode(LegacyAnkiFields.self, from: data) {
            cardFormats = [AnkiCardFormat(
                id: UUID(),
                name: "Default",
                icon: AnkiCardFormat.icons[0],
                selectedDeck: legacy.selectedDeck,
                selectedNoteType: legacy.selectedNoteType,
                fieldMappings: legacy.fieldMappings ?? [:],
                tags: legacy.tags ?? ""
            )]
        }
    }
    
    func importAnkiBackup(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try FileManager.default.unzipItem(at: url, to: tempDir)
        
        let collection = try Data(contentsOf: tempDir.appendingPathComponent("collection.anki21b"))
        let sqliteData = try Self.decompressZstd(collection)
        
        let dbFile = tempDir.appendingPathComponent("collection.db")
        try sqliteData.write(to: dbFile)
        
        savedWords = try Self.extractExpressionField(from: dbFile)
        try Self.saveWords(savedWords)
    }
    
    private func loadWords() {
        guard let url = try? BookStorage.getAppDirectory().appendingPathComponent(AnkiManager.ankiWords),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return
        }
        savedWords = words
    }
    
    func addWord(_ word: String) {
        savedWords.insert(word)
        try? Self.saveWords(savedWords)
        NotificationCenter.default.post(name: Self.wordAddedNotification, object: nil)
    }
    
    private static func stripGlossaryHeaders(_ html: String) -> String {
        html.replacing(#/(<li data-dictionary="[^"]*">)<i>[^<]*</i> /#) { $0.output.1 }
    }
    
    private static func stripDictionaryName(_ html: String) -> String {
        html.replacing(#/<li data-dictionary="(?<dict>[^"]+)"><i>(?<label>[^<]*)</i> /#) { match in
            let dict = String(match.dict)
            let label = String(match.label)
            let stripped = label.replacingOccurrences(of: ", \(dict))", with: ")")
            if stripped == "(\(dict))" {
                return "<li data-dictionary=\"\(dict)\">"
            }
            return "<li data-dictionary=\"\(dict)\"><i>\(stripped)</i> "
        }
    }
    
    private static func firstPitchAccentGraph(_ html: String) -> String {
        guard let match = html.firstMatch(of: #/<svg\b.*?</svg>/#) else { return "" }
        return String(match.output)
    }
    
    private static func clozeParts(sentence: String, matched: String, offset: Int?) -> (prefix: String, body: String, suffix: String) {
        let range = offset.flatMap { Range(NSRange(location: $0, length: matched.utf16.count), in: sentence) } ?? sentence.range(of: matched)
        guard let range else { return (sentence, "", "") }
        return (String(sentence[..<range.lowerBound]), String(sentence[range]), String(sentence[range.upperBound...]))
    }
    
    private static func saveWords(_ words: Set<String>) throws {
        let file = try BookStorage.getAppDirectory().appendingPathComponent(ankiWords)
        try JSONEncoder().encode(words).write(to: file)
    }
    
    private static func decompressZstd(_ data: Data) throws -> Data {
        let dctx = ZSTD_createDCtx()!
        defer { ZSTD_freeDCtx(dctx) }
        
        var result = Data()
        let blockSize = ZSTD_DStreamOutSize()
        
        try data.withUnsafeBytes { src in
            var input = ZSTD_inBuffer(src: src.baseAddress, size: src.count, pos: 0)
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
            defer { dst.deallocate() }
            
            while input.pos < input.size {
                var outBuf = ZSTD_outBuffer(dst: dst, size: blockSize, pos: 0)
                let ret = ZSTD_decompressStream(dctx, &outBuf, &input)
                guard ZSTD_isError(ret) == 0 else {
                    throw ColpkgError.zstd
                }
                result.append(dst, count: outBuf.pos)
            }
        }
        return result
    }
    
    private static func extractExpressionField(from url: URL) throws -> Set<String> {
        var db: OpaquePointer?
        sqlite3_open_v2(url.path(percentEncoded: false), &db, SQLITE_OPEN_READWRITE, nil)
        sqlite3_exec(db, "PRAGMA journal_mode=OFF", nil, nil, nil)
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT flds FROM notes", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        
        var words = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let row = sqlite3_column_text(stmt, 0) else {
                continue
            }
            let word = String(cString: row).prefix(while: { $0 != "\u{1f}" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty {
                words.insert(word)
            }
        }
        return words
    }
    
    private func ankiConnectRequest(action: String, params: [String: Any]? = nil) async throws -> Any? {
        guard let urlString = ankiConnectConfig?.url,
              let url = URL(string: urlString) else {
            throw AnkiConnectError.invalidUrl
        }
        
        var body: [String: Any] = ["action": action, "version": 6]
        if let params {
            body["params"] = params
        }
        if let apiKey = ankiConnectConfig?.apiKey, !apiKey.isEmpty {
            body["key"] = apiKey
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        if let error = json["error"] as? String {
            throw AnkiConnectError.ankiconnectError(error)
        }
        
        return json["result"]
    }
    
    private func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
    
    enum AnkiConnectError: LocalizedError {
        case invalidUrl
        case ankiconnectError(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidUrl: String(localized: "Invalid URL specified")
            case .ankiconnectError(let error): error
            }
        }
    }
    
    enum ColpkgError: LocalizedError {
        case zstd
        
        var errorDescription: String? {
            switch self {
            case .zstd: String(localized: "Failed to decompress database")
            }
        }
    }
}
