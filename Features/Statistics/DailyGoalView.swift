//
//  DailyGoalView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct DailyGoalView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var showGoalPicker = false
    var viewModel: StatisticsViewModel
    
    private let markerBorder: CGFloat = 1
    private let markerRadius: CGFloat = 2.5
    private let markerSize: CGFloat = 12
    private let markerSpacing: CGFloat = 3
    private let monthLabelHeight: CGFloat = 14
    
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    gauge
                        .frame(width: 320, height: 160)
                    statGrid
                        .frame(minWidth: 320, maxWidth: 460)
                        .frame(maxWidth: .infinity)
                }
                
                VStack(spacing: 0) {
                    gauge
                    Divider()
                        .padding(.top, 18)
                        .padding(.bottom, 14)
                    statGrid
                }
            }
            
            Divider()
                .padding(.top, 14)
                .padding(.bottom, 12)
            
            heatmap
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
    
    private var gauge: some View {
        ZStack(alignment: .bottom) {
            arc(to: 1)
                .foregroundStyle(Color(.systemFill))
            arc(to: progress)
                .foregroundStyle(Color.accentColor)
                .animation(.easeOut, value: progress)
            
            VStack(spacing: 0) {
                todayLabel
                    .font(.subheadline.weight(.semibold))
                
                Text(headline)
                    .font(.system(size: 46, weight: .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.bottom, -4)
                
                secondaryValue
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                
                Button {
                    showGoalPicker = true
                } label: {
                    HStack(spacing: 3) {
                        switch metric {
                        case .time:
                            Text("/ \(userConfig.statisticsDailyTimeGoal) minute goal")
                        case .characters:
                            Text("/ \(userConfig.statisticsDailyCharacterGoal.formatted(.number)) character goal")
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .popover(isPresented: $showGoalPicker) {
                    goalPicker
                }
            }
            .padding(.horizontal, 12)
        }
        .aspectRatio(2, contentMode: .fit)
        .padding(.horizontal, 20)
    }
    
    private var todayLabel: Text {
        guard progress >= 1 else {
            return Text("Today")
        }
        return Text("Today")
        + Text(verbatim: " ")
        + Text(Image(systemName: "checkmark.circle.fill")).foregroundStyle(Color.accentColor)
    }
    
    private func arc(to progress: Double) -> some View {
        GeometryReader { proxy in
            Circle()
                .trim(from: 0.5, to: 0.5 + max(progress, 0.001) / 2)
                .stroke(style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: proxy.size.width, height: proxy.size.width)
        }
        .padding(.horizontal, 4.5)
        .padding(.top, 4.5)
    }
    
    private var statGrid: some View {
        let met = viewModel.days.filter { wasGoalMet($0) }.map(\.date)
        let (current, longest) = streaks(met)
        let best = viewModel.days.max { $0.value(for: metric) < $1.value(for: metric) }
        let bestValue = metric == .time ? (best?.readingTime ?? 0).formattedDuration : (best?.charactersRead ?? 0).formatted(.number)
        
        return Grid(alignment: .top, horizontalSpacing: 0, verticalSpacing: 14) {
            GridRow {
                stat(
                    "Current Streak",
                    value: String(localized: "\(current.count) days"),
                    detail: current.range.map { Text("since \(streakDate($0.lowerBound))") }
                )
                stat(
                    "Longest Streak",
                    value: String(localized: "\(longest.count) days"),
                    detail: longest.range.map { range in
                        range.lowerBound == range.upperBound
                        ? Text(verbatim: streakDate(range.lowerBound))
                        : Text("\(streakDate(range.lowerBound)) – \(streakDate(range.upperBound))")
                    }
                )
            }
            
            GridRow {
                stat(
                    "Days Met",
                    value: String(localized: "\(met.count) days"),
                    detail: Text("of \(viewModel.days.count) days read")
                )
                stat(
                    "Best Day",
                    value: bestValue,
                    detail: best.map { Text(verbatim: streakDate($0.date)) }
                )
            }
        }
    }
    
    private func stat(_ title: LocalizedStringKey, value: String, detail: Text?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            
            if let detail {
                detail
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var goalPicker: some View {
        VStack(spacing: 6) {
            Text("Daily Reading Goal")
                .font(.headline)
            
            Group {
                switch metric {
                case .time:
                    Text("min/day")
                case .characters:
                    Text("characters/day")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Picker("Goal", selection: Bindable(userConfig).statisticsGoalMetric) {
                Text("Time").tag(StatisticsGoalMetric.time)
                Text("Characters").tag(StatisticsGoalMetric.characters)
            }
            .pickerStyle(.segmented)
            
            Picker(
                "Daily Goal",
                selection: metric == .time
                ? Bindable(userConfig).statisticsDailyTimeGoal
                : Bindable(userConfig).statisticsDailyCharacterGoal
            ) {
                ForEach(metric == .time ? Self.minuteGoals : Self.characterGoals, id: \.self) { value in
                    Text(value.formatted(.number)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .id(metric)
        }
        .padding(16)
        .frame(width: 260, height: 300)
        .presentationCompactAdaptation(.popover)
    }
    
    private var heatmap: some View {
        let weeks = heatmapWeeks
        
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                ViewThatFits(in: .horizontal) {
                    heatmapGrid(weeks)
                    ScrollView(.horizontal, showsIndicators: false) {
                        heatmapGrid(weeks)
                    }
                    .defaultScrollAnchor(.trailing)
                }
            }
            legend
        }
        .frame(maxWidth: .infinity)
    }
    
    private func heatmapGrid(_ weeks: [HeatmapWeek]) -> some View {
        let today = viewModel.today
        let step = markerSize + markerSpacing
        let halo: CGFloat = 0.5
        let cells: [HeatmapCell] = weeks.enumerated().flatMap { column, week in
            week.days.enumerated().compactMap { row, date in
                guard date <= today else {
                    return nil
                }
                let day = viewModel.day(date)
                return HeatmapCell(
                    rect: CGRect(
                        x: halo + CGFloat(column) * step,
                        y: halo + CGFloat(row) * step,
                        width: markerSize,
                        height: markerSize
                    ),
                    read: day != nil,
                    met: wasGoalMet(day),
                    isToday: date == today
                )
            }
        }
        return VStack(spacing: markerSpacing - halo) {
            HStack(spacing: markerSpacing) {
                ForEach(weeks) { week in
                    Text(week.month ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: markerSize, height: monthLabelHeight)
                }
            }
            
            Canvas { context, _ in
                for cell in cells {
                    context.fill(
                        Path(roundedRect: cell.rect, cornerRadius: markerRadius, style: .continuous),
                        with: .color(cell.met ? .accentColor : Color(.tertiarySystemFill))
                    )
                    if cell.read && !cell.met {
                        context.fill(
                            border(cell.rect, lineWidth: markerBorder, cornerRadius: markerRadius),
                            with: .color(.accentColor),
                            style: FillStyle(eoFill: true)
                        )
                    }
                    if cell.isToday {
                        context.fill(
                            border(cell.rect.insetBy(dx: -halo, dy: -halo), lineWidth: halo, cornerRadius: markerRadius + halo),
                            with: .color(.primary),
                            style: FillStyle(eoFill: true)
                        )
                    }
                }
            }
            .frame(
                width: max(0, CGFloat(weeks.count) * step - markerSpacing) + halo * 2,
                height: 7 * step - markerSpacing + halo * 2
            )
        }
        .padding(.vertical, 2)
    }
    
    private func border(_ rect: CGRect, lineWidth: CGFloat, cornerRadius: CGFloat) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        path.addPath(
            Path(
                roundedRect: rect.insetBy(dx: lineWidth, dy: lineWidth),
                cornerRadius: cornerRadius - lineWidth,
                style: .continuous
            )
        )
        return path
    }
    
    private var weekdayLabels: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        
        return VStack(spacing: markerSpacing) {
            Color.clear
                .frame(width: 0, height: monthLabelHeight)
            
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (calendar.firstWeekday - 1 + offset) % 7
                Text(verbatim: offset % 3 == 0 ? symbols[weekday] : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(height: markerSize)
            }
        }
        .padding(.vertical, 2)
    }
    
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                marker(read: true, met: false, size: 10)
                Text("Read")
            }
            HStack(spacing: 5) {
                marker(read: true, met: true, size: 10)
                Text("Goal met")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 10)
    }
    
    private func marker(read: Bool, met: Bool, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: markerRadius, style: .continuous)
        
        return ZStack {
            shape.fill(met ? Color.accentColor : Color(.tertiarySystemFill))
            if read && !met {
                shape.strokeBorder(Color.accentColor, lineWidth: markerBorder)
            }
        }
        .frame(width: size, height: size)
    }
    
    private var heatmapWeeks: [HeatmapWeek] {
        let calendar = Calendar.current
        guard let end = calendar.dateInterval(of: .weekOfYear, for: viewModel.today)?.start,
              let start = calendar.dateInterval(of: .weekOfYear, for: viewModel.firstDay ?? viewModel.today)?.start else {
            return []
        }
        
        return sequence(first: start) { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) }
            .prefix { $0 <= end }
            .enumerated()
            .map { index, week in
                let showsMonth = index == 0 || calendar.component(.day, from: week) <= 7
                return HeatmapWeek(
                    days: (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) },
                    month: showsMonth ? week.formatted(.dateTime.month(.narrow)) : nil
                )
            }
    }
    
    private var metric: StatisticsGoalMetric {
        userConfig.statisticsGoalMetric
    }
    
    private var goal: Double {
        switch userConfig.statisticsGoalMetric {
        case .time:
            Double(userConfig.statisticsDailyTimeGoal)
        case .characters:
            Double(userConfig.statisticsDailyCharacterGoal)
        }
    }
    
    private var progress: Double {
        min(viewModel.todaysReading.value(for: metric) / goal, 1)
    }
    
    private var headline: String {
        let today = viewModel.todaysReading
        switch metric {
        case .time:
            return Duration.seconds(today.readingTime.rounded()).formatted(.time(pattern: .minuteSecond))
        case .characters:
            return today.charactersRead.formatted(.number)
        }
    }
    
    private var secondaryValue: Text {
        let today = viewModel.todaysReading
        switch metric {
        case .time:
            return Text("\(today.charactersRead) characters")
        case .characters:
            return Text(Duration.seconds(today.readingTime).formatted(.units(allowed: [.minutes], width: .wide)))
        }
    }
    
    private func streaks(_ dates: [Date]) -> (current: Streak, longest: Streak) {
        let calendar = Calendar.current
        var current = Streak()
        var longest = Streak()
        for date in dates {
            if let range = current.range, calendar.dateComponents([.day], from: range.upperBound, to: date).day == 1 {
                current = Streak(count: current.count + 1, range: range.lowerBound...date)
            } else {
                current = Streak(count: 1, range: date...date)
            }
            if current.count > longest.count {
                longest = current
            }
        }
        
        guard let end = current.range?.upperBound,
              calendar.dateComponents([.day], from: end, to: viewModel.today).day! <= 1 else {
            return (Streak(), longest)
        }
        return (current, longest)
    }
    
    private func streakDate(_ date: Date) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return date.formatted(
            Calendar.current.isDate(date, equalTo: viewModel.today, toGranularity: .year) ? style : style.year()
        )
    }
    
    private func wasGoalMet(_ day: ReadingDay?) -> Bool {
        (day?.value(for: metric) ?? 0) >= goal
    }
    
    private static let minuteGoals = Array(stride(from: 5, through: 1440, by: 5))
    private static let characterGoals = Array(stride(from: 500, through: 400_000, by: 500))
}

private struct Streak {
    var count = 0
    var range: ClosedRange<Date>?
}

private struct HeatmapWeek: Identifiable {
    let days: [Date]
    let month: String?
    var id: Date { days[0] }
}

private struct HeatmapCell {
    let rect: CGRect
    let read: Bool
    let met: Bool
    let isToday: Bool
}
