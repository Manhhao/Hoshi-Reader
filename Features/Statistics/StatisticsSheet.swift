//
//  StatisticsSheet.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct StatisticsSheet: View {
    let viewModel: ReaderViewModel
    
    private var chapterCharactersRemaining: Int {
        let range = viewModel.currentChapterRange
        return range.total - range.character
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Characters Read:")
                        Spacer()
                        Text("**\(viewModel.sessionStatistics.charactersRead)**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.sessionStatistics.lastReadingSpeed) / h**")
                    }
                    HStack {
                        Text("Reading Time:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.sessionStatistics.readingTime).formatted())**")
                    }
                    HStack {
                        Text("Time to finish Book:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.sessionStatistics.timeToRead(viewModel.bookInfo.characterCount - viewModel.currentCharacter)).formatted())**")
                    }
                    HStack {
                        Text("Time to finish Chapter:")
                        Spacer()
                        Text("**\(Duration.seconds(viewModel.sessionStatistics.timeToRead(chapterCharactersRemaining)).formatted())**")
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
                        Text("**\(viewModel.todaysStatistics.charactersRead)**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.todaysStatistics.lastReadingSpeed) / h**")
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
                        Text("**\(viewModel.allTimeStatistics.charactersRead)**")
                    }
                    HStack {
                        Text("Reading Speed:")
                        Spacer()
                        Text("**\(viewModel.allTimeStatistics.lastReadingSpeed) / h**")
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
            .monospacedDigit()
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.activeSheet = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}
