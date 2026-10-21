import Foundation

final class Listing {
    var listed = false
    var books: [String: String] = [:]
    var folders: [String: [Int: String]] = [:]
    var files: [String: [String: GoogleDriveFile]] = [:]
    var created: Set<String> = []
    var published = false
}

extension GoogleDriveSyncManager {
    func listFiles() async throws -> Listing {
        let listing = Listing()
        let listed = try await drive.list(query: "'me' in owners")
        let keys = Dictionary(uniqueKeysWithValues: listed.filter { $0.parents?.contains(cache.bookFolder) == true }.map { ($0.id, $0.name) })
        listing.listed = true
        var folders: [String: String] = [:]
        for file in listed {
            if keys[file.id] != nil, listing.books[file.name] == nil {
                listing.books[file.name] = file.id
            }
            guard let parent = file.parents?.first else { continue }
            if file.isFolder, let key = keys[parent], let generation = Int(file.name) {
                if listing.folders[key]?[generation] == nil {
                    listing.folders[key, default: [:]][generation] = file.id
                    folders["\(key)/\(generation)"] = file.id
                }
            } else if listing.files[parent]?[file.name] == nil {
                listing.files[parent, default: [:]][file.name] = file
            }
        }
        cache.bookFolders = folders
        return listing
    }
    
    func folder(_ listing: Listing, key: String, generation: Int) async throws -> String? {
        try await resolveFolder(listing, key: key, generation: generation).folder
    }
    
    func forgetFolder(_ listing: Listing, key: String, generation: Int) {
        listing.folders[key]?[generation] = nil
        cache.bookFolders?["\(key)/\(generation)"] = nil
    }
    
    func upload(_ listing: Listing, key: String, generation: Int, name: String, file: URL, resumable: Bool, onProgress: @MainActor @Sendable @escaping (Int64) -> Void) async throws {
        var (book, folder) = try await resolveFolder(listing, key: key, generation: generation)
        if folder == nil {
            if book == nil {
                book = try await drive.createFolder(parent: cache.bookFolder, name: key)
                listing.books[key] = book
            }
            let created = try await drive.createFolder(parent: book!, name: String(generation))
            listing.created.insert(created)
            rememberFolder(listing, key: key, generation: generation, folder: created)
            folder = created
        }
        if listing.files[folder!]?[name] != nil {
            return
        }
        let known = listing.listed || listing.created.contains(folder!)
        if resumable {
            if !known, try await !drive.children(parent: folder!, name: name).isEmpty {
                return
            }
            try await uploadResumable(file: file, name: name, folder: folder!, onProgress: onProgress)
        } else if known {
            try await GoogleDriveClient.shared.write(file: file, name: name, parent: folder!, onProgress: onProgress)
        } else {
            try await drive.upload(file: file, fileName: name, folder: folder!, onProgress: onProgress)
        }
    }
    
    private func uploadResumable(file: URL, name: String, folder: String, onProgress: @MainActor @Sendable @escaping (Int64) -> Void) async throws {
        let client = GoogleDriveClient.shared
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let total = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = Int64(((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000)
        let key = "\(folder)/\(name)/\(total)/\(modified)"
        var session: String
        var offset: Int64 = 0
        if let saved = cache.uploadSessions?[key] {
            switch try await client.uploadStatus(session: saved, total: total) {
            case .done:
                return try finishSession(key)
            case .received(let received):
                session = saved
                offset = received
            case .expired:
                session = try await client.startUpload(name: name, parent: folder, total: total)
            }
        } else {
            session = try await client.startUpload(name: name, parent: folder, total: total)
        }
        cache.uploadSessions = (cache.uploadSessions ?? [:]).merging([key: session]) { $1 }
        try saveCache()
        for _ in 0..<3 {
            switch try await client.upload(session: session, file: file, offset: offset, total: total, onProgress: onProgress) {
            case .done:
                return try finishSession(key)
            case .received(let received):
                offset = received
            case .expired:
                try finishSession(key)
                throw GoogleDriveError.apiError(String(localized: "The upload expired and will start over."), statusCode: nil)
            }
        }
        throw GoogleDriveError.unavailable(URLError(.networkConnectionLost))
    }
    
    private func finishSession(_ key: String) throws {
        cache.uploadSessions?[key] = nil
        try saveCache()
    }
    
    func size(_ listing: Listing, key: String, generation: Int, name: String) -> Int64? {
        guard let folder = listing.folders[key]?[generation] else { return nil }
        return listing.files[folder]?[name]?.size.flatMap { Int64($0) }
    }
    
    func findFile(_ listing: Listing, key: String, generation: Int, name: String) async throws -> GoogleDriveFile? {
        if let folder = listing.folders[key]?[generation] ?? cache.bookFolders?["\(key)/\(generation)"] {
            if let file = listing.files[folder]?[name] {
                return file
            }
            if let file = try await drive.children(parent: folder, name: name).first {
                return file
            }
        }
        for book in try await drive.children(parent: cache.bookFolder, name: key) {
            for folder in try await drive.children(parent: book.id, name: String(generation)) {
                if let file = try await drive.children(parent: folder.id, name: name).first {
                    rememberFolder(listing, key: key, generation: generation, folder: folder.id)
                    return file
                }
            }
        }
        return nil
    }
    
    private func resolveFolder(_ listing: Listing, key: String, generation: Int) async throws -> (book: String?, folder: String?) {
        var folder = listing.folders[key]?[generation]
        var book = listing.books[key]
        if folder != nil || listing.listed {
            return (book, folder)
        }
        if book == nil {
            book = try await drive.folder(parent: cache.bookFolder, name: key, create: false)
        }
        if let book {
            folder = try await drive.folder(parent: book, name: String(generation), create: false)
            listing.books[key] = book
        }
        if let folder {
            rememberFolder(listing, key: key, generation: generation, folder: folder)
        }
        return (book, folder)
    }
    
    private func rememberFolder(_ listing: Listing, key: String, generation: Int, folder: String) {
        listing.folders[key, default: [:]][generation] = folder
        cache.bookFolders = (cache.bookFolders ?? [:]).merging(["\(key)/\(generation)": folder]) { $1 }
    }
}
