//
//  GoogleDriveHandler.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

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

class GoogleDriveHandler {
    static let shared = GoogleDriveHandler()

    func findRootFolder(accessToken: String) async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and mimeType='application/vnd.google-apps.folder' and name = 'ttu-reader-data'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        return list.files.first?.id
    }
    
    func listBooks(accessToken: String, rootFolder: String) async throws -> [DriveFile] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and '\(rootFolder)' in parents and mimeType='application/vnd.google-apps.folder'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        return list.files
    }
    
    func getProgress(accessToken: String, folderId: String) async throws -> TtuProgress? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let query = "trashed=false and '\(folderId)' in parents and mimeType != 'application/vnd.google-apps.folder' and name contains 'progress_'"
        
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id, name)")
        ]
        
        guard let url = components.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let list = try JSONDecoder().decode(DriveFileList.self, from: data)
        guard let fileId = list.files.first?.id else { return nil }
        
        var downloadComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        downloadComponents.queryItems = [URLQueryItem(name: "alt", value: "media")]
        
        guard let downloadURL = downloadComponents.url else { return nil }
        
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.httpMethod = "GET"
        downloadRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (progressData, _) = try await URLSession.shared.data(for: downloadRequest)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let progress = try decoder.decode(TtuProgress.self, from: progressData)
        
        return progress
    }
}
