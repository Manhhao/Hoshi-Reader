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
    private var localAudioEnabled = false
    
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
        
        let newListener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
        newListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if case .failed = state {
                    // retry start if failed with a small delay in case port is still taken by old listener
                    self.listener = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if self.listener == nil && (self.localAudioEnabled || self.coverData != nil) {
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
        guard coverData == nil && !localAudioEnabled else {
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
    
    func clearCover() {
        coverData = nil
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
    
    // https://github.com/KamWithK/AnkiconnectAndroid/blob/d79d7543df63894cac726f255780369cd0e6b177/app/src/main/java/com/kamwithk/ankiconnectandroid/routing/LocalAudioAPIRouting.java#L102
    private func getAudioSources(_ request: Request, to connection: NWConnection) {
        let term = request.query["term"] ?? ""
        let rawReading = request.query["reading"] ?? ""
        let reading = katakanaToHiragana(rawReading)
        let dbURL = try! BookStorage.getDocumentsDirectory().appendingPathComponent(Self.localAudioPath)
        
        var db: OpaquePointer?
        sqlite3_open(dbURL.path(percentEncoded: false), &db)
        defer {
            sqlite3_close(db)
        }
        
        // Technically Ankiconnect Android and the original Local Audio plugin return multiple entries
        // sort by matching reading first for more accurate results
        let sortOrder = "CASE source " + Self.defaultSources.indices.map { "WHEN ? THEN \($0) " }.joined() + "ELSE 999 END"
        let sql: String
        if reading.isEmpty {
            sql = """
                SELECT source, file FROM entries
                WHERE expression = ? AND file LIKE '%.mp3'
                ORDER BY \(sortOrder)
                LIMIT 1;
                """
        } else {
            sql = """
                SELECT source, file FROM entries
                WHERE (expression = ? OR reading = ?) AND file LIKE '%.mp3'
                ORDER BY CASE WHEN reading = ? THEN 0 ELSE 1 END, \(sortOrder)
                LIMIT 1;
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
        
        sqlite3_bind_text(stmt, 1, term, -1, Self.sqliteTransient)
        var bindIndex = 2
        if !reading.isEmpty {
            sqlite3_bind_text(stmt, 2, reading, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, reading, -1, Self.sqliteTransient)
            bindIndex = 4
        }
        for (i, source) in Self.defaultSources.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + bindIndex), source, -1, Self.sqliteTransient)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let source = String(cString: sqlite3_column_text(stmt, 0))
            let file = String(cString: sqlite3_column_text(stmt, 1))
            
            let encodedFile = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
            let url = "http://localhost:\(Self.port)/localaudio/\(source)/\(encodedFile)"
            
            let response: [String: Any] = ["type": "audioSourceList", "audioSources": [["name": source, "url": url]]]
            let data = try! JSONSerialization.data(withJSONObject: response)
            send(data, status: "200 OK", contentType: "application/json", to: connection)
            return
        }
        
        sendEmpty(to: connection)
    }
    
    // https://github.com/KamWithK/AnkiconnectAndroid/blob/d79d7543df63894cac726f255780369cd0e6b177/app/src/main/java/com/kamwithk/ankiconnectandroid/routing/LocalAudioAPIRouting.java#L238
    private func getAudio(path: String, to connection: NWConnection) {
        let prefix = "/localaudio/"
        let tail = String(path.dropFirst(prefix.count))
        let parts = tail.split(separator: "/", maxSplits: 1)
        
        let source = String(parts.first ?? "")
        let file = String(parts[1]).removingPercentEncoding
        let dbURL = try! BookStorage.getDocumentsDirectory().appendingPathComponent(Self.localAudioPath)
        
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
