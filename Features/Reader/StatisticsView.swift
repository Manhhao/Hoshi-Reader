//
//  StatisticsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct StatisticsView: View {
    let viewModel: ReaderViewModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.sessionStatistics.charactersRead.formatted(.number.grouping(.never)))**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.sessionStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.sessionStatistics.readingTime).formatted())**")
                    }
                    HStack {
                        Text("Time to finish Book:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.sessionStatistics.lastReadingSpeed > 0 ? Double(viewModel.bookInfo.characterCount - viewModel.currentCharacter) / (Double(viewModel.sessionStatistics.lastReadingSpeed) / 3600.0) : 0).formatted())**")
                    }
                    HStack {
                        Text("Time to finish Chapter:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.sessionStatistics.lastReadingSpeed > 0 ? Double(viewModel.currentChapterCount) / (Double(viewModel.sessionStatistics.lastReadingSpeed) / 3600.0) : 0).formatted())**")
                    }
                } header: {
                    HStack {
                        Text("Session")
                        if !viewModel.isTracking {
                            Button {
                                viewModel.startTracking()
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .foregroundStyle(.primary)
                        } else {
                            Button {
                                viewModel.stopTracking()
                            } label: {
                                Image(systemName: "pause.fill")
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.todaysStatistics.charactersRead.formatted(.number.grouping(.never)))**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.todaysStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.todaysStatistics.readingTime).formatted())**")
                    }
                } header: {
                    Text("Today")
                }
                
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.allTimeStatistics.charactersRead.formatted(.number.grouping(.never)))**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.allTimeStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.allTimeStatistics.readingTime).formatted())**")
                    }
                } header: {
                    Text("All Time")
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
