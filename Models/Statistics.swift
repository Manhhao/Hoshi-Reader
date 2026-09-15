//
//  Statistics.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2026 ッツ Reader Authors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum StatisticsAutostartMode: String, CaseIterable, Codable {
    case off = "Off"
    case pageturn = "Page Turn"
    case on = "On"
}

enum StatisticsSyncMode: String, CaseIterable, Codable {
    case merge = "Merge"
    case replace = "Replace"
}

enum StatisticsGoalMetric: String {
    case time
    case characters
}

enum StatisticsPeriod {
    case week
    case month
    case year
    case all
}

// https://github.com/ttu-ttu/ebook-reader/blob/2703b50ec52b2e4f70afcab725c0f47dd8a66bf4/apps/web/src/lib/data/database/books-db/versions/v6/books-db-v6.ts#L68
struct Statistics: Codable, Identifiable {
    let title: String
    let dateKey: String
    var charactersRead: Int
    var readingTime: Double
    var minReadingSpeed: Int
    var altMinReadingSpeed: Int
    var lastReadingSpeed: Int
    var maxReadingSpeed: Int
    var lastStatisticModified: Int
    
    var id: String { dateKey }
    
    var hasActivity: Bool {
        charactersRead > 0 || readingTime > 0
    }
    
    var date: Date {
        let parts = dateKey.split(separator: "-").map { Int($0)! }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }
    
    var readingDay: ReadingDay {
        ReadingDay(date: date, charactersRead: charactersRead, readingTime: readingTime)
    }
    
    var readingSpeed: Int {
        ReadingDay.speed(charactersRead: charactersRead, readingTime: readingTime)
    }
    
    func timeToRead(_ characters: Int) -> Double {
        lastReadingSpeed > 0 ? Double(characters) / (Double(lastReadingSpeed) / 3600.0) : 0
    }
    
    mutating func update(charactersRead: Int, readingTime: Double) {
        self.charactersRead = max(charactersRead, 0)
        self.readingTime = max(readingTime, 0)
        lastReadingSpeed = readingSpeed
        maxReadingSpeed = max(maxReadingSpeed, lastReadingSpeed)
        minReadingSpeed = minReadingSpeed != 0 ? min(minReadingSpeed, lastReadingSpeed) : lastReadingSpeed
        lastStatisticModified = Int(Date.now.timeIntervalSince1970 * 1000)
    }
    
    static func merged(_ statistics: [Statistics]) -> [Statistics] {
        var grouped: [String: Statistics] = [:]
        for statistic in statistics {
            if let existing = grouped[statistic.dateKey],
               existing.lastStatisticModified >= statistic.lastStatisticModified {
                continue
            }
            grouped[statistic.dateKey] = statistic
        }
        return grouped.values.sorted { $0.dateKey < $1.dateKey }
    }
}

struct ReadingDay: Identifiable, Hashable {
    let date: Date
    var charactersRead = 0
    var readingTime = 0.0
    
    var id: Date { date }
    
    var readingSpeed: Int {
        Self.speed(charactersRead: charactersRead, readingTime: readingTime)
    }
    
    func value(for metric: StatisticsGoalMetric) -> Double {
        switch metric {
        case .time:
            readingTime / 60
        case .characters:
            Double(charactersRead)
        }
    }
    
    mutating func add(_ day: ReadingDay) {
        charactersRead += day.charactersRead
        readingTime += day.readingTime
    }
    
    mutating func add(_ statistic: Statistics) {
        charactersRead += statistic.charactersRead
        readingTime += statistic.readingTime
    }
    
    static func speed(charactersRead: Int, readingTime: Double) -> Int {
        readingTime > 0 ? Int((Double(charactersRead) / readingTime) * 3600.0) : 0
    }
}

struct BookStatistics: Identifiable, Hashable {
    let metadata: BookMetadata
    let isDeleted: Bool
    var days: [ReadingDay]
    
    var id: String { metadata.folder }
    var readingTime: Double { days.reduce(0) { $0 + $1.readingTime } }
}
