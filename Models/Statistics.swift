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

nonisolated struct ReadingSession: Codable, Equatable, Sendable {
    var startedAt: Int64
    var endedAt: Int64
    var charactersRead = 0
    var readingTime = 0.0
    
    var hasActivity: Bool {
        charactersRead > 0 || readingTime > 0
    }
    
    var readingSpeed: Int {
        ReadingTotal.speed(charactersRead: charactersRead, readingTime: readingTime)
    }
    
    func timeToRead(_ characters: Int) -> Double {
        readingSpeed > 0 ? Double(characters) / (Double(readingSpeed) / 3600) : 0
    }
    
    mutating func track(characters: Int, time: Double, until date: Date) {
        charactersRead = max(charactersRead + characters, 0)
        readingTime += time
        endedAt = date.milliseconds
    }
    
    static func starting(at date: Date) -> ReadingSession {
        let timestamp = date.milliseconds
        
        return ReadingSession(startedAt: timestamp, endedAt: timestamp)
    }
}

nonisolated struct StatisticsDay: Identifiable {
    let date: Date
    var sessions: [String: Timestamped<ReadingSession?>]
    
    var id: Date {
        date
    }
    
    var total: ReadingTotal {
        sessions.values.reduce(into: ReadingTotal(date: date)) {
            $0.add($1.value!)
        }
    }
    
    static func date(_ date: Date, resetTime: Int, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-Double(resetTime) * 60))
    }
    
    static func grouped(_ sessions: [String: Timestamped<ReadingSession?>], resetTime: Int) -> [StatisticsDay] {
        let calendar = Calendar.current
        var days: [Date: StatisticsDay] = [:]
        
        for (id, change) in sessions {
            guard let session = change.value else {
                continue
            }
            
            let date = date(
                Date(milliseconds: session.startedAt),
                resetTime: resetTime,
                calendar: calendar
            )
            days[date, default: StatisticsDay(date: date, sessions: [:])].sessions[id] = change
        }
        
        return days.values.sorted {
            $0.date < $1.date
        }
    }
}

nonisolated struct ReadingTotal: Identifiable, Hashable {
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
    
    mutating func add(_ total: ReadingTotal) {
        charactersRead += total.charactersRead
        readingTime += total.readingTime
    }
    
    mutating func add(_ session: ReadingSession) {
        charactersRead += session.charactersRead
        readingTime += session.readingTime
    }
    
    static func speed(charactersRead: Int, readingTime: Double) -> Int {
        readingTime > 0 ? Int((Double(charactersRead) / readingTime) * 3600.0) : 0
    }
}

struct BookStatistics: Identifiable {
    let metadata: BookMetadata
    let isDeleted: Bool
    var days: [StatisticsDay]
    
    var id: String { metadata.folder }
    var readingTime: Double { days.reduce(0) { $0 + $1.total.readingTime } }
}
