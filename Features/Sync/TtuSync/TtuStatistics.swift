import CryptoKit
import Foundation

struct TtuStatistics: Codable, Equatable {
    let title: String
    let dateKey: String
    var charactersRead: Int
    var readingTime: Double
    var minReadingSpeed: Int
    var altMinReadingSpeed: Int
    var lastReadingSpeed: Int
    var maxReadingSpeed: Int
    var lastStatisticModified: Int
    
    var hasActivity: Bool {
        charactersRead > 0 || readingTime > 0
    }
    
    static func merged(_ statistics: [TtuStatistics]) -> [TtuStatistics] {
        var grouped: [String: TtuStatistics] = [:]
        for statistic in statistics {
            if let existing = grouped[statistic.dateKey], existing.lastStatisticModified >= statistic.lastStatisticModified {
                continue
            }
            grouped[statistic.dateKey] = statistic
        }
        return grouped.values.sorted {
            $0.dateKey < $1.dateKey
        }
    }
    
    static func legacySessions(_ statistics: [TtuStatistics], key: String) -> [String: Timestamped<ReadingSession?>] {
        var sessions: [String: Timestamped<ReadingSession?>] = [:]
        
        for statistic in merged(statistics).filter(\.hasActivity) {
            sessions[legacyId(key: key, dateKey: statistic.dateKey)] = Timestamped(
                modified: Int64(statistic.lastStatisticModified),
                value: statistic.session
            )
        }
        
        return sessions
    }
    
    static func legacyId(key: String, dateKey: String) -> String {
        let hash = SHA256.hash(data: Data("\(key.precomposedStringWithCanonicalMapping)\n\(dateKey)\nlegacy".utf8))
        return hash.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }.uuidString
    }
    
    static func export(_ sessions: [String: Timestamped<ReadingSession?>], title: String) -> [TtuStatistics] {
        let days = StatisticsDay.grouped(sessions, resetTime: UserConfig.shared.statisticsResetTime)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withFullDate]
        
        return days.map { day in
            let total = day.total
            
            return TtuStatistics(
                title: title,
                dateKey: formatter.string(from: day.date),
                charactersRead: total.charactersRead,
                readingTime: total.readingTime,
                minReadingSpeed: total.readingSpeed,
                altMinReadingSpeed: total.readingSpeed,
                lastReadingSpeed: total.readingSpeed,
                maxReadingSpeed: total.readingSpeed,
                lastStatisticModified: Int(day.sessions.values.map(\.modified).max() ?? 0)
            )
        }.filter(\.hasActivity)
    }
    
    static func importHistory(_ statistics: [TtuStatistics], key: String, mode: StatisticsSyncMode = .merge) {
        if statistics.isEmpty {
            return
        }
        
        var sessions = StatisticsStorage.load(folder: key)
        let original = sessions
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withFullDate]
        var days = Dictionary(
            uniqueKeysWithValues: StatisticsDay.grouped(sessions, resetTime: UserConfig.shared.statisticsResetTime).map {
                (formatter.string(from: $0.date), $0.sessions)
            }
        )
        
        for imported in merged(statistics) {
            let previous = days.removeValue(forKey: imported.dateKey) ?? [:]
            let modified = Int64(imported.lastStatisticModified)
            if mode == .merge, let latest = previous.values.map(\.modified).max(), latest >= modified {
                continue
            }
            
            var id = previous.keys.min() ?? legacyId(key: key, dateKey: imported.dateKey)
            if previous[id] == nil && sessions[id] != nil {
                id = UUID().uuidString
            }
            
            let value = imported.hasActivity ? imported.session : nil
            if mode == .replace && previous.count == 1 && previous[id]?.value == value {
                continue
            }
            
            let timestamp = mode == .replace ? Date.now.milliseconds : modified
            for previousId in previous.keys where previousId != id || value == nil {
                sessions[previousId] = Timestamped(modified: timestamp, value: nil)
            }
            if let value {
                sessions[id] = Timestamped(modified: timestamp, value: value)
            }
        }
        
        if mode == .replace {
            for day in days.values {
                for id in day.keys {
                    sessions[id] = Timestamped(modified: Date.now.milliseconds, value: nil as ReadingSession?)
                }
            }
        }
        
        if sessions != original {
            StatisticsStorage.save(sessions, folder: key)
        }
    }
    
    private var session: ReadingSession {
        let resetTime = UserConfig.shared.statisticsResetTime
        let parts = dateKey.split(separator: "-").map {
            Int($0)!
        }
        var start = Calendar.current.date(
            from: DateComponents(
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: resetTime / 60,
                minute: resetTime % 60
            )
        )!
        
        let estimatedEnd = Date(milliseconds: Int64(lastStatisticModified))
        let estimatedStart = estimatedEnd.addingTimeInterval(-readingTime)
        let day = Calendar.current.startOfDay(for: start)
        if StatisticsDay.date(estimatedStart, resetTime: resetTime) == day,
           StatisticsDay.date(estimatedEnd, resetTime: resetTime) == day {
            start = estimatedStart
        }
        
        return ReadingSession(
            startedAt: start.milliseconds,
            endedAt: start.addingTimeInterval(readingTime).milliseconds,
            charactersRead: charactersRead,
            readingTime: readingTime
        )
    }
}
