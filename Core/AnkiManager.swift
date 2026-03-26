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
    
    var useAnkiConnect: Bool = false
    var ankiConnectConfig: AnkiConnectConfig?
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
            Task { await checkConnection() }
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
    
    func checkConnection() async {
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
            if !value.isEmpty {
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
            UIApplication.shared.open(url)
        }
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
            fieldMappings: fieldMappings,
            tags: tags,
            availableDecks: availableDecks,
            availableNoteTypes: availableNoteTypes,
            useAnkiConnect: useAnkiConnect,
            ankiConnectConfig: ankiConnectConfig
        )
        
        guard let directory = try? BookStorage.getDocumentsDirectory() else {
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
            }
        }
        return ""
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
        compactGlossaries = config.compactGlossaries ?? false
        fieldMappings = config.fieldMappings
        tags = config.tags ?? ""
        availableDecks = config.availableDecks
        availableNoteTypes = config.availableNoteTypes
        useAnkiConnect = config.useAnkiConnect ?? false
        ankiConnectConfig = config.ankiConnectConfig ?? AnkiConnectConfig(url: nil, timeout: 10, duplicateScope: .collection, forceSync: false)
    }
    
    func importColpkg(from url: URL) throws {
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
        guard let url = try? BookStorage.getDocumentsDirectory().appendingPathComponent(AnkiManager.ankiWords),
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
        let file = try BookStorage.getDocumentsDirectory().appendingPathComponent(ankiWords)
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
