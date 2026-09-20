//
//  Sasayaki.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct SasayakiCue: Hashable {
    let id: String
    let startTime: Double
    let endTime: Double
    let text: String
}

enum SasayakiTranscriptionProgress {
    case downloading(Double)
    case transcribing(through: Double, duration: Double, remaining: Double?)
    case aligning
}

struct SasayakiToken: Codable, Sendable {
    let text: String
    let start: Double
    let end: Double
}

struct SasayakiTranscript: Codable {
    var through: Double
    var duration: Double
    var tokens: [SasayakiToken]
    
    var isComplete: Bool {
        duration > 0 && through + 1.5 >= duration
    }
}

struct SasayakiMatch: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let startTime: Double
    var endTime: Double
    let text: String
    let chapterIndex: Int
    let start: Int
    let length: Int
}

struct SasayakiCueRange: Encodable {
    let id: String
    let start: Int
    let length: Int
}

struct SasayakiImage: Codable, Sendable {
    let chapterIndex: Int
    let imageIndex: Int
    let offset: Int
}

nonisolated struct SasayakiMatchData: Codable, Sendable {
    let matches: [SasayakiMatch]
    let unmatched: Int
    let images: [SasayakiImage]
    
    var matchedCharacters: Int {
        matches.reduce(0) { $0 + $1.length }
    }
}

struct SasayakiPlaybackData: Codable {
    var lastPosition: Double
    var delay: Double = 0
    var rate: Float = 1
    var audioBookmark: Data?
    
    init(lastPosition: Double) {
        self.lastPosition = lastPosition
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastPosition = try container.decode(Double.self, forKey: .lastPosition)
        delay = try container.decodeIfPresent(Double.self, forKey: .delay) ?? 0
        rate = try container.decodeIfPresent(Float.self, forKey: .rate) ?? 1
        audioBookmark = try container.decodeIfPresent(Data.self, forKey: .audioBookmark)
    }
}
