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

struct SasayakiMatch: Codable, Identifiable, Hashable {
    let id: String
    let startTime: Double
    let endTime: Double
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

struct SasayakiMatchData: Codable {
    let matches: [SasayakiMatch]
    let unmatched: Int
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
