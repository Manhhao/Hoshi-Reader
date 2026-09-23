import Foundation

nonisolated enum SyncFormatError: LocalizedError {
    case unsupportedVersion
    
    var errorDescription: String? {
        String(localized: "Unsupported sync format.")
    }
}

nonisolated enum SyncFormat {
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(Document<T>.self, from: data).value
    }
    
    static func encode<T: Codable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(Document(value: value))
    }
    
    private struct Document<Value: Codable>: Codable {
        var value: Value
        
        enum CodingKeys: String, CodingKey {
            case formatVersion
        }
        
        init(value: Value) {
            self.value = value
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decodeIfPresent(Int.self, forKey: .formatVersion) == 1 else {
                throw SyncFormatError.unsupportedVersion
            }
            value = try Value(from: decoder)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .formatVersion)
            try value.encode(to: encoder)
        }
    }
}

nonisolated struct Timestamped<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var modified: Int64
    var value: Value
    
    func replacing<T>(_ value: T) -> Timestamped<T> {
        Timestamped<T>(modified: modified, value: value)
    }
    
    static func newest(_ first: Self, _ second: Self) -> Self {
        first.modified >= second.modified ? first : second
    }
    
    static func newest(_ first: Self?, _ second: Self?) -> Self? {
        switch (first, second) {
        case let (first?, second?):
            newest(first, second)
        case let (first?, nil):
            first
        case let (nil, second?):
            second
        case (nil, nil):
            nil
        }
    }
    
    static func merge<Key>(_ first: [Key: Self], _ second: [Key: Self]) -> [Key: Self] {
        first.merging(second) { newest($0, $1) }
    }
}

nonisolated extension Timestamped: Hashable where Value: Hashable {}

enum SyncProvider: String, CaseIterable {
    case gdrive
    case ttu
}

nonisolated struct SyncMetadata: Codable, Equatable, Sendable {
    var title: String
    var author: String?
}

nonisolated enum SyncFileType: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case epub
    case cover
    case sasayaki
}

typealias SyncFiles = [SyncFileType: Timestamped<String?>]

nonisolated struct SyncBookmark: Codable, Equatable, Sendable {
    var characterCount: Int
}

nonisolated struct SyncPlayback: Codable, Equatable, Sendable {
    var lastPosition: Double
    var delay: Double
    var rate: Double
}

nonisolated struct SyncHighlight: Codable, Equatable, Sendable {
    var character: Int
    var offset: Int
    var text: String
    var textFurigana: String?
    var color: String
    var createdAt: Int64
    
    init(_ highlight: Highlight) {
        character = highlight.character
        offset = highlight.offset
        text = highlight.text
        textFurigana = highlight.textFurigana
        color = highlight.color.rawValue
        createdAt = highlight.createdAt.milliseconds
    }
    
    func highlight(id: String) -> Highlight {
        Highlight(
            id: UUID(uuidString: id)!,
            character: character,
            offset: offset,
            text: text,
            textFurigana: textFurigana,
            color: HighlightColor(rawValue: color)!,
            createdAt: Date(milliseconds: createdAt)
        )
    }
}

nonisolated struct SyncBook: Codable, Equatable, Sendable {
    var generation: Int
    var deleted: Bool
    var metadata: Timestamped<SyncMetadata>
    var characterCount = 0
    var files: SyncFiles = [:]
    var bookmark: Timestamped<SyncBookmark>?
    var audiobook: Timestamped<SyncPlayback>?
    var highlights: [String: Timestamped<SyncHighlight?>] = [:]
    var sessions: [String: Timestamped<ReadingSession?>] = [:]
    var shelves: [String: Timestamped<Bool>] = [:]
    
    mutating func delete() {
        deleted = true
        files[.epub] = nil
        files[.sasayaki] = nil
        bookmark = nil
        audiobook = nil
        highlights = [:]
        shelves = [:]
    }
    
    func needsUpload(remote: Self?) -> Bool {
        guard let remote else { return true }
        return Self.merge(remote, self) != remote
    }
    
    static func merge(_ first: Self, _ second: Self) -> Self {
        var result: Self
        if first.generation != second.generation {
            result = first.generation > second.generation ? first : second
        } else {
            result = first
            result.metadata = .newest(first.metadata, second.metadata)
            result.characterCount = max(first.characterCount, second.characterCount)
            
            for fileType in SyncFileType.allCases {
                result.files[fileType] = .newest(first.files[fileType], second.files[fileType])
            }
            
            result.bookmark = .newest(first.bookmark, second.bookmark)
            result.audiobook = .newest(first.audiobook, second.audiobook)
            result.highlights = mergeRecords(first.highlights, second.highlights)
            result.shelves = Timestamped.merge(first.shelves, second.shelves)
            
            if first.deleted || second.deleted {
                result.delete()
            }
        }
        
        result.sessions = mergeRecords(first.sessions, second.sessions)
        return result
    }
    
    static func mergeRecords<T>(_ first: [String: Timestamped<T?>],_ second: [String: Timestamped<T?>]) -> [String: Timestamped<T?>] {
        first.merging(second) { first, second in
            if first.value == nil && second.value != nil {
                return first
            }
            
            if second.value == nil && first.value != nil {
                return second
            }
            
            return .newest(first, second)
        }
    }
}

nonisolated struct SyncShelves: Codable, Equatable, Sendable {
    var shelves: [String: Timestamped<Int?>]
    var orders: [String: Timestamped<[String]?>] = [:]
    
    static func merge(_ first: Self, _ second: Self) -> Self {
        Self(shelves: Timestamped.merge(first.shelves, second.shelves), orders: Timestamped.merge(first.orders, second.orders))
    }
}
