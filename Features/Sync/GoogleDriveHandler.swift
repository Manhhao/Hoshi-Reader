//
//  GoogleDriveHandler.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum GoogleDriveError: LocalizedError {
    case folderNotFound
    case fileNotFound
    case invalidResponse
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .folderNotFound:
            return "No ttu-reader-data folder on Google Drive"
        case .fileNotFound:
            return "Progress file not found"
        case .invalidResponse:
            return "Invalid response from Google Drive"
        case .apiError(let message):
            return message
        }
    }
}

enum SyncDirection {
    case importFromTtu
    case exportToTtu
    case synced
}

struct DriveFileList: Codable {
    let files: [DriveFile]
}

struct DriveFile: Codable {
    let id: String
    let name: String
}

struct TtuProgress: Codable {
    let dataId: Int
    let exploredCharCount: Int
    let progress: Double
    let lastBookmarkModified: Date
}

@MainActor
class GoogleDriveHandler {
    static let shared = GoogleDriveHandler()
    private init() {}
    
    private func performRequest(_ request: URLRequest, retry: Bool = true) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 && retry {
            let newToken = try await GoogleDriveAuth.shared.refreshAccessToken()
            var newRequest = request
            newRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await performRequest(newRequest, retry: false)
        }
        
        if httpResponse.statusCode >= 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GoogleDriveError.apiError(message)
            }
            throw GoogleDriveError.apiError("Request failed with status \(httpResponse.statusCode)")
        }
        
        return data
    }
    
    func findRootFolder() async throws -> String {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and mimeType='application/vnd.google-apps.folder' and name = 'ttu-reader-data'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { throw GoogleDriveError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        guard let folderId = list.files.first?.id else {
            throw GoogleDriveError.folderNotFound
        }
        return folderId
    }
    
    func listBooks(rootFolder: String) async throws -> [DriveFile] {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and '\(rootFolder)' in parents and mimeType='application/vnd.google-apps.folder'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { throw GoogleDriveError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        return list.files
    }
    
    func findProgressFileId(folderId: String) async throws -> String? {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and '\(folderId)' in parents and mimeType != 'application/vnd.google-apps.folder' and name contains 'progress_'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { throw GoogleDriveError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        return list.files.first?.id
    }
    
    func findStatsFileId(folderId: String) async throws -> String? {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and '\(folderId)' in parents and mimeType != 'application/vnd.google-apps.folder' and name contains 'statistics_'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { throw GoogleDriveError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        return list.files.first?.id
    }
    
    func getProgressFile(fileId: String) async throws -> TtuProgress {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        
        guard let url = components.url else { throw GoogleDriveError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(TtuProgress.self, from: data)
    }
    
    func getStatsFile(fileId: String) async throws -> [Statistics] {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        
        guard let url = components.url else { throw GoogleDriveError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let data = try await performRequest(request)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode([Statistics].self, from: data)
    }
    
    func updateProgressFile(folderId: String, fileId: String?, progress: TtuProgress) async throws {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        let timestamp = Int(progress.lastBookmarkModified.timeIntervalSince1970 * 1000)
        let fileName = "progress_1_6_\(timestamp)_\(progress.progress).json"
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let contentData = try encoder.encode(progress)
        
        let boundary = UUID().uuidString
        
        let url: URL
        let method: String
        let metadata: Data
        
        if let fileId = fileId {
            url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=multipart")!
            method = "PATCH"
            metadata = try JSONEncoder().encode(["name": fileName])
        } else {
            url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
            method = "POST"
            metadata = try JSONSerialization.data(withJSONObject: ["name": fileName, "parents": [folderId]])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadata)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(contentData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let _ = try await performRequest(request)
    }
    
    func updateStatsFile(folderId: String, fileId: String?, stats: [Statistics]) async throws {
        let accessToken = try GoogleDriveAuth.shared.getAccessToken()
        let fileName = getStatisticsFileName(stats: stats)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let contentData = try encoder.encode(stats)
        
        let boundary = UUID().uuidString
        
        let url: URL
        let method: String
        let metadata: Data
        
        if let fileId = fileId {
            url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=multipart")!
            method = "PATCH"
            metadata = try JSONEncoder().encode(["name": fileName])
        } else {
            url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
            method = "POST"
            metadata = try JSONSerialization.data(withJSONObject: ["name": fileName, "parents": [folderId]])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadata)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(contentData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let _ = try await performRequest(request)
    }
    
    private func getStatisticsFileName(stats: [Statistics]) -> String {
        var readingTime: Double = 0;
        var charactersRead: Int = 0;
        var minReadingSpeed: Int = 0;
        var altMinReadingSpeed: Int = 0;
        var maxReadingSpeed: Int = 0;
        var weightedSum: Int = 0;
        var validReadingDays: Int = 0;
        var lastStatisticModified: Int = 0;
        
        for stat in stats {
            readingTime += stat.readingTime;
            charactersRead += stat.charactersRead;
            minReadingSpeed = minReadingSpeed > 0 ? min(minReadingSpeed, stat.minReadingSpeed) : stat.minReadingSpeed;
            altMinReadingSpeed = altMinReadingSpeed > 0 ? min(altMinReadingSpeed, stat.altMinReadingSpeed) : stat.altMinReadingSpeed;
            maxReadingSpeed = max(maxReadingSpeed, stat.lastReadingSpeed);
            weightedSum += Int(stat.readingTime) * stat.charactersRead;
            lastStatisticModified = max(lastStatisticModified, stat.lastStatisticModified)
            if (stat.readingTime > 0) {
                validReadingDays += 1;
            }
        }
        
        let averageReadingTime = validReadingDays > 0 ? ceil(readingTime / Double(validReadingDays)) : 0;
        let averageWeightedReadingTime = charactersRead > 0 ? ceil(Double(weightedSum) /  Double(charactersRead)) : 0;
        let averageCharactersRead = validReadingDays > 0 ? ceil(Double(charactersRead) /  Double(validReadingDays)) : 0;
        let averageWeightedCharactersRead = readingTime > 0 ? ceil(Double(weightedSum) / Double(readingTime)) : 0;
        let lastReadingSpeed = readingTime > 0 ? ceil((3600.0 * Double(charactersRead)) / readingTime) : 0;
        let averageReadingSpeed = averageReadingTime > 0 ? ceil((3600 * averageCharactersRead) / averageReadingTime) : 0;
        let averageWeightedReadingSpeed = averageWeightedReadingTime > 0 ? ceil((3600 * averageWeightedCharactersRead) / averageWeightedReadingTime) : 0;
        return "statistics_1_6_\(lastStatisticModified)_\(charactersRead)_\(readingTime)_\(minReadingSpeed)_\(altMinReadingSpeed)_\(lastReadingSpeed)_\(maxReadingSpeed)_\(averageReadingTime)_\(averageWeightedReadingTime)_\(averageCharactersRead)_\(averageWeightedCharactersRead)_\(averageReadingSpeed)_\(averageWeightedReadingSpeed)_na.json"
    }
}
