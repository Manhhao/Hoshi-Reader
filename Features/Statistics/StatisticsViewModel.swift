//
//  StatisticsViewModel.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

@Observable
@MainActor
class StatisticsViewModel {
    var period: StatisticsPeriod = .week {
        didSet {
            referenceDate = today
            selectedDate = nil
        }
    }
    
    var referenceDate = Calendar.current.startOfDay(for: .now) {
        didSet {
            guard referenceDate != oldValue else {
                return
            }
            selectedDate = nil
        }
    }
    
    var resetTime = 0 {
        didSet {
            guard resetTime != oldValue else {
                return
            }
            today = Self.startOfDay(resetTime: resetTime)
            referenceDate = today
        }
    }
    
    var selectedDate: Date? {
        didSet {
            visibleBookCount = 5
            updateBooks()
        }
    }
    
    var visibleBookCount = 5
    
    private(set) var today = StatisticsViewModel.startOfDay(resetTime: 0)
    private(set) var dailyTotals: [ReadingTotal] = []
    private(set) var books: [BookStatistics] = []
    
    private var allBooks: [BookStatistics] = []
    private var totalsByDate: [Date: ReadingTotal] = [:]
    private var totalsByMonth: [Date: ReadingTotal] = [:]
    
    var firstDay: Date? {
        dailyTotals.first?.date
    }
    
    var todaysTotal: ReadingTotal {
        total(on: today) ?? ReadingTotal(date: today)
    }
    
    var bucketUnit: Calendar.Component {
        switch period {
        case .week, .month:
                .day
        case .year, .all:
                .month
        }
    }
    
    var referenceDates: [Date] {
        guard period != .all, let firstDay else {
            return [referenceDate]
        }
        
        return Array(
            sequence(first: today) { self.previousDate(from: $0) }
                .prefix { date in (interval(for: date)?.end ?? .distantPast) > firstDay }
                .reversed()
        )
    }
    
    var selectedTotal: ReadingTotal? {
        guard let selectedDate else {
            return nil
        }
        return buckets(for: referenceDate).first { $0.date == selectedDate }
    }
    
    var summary: ReadingTotal {
        selectedTotal ?? periodTotals(for: referenceDate)
            .reduce(into: ReadingTotal(date: referenceDate)) { $0.add($1) }
    }
    
    var readingTimeDelta: Double? {
        guard period != .all, selectedDate == nil,
              let previous = previousDate(from: referenceDate),
              let current = averageReadingTime(for: referenceDate),
              let earlier = averageReadingTime(for: previous), earlier > 0 else {
            return nil
        }
        return (current - earlier) / earlier * 100
    }
    
    func load() {
        let current = Self.startOfDay(resetTime: resetTime)
        if current != today, interval(for: referenceDate)?.halfOpen.contains(today) ?? true {
            referenceDate = current
        }
        today = current
        
        allBooks = StatisticsStorage.loadAll(resetTime: resetTime)
        totalsByDate = allBooks.flatMap(\.days).map(\.total).reduce(into: [:]) { grouped, total in
            grouped[total.date, default: ReadingTotal(date: total.date)].add(total)
        }
        dailyTotals = totalsByDate.values.sorted { $0.date < $1.date }
        let calendar = Calendar.current
        totalsByMonth = dailyTotals.reduce(into: [:]) { grouped, total in
            guard let month = calendar.dateInterval(of: .month, for: total.date)?.start else {
                return
            }
            grouped[month, default: ReadingTotal(date: month)].add(total)
        }
        updateBooks()
    }
    
    func total(on date: Date) -> ReadingTotal? {
        totalsByDate[Calendar.current.startOfDay(for: date)]
    }
    
    func buckets(for referenceDate: Date) -> [ReadingTotal] {
        let calendar = Calendar.current
        let unit = bucketUnit
        let dayStart = calendar.startOfDay(for: referenceDate)
        let span = interval(for: referenceDate) ?? DateInterval(
            start: min(firstDay ?? dayStart, dayStart),
            end: calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        )
        guard let start = calendar.dateInterval(of: unit, for: span.start)?.start else {
            return []
        }
        
        let grouped = unit == .day ? totalsByDate : totalsByMonth
        
        return sequence(first: start) { calendar.date(byAdding: unit, value: 1, to: $0) }
            .prefix { $0 < span.end }
            .map { grouped[$0] ?? ReadingTotal(date: $0) }
    }
    
    func averageReadingTime(for referenceDate: Date) -> Double? {
        let elapsed = buckets(for: referenceDate).count { $0.date <= today }
        guard elapsed > 0 else {
            return nil
        }
        
        return periodTotals(for: referenceDate).reduce(0) { $0 + $1.readingTime } / Double(elapsed)
    }
    
    func title(for date: Date) -> String {
        switch period {
        case .week:
            let interval = interval(for: date)!
            let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)!
            return (interval.start..<end).formatted(.interval.day().month(.abbreviated))
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        case .year:
            return date.formatted(.dateTime.year())
        case .all:
            return String(localized: "All Time")
        }
    }
    
    private var periodUnit: Calendar.Component? {
        switch period {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }
    
    private func periodTotals(for referenceDate: Date) -> [ReadingTotal] {
        let interval = interval(for: referenceDate)
        return dailyTotals.filter { interval?.halfOpen.contains($0.date) ?? true }
    }
    
    private func interval(for date: Date) -> DateInterval? {
        periodUnit.flatMap { Calendar.current.dateInterval(of: $0, for: date) }
    }
    
    private func previousDate(from date: Date) -> Date? {
        periodUnit.flatMap { Calendar.current.date(byAdding: $0, value: -1, to: date) }
    }
    
    private func updateBooks() {
        let interval = selectedDate.flatMap { Calendar.current.dateInterval(of: bucketUnit, for: $0) }
        ?? interval(for: referenceDate)
        books = allBooks.compactMap { book in
            var book = book
            if let interval {
                book.days = book.days.filter { interval.halfOpen.contains($0.date) }
            }
            return book.days.isEmpty ? nil : book
        }
        .sorted { $0.readingTime > $1.readingTime }
    }
    
    private static func startOfDay(resetTime: Int) -> Date {
        Calendar.current.startOfDay(for: Date.now.addingTimeInterval(-Double(resetTime) * 60))
    }
}

private extension DateInterval {
    var halfOpen: Range<Date> { start..<end }
}
