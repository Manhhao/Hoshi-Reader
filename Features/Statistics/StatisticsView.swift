//
//  StatisticsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct StatisticsView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel = StatisticsViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                Section("Daily Goal") {
                    DailyGoalView(viewModel: viewModel)
                        .listRowInsets(.init())
                }
                
                Section("Reading Time") {
                    ReadingTimeView(viewModel: viewModel)
                        .listRowInsets(.init())
                    
                    LabeledContent("Characters Read") {
                        Text(viewModel.summary.charactersRead.formatted(.number))
                            .monospacedDigit()
                    }
                    LabeledContent("Reading Speed") {
                        Text("\(viewModel.summary.readingSpeed.formatted(.number)) / h")
                            .monospacedDigit()
                    }
                    if viewModel.selectedDay == nil {
                        LabeledContent("Total Time") {
                            Text(viewModel.summary.readingTime.formattedDuration)
                                .monospacedDigit()
                        }
                    }
                }
                
                if !viewModel.books.isEmpty {
                    Section("Most Read") {
                        ForEach(viewModel.books.prefix(viewModel.visibleBookCount)) { book in
                            NavigationLink {
                                StatisticsEditView(book: book.metadata)
                                    .onDisappear {
                                        viewModel.load()
                                    }
                            } label: {
                                BookStatisticsRow(
                                    book: book,
                                    maxReadingTime: viewModel.books.first?.readingTime ?? 0
                                )
                            }
                        }
                        if viewModel.visibleBookCount < viewModel.books.count {
                            Button("Show More") {
                                withAnimation {
                                    viewModel.visibleBookCount += 5
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        StatisticsSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                viewModel.resetTime = userConfig.statisticsResetTime
                viewModel.load()
            }
            .onChange(of: userConfig.statisticsResetTime) { _, resetTime in
                viewModel.resetTime = resetTime
            }
        }
    }
}

private struct BookStatisticsRow: View {
    let book: BookStatistics
    let maxReadingTime: Double
    @State private var availableWidth: CGFloat = 0
    
    private let coverAspectRatio: CGFloat = 0.709
    private let cornerRadius: CGFloat = 4
    
    private var barFraction: Double {
        guard maxReadingTime > 0 else {
            return 0
        }
        return min(1, book.readingTime / maxReadingTime)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: book.metadata.coverURL, maxPixelSize: 120) { image in
                image
                    .resizable()
                    .aspectRatio(coverAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } placeholder: {
                CoverFallback(title: book.metadata.displayTitle, aspectRatio: coverAspectRatio, cornerRadius: cornerRadius)
            }
            .frame(width: 34)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if book.isDeleted {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(book.metadata.displayTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color(.tertiaryLabel))
                        .frame(width: availableWidth * 0.7 * barFraction, height: 5)
                    Text(book.readingTime.formattedDuration)
                        .font(.footnote)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .monospacedDigit()
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            }
        }
    }
}
