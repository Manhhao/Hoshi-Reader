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
            referenceDate = today
        }
    }
    
    var selectedDate: Date? {
        didSet { updateBooks() }
    }
    
    var visibleBookCount = 5
    
    private(set) var days: [ReadingDay] = []
    private(set) var books: [BookStatistics] = []
    
    private var allBooks: [BookStatistics] = []
    private var daysByDate: [Date: ReadingDay] = [:]
    private var daysByMonth: [Date: ReadingDay] = [:]
    
    var today: Date {
        Calendar.current.startOfDay(for: Date.now.addingTimeInterval(-Double(resetTime) * 60))
    }
    
    var firstDay: Date? {
        days.first?.date
    }
    
    var todaysReading: ReadingDay {
        day(today) ?? ReadingDay(date: today)
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
    
    var selectedDay: ReadingDay? {
        guard let selectedDate else {
            return nil
        }
        return buckets(for: referenceDate).first { $0.date == selectedDate }
    }
    
    var summary: ReadingDay {
        selectedDay ?? periodDays(for: referenceDate)
            .reduce(into: ReadingDay(date: referenceDate)) { $0.add($1) }
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
        allBooks = StatisticsStorage.loadAll()
        daysByDate = allBooks.flatMap(\.days).reduce(into: [:]) { grouped, day in
            grouped[day.date, default: ReadingDay(date: day.date)].add(day)
        }
        days = daysByDate.values.sorted { $0.date < $1.date }
        daysByMonth = days.reduce(into: [:]) { grouped, day in
            guard let month = Calendar.current.dateInterval(of: .month, for: day.date)?.start else {
                return
            }
            grouped[month, default: ReadingDay(date: month)].add(day)
        }
        updateBooks()
    }
    
    func day(_ date: Date) -> ReadingDay? {
        daysByDate[Calendar.current.startOfDay(for: date)]
    }
    
    func buckets(for referenceDate: Date) -> [ReadingDay] {
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
        
        let grouped = unit == .day ? daysByDate : daysByMonth
        
        return sequence(first: start) { calendar.date(byAdding: unit, value: 1, to: $0) }
            .prefix { $0 < span.end }
            .map { grouped[$0] ?? ReadingDay(date: $0) }
    }
    
    func averageReadingTime(for referenceDate: Date) -> Double? {
        let elapsed = buckets(for: referenceDate).count { $0.date <= today }
        guard elapsed > 0 else {
            return nil
        }
        
        return periodDays(for: referenceDate).reduce(0) { $0 + $1.readingTime } / Double(elapsed)
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
    
    private func periodDays(for referenceDate: Date) -> [ReadingDay] {
        let interval = interval(for: referenceDate)
        return days.filter { interval?.halfOpen.contains($0.date) ?? true }
    }
    
    private func interval(for date: Date) -> DateInterval? {
        periodUnit.flatMap { Calendar.current.dateInterval(of: $0, for: date) }
    }
    
    private func previousDate(from date: Date) -> Date? {
        periodUnit.flatMap { Calendar.current.date(byAdding: $0, value: -1, to: date) }
    }
    
    private func updateBooks() {
        visibleBookCount = 5
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
}

private extension DateInterval {
    var halfOpen: Range<Date> { start..<end }
}
