import Foundation

nonisolated struct GoogleDriveFile: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var mimeType: String
    var version: String
    var size: String?
    var parents: [String]?
    var trashed: Bool?
    var createdTime: String
    
    var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
    
    var isRecent: Bool { (try? Date(createdTime, strategy: .iso8601)).map { Date.now.timeIntervalSince($0) < 86400 } ?? false }
    
    var stateKey: String? { name.hasSuffix(".json") && !isFolder ? String(name.dropLast(5)).precomposedStringWithCanonicalMapping : nil }
}

nonisolated struct GoogleDriveFileList: Decodable {
    var files: [GoogleDriveFile]
    var nextPageToken: String?
}

nonisolated struct GoogleDriveChanges: Decodable {
    struct Change: Decodable {
        var removed: Bool
        var file: GoogleDriveFile?
    }
    
    var changes: [Change]
    var nextPageToken: String?
    var newStartPageToken: String?
}

@MainActor
final class GoogleDriveSyncHandler {
    static let shared = GoogleDriveSyncHandler()
    private let client = GoogleDriveClient.shared
    private let fileFields = "id,name,mimeType,version,size,parents,trashed,createdTime"
    
    func startToken() async throws -> String {
        struct Token: Decodable {
            var startPageToken: String
        }
        
        let data = try await client.request("changes/startPageToken")
        return try JSONDecoder().decode(Token.self, from: data).startPageToken
    }
    
    func changes(cursor: String) async throws -> GoogleDriveChanges {
        let data = try await client.request(
            "changes",
            query: [
                URLQueryItem(name: "pageToken", value: cursor),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "spaces", value: "drive"),
                URLQueryItem(name: "includeRemoved", value: "true"),
                URLQueryItem(
                    name: "fields",
                    value: "nextPageToken,newStartPageToken,changes(removed,file(\(fileFields)))"
                )
            ]
        )
        return try JSONDecoder().decode(GoogleDriveChanges.self, from: data)
    }
    
    func layout() async throws -> (root: String, state: String, books: String) {
        let root = try await folder(parent: "root", name: "Hoshi Reader", create: true)!
        let state = try await folder(parent: root, name: "state", create: true)!
        let books = try await folder(parent: root, name: "books", create: true)!
        return (root, state, books)
    }
    
    func fileFolder(books: String, key: String, generation: Int, create: Bool) async throws -> String? {
        guard let book = try await folder(parent: books, name: key, create: create) else {
            return nil
        }
        return try await folder(parent: book, name: String(generation), create: create)
    }
    
    func folder(parent: String, name: String, create: Bool) async throws -> String? {
        if let folder = try await children(parent: parent, name: name).first(where: \.isFolder) {
            return folder.id
        }
        
        if !create {
            return nil
        }
        
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "parents": [parent],
            "mimeType": "application/vnd.google-apps.folder"
        ])
        
        let data = try await client.request("files", query: [URLQueryItem(name: "fields", value: fileFields)], method: "POST", body: body)
        return try JSONDecoder().decode(GoogleDriveFile.self, from: data).id
    }
    
    func children(parent: String, name: String? = nil) async throws -> [GoogleDriveFile] {
        var query = "'\(escape(parent))' in parents"
        if let name {
            query += " and name='\(escape(name))'"
        }
        return try await list(query: query)
    }
    
    func list(query: String) async throws -> [GoogleDriveFile] {
        var result: [GoogleDriveFile] = []
        var cursor: String?
        
        repeat {
            var items = [
                URLQueryItem(name: "q", value: "trashed=false and (\(query))"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "spaces", value: "drive"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(\(fileFields))")
            ]
            
            if let cursor {
                items.append(URLQueryItem(name: "pageToken", value: cursor))
            }
            
            let data = try await client.request("files", query: items)
            let page = try JSONDecoder().decode(GoogleDriveFileList.self, from: data)
            
            result.append(contentsOf: page.files)
            cursor = page.nextPageToken
        } while cursor != nil
        return result.sorted { $0.id < $1.id }
    }
    
    func read(_ file: GoogleDriveFile) async throws -> Data {
        try await client.request("files/\(file.id)", query: [URLQueryItem(name: "alt", value: "media")])
    }
    
    func upload(data: Data, fileName: String, folder: String) async throws {
        let existing = try await children(parent: folder, name: fileName)
        if !existing.isEmpty {
            return
        }
        try await client.write(data: data, name: fileName, parent: folder)
    }
    
    func download(fileName: String, folder: String?, onProgress: @MainActor @Sendable @escaping (Double) -> Void) async throws -> Data {
        guard let folder, let file = try await children(parent: folder, name: fileName).first else {
            throw GoogleDriveError.apiError("\(fileName) is missing from Google Drive.", statusCode: 404)
        }
        return try await GoogleDriveClient.shared.downloadFile(fileId: file.id, fileSize: file.size.flatMap(Int64.init)!, onProgress: onProgress)
    }
    
    func trash(_ file: GoogleDriveFile) async throws {
        try await GoogleDriveClient.shared.trashFile(fileId: file.id)
    }
    
    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}
