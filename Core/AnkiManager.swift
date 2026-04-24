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
import ZipArchive

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
    var compactGlossaries: Bool = false
    var embedMedia: Bool = false
    
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
        fieldMappings.values.contains(Handlebars.audio.rawValue)
    }
    
    var needsSasayakiAudio: Bool {
        fieldMappings.values.contains(Handlebars.sasayakiAudio.rawValue)
    }
    
    var useAnkiConnect: Bool = false
    var ankiConnectConfig: AnkiConnectConfig? = AnkiConnectConfig(url: nil, timeout: 10, duplicateScope: .collection, forceSync: false)
    var isAnkiConnectReachable = false
    
    private static let scheme = "hoshi://"
    private static let fetchCallback = scheme + "ankiFetch"
    private static let successCallback = scheme + "ankiSuccess"
    
    private static let pasteboardType = "net.ankimobile.json"
    private static let infoCallback = "anki://x-callback-url/infoForAdding"
    private static let addNoteCallback = "anki://x-callback-url/addnote"
    
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
            
            if let deck = decks.first(where: { $0.caseInsensitiveCompare("Default") != .orderedSame }) {
                selectedDeck = deck
            } else {
                selectedDeck = decks.first
            }
            
            if let noteType = noteTypes.first {
                selectedNoteType = noteType.name
                fieldMappings.removeAll()
            } else {
                selectedNoteType = nil
                fieldMappings.removeAll()
            }
            
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addNote(content: [String: String], context: MiningContext) async -> Bool {
        guard let deck = selectedDeck,
              let noteType = selectedNoteType else {
            return false
        }
        
        if useAnkiConnect {
            return await addNoteAnkiConnect(content: content, context: context, deck: deck, noteType: noteType)
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
        
        for (field, fieldContent) in fieldMappings {
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
        
        if !tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: tags))
        }
        
        if allowDupes {
            queryItems.append(URLQueryItem(name: "dupes", value: "1"))
        }
        
        let expression = content["expression"] ?? ""
        let successURL = Self.successCallback + "?expression=" + (expression.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? expression)
        queryItems.append(URLQueryItem(name: "x-success", value: successURL))
        
        urlComponents?.queryItems = queryItems
        
        if let url = urlComponents?.url {
            await UIApplication.shared.open(url)
        }
        
        return false
    }
    
    private func addNoteAnkiConnect(content: [String: String], context: MiningContext, deck: String, noteType: String) async -> Bool {
        let singleGlossaries: [String: String]
        if let json = content["singleGlossaries"],
           let data = json.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            singleGlossaries = parsed
        } else {
            singleGlossaries = [:]
        }
        
        var fields: [String: String] = [:]
        var audioFields: [String] = []
        var sasayakiAudioFields: [String] = []
        var pictureFields: [String] = []
        
        for (field, fieldContent) in fieldMappings {
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
        
        var options: [String: Any] = ["allowDuplicate": allowDupes]
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
                "filename": "hoshi_sasayaki_\(audioData.sha1).m4a",
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
        
        let tagList = tags.split(separator: " ").map(String.init)
        if !tagList.isEmpty {
            note["tags"] = tagList
        }
        
        do {
            _ = try await ankiConnectRequest(action: "addNote", params: ["note": note])
            addWord(content["expression"] ?? "")
            LocalFileServer.shared.clearMedia()
            
            if ankiConnectConfig?.forceSync == true {
                await syncAnkiConnect()
            }
            return true
        } catch {
            return false
        }
    }
    
    func checkDuplicate(word: String) async -> Bool {
        guard useAnkiConnect else {
            return savedWords.contains(word)
        }
        
        guard let noteTypeName = selectedNoteType,
              let noteType = availableNoteTypes.first(where: { $0.name == selectedNoteType }),
              let firstField = noteType.fields.first,
              let deck = selectedDeck else {
            return savedWords.contains(word)
        }
        
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
        let note: [String: Any] = [
            "deckName": deck,
            "modelName": noteTypeName,
            "fields": [firstField: word],
            "options": options
        ]
        
        do {
            let result = try await ankiConnectRequest(action: "canAddNotesWithErrorDetail", params: ["notes": [note]])
            if let results = result as? [[String: Any]],
               let first = results.first,
               let canAdd = first["canAdd"] as? Bool {
                if !canAdd { savedWords.insert(word) }
                return !canAdd
            }
        } catch {}
        
        return savedWords.contains(word)
    }
    
    func syncAnkiConnect() async  {
        do {
            _ = try await ankiConnectRequest(action: "sync")
        } catch {}
    }
    
    func updateHandlebar(old: String, new: String) {
        guard old != new else { return }
        fieldMappings = fieldMappings.mapValues {
            $0.replacingOccurrences(of: "\(Handlebars.singleGlossaryPrefix)\(old)}", with: "\(Handlebars.singleGlossaryPrefix)\(new)}")
        }
        
        save()
    }
    
    func save() {
        let data = AnkiConfig(
            selectedDeck: selectedDeck,
            selectedNoteType: selectedNoteType,
            allowDupes: allowDupes,
            compactGlossaries: compactGlossaries,
            embedMedia: embedMedia,
            fieldMappings: fieldMappings,
            tags: tags,
            availableDecks: availableDecks,
            availableNoteTypes: availableNoteTypes,
            useAnkiConnect: useAnkiConnect,
            ankiConnectConfig: ankiConnectConfig
        )
        
        guard let directory = try? BookStorage.getAppDirectory() else {
            return
        }
        try? BookStorage.save(data, inside: directory, as: Self.ankiConfig)
    }
    
    private func handlebarToValue(handlebar: String, context: MiningContext, content: [String: String], singleGlossaries: [String: String]) -> String {
        if handlebar.hasPrefix(Handlebars.singleGlossaryPrefix) {
            let dictName = String(handlebar.dropFirst(Handlebars.singleGlossaryPrefix.count).dropLast())
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
            case .sasayakiAudio:
                guard let data = context.sasayakiAudioData else { return "" }
                LocalFileServer.shared.setSasayakiAudio(data)
                return "http://localhost:\(LocalFileServer.port)/sasayaki/audio.m4a"
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
        
        selectedDeck = config.selectedDeck
        selectedNoteType = config.selectedNoteType
        allowDupes = config.allowDupes
        compactGlossaries = config.compactGlossaries ?? false
        embedMedia = config.embedMedia ?? false
        fieldMappings = config.fieldMappings
        tags = config.tags ?? ""
        availableDecks = config.availableDecks
        availableNoteTypes = config.availableNoteTypes
        useAnkiConnect = config.useAnkiConnect ?? false
        ankiConnectConfig = config.ankiConnectConfig ?? AnkiConnectConfig(url: nil, timeout: 10, duplicateScope: .collection, forceSync: false)
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
        
        SSZipArchive.unzipFile(
            atPath: url.path(percentEncoded: false),
            toDestination: tempDir.path(percentEncoded: false)
        )
        
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
            case .invalidUrl: "Invalid URL specified"
            case .ankiconnectError(let error): error
            }
        }
    }
    
    enum ColpkgError: LocalizedError {
        case zstd
        
        var errorDescription: String? {
            switch self {
            case .zstd: "Failed to decompress database"
            }
        }
    }
}
