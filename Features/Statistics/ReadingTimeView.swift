//
//  ReadingTrendCard.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import Charts

struct ReadingTimeView: View {
    var viewModel: StatisticsViewModel
    @State private var settledDate: Date?
    @State private var isIdle = true
    @State private var didScroll = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Period", selection: Bindable(viewModel).period) {
                Text("Week").tag(StatisticsPeriod.week)
                Text("Month").tag(StatisticsPeriod.month)
                Text("Year").tag(StatisticsPeriod.year)
                Text("All").tag(StatisticsPeriod.all)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 2) {
                headline
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline) {
                    Text((viewModel.selectedDay?.readingTime ?? viewModel.averageReadingTime(for: viewModel.referenceDate) ?? 0).formattedDuration)
                        .font(.system(size: 38, weight: .regular))
                        .monospacedDigit()
                    
                    Spacer()
                    
                    if let delta = viewModel.readingTimeDelta {
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            deltaText(abs(Int(delta.rounded())))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Group {
                if viewModel.period == .all {
                    chart(for: viewModel.referenceDate)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(viewModel.referenceDates, id: \.self) { referenceDate in
                                chart(for: referenceDate)
                                    .containerRelativeFrame(.horizontal)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .defaultScrollAnchor(.trailing)
                    .scrollPosition(id: Binding {
                        viewModel.referenceDate
                    } set: { _ in })
                    .onScrollPhaseChange { _, phase in
                        isIdle = phase == .idle
                        didScroll = didScroll || !isIdle
                        commitScroll()
                    }
                    .onScrollGeometryChange(for: Date?.self) { geometry in
                        let width = geometry.containerSize.width
                        let offset = geometry.contentOffset.x + geometry.contentInsets.leading
                        guard width > 0, abs(offset.remainder(dividingBy: width)) < 0.5 else {
                            return nil
                        }
                        let dates = viewModel.referenceDates
                        let index = Int((offset / width).rounded())
                        return dates.indices.contains(index) ? dates[index] : nil
                    } action: { _, date in
                        settledDate = date
                        commitScroll()
                    }
                }
            }
            .frame(height: 128)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func commitScroll() {
        guard isIdle, didScroll, let settledDate else {
            return
        }
        didScroll = false
        viewModel.referenceDate = settledDate
    }
    
    private var headline: Text {
        guard let selectedDay = viewModel.selectedDay else {
            return Text("\(viewModel.title(for: viewModel.referenceDate)) Average")
        }
        
        switch viewModel.bucketUnit {
        case .month:
            return Text(verbatim: selectedDay.date.formatted(.dateTime.month(.wide).year()))
        default:
            return Text(verbatim: selectedDay.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        }
    }
    
    private func chart(for referenceDate: Date) -> some View {
        let buckets = viewModel.buckets(for: referenceDate)
        let average = (viewModel.averageReadingTime(for: referenceDate) ?? 0) / 3600
        let maximum = max(5, ceil((buckets.map(\.readingTime).max() ?? 0) / 3600))
        let selected = buckets.first { $0.date == viewModel.selectedDate }?.date
        let end = Calendar.current.date(byAdding: viewModel.bucketUnit, value: 1, to: buckets.last!.date)!
        
        return Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.date, unit: viewModel.bucketUnit),
                    y: .value("Hours", bucket.readingTime / 3600),
                    width: .ratio(0.6)
                )
                .cornerRadius(3)
                .foregroundStyle(selected == nil || bucket.date == selected ? Color.accentColor : Color(.systemGray4))
            }
            
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
            }
        }
        .chartXScale(domain: buckets.first!.date...end)
        .chartYScale(domain: 0...maximum)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { event in
                guard let date = proxy.value(atX: event.location.x, as: Date.self) else {
                    return
                }
                let start = Calendar.current.dateInterval(of: viewModel.bucketUnit, for: date)?.start
                let tapped = buckets.first { $0.date == start }?.date
                viewModel.selectedDate = tapped == viewModel.selectedDate ? nil : tapped
            }
        }
        .chartYAxis {
            AxisMarks(values: (0...4).map { maximum * Double($0) / 4 }) { _ in
                AxisGridLine()
            }
            AxisMarks(position: .trailing, values: [0, maximum]) { value in
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(hours > 0 ? "\(Int(hours))h" : "0")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxis.values) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                AxisTick(length: .longestLabel, stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                AxisValueLabel(centered: false) {
                    if let date = value.as(Date.self) {
                        Text(date, format: xAxis.format)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { $0.frame(height: 96) }
        .padding(.trailing, 24)
    }
    
    private var xAxis: (values: AxisMarkValues, format: Date.FormatStyle) {
        switch viewModel.period {
        case .week:
            (.stride(by: .day, count: 1), .dateTime.weekday(.narrow))
        case .month:
            (.stride(by: .weekOfYear, count: 1), .dateTime.day())
        case .year:
            (.stride(by: .month, count: 2), .dateTime.month(.narrow))
        case .all:
            (.stride(by: .month, count: 3), .dateTime.month(.abbreviated).year(.twoDigits))
        }
    }
    
    private func deltaText(_ percent: Int) -> Text {
        switch viewModel.period {
        case .week:
            Text("\(percent)% from previous week")
        case .month:
            Text("\(percent)% from previous month")
        case .year:
            Text("\(percent)% from previous year")
        case .all:
            Text("")
        }
    }
}
