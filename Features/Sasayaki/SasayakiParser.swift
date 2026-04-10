//
//  SasayakiParser.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct SasayakiParser {
    static func parseCues(from data: Data) -> [SasayakiCue] {
        /*
         1
         00:00:19,124 --> 00:00:22,016
         ＊シックスイヤーザー号、
         
         2
         00:00:24,148 --> 00:00:28,468
         渚　それはある日の、あたし達にとっては日常の光景だった。
         */
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { block in
                let lines = block.components(separatedBy: "\n")
                guard lines.count >= 3, lines[1].contains("-->") else {
                    return nil
                }
                
                let times = lines[1].components(separatedBy: "-->")
                let start = parseTimestamp(times[0])
                let end = parseTimestamp(times[1])
                
                let text = lines[2].trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("＊") {
                    return nil
                }
                
                return SasayakiCue(
                    id: lines[0].trimmingCharacters(in: .whitespaces),
                    startTime: start,
                    endTime: end,
                    text: text
                )
            }
    }
    
    private static func parseTimestamp(_ timestamp: String) -> Double {
        let parts = timestamp
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: ":")
        return Double(parts[0])! * 3600 + Double(parts[1])! * 60 + Double(parts[2])!
    }
}
