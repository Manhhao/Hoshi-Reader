//
//  LocalFileServer.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2022-2026 Ankiconnect Android.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Network
import SQLite3
import UIKit

@MainActor
class LocalFileServer {
    static let shared = LocalFileServer()
    
    static let port: UInt16 = 8765
    static let localAudioPath = "Audio/android.db"
    static let localAudioURL = "http://localhost:\(port)/localaudio/get/?term={term}&reading={reading}"
    
    private var listener: NWListener?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var coverData: Data?
    private var sasayakiAudioData: Data?
    private var localAudioEnabled = false
    
    private static let sourceDisplayNames = [
        "nhk16": "NHK16 %@",
        "daijisen": "Daijisen %@",
        "shinmeikai8": "SMK8 %@",
        "jpod": "JPod101",
        "jpod_alternate": "JPod101 Alt",
        "taas": "TAAS",
        "ozk5": "OZK5 %@",
        "forvo": "Forvo (%@)",
        "forvo_ext": "Forvo Ext",
        "forvo_ext2": "Forvo Ext2"
    ]
    private static let defaultSources = ["nhk16", "daijisen", "shinmeikai8", "jpod", "jpod_alternate", "taas", "ozk5", "forvo", "forvo_ext", "forvo_ext2"]
    private static let emptyAudioResponse = Data(#"{"type":"audioSourceList","audioSources":[]}"#.utf8)
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private init() {}
    
    private func katakanaToHiragana(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> UnicodeScalar in
            let value = scalar.value
            if value >= 0x30A1 && value <= 0x30F6 {
                return UnicodeScalar(value - 0x60)!
            }
            return scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }
    
    private func startServer() {
        guard listener == nil else {
            return
        }
        
        guard let newListener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                if self.listener == nil && (self.localAudioEnabled || self.coverData != nil || self.sasayakiAudioData != nil) {
                    self.startServer()
                }
            }
            return
        }
        newListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if case .failed = state {
                    self.listener = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if self.listener == nil && (self.localAudioEnabled || self.coverData != nil || self.sasayakiAudioData != nil) {
                            self.startServer()
                        }
                    }
                }
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        newListener.start(queue: .main)
        listener = newListener
    }
    
    private func stopServer() {
        // only stop if no more files are served
        guard coverData == nil && sasayakiAudioData == nil && !localAudioEnabled else {
            return
        }
        
        listener?.cancel()
        listener = nil
    }
    
    func startBackgroundTask() {
        guard listener != nil, backgroundTask == .invalid else {
            return
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            self.listener?.cancel()
            self.listener = nil
            self.endBackgroundTask()
        }
    }
    
    func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    
    func setAudioServer(enabled: Bool) {
        guard localAudioEnabled != enabled else {
            if enabled {
                startServer()
            }
            return
        }
        localAudioEnabled = enabled
        if enabled {
            listener?.cancel()
            listener = nil
            startServer()
        } else {
            stopServer()
        }
    }
    
    func setCover(file: URL) throws {
        coverData = try Data(contentsOf: file)
        startServer()
    }
    
    func setSasayakiAudio(_ data: Data) {
        sasayakiAudioData = data
        startServer()
    }
    
    func clearMedia() {
        coverData = nil
        sasayakiAudioData = nil
        stopServer()
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            Task { @MainActor in
                self?.respond(to: connection, requestData: data ?? Data())
            }
        }
    }
    
    private func respond(to connection: NWConnection, requestData: Data) {
        let request = parseRequest(from: requestData)
        let path = request.path
        
        if path.hasPrefix("/cover/cover.") {
            getCover(to: connection)
        } else if path == "/sasayaki/audio.mp3" {
            getSasayakiAudio(to: connection)
        } else if path == "/localaudio/get/" {
            getAudioSources(request, to: connection)
        } else if path.hasPrefix("/localaudio/") {
            getAudio(path: path, to: connection)
        } else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
        }
    }
    
    private func sendEmpty(to connection: NWConnection) {
        send(Self.emptyAudioResponse, status: "200 OK", contentType: "application/json", to: connection)
    }
    
    private func displayName(source: String, display: String) -> String {
        let template = Self.sourceDisplayNames[source] ?? "\(source) %@"
        return template.replacingOccurrences(of: "%@", with: display).trimmingCharacters(in: .whitespaces)
    }
    
    // https://github.com/KamWithK/AnkiconnectAndroid/blob/d79d7543df63894cac726f255780369cd0e6b177/app/src/main/java/com/kamwithk/ankiconnectandroid/routing/LocalAudioAPIRouting.java#L102
    private func getAudioSources(_ request: Request, to connection: NWConnection) {
        let term = request.query["term"] ?? ""
        let rawReading = request.query["reading"] ?? ""
        let reading = katakanaToHiragana(rawReading)
        let dbURL = try! BookStorage.getAppDirectory().appendingPathComponent(Self.localAudioPath)
        
        var db: OpaquePointer?
        sqlite3_open(dbURL.path(percentEncoded: false), &db)
        defer {
            sqlite3_close(db)
        }
        
        let sortOrder = "CASE source " + Self.defaultSources.indices.map { "WHEN ? THEN \($0) " }.joined() + "ELSE 999 END"
        let sql: String
        if reading.isEmpty {
            sql = """
                SELECT source, display, file, expression, reading, 0 AS rank FROM entries
                WHERE expression = ? AND file LIKE '%.mp3'
                ORDER BY \(sortOrder), reading;
                """
        } else {
            sql = """
                SELECT source, display, file, expression, reading, CASE
                    WHEN expression = ? AND (reading IS NULL OR reading = ?) THEN 0
                    WHEN reading = ? THEN 1
                    ELSE 2
                END AS rank FROM entries
                WHERE (expression = ? OR reading = ?) AND file LIKE '%.mp3'
                ORDER BY rank, \(sortOrder), reading;
                """
        }
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            sendEmpty(to: connection)
            return
        }
        defer {
            sqlite3_finalize(stmt)
        }
        
        let matchBindings = reading.isEmpty ? [term] : [term, reading, reading, term, reading]
        for (i, value) in matchBindings.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, Self.sqliteTransient)
        }
        for (i, source) in Self.defaultSources.enumerated() {
            sqlite3_bind_text(stmt, Int32(matchBindings.count + i + 1), source, -1, Self.sqliteTransient)
        }
        
        var sources: [[String: String]] = []
        var seen = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let source = String(cString: sqlite3_column_text(stmt, 0))
            let display = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let file = String(cString: sqlite3_column_text(stmt, 2))
            let expression = String(cString: sqlite3_column_text(stmt, 3))
            let rowReading = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let rank = sqlite3_column_int(stmt, 5)
            
            let encodedFile = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
            let url = "http://localhost:\(Self.port)/localaudio/\(source)/\(encodedFile)"
            
            guard seen.insert(url).inserted else {
                continue
            }
            
            let matched = switch rank {
            case 1: " (\(expression))"
            case 2: " (\(rowReading))"
            default: ""
            }
            
            sources.append(["name": displayName(source: source, display: display) + matched, "url": url])
        }
        
        guard !sources.isEmpty else {
            sendEmpty(to: connection)
            return
        }
        
        let response: [String: Any] = ["type": "audioSourceList", "audioSources": sources]
        let data = try! JSONSerialization.data(withJSONObject: response)
        send(data, status: "200 OK", contentType: "application/json", to: connection)
    }
    
    // https://github.com/KamWithK/AnkiconnectAndroid/blob/d79d7543df63894cac726f255780369cd0e6b177/app/src/main/java/com/kamwithk/ankiconnectandroid/routing/LocalAudioAPIRouting.java#L238
    private func getAudio(path: String, to connection: NWConnection) {
        let prefix = "/localaudio/"
        let tail = String(path.dropFirst(prefix.count))
        let parts = tail.split(separator: "/", maxSplits: 1)
        
        let source = String(parts.first ?? "")
        let file = String(parts[1]).removingPercentEncoding
        let dbURL = try! BookStorage.getAppDirectory().appendingPathComponent(Self.localAudioPath)
        
        var db: OpaquePointer?
        sqlite3_open(dbURL.path(percentEncoded: false), &db)
        defer {
            sqlite3_close(db)
        }
        
        let sql = "SELECT data FROM android WHERE source = ? AND file = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }
        defer {
            sqlite3_finalize(stmt)
        }
        
        sqlite3_bind_text(stmt, 1, source, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, file, -1, Self.sqliteTransient)
        
        guard sqlite3_step(stmt) == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }
        let count = Int(sqlite3_column_bytes(stmt, 0))
        let audioData = Data(bytes: bytes, count: count)
        send(audioData, status: "200 OK", contentType: "audio/mpeg", to: connection)
    }
    
    private func getCover(to connection: NWConnection) {
        guard let coverData else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }
        
        send(coverData, status: "200 OK", contentType: "application/octet-stream", to: connection)
    }
    
    private func getSasayakiAudio(to connection: NWConnection) {
        guard let sasayakiAudioData else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }
        
        send(sasayakiAudioData, status: "200 OK", contentType: "audio/mpeg", to: connection)
    }
    
    private func parseRequest(from requestData: Data) -> Request {
        guard let request = String(data: requestData, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            return Request(path: "/", query: [:])
        }
        
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return Request(path: "/", query: [:])
        }
        
        let target = String(parts[1])
        let components = URLComponents(string: "http://localhost\(target)")
        
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        
        return Request(path: components?.path ?? "/", query: query)
    }
    
    private func send(_ body: Data, status: String, contentType: String, to connection: NWConnection) {
        let header =
        "HTTP/1.1 \(status)\r\n" +
        "Content-Type: \(contentType)\r\n" +
        "Content-Length: \(body.count)\r\n" +
        "Connection: close\r\n" +
        "\r\n"
        
        var responseData = Data(header.utf8)
        responseData.append(body)
        
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private struct Request {
        let path: String
        let query: [String: String]
    }
}
